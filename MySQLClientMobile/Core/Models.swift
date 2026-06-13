import Foundation

struct DBConnectionProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var groupName: String?
    var host: String
    var port: Int = 3306
    var username: String
    var defaultDatabase: String?
    var useTLS: Bool = true
    var readOnlyMode: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

enum DBObjectType: String, Codable, CaseIterable, Identifiable {
    case table, view, procedure, function, trigger
    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: return "表"
        case .view: return "视图"
        case .procedure: return "存储过程"
        case .function: return "函数"
        case .trigger: return "触发器"
        }
    }

    var systemImage: String {
        switch self {
        case .table: return "tablecells"
        case .view: return "eye"
        case .procedure: return "gearshape.2"
        case .function: return "function"
        case .trigger: return "bolt"
        }
    }
}

struct DBObjectItem: Identifiable, Hashable {
    var id: String { "\(schema).\(name).\(type.rawValue)" }
    let schema: String
    let name: String
    let type: DBObjectType
    let comment: String?
    let rows: Int?
    let sizeInBytes: Int?
}

struct DBColumn: Identifiable, Hashable, Codable {
    var id: String { name }
    var name: String
    var dataType: String
    var columnType: String
    var isNullable: Bool
    var isPrimaryKey: Bool
    var isAutoIncrement: Bool
    var defaultValue: String?
    var comment: String?
    var ordinalPosition: Int

    var displayType: String {
        var value = columnType
        if isPrimaryKey { value += " · PK" }
        if isAutoIncrement { value += " · AI" }
        if !isNullable { value += " · NOT NULL" }
        return value
    }

    var valueKind: DBColumnValueKind {
        DBColumnValueKind(dataType: dataType, columnType: columnType)
    }

    var enumValues: [String] {
        guard columnType.lowercased().hasPrefix("enum(") else { return [] }
        let inner = columnType.dropFirst(5).dropLast()
        return inner
            .split(separator: ",")
            .map { item in
                item.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }
            .filter { !$0.isEmpty }
    }
}

enum DBColumnValueKind: String, Codable, Hashable {
    case integer
    case decimal
    case boolean
    case date
    case dateTime
    case time
    case text
    case longText
    case json
    case binary
    case enumeration
    case plain

    init(dataType: String, columnType: String) {
        let dataType = dataType.lowercased()
        let columnType = columnType.lowercased()

        if columnType.hasPrefix("enum(") { self = .enumeration; return }
        if dataType == "json" { self = .json; return }
        if ["tinytext", "text", "mediumtext", "longtext"].contains(dataType) { self = .longText; return }
        if ["blob", "tinyblob", "mediumblob", "longblob", "binary", "varbinary"].contains(dataType) { self = .binary; return }
        if ["datetime", "timestamp"].contains(dataType) { self = .dateTime; return }
        if dataType == "date" { self = .date; return }
        if dataType == "time" { self = .time; return }
        if ["decimal", "float", "double", "real"].contains(dataType) { self = .decimal; return }
        if ["int", "integer", "bigint", "smallint", "mediumint"].contains(dataType) { self = .integer; return }
        if dataType == "tinyint" && columnType.contains("tinyint(1)") { self = .boolean; return }
        if ["char", "varchar"].contains(dataType) { self = .text; return }
        self = .plain
    }

    var inputHint: String {
        switch self {
        case .integer: return "整数，例如 1001"
        case .decimal: return "数字，例如 99.50"
        case .boolean: return "0 或 1"
        case .date: return "日期格式：yyyy-MM-dd"
        case .dateTime: return "时间格式：yyyy-MM-dd HH:mm:ss"
        case .time: return "时间格式：HH:mm:ss"
        case .json: return "JSON 文本"
        case .binary: return "二进制字段暂不支持直接编辑"
        case .enumeration: return "请选择枚举值"
        case .longText: return "长文本"
        case .text: return "文本"
        case .plain: return "请输入值"
        }
    }
}

enum TableSortDirection: String, Codable, Hashable, CaseIterable, Identifiable {
    case ascending = "ASC"
    case descending = "DESC"

    var id: String { rawValue }
    var title: String { self == .ascending ? "升序" : "降序" }
}

struct TableSortDescriptor: Hashable, Codable {
    var column: String
    var direction: TableSortDirection

    var sqlOrderBy: String {
        "\(column) \(direction.rawValue)"
    }
}

enum TableFilterOperator: String, Codable, Hashable, CaseIterable, Identifiable {
    case contains
    case equals
    case notEquals
    case startsWith
    case endsWith
    case greaterThan
    case lessThan
    case isNull
    case isNotNull

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains: return "包含"
        case .equals: return "等于"
        case .notEquals: return "不等于"
        case .startsWith: return "开头是"
        case .endsWith: return "结尾是"
        case .greaterThan: return "大于"
        case .lessThan: return "小于"
        case .isNull: return "为空"
        case .isNotNull: return "不为空"
        }
    }

    var requiresValue: Bool {
        switch self {
        case .isNull, .isNotNull: return false
        default: return true
        }
    }
}

struct TableFilter: Identifiable, Hashable, Codable {
    var id = UUID()
    var column: String
    var op: TableFilterOperator
    var value: String
}

struct DBIndex: Identifiable, Hashable, Codable {
    var id: String { "\(name)-\(columns.joined(separator: ","))" }
    var name: String
    var columns: [String]
    var isUnique: Bool
    var indexType: String?
    var comment: String?
}

struct SQLQueryResult: Identifiable, Hashable {
    var id = UUID()
    var columns: [String]
    var rows: [[String: String?]]
    var affectedRows: Int?
    var executionTime: TimeInterval
    var warningCount: Int?
    var message: String?

    var isEmpty: Bool {
        rows.isEmpty && affectedRows == nil && columns.isEmpty
    }

    static let empty = SQLQueryResult(columns: [], rows: [], affectedRows: nil, executionTime: 0, warningCount: nil, message: nil)
}

struct ExplainResult: Identifiable, Hashable {
    var id = UUID()
    var selectType: String?
    var table: String?
    var type: String?
    var possibleKeys: String?
    var key: String?
    var rows: Int?
    var extra: String?

    var riskLevel: ExplainRiskLevel {
        if type?.uppercased() == "ALL" { return .high }
        if key == nil || key?.isEmpty == true { return .medium }
        return .low
    }
}

enum ExplainRiskLevel: String {
    case low = "正常"
    case medium = "注意"
    case high = "高风险"

    var systemImage: String {
        switch self {
        case .low: return "checkmark.seal"
        case .medium: return "exclamationmark.triangle"
        case .high: return "xmark.octagon"
        }
    }
}

enum MySQLClientError: LocalizedError {
    case notConnected
    case notImplemented
    case invalidSQL(String)
    case unsafeSQL([SQLSafetyWarning])
    case keychainError(Int32)
    case driverError(String)
    case emptyRowValues
    case rowLocatorMissing
    case noRowChanges

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "尚未连接到 MySQL 数据库"
        case .notImplemented:
            return "真实 MySQL 连接实现尚未接入，当前工程骨架默认使用 Mock 服务"
        case .invalidSQL(let reason):
            return "SQL 不合法：\(reason)"
        case .unsafeSQL(let warnings):
            return warnings.map(\.message).joined(separator: "\n")
        case .keychainError(let status):
            return "Keychain 操作失败，状态码：\(status)"
        case .driverError(let message):
            return message
        case .emptyRowValues:
            return "没有可保存的字段值"
        case .rowLocatorMissing:
            return "无法定位要更新/删除的行：未获取到主键，也无法构造安全的行匹配条件"
        case .noRowChanges:
            return "没有检测到字段变更"
        }
    }
}

enum MySQLErrorTranslator {
    static func wrap(_ error: Error) -> Error {
        if error is MySQLClientError { return error }
        return MySQLClientError.driverError(message(from: error))
    }

    static func message(from error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }

        let text = String(describing: error)
        let nsError = error as NSError
        let lower = text.lowercased()

        if lower.contains("access denied") || lower.contains("1045") {
            return "连接失败：用户名或密码错误，或者该 MySQL 用户没有从当前设备 IP 登录的权限。\n原始错误：\(text)"
        }

        if lower.contains("unknown database") || lower.contains("1049") {
            return "连接失败：指定的默认数据库不存在，请检查连接配置中的数据库名。\n原始错误：\(text)"
        }

        if lower.contains("can't connect") || lower.contains("connection refused") || lower.contains("network is unreachable") || lower.contains("timed out") || nsError.code == 61 || nsError.code == 60 {
            return "连接失败：无法连接到 MySQL 服务。请检查 host、port、防火墙、MySQL 是否监听远程地址，以及模拟器/真机网络是否可达。\n原始错误：\(text)"
        }

        if lower.contains("ssl") || lower.contains("tls") || lower.contains("certificate") {
            return "连接失败：TLS/SSL 握手异常。可以先关闭 TLS 测试连接，或检查服务器证书配置。\n原始错误：\(text)"
        }

        if lower.contains("syntax") || lower.contains("1064") {
            return "SQL 执行失败：语法错误，请检查 SQL 语句。\n原始错误：\(text)"
        }

        if lower.contains("duplicate") || lower.contains("1062") {
            return "SQL 执行失败：唯一键/主键冲突，存在重复数据。\n原始错误：\(text)"
        }

        if lower.contains("foreign key") || lower.contains("1451") || lower.contains("1452") {
            return "SQL 执行失败：外键约束不满足，请检查关联表数据。\n原始错误：\(text)"
        }

        if lower.contains("unknown column") || lower.contains("1054") {
            return "SQL 执行失败：字段不存在，请检查列名或表结构。\n原始错误：\(text)"
        }

        if lower.contains("doesn't exist") || lower.contains("1146") {
            return "SQL 执行失败：表或对象不存在，请刷新数据库对象后重试。\n原始错误：\(text)"
        }

        return "操作失败：\(text)"
    }
}
