import SwiftUI
import SwiftData

struct QueryHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QueryHistoryEntity.executedAt, order: .reverse) private var histories: [QueryHistoryEntity]

    var body: some View {
        NavigationStack {
            List {
                if histories.isEmpty {
                    EmptyStateView(systemImage: "clock", title: "暂无查询历史", message: "成功或失败的 SQL 执行记录会保存在这里。")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(histories) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(item.success ? "成功" : "失败", systemImage: item.success ? "checkmark.circle" : "xmark.octagon")
                                    .font(.caption)
                                    .foregroundStyle(item.success ? .green : .red)
                                Spacer()
                                Text(AppDateFormatters.dateTime.string(from: item.executedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.sql)
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(4)
                            if let error = item.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteHistory(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除")
                        }
                    }
                }
            }
            .navigationTitle("查询历史")
            .toolbar {
                NavigationLink { FavoriteSQLView() } label: {
                    Label("收藏", systemImage: "star")
                }
            }
        }
    }

    private func deleteHistory(_ item: QueryHistoryEntity) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}

struct FavoriteSQLView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteSQLEntity.updatedAt, order: .reverse) private var favorites: [FavoriteSQLEntity]

    var body: some View {
        List {
            if favorites.isEmpty {
                EmptyStateView(systemImage: "star", title: "暂无收藏 SQL", message: "在 SQL 工作台点击收藏后，会出现在这里。")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(favorites) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.headline)
                        Text(item.sql)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(5)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteFavorite(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除")
                    }
                }
            }
        }
        .navigationTitle("SQL 收藏")
    }

    private func deleteFavorite(_ item: FavoriteSQLEntity) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}

struct SettingsView: View {
    @AppStorage("defaultLimit") private var defaultLimit = 50
    @AppStorage("requireBiometrics") private var requireBiometrics = false
    @AppStorage("dangerousSQLConfirmation") private var dangerousSQLConfirmation = true
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    private let feedbackURL = URL(string: "mailto:i@devonchan.com?subject=MySQL%20Client%20Mobile%20%E6%84%8F%E8%A7%81%E5%8F%8D%E9%A6%88")!

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("显示模式", selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                }

                Section("查询") {
                    Stepper("默认分页：\(defaultLimit)", value: $defaultLimit, in: 20...500, step: 10)
                    Toggle("危险 SQL 二次确认", isOn: $dangerousSQLConfirmation)
                }

                Section("安全") {
                    Toggle("启动后要求 Face ID / Touch ID", isOn: $requireBiometrics)
                }

                Section("导入导出") {
                    NavigationLink("导入 CSV") { ImportCSVView() }
                }

                Section("支持") {
                    Link(destination: feedbackURL) {
                        Text("意见反馈")
                    }
                }

                Section("关于") {
                    LabeledContent("应用名称", value: "SQLink")
                    LabeledContent("版本", value: "1.0.0")
                }
            }
            .navigationTitle("设置")
        }
    }
}

struct ImportCSVView: View {
    @State private var previewText = ""

    var body: some View {
        List {
            Section("CSV 预览") {
                TextEditor(text: $previewText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
            }

            Section("导入策略") {
                Toggle("首行为字段名", isOn: .constant(true))
                Toggle("导入前预览前 20 行", isOn: .constant(true))
                Toggle("失败行导出为日志", isOn: .constant(true))
            }
        }
        .navigationTitle("导入 CSV")
    }
}

struct ExportDataView: View {
    let result: SQLQueryResult
    @State private var exportedText = ""

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $exportedText)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding()
        .navigationTitle("导出")
        .onAppear {
            exportedText = CSVExporter.export(result: result)
        }
    }
}
