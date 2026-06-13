import Foundation

#if canImport(MySQLNIO)
import Logging
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL

/// 基于 MySQLNIO 的真实 MySQL 连接实现。
///
/// 说明：
/// - 该服务保持一个当前活动连接，适合移动端单连接工作台。
/// - 对 information_schema 查询和表数据分页做了基础封装。
/// - 任意 SQL 执行前的风险控制由 MySQLSessionStore + SQLSafetyGuard 处理。
actor MySQLNIOClientService: MySQLClientServicing {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let logger = Logger(label: "com.devonchan.MySQLClientMobile.mysql-nio")

    private var connection: MySQLConnection?
    private var activeDatabase: String?
    private var currentProfile: DBConnectionProfile?

    deinit {
        if let connection, !connection.isClosed {
            try? connection.close().wait()
        }
        try? group.syncShutdownGracefully()
    }

    func connect(profile: DBConnectionProfile, password: String) async throws {
        await disconnect()

        let eventLoop = group.next()
        let socketAddress = try SocketAddress.makeAddressResolvingHost(profile.host, port: profile.port)
        let database = profile.defaultDatabase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tlsConfiguration: TLSConfiguration? = profile.useTLS ? .makeClientConfiguration() : nil

        let newConnection = try await MySQLConnection.connect(
            to: socketAddress,
            username: profile.username,
            database: database,
            password: password.isEmpty ? nil : password,
            tlsConfiguration: tlsConfiguration,
            serverHostname: profile.useTLS ? profile.host : nil,
            logger: logger,
            on: eventLoop
        ).get()

        connection = newConnection
        activeDatabase = database.isEmpty ? nil : database
        currentProfile = profile
    }

    func disconnect() async {
        if let connection, !connection.isClosed {
            try? await connection.close().get()
        }
        connection = nil
        activeDatabase = nil
        currentProfile = nil
    }

    func testConnection(profile: DBConnectionProfile, password: String) async throws -> String {
        let eventLoop = group.next()
        let socketAddress = try SocketAddress.makeAddressResolvingHost(profile.host, port: profile.port)
        let database = profile.defaultDatabase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tlsConfiguration: TLSConfiguration? = profile.useTLS ? .makeClientConfiguration() : nil

        let testConnection = try await MySQLConnection.connect(
            to: socketAddress,
            username: profile.username,
            database: database,
            password: password.isEmpty ? nil : password,
            tlsConfiguration: tlsConfiguration,
            serverHostname: profile.useTLS ? profile.host : nil,
            logger: logger,
            on: eventLoop
        ).get()

        defer {
            try? testConnection.close().wait()
        }

        let rows = try await testConnection.simpleQuery("SELECT VERSION() AS version").get()
        let version = rows.first?.column("version")?.string ?? "Connected"
        return "MySQL \(version) · \(profile.host):\(profile.port)"
    }

    func fetchDatabases() async throws -> [String] {
        let rows = try await requireConnection().simpleQuery("SHOW DATABASES").get()
        return rows.compactMap { row in
            row.columnDefinitions.first.flatMap { row.column($0.name)?.string }
        }
    }

    func fetchObjects(schema: String) async throws -> [DBObjectItem] {
        let tableRows = try await requireConnection().simpleQuery("""
        SELECT
            TABLE_NAME,
            TABLE_TYPE,
            TABLE_COMMENT,
            TABLE_ROWS,
            COALESCE(DATA_LENGTH, 0) + COALESCE(INDEX_LENGTH, 0) AS SIZE_BYTES
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = '\(Self.escapeSQLString(schema))'
        ORDER BY TABLE_TYPE, TABLE_NAME
        """).get()

        var items = tableRows.compactMap { row -> DBObjectItem? in
            guard let name = row.column("TABLE_NAME")?.string else { return nil }
            let tableType = row.column("TABLE_TYPE")?.string?.uppercased() ?? ""
            let type: DBObjectType = tableType.contains("VIEW") ? .view : .table
            let comment = row.column("TABLE_COMMENT")?.string?.nilIfBlank
            let rows = row.column("TABLE_ROWS")?.int
            let size = row.column("SIZE_BYTES")?.int
            return DBObjectItem(schema: schema, name: name, type: type, comment: comment, rows: rows, sizeInBytes: size)
        }

        let routineRows = try await requireConnection().simpleQuery("""
        SELECT ROUTINE_NAME, ROUTINE_TYPE, ROUTINE_COMMENT
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = '\(Self.escapeSQLString(schema))'
        ORDER BY ROUTINE_TYPE, ROUTINE_NAME
        """).get()

        items += routineRows.compactMap { row -> DBObjectItem? in
            guard let name = row.column("ROUTINE_NAME")?.string else { return nil }
            let routineType = row.column("ROUTINE_TYPE")?.string?.uppercased() ?? ""
            let type: DBObjectType = routineType == "FUNCTION" ? .function : .procedure
            let comment = row.column("ROUTINE_COMMENT")?.string?.nilIfBlank
            return DBObjectItem(schema: schema, name: name, type: type, comment: comment, rows: nil, sizeInBytes: nil)
        }

        let triggerRows = try await requireConnection().simpleQuery("""
        SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE
        FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = '\(Self.escapeSQLString(schema))'
        ORDER BY TRIGGER_NAME
        """).get()

        items += triggerRows.compactMap { row -> DBObjectItem? in
            guard let name = row.column("TRIGGER_NAME")?.string else { return nil }
            let table = row.column("EVENT_OBJECT_TABLE")?.string
            return DBObjectItem(schema: schema, name: name, type: .trigger, comment: table.map { "触发表：\($0)" }, rows: nil, sizeInBytes: nil)
        }

        return items
    }

    func fetchColumns(schema: String, table: String) async throws -> [DBColumn] {
        let rows = try await requireConnection().simpleQuery("""
        SELECT
            COLUMN_NAME,
            DATA_TYPE,
            COLUMN_TYPE,
            IS_NULLABLE,
            COLUMN_KEY,
            COLUMN_DEFAULT,
            EXTRA,
            COLUMN_COMMENT,
            ORDINAL_POSITION
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = '\(Self.escapeSQLString(schema))'
          AND TABLE_NAME = '\(Self.escapeSQLString(table))'
        ORDER BY ORDINAL_POSITION
        """).get()

        return rows.compactMap { row in
            guard let name = row.column("COLUMN_NAME")?.string else { return nil }
            let extra = row.column("EXTRA")?.string?.lowercased() ?? ""
            return DBColumn(
                name: name,
                dataType: row.column("DATA_TYPE")?.string ?? "",
                columnType: row.column("COLUMN_TYPE")?.string ?? "",
                isNullable: (row.column("IS_NULLABLE")?.string ?? "YES") == "YES",
                isPrimaryKey: (row.column("COLUMN_KEY")?.string ?? "") == "PRI",
                isAutoIncrement: extra.contains("auto_increment"),
                defaultValue: row.column("COLUMN_DEFAULT")?.string,
                comment: row.column("COLUMN_COMMENT")?.string?.nilIfBlank,
                ordinalPosition: row.column("ORDINAL_POSITION")?.int ?? 0
            )
        }
    }

    func fetchIndexes(schema: String, table: String) async throws -> [DBIndex] {
        let rows = try await requireConnection().simpleQuery("""
        SELECT
            INDEX_NAME,
            COLUMN_NAME,
            NON_UNIQUE,
            INDEX_TYPE,
            INDEX_COMMENT,
            SEQ_IN_INDEX
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = '\(Self.escapeSQLString(schema))'
          AND TABLE_NAME = '\(Self.escapeSQLString(table))'
        ORDER BY INDEX_NAME, SEQ_IN_INDEX
        """).get()

        struct Accumulator {
            var columns: [String] = []
            var isUnique: Bool = false
            var indexType: String?
            var comment: String?
        }

        var grouped: [String: Accumulator] = [:]
        var order: [String] = []

        for row in rows {
            guard let name = row.column("INDEX_NAME")?.string else { continue }
            if grouped[name] == nil {
                grouped[name] = Accumulator()
                order.append(name)
            }

            if let column = row.column("COLUMN_NAME")?.string {
                grouped[name]?.columns.append(column)
            }

            let nonUnique = row.column("NON_UNIQUE")?.int ?? 1
            grouped[name]?.isUnique = nonUnique == 0
            grouped[name]?.indexType = row.column("INDEX_TYPE")?.string
            grouped[name]?.comment = row.column("INDEX_COMMENT")?.string?.nilIfBlank
        }

        return order.compactMap { name in
            guard let item = grouped[name] else { return nil }
            return DBIndex(name: name, columns: item.columns, isUnique: item.isUnique, indexType: item.indexType, comment: item.comment)
        }
    }

    func showCreateTable(schema: String, table: String) async throws -> String {
        try await useDatabase(schema)
        let rows = try await requireConnection().simpleQuery("SHOW CREATE TABLE \(Self.quoteIdentifier(table))").get()
        guard let row = rows.first else { return "" }

        // MySQL 对表和视图会返回不同列名：Create Table / Create View。
        if let value = row.column("Create Table")?.string { return value }
        if let value = row.column("Create View")?.string { return value }
        return row.columnDefinitions.compactMap { row.column($0.name)?.string }.joined(separator: "\n")
    }

    func showCreateRoutine(schema: String, name: String, type: DBObjectType) async throws -> String {
        try await useDatabase(schema)
        let objectKind = type == .function ? "FUNCTION" : "PROCEDURE"
        let rows = try await requireConnection().simpleQuery("SHOW CREATE \(objectKind) \(Self.quoteIdentifier(name))").get()
        guard let row = rows.first else { return "" }

        if type == .function, let value = row.column("Create Function")?.string { return value }
        if type == .procedure, let value = row.column("Create Procedure")?.string { return value }
        return row.columnDefinitions.compactMap { row.column($0.name)?.string }.joined(separator: "\n")
    }

    func fetchTableData(schema: String, table: String, limit: Int, offset: Int, sort: TableSortDescriptor?, filters: [TableFilter]) async throws -> SQLQueryResult {
        try await useDatabase(schema)

        let safeLimit = min(max(limit, 1), 500)
        let safeOffset = max(offset, 0)
        var sql = "SELECT * FROM \(Self.quoteIdentifier(table))"

        let whereSQL = buildFilterWhereClause(filters)
        if !whereSQL.isEmpty {
            sql += " WHERE \(whereSQL)"
        }

        if let sort, Self.isSafeIdentifier(sort.column) {
            sql += " ORDER BY \(Self.quoteIdentifier(sort.column)) \(sort.direction.rawValue)"
        }

        sql += " LIMIT \(safeLimit) OFFSET \(safeOffset)"
        return try await runSimpleQuery(sql, messagePrefix: "查询成功")
    }


    func insertRow(schema: String, table: String, values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        try await useDatabase(schema)

        let writableColumns = columns.filter { column in
            guard values.keys.contains(column.name) else { return false }
            if column.isAutoIncrement {
                let value = values[column.name] ?? nil
                return value?.isEmpty == false
            }
            return true
        }

        guard !writableColumns.isEmpty else {
            throw MySQLClientError.emptyRowValues
        }

        let columnSQL = writableColumns.map { Self.quoteIdentifier($0.name) }.joined(separator: ", ")
        let valueSQL = writableColumns.map { column in
            Self.sqlLiteral(values[column.name] ?? nil)
        }.joined(separator: ", ")

        let sql = "INSERT INTO \(Self.qualifiedName(schema: schema, table: table)) (\(columnSQL)) VALUES (\(valueSQL))"
        return try await runSimpleQuery(sql, messagePrefix: "新增成功")
    }

    func updateRow(schema: String, table: String, originalRow: [String: String?], values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        try await useDatabase(schema)

        let changedColumns = columns.filter { column in
            guard values.keys.contains(column.name) else { return false }
            let oldValue = originalRow[column.name] ?? nil
            let newValue = values[column.name] ?? nil
            return oldValue != newValue
        }

        guard !changedColumns.isEmpty else {
            throw MySQLClientError.noRowChanges
        }

        let setSQL = changedColumns.map { column in
            "\(Self.quoteIdentifier(column.name)) = \(Self.sqlLiteral(values[column.name] ?? nil))"
        }.joined(separator: ", ")

        let whereSQL = try buildWhereClause(row: originalRow, columns: columns)
        let sql = "UPDATE \(Self.qualifiedName(schema: schema, table: table)) SET \(setSQL) WHERE \(whereSQL) LIMIT 1"
        return try await runSimpleQuery(sql, messagePrefix: "更新成功")
    }

    func deleteRow(schema: String, table: String, row: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        try await useDatabase(schema)
        let whereSQL = try buildWhereClause(row: row, columns: columns)
        let sql = "DELETE FROM \(Self.qualifiedName(schema: schema, table: table)) WHERE \(whereSQL) LIMIT 1"
        return try await runSimpleQuery(sql, messagePrefix: "删除成功")
    }

    func execute(sql: String, database: String?) async throws -> SQLQueryResult {
        if let database, !database.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await useDatabase(database)
        }
        return try await runSimpleQuery(sql, messagePrefix: "执行完成")
    }

    func explain(sql: String, database: String?) async throws -> [ExplainResult] {
        if let database, !database.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await useDatabase(database)
        }

        let trimmedSQL = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let explainSQL = trimmedSQL.uppercased().hasPrefix("EXPLAIN") ? trimmedSQL : "EXPLAIN \(trimmedSQL)"
        let rows = try await requireConnection().simpleQuery(explainSQL).get()

        return rows.map { row in
            ExplainResult(
                selectType: row.column("select_type")?.string ?? row.column("SELECT_TYPE")?.string,
                table: row.column("table")?.string ?? row.column("TABLE")?.string,
                type: row.column("type")?.string ?? row.column("TYPE")?.string,
                possibleKeys: row.column("possible_keys")?.string ?? row.column("POSSIBLE_KEYS")?.string,
                key: row.column("key")?.string ?? row.column("KEY")?.string,
                rows: row.column("rows")?.int ?? row.column("ROWS")?.int,
                extra: row.column("Extra")?.string ?? row.column("EXTRA")?.string
            )
        }
    }

    // MARK: - Private helpers

    private func buildFilterWhereClause(_ filters: [TableFilter]) -> String {
        filters.compactMap { filter -> String? in
            let column = filter.column.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isSafeIdentifier(column) else { return nil }

            let identifier = Self.quoteIdentifier(column)
            let rawValue = filter.value.trimmingCharacters(in: .whitespacesAndNewlines)

            switch filter.op {
            case .isNull:
                return "\(identifier) IS NULL"
            case .isNotNull:
                return "\(identifier) IS NOT NULL"
            case .equals:
                guard !rawValue.isEmpty else { return nil }
                return "\(identifier) = \(Self.sqlLiteral(rawValue))"
            case .notEquals:
                guard !rawValue.isEmpty else { return nil }
                return "\(identifier) <> \(Self.sqlLiteral(rawValue))"
            case .greaterThan:
                guard !rawValue.isEmpty else { return nil }
                return "\(identifier) > \(Self.sqlLiteral(rawValue))"
            case .lessThan:
                guard !rawValue.isEmpty else { return nil }
                return "\(identifier) < \(Self.sqlLiteral(rawValue))"
            case .contains:
                guard !rawValue.isEmpty else { return nil }
                return "\(identifier) LIKE \(Self.sqlLiteral("%" + rawValue + "%"))"
            case .startsWith:
                guard !rawValue.isEmpty else { return nil }
                return "\(identifier) LIKE \(Self.sqlLiteral(rawValue + "%"))"
            case .endsWith:
                guard !rawValue.isEmpty else { return nil }
                return "\(identifier) LIKE \(Self.sqlLiteral("%" + rawValue))"
            }
        }
        .joined(separator: " AND ")
    }


    private func buildWhereClause(row: [String: String?], columns: [DBColumn]) throws -> String {
        let primaryKeyColumns = columns.filter(\.isPrimaryKey)
        let locatorColumns = primaryKeyColumns.isEmpty ? columns : primaryKeyColumns

        let parts = locatorColumns.compactMap { column -> String? in
            guard row.keys.contains(column.name) else { return nil }
            return "\(Self.quoteIdentifier(column.name)) <=> \(Self.sqlLiteral(row[column.name] ?? nil))"
        }

        guard !parts.isEmpty else {
            throw MySQLClientError.rowLocatorMissing
        }

        return parts.joined(separator: " AND ")
    }

    private func requireConnection() throws -> MySQLConnection {
        guard let connection, !connection.isClosed else {
            throw MySQLClientError.notConnected
        }
        return connection
    }

    private func useDatabase(_ database: String) async throws {
        let trimmed = database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != activeDatabase else { return }
        try await requireConnection().simpleQuery("USE \(Self.quoteIdentifier(trimmed))").get()
        activeDatabase = trimmed
    }

    private func runSimpleQuery(_ sql: String, messagePrefix: String) async throws -> SQLQueryResult {
        let startedAt = Date()
        let rows = try await requireConnection().simpleQuery(sql).get()
        let executionTime = Date().timeIntervalSince(startedAt)
        let columns = rows.first?.columnDefinitions.map(\.name) ?? []
        let mappedRows = rows.map(Self.dictionary(from:))

        let message: String
        if columns.isEmpty {
            message = "\(messagePrefix)，无结果集"
        } else {
            message = "\(messagePrefix)，返回 \(mappedRows.count) 行"
        }

        return SQLQueryResult(
            columns: columns,
            rows: mappedRows,
            affectedRows: nil,
            executionTime: executionTime,
            warningCount: nil,
            message: message
        )
    }

    private static func dictionary(from row: MySQLRow) -> [String: String?] {
        var result: [String: String?] = [:]
        for column in row.columnDefinitions {
            let key = column.name
            guard let data = row.column(key) else {
                result[key] = nil
                continue
            }
            result[key] = displayString(from: data)
        }
        return result
    }

    private static func displayString(from data: MySQLData) -> String? {
        if data.buffer == nil { return nil }
        if let string = data.string { return string }
        if let int = data.int { return String(int) }
        if let uint = data.uint { return String(uint) }
        if let decimal = data.decimal { return NSDecimalNumber(decimal: decimal).stringValue }
        if let double = data.double { return String(double) }
        if let date = data.date { return ISO8601DateFormatter().string(from: date) }
        if let bytes = data.buffer?.readableBytes {
            return "<binary: \(bytes) bytes>"
        }
        return data.description
    }

    private func sanitizedOrderBy(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let parts = value.split(separator: " ").map(String.init)
        guard let first = parts.first, Self.isSafeIdentifier(first) else { return nil }
        let direction = parts.dropFirst().first?.uppercased()

        if direction == "DESC" {
            return "\(Self.quoteIdentifier(first)) DESC"
        }
        return "\(Self.quoteIdentifier(first)) ASC"
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$")
        return !value.isEmpty && value.rangeOfCharacter(from: allowed.inverted) == nil
    }

    private static func qualifiedName(schema: String, table: String) -> String {
        "\(quoteIdentifier(schema)).\(quoteIdentifier(table))"
    }

    private static func sqlLiteral(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'\(escapeSQLString(value))'"
    }

    private static func quoteIdentifier(_ value: String) -> String {
        "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    private static func escapeSQLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
