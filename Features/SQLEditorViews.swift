import SwiftUI
import SwiftData
import UIKit

private enum DangerousSQLAction {
    case execute
}

struct SQLEditorView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteSQLEntity.updatedAt, order: .reverse) private var favoriteSQLs: [FavoriteSQLEntity]
    var embedInNavigation: Bool = true

    @State private var sql = "SELECT * FROM sys_user LIMIT 20;"
    @State private var result = SQLQueryResult.empty
    @State private var explainResults: [ExplainResult] = []
    @State private var errorMessage: String?
    @State private var showingExplain = false
    @State private var showingSafetyConfirm = false
    @State private var showingExportSheet = false
    @State private var pendingDangerousAction: DangerousSQLAction?
    @State private var toastMessage: String?

    private var assessment: SQLSafetyAssessment {
        SQLSafetyGuard.assess(sql: sql, readOnlyMode: session.currentConnection?.readOnlyMode == true)
    }

    private var safetyWarningText: String {
        assessment.warnings.map { "• \($0.message)" }.joined(separator: "\n")
    }

    var body: some View {
        Group {
            if embedInNavigation {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            pageHeader
            editor
            Divider()
            resultArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let toastMessage {
                TopToastView(message: toastMessage)
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: toastMessage)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                editorActionMenu

                Button { executeTapped() } label: {
                    Label("执行", systemImage: "play.fill")
                }
                    .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showingExplain) {
            NavigationStack { ExplainResultView(results: explainResults) }
        }
        .sheet(isPresented: $showingExportSheet) {
            NavigationStack {
                ExportResultSheet(title: "导出查询结果", result: result, baseFilename: "sql_result")
            }
        }
        .confirmationDialog("确认执行高风险 SQL？", isPresented: $showingSafetyConfirm, titleVisibility: .visible) {
            Button("确认执行", role: .destructive) {
                let action = pendingDangerousAction
                pendingDangerousAction = nil
                if action == .execute {
                    Task { await execute() }
                }
            }
            Button("取消", role: .cancel) {
                pendingDangerousAction = nil
            }
        } message: {
            Text("当前连接：\(session.title)\n当前数据库：\(session.selectedDatabase ?? "未选择")\n\n\(safetyWarningText)")
        }
    }

    private var pageHeader: some View {
        HStack {
            Text("SQL 工作台")
                .font(.largeTitle.weight(.bold))
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var editorActionMenu: some View {
        Menu {
            Button {
                sql = SQLFormatter.format(sql)
            } label: {
                Label("格式化 SQL", systemImage: "text.alignleft")
            }

            Button {
                saveFavorite()
            } label: {
                Label("收藏 SQL", systemImage: "star")
            }

            Button {
                showingExportSheet = true
            } label: {
                Label("导出结果", systemImage: "square.and.arrow.up")
            }
            .disabled(result.columns.isEmpty)

            Button {
                Task { await explain() }
            } label: {
                Label("执行计划", systemImage: "chart.bar.doc.horizontal")
            }
        } label: {
            Label("更多操作", systemImage: "ellipsis.circle")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(text: session.title, systemImage: session.isConnected ? "bolt.horizontal.circle" : "wifi.slash")
                if let database = session.selectedDatabase {
                    StatusBadge(text: database, systemImage: "cylinder.split.1x2")
                }
                Spacer()
            }

            SQLSyntaxTextEditor(text: $sql)
                .frame(minHeight: 160, maxHeight: 260)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !assessment.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(assessment.warnings) { warning in
                        Label(warning.message, systemImage: warning.level == .danger ? "exclamationmark.triangle.fill" : "info.circle")
                            .font(.caption)
                            .foregroundStyle(warning.level == .danger ? .red : .secondary)
                    }
                }
            }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var resultArea: some View {
        Group {
            if result.isEmpty {
                EmptyStateView(systemImage: "tablecells", title: "暂无结果", message: "执行 SQL 后，查询结果、影响行数和错误信息会显示在这里。")
            } else {
                QueryResultView(result: result)
            }
        }
    }

    private func executeTapped() {
        guard session.isConnected else {
            errorMessage = "请先连接数据库"
            return
        }

        if assessment.shouldBlock {
            errorMessage = assessment.warnings.map(\.message).joined(separator: "\n")
            return
        }

        if assessment.requiresConfirmation {
            pendingDangerousAction = .execute
            showingSafetyConfirm = true
            return
        }

        Task { await execute() }
    }

    private func execute() async {
        guard session.isConnected else {
            errorMessage = "请先连接数据库"
            return
        }

        do {
            let output = try await session.execute(sql: sql)
            result = output
            errorMessage = nil
            modelContext.insert(QueryHistoryEntity(
                connectionId: session.currentConnection?.id,
                connectionName: session.currentConnection?.name,
                databaseName: session.selectedDatabase,
                sql: sql,
                executionTime: output.executionTime,
                success: true
            ))
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            modelContext.insert(QueryHistoryEntity(
                connectionId: session.currentConnection?.id,
                connectionName: session.currentConnection?.name,
                databaseName: session.selectedDatabase,
                sql: sql,
                success: false,
                errorMessage: error.localizedDescription
            ))
            try? modelContext.save()
        }
    }

    private func explain() async {
        guard session.isConnected else {
            errorMessage = "请先连接数据库"
            return
        }
        do {
            explainResults = try await session.explain(sql: sql)
            showingExplain = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveFavorite() {
        let normalizedSQL = normalizedFavoriteSQL(sql)
        guard !normalizedSQL.isEmpty else {
            showToast("SQL 为空")
            return
        }

        if favoriteSQLs.contains(where: { normalizedFavoriteSQL($0.sql) == normalizedSQL }) {
            showToast("SQL 已收藏过")
            return
        }

        let title = normalizedSQL.split(separator: "\n").first.map(String.init) ?? "未命名 SQL"
        modelContext.insert(FavoriteSQLEntity(title: title, sql: sql, databaseName: session.selectedDatabase))
        try? modelContext.save()
        showToast("SQL 已收藏")
    }

    private func normalizedFavoriteSQL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showToast(_ message: String) {
        toastMessage = message

        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

struct QueryResultView: View {
    let result: SQLQueryResult

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let affected = result.affectedRows {
                    Label("影响 \(affected) 行", systemImage: "checkmark.circle")
                } else {
                    Label("返回 \(result.rows.count) 行", systemImage: "tablecells")
                }
                Spacer()
                Text(String(format: "%.3fs", result.executionTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .padding(.horizontal)
            .padding(.vertical, 10)

            if !result.columns.isEmpty {
                DataGridView(result: result)
            } else {
                EmptyStateView(systemImage: "checkmark.seal", title: "执行完成", message: result.message ?? "SQL 已执行完成。")
            }
        }
    }
}

struct SQLSyntaxTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = Self.editorFont
        textView.adjustsFontForContentSizeCategory = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.alwaysBounceVertical = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = SQLSyntaxHighlighter.highlight(text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text else { return }
        let selectedRange = textView.selectedRange
        textView.attributedText = SQLSyntaxHighlighter.highlight(text)
        textView.selectedRange = NSRange(location: min(selectedRange.location, text.count), length: 0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text

            let selectedRange = textView.selectedRange
            textView.attributedText = SQLSyntaxHighlighter.highlight(textView.text)
            textView.selectedRange = selectedRange
        }
    }

    private static var editorFont: UIFont {
        .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }
}

private enum SQLSyntaxHighlighter {
    private static let keywords = [
        "ADD", "ALTER", "AND", "AS", "ASC", "BETWEEN", "BY", "CASE", "CREATE", "DATABASE",
        "DELETE", "DESC", "DISTINCT", "DROP", "ELSE", "END", "EXISTS", "EXPLAIN", "FROM",
        "GROUP", "HAVING", "IN", "INDEX", "INNER", "INSERT", "INTO", "IS", "JOIN", "KEY",
        "LEFT", "LIKE", "LIMIT", "NOT", "NULL", "ON", "OR", "ORDER", "OUTER", "PRIMARY",
        "RIGHT", "SELECT", "SET", "TABLE", "THEN", "UPDATE", "USE", "VALUES", "VIEW",
        "WHEN", "WHERE"
    ]

    private static let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
    private static let commentPattern = "(--[^\\n]*|#[^\\n]*|/\\*[\\s\\S]*?\\*/)"
    private static let stringPattern = "'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\""
    private static let numberPattern = "\\b\\d+(?:\\.\\d+)?\\b"

    static func highlight(_ sql: String) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (sql as NSString).length)
        let attributed = NSMutableAttributedString(string: sql, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular),
            .foregroundColor: UIColor.label
        ])

        apply(pattern: keywordPattern, to: attributed, in: sql, color: .systemBlue, options: [.caseInsensitive])
        apply(pattern: numberPattern, to: attributed, in: sql, color: .systemOrange)
        apply(pattern: stringPattern, to: attributed, in: sql, color: .systemGreen)
        apply(pattern: commentPattern, to: attributed, in: sql, color: .secondaryLabel)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        return attributed
    }

    private static func apply(
        pattern: String,
        to attributed: NSMutableAttributedString,
        in text: String,
        color: UIColor,
        options: NSRegularExpression.Options = []
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        expression.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: matchRange)
        }
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        return style
    }
}

struct ExplainResultView: View {
    let results: [ExplainResult]

    var body: some View {
        List {
            ForEach(results) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(item.riskLevel.rawValue, systemImage: item.riskLevel.systemImage)
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(item.table ?? "unknown")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        info("type", item.type)
                        info("key", item.key)
                        info("rows", item.rows.map(String.init))
                    }

                    if item.riskLevel == .high {
                        Text("发现全表扫描，建议检查 WHERE 条件字段是否建立索引。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if item.riskLevel == .medium {
                        Text("未使用明确索引，建议检查 possible_keys 与实际 key。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let extra = item.extra {
                        Text(extra)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Explain")
    }

    private func info(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value ?? "-").font(.caption.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
