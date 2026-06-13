import Foundation
import Combine

@MainActor
final class MySQLSessionStore: ObservableObject {
    @Published private(set) var currentConnection: DBConnectionProfile?
    @Published private(set) var selectedDatabase: String?
    @Published private(set) var isConnected = false
    @Published var lastErrorMessage: String?

    private let client: any MySQLClientServicing

    init(client: any MySQLClientServicing) {
        self.client = client
    }

    var title: String {
        currentConnection?.name ?? "未连接"
    }

    func connect(profile: DBConnectionProfile, password: String) async {
        do {
            try await client.connect(profile: profile, password: password)
            currentConnection = profile
            selectedDatabase = profile.defaultDatabase
            isConnected = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = MySQLErrorTranslator.message(from: error)
            isConnected = false
        }
    }

    func disconnect() async {
        await client.disconnect()
        currentConnection = nil
        selectedDatabase = nil
        isConnected = false
    }

    func testConnection(profile: DBConnectionProfile, password: String) async throws -> String {
        try await readable { try await client.testConnection(profile: profile, password: password) }
    }

    func selectDatabase(_ name: String) {
        selectedDatabase = name
    }

    func fetchDatabases() async throws -> [String] {
        try await readable { try await client.fetchDatabases() }
    }

    func fetchObjects(schema: String) async throws -> [DBObjectItem] {
        try await readable { try await client.fetchObjects(schema: schema) }
    }

    func fetchColumns(schema: String, table: String) async throws -> [DBColumn] {
        try await readable { try await client.fetchColumns(schema: schema, table: table) }
    }

    func fetchIndexes(schema: String, table: String) async throws -> [DBIndex] {
        try await readable { try await client.fetchIndexes(schema: schema, table: table) }
    }

    func showCreateTable(schema: String, table: String) async throws -> String {
        try await readable { try await client.showCreateTable(schema: schema, table: table) }
    }

    func showCreateRoutine(schema: String, name: String, type: DBObjectType) async throws -> String {
        try await readable { try await client.showCreateRoutine(schema: schema, name: name, type: type) }
    }

    func fetchTableData(schema: String, table: String, limit: Int = 50, offset: Int = 0, sort: TableSortDescriptor? = nil, filters: [TableFilter] = []) async throws -> SQLQueryResult {
        try await readable { try await client.fetchTableData(schema: schema, table: table, limit: limit, offset: offset, sort: sort, filters: filters) }
    }

    func insertRow(schema: String, table: String, values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        guard currentConnection?.readOnlyMode != true else {
            throw MySQLClientError.unsafeSQL([SQLSafetyWarning(level: .danger, message: "当前连接处于只读模式，禁止新增数据")])
        }
        return try await readable { try await client.insertRow(schema: schema, table: table, values: values, columns: columns) }
    }

    func updateRow(schema: String, table: String, originalRow: [String: String?], values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        guard currentConnection?.readOnlyMode != true else {
            throw MySQLClientError.unsafeSQL([SQLSafetyWarning(level: .danger, message: "当前连接处于只读模式，禁止编辑数据")])
        }
        return try await readable { try await client.updateRow(schema: schema, table: table, originalRow: originalRow, values: values, columns: columns) }
    }

    func deleteRow(schema: String, table: String, row: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult {
        guard currentConnection?.readOnlyMode != true else {
            throw MySQLClientError.unsafeSQL([SQLSafetyWarning(level: .danger, message: "当前连接处于只读模式，禁止删除数据")])
        }
        return try await readable { try await client.deleteRow(schema: schema, table: table, row: row, columns: columns) }
    }

    func execute(sql: String, database: String? = nil) async throws -> SQLQueryResult {
        let assessment = SQLSafetyGuard.assess(sql: sql, readOnlyMode: currentConnection?.readOnlyMode == true)
        if assessment.shouldBlock {
            throw MySQLClientError.unsafeSQL(assessment.warnings)
        }
        return try await readable { try await client.execute(sql: sql, database: database ?? selectedDatabase) }
    }

    func explain(sql: String, database: String? = nil) async throws -> [ExplainResult] {
        try await readable { try await client.explain(sql: sql, database: database ?? selectedDatabase) }
    }

    private func readable<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw MySQLErrorTranslator.wrap(error)
        }
    }
}
