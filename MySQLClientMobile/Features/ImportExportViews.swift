import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ExportResultSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let result: SQLQueryResult
    let baseFilename: String

    @State private var csvURL: URL?
    @State private var jsonURL: URL?
    @State private var errorMessage: String?
    @State private var shareFile: ShareFile?

    var body: some View {
        Form {
            Section("导出内容") {
                LabeledContent("列数", value: "\(result.columns.count)")
                LabeledContent("行数", value: "\(result.rows.count)")
                LabeledContent("文件名", value: baseFilename)
            }

            if let errorMessage {
                Section {
                    ErrorBanner(message: errorMessage)
                }
            }

            Section {
                exportButton(
                    title: "分享 CSV 文件",
                    systemImage: "doc.text",
                    url: csvURL,
                    placeholder: "CSV 文件准备中"
                )

                exportButton(
                    title: "分享 JSON 文件",
                    systemImage: "curlybraces",
                    url: jsonURL,
                    placeholder: "JSON 文件准备中"
                )
            } header: {
                Text("导出格式")
            } footer: {
                Text("会将当前结果写入临时文件，再通过系统分享面板保存到文件 App、AirDrop、邮件或其他应用。CSV 已加入 UTF-8 BOM，方便中文在表格软件中正常显示。")
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .task {
            prepareFiles()
        }
    }

    @ViewBuilder
    private func exportButton(title: String, systemImage: String, url: URL?, placeholder: String) -> some View {
        if let url {
            Button {
                shareFile = ShareFile(url: url)
            } label: {
                Label(title, systemImage: systemImage)
            }
        } else {
            Label(placeholder, systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private func prepareFiles() {
        do {
            csvURL = try ExportFileWriter.write(result: result, baseFilename: baseFilename, kind: .csv)
            jsonURL = try ExportFileWriter.write(result: result, baseFilename: baseFilename, kind: .json)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CSVImportView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    @Environment(\.dismiss) private var dismiss

    let schema: String
    let table: String
    let initialColumns: [DBColumn]
    let onFinished: () -> Void

    @State private var columns: [DBColumn] = []
    @State private var document: CSVImportDocument?
    @State private var mappings: [String: String] = [:]
    @State private var emptyStringAsNull = true
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var importedCount = 0
    @State private var failedMessages: [String] = []
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var importableColumns: [DBColumn] {
        columns.filter { !$0.isAutoIncrement && $0.valueKind != .binary }
    }

    private var mappedColumnCount: Int {
        mappings.values.filter { !$0.isEmpty }.count
    }

    var body: some View {
        Form {
            Section("1. 选择 CSV 文件") {
                Button {
                    showingFileImporter = true
                } label: {
                    Label(document == nil ? "选择 CSV 文件" : "重新选择 CSV 文件", systemImage: "doc.badge.plus")
                }

                if let document {
                    LabeledContent("表头数量", value: "\(document.headers.count)")
                    LabeledContent("数据行数", value: "\(document.rowCount)")
                }
            }

            if let document {
                Section("2. 预览") {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            GridRow {
                                ForEach(document.headers, id: \.self) { header in
                                    Text(header)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 100, alignment: .leading)
                                }
                            }

                            ForEach(Array(document.previewRows.enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(document.headers, id: \.self) { header in
                                        Text(row[header] ?? "")
                                            .font(.caption.monospaced())
                                            .lineLimit(2)
                                            .frame(minWidth: 100, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Toggle("空字符串按 NULL 导入", isOn: $emptyStringAsNull)

                    if importableColumns.isEmpty {
                        Text("没有可导入字段。自增字段和二进制字段会被自动跳过。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(importableColumns) { column in
                            Picker(column.name, selection: Binding<String>(
                                get: { mappings[column.name] ?? "" },
                                set: { newValue in mappings[column.name] = newValue }
                            )) {
                                Text("不导入").tag("")
                                ForEach(document.headers, id: \.self) { header in
                                    Text(header).tag(header)
                                }
                            }
                        }
                    }
                } header: {
                    Text("3. 字段映射")
                } footer: {
                    Text("默认会按字段名自动匹配 CSV 表头；未映射字段不会参与 INSERT。建议先用测试库验证导入结果。")
                }

                Section("4. 执行导入") {
                    Button(isImporting ? "导入中..." : "开始导入") {
                        Task { await importRows() }
                    }
                    .disabled(isImporting || mappedColumnCount == 0 || document.rowCount == 0)

                    if isImporting || importedCount > 0 {
                        ProgressView(value: Double(importedCount), total: Double(max(document.rowCount, 1))) {
                            Text("已处理 \(importedCount) / \(document.rowCount) 行")
                        }
                    }
                }
            }

            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section {
                    ErrorBanner(message: errorMessage)
                }
            }

            if !failedMessages.isEmpty {
                Section("失败记录") {
                    ForEach(failedMessages, id: \.self) { message in
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("导入 CSV")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .task {
            await loadColumns()
        }
    }

    private func loadColumns() async {
        if !initialColumns.isEmpty {
            columns = initialColumns
            setupDefaultMappings()
            return
        }

        do {
            columns = try await session.fetchColumns(schema: schema, table: table)
            setupDefaultMappings()
        } catch {
            errorMessage = "字段元数据加载失败：\(error.localizedDescription)"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                errorMessage = "未选择 CSV 文件"
                return
            }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            document = try CSVImporter.parse(data: data)
            importedCount = 0
            failedMessages = []
            successMessage = nil
            errorMessage = nil
            setupDefaultMappings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setupDefaultMappings() {
        guard let document else { return }

        var next: [String: String] = [:]
        var lowerHeaderMap: [String: String] = [:]

        for header in document.headers {
            lowerHeaderMap[header.lowercased()] = lowerHeaderMap[header.lowercased()] ?? header
        }

        for column in importableColumns {
            if document.headers.contains(column.name) {
                next[column.name] = column.name
            } else if let matched = lowerHeaderMap[column.name.lowercased()] {
                next[column.name] = matched
            } else {
                next[column.name] = ""
            }
        }

        mappings = next
    }

    private func importRows() async {
        guard let document else { return }

        if session.currentConnection?.readOnlyMode == true {
            errorMessage = "当前连接处于只读模式，禁止导入数据"
            return
        }

        isImporting = true
        importedCount = 0
        failedMessages = []
        successMessage = nil
        errorMessage = nil

        let metadata = columns
        var success = 0
        var failed = 0

        for (index, row) in document.rows.enumerated() {
            let payload = makePayload(from: row)
            if payload.isEmpty {
                failed += 1
                appendFailure("第 \(index + 1) 行：没有映射字段，已跳过")
                importedCount += 1
                continue
            }

            do {
                _ = try await session.insertRow(schema: schema, table: table, values: payload, columns: metadata)
                success += 1
            } catch {
                failed += 1
                appendFailure("第 \(index + 1) 行：\(error.localizedDescription)")
            }

            importedCount += 1
        }

        isImporting = false
        successMessage = "导入完成：成功 \(success) 行，失败 \(failed) 行"
        onFinished()
    }

    private func makePayload(from row: [String: String]) -> [String: String?] {
        var payload: [String: String?] = [:]

        for column in importableColumns {
            guard let header = mappings[column.name], !header.isEmpty else { continue }
            let rawValue = row[header] ?? ""

            if emptyStringAsNull && rawValue.isEmpty && column.isNullable {
                payload[column.name] = nil
            } else {
                payload[column.name] = rawValue
            }
        }

        return payload
    }

    private func appendFailure(_ message: String) {
        if failedMessages.count < 10 {
            failedMessages.append(message)
        }
    }
}

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed.
    }
}
