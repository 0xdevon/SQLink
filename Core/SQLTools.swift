import Foundation

enum SQLFormatter {
    static func format(_ sql: String) -> String {
        var result = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = ["SELECT", "FROM", "WHERE", "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "JOIN", "VALUES", "SET"]
        for keyword in keywords {
            result = result.replacingOccurrences(of: " \(keyword) ", with: "\n\(keyword) ", options: [.caseInsensitive])
        }
        return result
    }
}

enum SQLBuilder {
    static func quotedIdentifier(_ value: String) -> String {
        "`" + value.replacingOccurrences(of: "`", with: "``") + "`"
    }

    static func selectAll(schema: String, table: String, limit: Int, offset: Int, orderBy: String? = nil) -> String {
        let target = "\(quotedIdentifier(schema)).\(quotedIdentifier(table))"
        let order = orderBy.map { " ORDER BY \($0)" } ?? ""
        return "SELECT * FROM \(target)\(order) LIMIT \(limit) OFFSET \(offset);"
    }
}

enum CSVExporter {
    static func export(result: SQLQueryResult) -> String {
        let header = result.columns.map(escape).joined(separator: ",")
        let rows = result.rows.map { row in
            result.columns.map { column in
                escape(row[column].flatMap { $0 } ?? "")
            }.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func escape(_ value: String?) -> String {
        let value = value ?? ""
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum JSONExporter {
    static func export(result: SQLQueryResult) -> Data? {
        let rows: [[String: Any]] = result.rows.map { row in
            var dict: [String: Any] = [:]
            for (key, value) in row {
                dict[key] = value ?? NSNull()
            }
            return dict
        }
        return try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    }
}

enum AppDateFormatters {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

// MARK: - Import / Export helpers

enum ExportFileKind: String, CaseIterable, Identifiable {
    case csv
    case json

    var id: String { rawValue }
    var title: String { self == .csv ? "CSV" : "JSON" }
    var fileExtension: String { rawValue }
}

enum ExportFileWriter {
    static func write(result: SQLQueryResult, baseFilename: String, kind: ExportFileKind) throws -> URL {
        guard !result.columns.isEmpty else {
            throw CSVImportError.invalidContent("当前结果没有可导出的列")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MySQLClientMobileExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = AppDateFormatters.exportTimestamp.string(from: Date())
        let filename = "\(sanitize(baseFilename))_\(timestamp).\(kind.fileExtension)"
        let url = directory.appendingPathComponent(filename)

        switch kind {
        case .csv:
            // Add UTF-8 BOM to improve Chinese text compatibility in spreadsheet apps.
            let content = "\u{FEFF}" + CSVExporter.export(result: result)
            try Data(content.utf8).write(to: url, options: [.atomic])
        case .json:
            guard let data = JSONExporter.export(result: result) else {
                throw CSVImportError.invalidContent("JSON 序列化失败")
            }
            try data.write(to: url, options: [.atomic])
        }

        return url
    }

    private static func sanitize(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "mysql_export" : cleaned
    }
}

struct CSVImportDocument: Hashable {
    var headers: [String]
    var rows: [[String: String]]

    var rowCount: Int { rows.count }
    var previewRows: [[String: String]] { Array(rows.prefix(8)) }
}

enum CSVImportError: LocalizedError {
    case unsupportedEncoding
    case invalidContent(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return "无法识别 CSV 文件编码，建议保存为 UTF-8 后重试"
        case .invalidContent(let message):
            return message
        }
    }
}

enum CSVImporter {
    static func parse(data: Data) throws -> CSVImportDocument {
        let text = decode(data: data)
        guard let text else { throw CSVImportError.unsupportedEncoding }

        let records = parseRecords(text)
            .filter { record in record.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

        guard let headerRecord = records.first, !headerRecord.isEmpty else {
            throw CSVImportError.invalidContent("CSV 文件为空或没有表头")
        }

        let headers = makeUniqueHeaders(headerRecord.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !headers.isEmpty else {
            throw CSVImportError.invalidContent("CSV 表头为空")
        }

        let rows = records.dropFirst().map { record in
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = index < record.count ? record[index] : ""
            }
            return row
        }

        return CSVImportDocument(headers: headers, rows: rows)
    }

    private static func decode(data: Data) -> String? {
        if let value = String(data: data, encoding: .utf8) { return value }
        if let value = String(data: data, encoding: .utf16) { return value }
        if let value = String(data: data, encoding: .unicode) { return value }
        return nil
    }

    private static func makeUniqueHeaders(_ headers: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return headers.enumerated().map { index, raw in
            let base = raw.isEmpty ? "column_\(index + 1)" : raw
            let count = seen[base, default: 0]
            seen[base] = count + 1
            return count == 0 ? base : "\(base)_\(count + 1)"
        }
    }

    private static func parseRecords(_ text: String) -> [[String]] {
        let characters = Array(text)
        var records: [[String]] = []
        var currentRecord: [String] = []
        var currentField = ""
        var insideQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if insideQuotes && index + 1 < characters.count && characters[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 2
                    continue
                }
                insideQuotes.toggle()
                index += 1
                continue
            }

            if !insideQuotes && character == "," {
                currentRecord.append(currentField)
                currentField = ""
                index += 1
                continue
            }

            if !insideQuotes && (character == "\n" || character == "\r") {
                currentRecord.append(currentField)
                records.append(currentRecord)
                currentRecord = []
                currentField = ""

                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            currentField.append(character)
            index += 1
        }

        if !currentField.isEmpty || !currentRecord.isEmpty {
            currentRecord.append(currentField)
            records.append(currentRecord)
        }

        return records
    }

}

extension AppDateFormatters {
    static let exportTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
