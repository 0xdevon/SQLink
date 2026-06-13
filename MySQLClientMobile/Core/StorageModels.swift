import Foundation
import SwiftData

@Model
final class ConnectionProfileEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var groupName: String?
    var host: String
    var port: Int
    var username: String
    var defaultDatabase: String?
    var useTLS: Bool
    var readOnlyMode: Bool
    var isFavorite: Bool
    var passwordKey: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        groupName: String? = nil,
        host: String,
        port: Int = 3306,
        username: String,
        defaultDatabase: String? = nil,
        useTLS: Bool = true,
        readOnlyMode: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.host = host
        self.port = port
        self.username = username
        self.defaultDatabase = defaultDatabase
        self.useTLS = useTLS
        self.readOnlyMode = readOnlyMode
        self.isFavorite = isFavorite
        self.passwordKey = "mysql-client-mobile-\(id.uuidString)"
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func toProfile() -> DBConnectionProfile {
        DBConnectionProfile(
            id: id,
            name: name,
            groupName: groupName,
            host: host,
            port: port,
            username: username,
            defaultDatabase: defaultDatabase,
            useTLS: useTLS,
            readOnlyMode: readOnlyMode,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(
        name: String,
        groupName: String?,
        host: String,
        port: Int,
        username: String,
        defaultDatabase: String?,
        useTLS: Bool,
        readOnlyMode: Bool,
        isFavorite: Bool
    ) {
        self.name = name
        self.groupName = groupName
        self.host = host
        self.port = port
        self.username = username
        self.defaultDatabase = defaultDatabase
        self.useTLS = useTLS
        self.readOnlyMode = readOnlyMode
        self.isFavorite = isFavorite
        self.updatedAt = Date()
    }
}

@Model
final class QueryHistoryEntity {
    @Attribute(.unique) var id: UUID
    var connectionId: UUID?
    var connectionName: String?
    var databaseName: String?
    var sql: String
    var executedAt: Date
    var executionTime: TimeInterval
    var success: Bool
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        connectionId: UUID? = nil,
        connectionName: String? = nil,
        databaseName: String? = nil,
        sql: String,
        executionTime: TimeInterval = 0,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.databaseName = databaseName
        self.sql = sql
        self.executedAt = Date()
        self.executionTime = executionTime
        self.success = success
        self.errorMessage = errorMessage
    }
}

@Model
final class FavoriteSQLEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var sql: String
    var databaseName: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, sql: String, databaseName: String? = nil) {
        self.id = id
        self.title = title
        self.sql = sql
        self.databaseName = databaseName
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
