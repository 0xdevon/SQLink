import Foundation

actor MockMySQLClientService: MySQLClientServicing {
    private var connected = false
    private var mockRows: [[String: String?]] = [
        ["id": "1", "username": "admin", "status": "ENABLED", "created_at": "2026-04-30 10:01:00"],
        ["id": "2", "username": "devon", "status": "ENABLED", "created_at": "2026-04-30 10:02:00"],
        ["id": "3", "username": "guest", "status": "DISABLED", "created_at": "2026-04-30 10:03:00"]
    ]

    private func flattenedValue(_ value: String??) -> String {
        guard let outerValue = value else { return "" }
        return outerValue ?? ""
    }

    func connect(profile: DBConnectionProfile, password: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        connected = true
    }

    func disconnect() async {
        connected = false
    }

    func testConnection(profile: DBConnectionProfile, password: String) async throws -> String {
        try await Task.sleep(nanoseconds: 200_000_000)
        return "Mock MySQL 8.0.36 · \(profile.host):\(profile.port)"
    }

    func fetchDatabases() async throws -> [String] {
        try requireConnection()
        return ["app_production", "app_staging", "information_schema", "mysql"]
    }

    func fetchObjects(schema: String) async throws -> [DBObjectItem] {
        try requireConnection()
        return [
            DBObjectItem(schema: schema, name: "sys_user", type: .table, comment: "系统用户", rows: 1280, sizeInBytes: 2_400_000),
            DBObjectItem(schema: schema, name: "sys_role", type: .table, comment: "角色", rows: 28, sizeInBytes: 180_000),
            DBObjectItem(schema: schema, name: "article_info", type: .table, comment: "知识库文章", rows: 93_201, sizeInBytes: 78_000_000),
            DBObjectItem(schema: schema, name: "v_user_role", type: .view, comment: "用户角色视图", rows: nil, sizeInBytes: nil),
            DBObjectItem(schema: schema, name: "format_user_status", type: .function, comment: "格式化用户状态", rows: nil, sizeInBytes: nil)
        ]
    }

    func fetchColumns(schema: String, table: String) async throws -> [DBColumn] {
        try requireConnection()
        return [
            DBColumn(name: "id", dataType: "bigint", columnType: "bigint unsigned", isNullable: false, isPrimaryKey: true, isAutoIncrement: true, defaultValue: nil, comment: "主键", ordinalPosition: 1),
            DBColumn(name: "username", dataType: "varchar", columnType: "varchar(64)", isNullable: false, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil, comment: "用户名", ordinalPosition: 2),
            DBColumn(name: "status", dataType: "varchar", columnType: "varchar(16)", isNullable: false, isPrimaryKey: false, isAutoIncrement: false, defaultValue: "ENABLED", comment: "状态", ordinalPosition: 3),
            DBColumn(name: "created_at", dataType: "datetime", columnType: "datetime", isNullable: false, isPrimaryKey: false, isAutoIncrement: false, defaultValue: "CURRENT_TIMESTAMP", comment: "创建时间", ordinalPosition: 4)
        ]
    }

    func fetchIndexes(schema: String, table: String) async throws -> [DBIndex] {
        try requireConnection()
        return [
            DBIndex(name: "PRIMARY", columns: ["id"], isUnique: true, indexType: "BTREE", comment: nil),
            DBIndex(name: "idx_username", columns: ["username"], isUnique: true, indexType: "BTREE", comment: nil),
            DBIndex(name: "idx_status_created", columns: ["status", "created_at"], isUnique: false, indexType: "BTREE", comment: nil)
        ]
    }

    func showCreateTable(schema: String, table: String) async throws -> String {
        try requireConnection()
        return """
        CREATE TABLE `\(table)` (
          `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
          `username` varchar(64) NOT NULL COMMENT '用户名',
          `status` varchar(16) NOT NULL DEFAULT 'ENABLED' COMMENT '状态',
          `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
          PRIMARY KEY (`id`),
          UNIQUE KEY `idx_username` (`username`),
          KEY `idx_status_created` (`status`,`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='\(table)';
        """
    }

    func showCreateRoutine(schema: String, name: String, type: DBObjectType) async throws -> String {
        try requireConnection()
        return """
        CREATE FUNCTION `\(name)`(status_value varchar(16))
        RETURNS varchar(32)
        DETERMINISTIC
        BEGIN
          RETURN CASE status_value
            WHEN 'ENABLED' THEN '启用'
            WHEN 'DISABLED' THEN '停用'
            ELSE '未知'
          END;
        END
        """
    }

    func fetchTableData(schema: String, table: String, limit: Int, offset: Int, sort: TableSortDescriptor?, filters: [TableFilter]) async throws -> SQLQueryResult {
        try requireConnection()
        var rows = mockRows

        for filter in filters {
            rows = rows.filter { row in
                let value = row[filter.column] ?? nil
                switch filter.op {
                case .isNull:
                    return value == nil
                case .isNotNull:
                    return value != nil
                case .equals:
                    return value == filter.value
                case .notEquals:
                    return value != filter.value
                case .contains:
                    return value?.localizedCaseInsensitiveContains(filter.value) == true
                case .startsWith:
                    return value?.lowercased().hasPrefix(filter.value.lowercased()) == true
                case .endsWith:
                    return value?.lowercased().hasSuffix(filter.value.lowercased()) == true
                case .greaterThan:
                    return (value ?? "") > filter.value
                case .lessThan:
                    return (value ?? "") < filter.value
                }
            }
        }

        if let sort {
            rows.sort { lhs, rhs in
                let left = flattenedValue(lhs[sort.column])
                let right = flattenedValue(rhs[sort.column])
                return sort.direction == .ascending ? left < right : left > right
            }
        }

        let page = Array(rows.dropFirst(offset).prefix(limit))
        return SQLQueryResult(columns: ["id", "username", "status", "created_at"], rows: page, affectedRows: nil, executionTime: 0.038, warningCount: 0, message: "Mock result")
    }


    func insertRow(schema: String, table: String, values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        try requireConnection()
        let nextNumericId = (mockRows.compactMap { row -> Int? in
            if let value = row["id"] ?? nil { return Int(value) }
            return nil
        }.max() ?? 0) + 1
        let nextId = String(nextNumericId)
        var row: [String: String?] = ["id": nextId]
        for column in columns where !column.isAutoIncrement {
            if values.keys.contains(column.name) {
                row.updateValue(values[column.name] ?? nil, forKey: column.name)
            } else if let defaultValue = column.defaultValue, defaultValue != "CURRENT_TIMESTAMP" {
                row[column.name] = defaultValue
            } else {
                row[column.name] = column.name == "created_at" ? AppDateFormatters.dateTime.string(from: Date()) : ""
            }
        }
        mockRows.insert(row, at: 0)
        return SQLQueryResult(columns: [], rows: [], affectedRows: 1, executionTime: 0.022, warningCount: 0, message: "新增成功，影响 1 行")
    }

    func updateRow(schema: String, table: String, originalRow: [String: String?], values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        try requireConnection()
        guard let id = originalRow["id"] ?? nil else { throw MySQLClientError.rowLocatorMissing }
        guard let index = mockRows.firstIndex(where: { ($0["id"] ?? nil) == id }) else { throw MySQLClientError.rowLocatorMissing }
        for (key, value) in values {
            mockRows[index].updateValue(value, forKey: key)
        }
        return SQLQueryResult(columns: [], rows: [], affectedRows: 1, executionTime: 0.019, warningCount: 0, message: "更新成功，影响 1 行")
    }

    func deleteRow(schema: String, table: String, row: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        try requireConnection()
        guard let id = row["id"] ?? nil else { throw MySQLClientError.rowLocatorMissing }
        mockRows.removeAll { ($0["id"] ?? nil) == id }
        return SQLQueryResult(columns: [], rows: [], affectedRows: 1, executionTime: 0.018, warningCount: 0, message: "删除成功，影响 1 行")
    }

    func execute(sql: String, database: String?) async throws -> SQLQueryResult {
        try requireConnection()
        let upper = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.hasPrefix("SELECT") || upper.hasPrefix("SHOW") || upper.hasPrefix("DESC") || upper.hasPrefix("EXPLAIN") {
            return SQLQueryResult(
                columns: ["id", "title", "status"],
                rows: [
                    ["id": "1", "title": "Mock 查询结果 A", "status": "OK"],
                    ["id": "2", "title": "Mock 查询结果 B", "status": "OK"]
                ],
                affectedRows: nil,
                executionTime: 0.041,
                warningCount: 0,
                message: "查询成功"
            )
        }

        return SQLQueryResult(columns: [], rows: [], affectedRows: 1, executionTime: 0.029, warningCount: 0, message: "执行成功，影响 1 行")
    }

    func explain(sql: String, database: String?) async throws -> [ExplainResult] {
        try requireConnection()
        return [
            ExplainResult(selectType: "SIMPLE", table: "sys_user", type: "ALL", possibleKeys: "idx_username", key: nil, rows: 1280, extra: "Using where"),
            ExplainResult(selectType: "SIMPLE", table: "sys_role", type: "ref", possibleKeys: "PRIMARY", key: "PRIMARY", rows: 1, extra: nil)
        ]
    }

    private func requireConnection() throws {
        if !connected {
            throw MySQLClientError.notConnected
        }
    }
}
