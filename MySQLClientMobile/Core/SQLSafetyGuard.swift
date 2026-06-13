import Foundation

struct SQLSafetyAssessment: Hashable {
    var warnings: [SQLSafetyWarning]
    var shouldBlock: Bool
    var requiresConfirmation: Bool

    static let safe = SQLSafetyAssessment(warnings: [], shouldBlock: false, requiresConfirmation: false)
}

struct SQLSafetyWarning: Identifiable, Hashable, Error {
    var id = UUID()
    var level: SQLSafetyLevel
    var message: String
}

enum SQLSafetyLevel: String, Hashable {
    case info = "提示"
    case warning = "警告"
    case danger = "危险"
}

enum SQLSafetyGuard {
    static func assess(sql: String, readOnlyMode: Bool) -> SQLSafetyAssessment {
        let normalized = normalize(sql)
        guard !normalized.isEmpty else {
            return SQLSafetyAssessment(
                warnings: [SQLSafetyWarning(level: .warning, message: "SQL 内容为空")],
                shouldBlock: true,
                requiresConfirmation: false
            )
        }

        var warnings: [SQLSafetyWarning] = []
        var shouldBlock = false
        var requiresConfirmation = false

        let writePrefixes = ["INSERT", "UPDATE", "DELETE", "REPLACE", "ALTER", "DROP", "TRUNCATE", "CREATE"]
        let isWriteSQL = writePrefixes.contains { normalized.hasPrefix($0) }

        if readOnlyMode && isWriteSQL {
            warnings.append(SQLSafetyWarning(level: .danger, message: "当前连接处于只读模式，禁止执行写入、修改或 DDL SQL"))
            shouldBlock = true
        }

        if normalized.hasPrefix("DELETE") && !normalized.contains(" WHERE ") {
            warnings.append(SQLSafetyWarning(level: .danger, message: "DELETE 未包含 WHERE，可能删除整表数据"))
            requiresConfirmation = true
        }

        if normalized.hasPrefix("UPDATE") && !normalized.contains(" WHERE ") {
            warnings.append(SQLSafetyWarning(level: .danger, message: "UPDATE 未包含 WHERE，可能更新整表数据"))
            requiresConfirmation = true
        }

        if normalized.hasPrefix("DROP") || normalized.hasPrefix("TRUNCATE") {
            warnings.append(SQLSafetyWarning(level: .danger, message: "检测到 DROP / TRUNCATE 高危操作，执行前需要二次确认"))
            requiresConfirmation = true
        }

        if normalized.hasPrefix("ALTER") {
            warnings.append(SQLSafetyWarning(level: .warning, message: "检测到 ALTER 表结构修改操作，执行前需要确认目标库和 SQL 内容"))
            requiresConfirmation = true
        }

        if normalized.contains("; DROP ") || normalized.contains("; TRUNCATE ") || normalized.contains("; DELETE ") || normalized.contains("; UPDATE ") {
            warnings.append(SQLSafetyWarning(level: .warning, message: "检测到多语句中包含写入或高危操作，建议逐条确认后执行"))
            requiresConfirmation = true
        }

        if normalized.hasPrefix("SELECT") && !normalized.contains(" LIMIT ") {
            warnings.append(SQLSafetyWarning(level: .info, message: "SELECT 未设置 LIMIT，移动端建议限制返回行数"))
        }

        return SQLSafetyAssessment(warnings: warnings, shouldBlock: shouldBlock, requiresConfirmation: requiresConfirmation)
    }

    private static func normalize(_ sql: String) -> String {
        sql
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}
