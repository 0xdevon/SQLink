import Foundation

protocol MySQLClientServicing {
    func connect(profile: DBConnectionProfile, password: String) async throws
    func disconnect() async
    func testConnection(profile: DBConnectionProfile, password: String) async throws -> String

    func fetchDatabases() async throws -> [String]
    func fetchObjects(schema: String) async throws -> [DBObjectItem]
    func fetchColumns(schema: String, table: String) async throws -> [DBColumn]
    func fetchIndexes(schema: String, table: String) async throws -> [DBIndex]
    func showCreateTable(schema: String, table: String) async throws -> String
    func showCreateRoutine(schema: String, name: String, type: DBObjectType) async throws -> String

    func fetchTableData(schema: String, table: String, limit: Int, offset: Int, sort: TableSortDescriptor?, filters: [TableFilter]) async throws -> SQLQueryResult
    func insertRow(schema: String, table: String, values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult
    func updateRow(schema: String, table: String, originalRow: [String: String?], values: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult
    func deleteRow(schema: String, table: String, row: [String: String?], columns: [DBColumn]) async throws -> SQLQueryResult

    func execute(sql: String, database: String?) async throws -> SQLQueryResult
    func explain(sql: String, database: String?) async throws -> [ExplainResult]
}
