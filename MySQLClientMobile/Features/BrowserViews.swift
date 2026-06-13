import SwiftUI

struct DatabaseListView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    var embedInNavigation: Bool = true

    @State private var databases: [String] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if embedInNavigation {
                NavigationStack { content }
            } else {
                content
            }
        }
        .task { await load() }
    }

    private var content: some View {
        List {
            if !session.isConnected {
                EmptyStateView(systemImage: "wifi.slash", title: "尚未连接", message: "请先在「连接」中选择一个 MySQL 连接。")
                    .listRowBackground(Color.clear)
            } else {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                        .listRowBackground(Color.clear)
                }

                Section(session.title) {
                    ForEach(databases, id: \.self) { database in
                        NavigationLink {
                            DBObjectListView(schema: database)
                        } label: {
                            HStack {
                                Label(database, systemImage: "cylinder.split.1x2")
                                Spacer()
                                if session.selectedDatabase == database {
                                    ActiveIndicatorBadge(text: "当前库")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("数据库")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(!session.isConnected || isLoading)
            }
        }
    }

    private func load() async {
        guard session.isConnected else { return }
        do {
            isLoading = true
            databases = try await session.fetchDatabases()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct DBObjectListView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    let schema: String

    @State private var objects: [DBObjectItem] = []
    @State private var selectedType: DBObjectType?
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private var filteredObjects: [DBObjectItem] {
        guard let selectedType else { return objects }
        return objects.filter { $0.type == selectedType }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("类型", selection: $selectedType) {
                Text("全部").tag(DBObjectType?.none)
                ForEach(DBObjectType.allCases) { type in
                    Text(type.title).tag(DBObjectType?.some(type))
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            List {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                        .listRowBackground(Color.clear)
                }

                ForEach(filteredObjects) { object in
                    NavigationLink {
                        if object.type == .function {
                            RoutineDetailView(object: object)
                        } else {
                            TableDetailView(schema: schema, object: object)
                        }
                    } label: {
                        HStack {
                            Image(systemName: object.type.systemImage)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(object.name).font(.headline)
                                Text(object.comment ?? object.type.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let rows = object.rows {
                                Text("\(rows) 行").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(schema)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: toastMessage)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let toastMessage {
                    TopToastView(message: toastMessage)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectCurrentDatabase()
                } label: {
                    Label("设为当前库", systemImage: "checkmark.circle")
                }
            }
        }
        .task { await load() }
    }

    private func selectCurrentDatabase() {
        session.selectDatabase(schema)
        toastMessage = "当前数据库已选择"

        let message = toastMessage
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func load() async {
        do {
            objects = try await session.fetchObjects(schema: schema)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TableDetailView: View {
    let schema: String
    let object: DBObjectItem
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("视图", selection: $selection) {
                Text("数据").tag(0)
                Text("结构").tag(1)
                Text("索引").tag(2)
                Text("DDL").tag(3)
                Text("设计").tag(4)
            }
            .pickerStyle(.segmented)
            .padding()

            switch selection {
            case 0: TableDataView(schema: schema, table: object.name)
            case 1: TableStructureView(schema: schema, table: object.name)
            case 2: IndexListView(schema: schema, table: object.name)
            case 3: CreateTableSQLView(schema: schema, table: object.name)
            default: TableDesignerView(schema: schema, table: object.name)
            }
        }
        .navigationTitle(object.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RoutineDetailView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    let object: DBObjectItem

    @State private var definition = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }

            routineSummaryCard

            VStack(alignment: .leading, spacing: 8) {
                Text("定义")
                    .font(.headline)
                SQLSyntaxTextEditor(text: $definition)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(object.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var routineSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: object.type.systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(object.name)
                        .font(.headline)
                    Text(object.type.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let comment = object.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func load() async {
        do {
            definition = try await session.showCreateRoutine(schema: object.schema, name: object.name, type: object.type)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TableStructureView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    let schema: String
    let table: String

    @State private var columns: [DBColumn] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                ErrorBanner(message: errorMessage).listRowBackground(Color.clear)
            }

            ForEach(columns) { column in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(column.name).font(.headline.monospaced())
                        Spacer()
                        if column.isPrimaryKey {
                            StatusBadge(text: "PK", systemImage: "key")
                        }
                    }
                    Text(column.displayType).font(.subheadline).foregroundStyle(.secondary)
                    if let comment = column.comment, !comment.isEmpty {
                        Text(comment).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            columns = try await session.fetchColumns(schema: schema, table: table)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct IndexListView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    let schema: String
    let table: String

    @State private var indexes: [DBIndex] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                ErrorBanner(message: errorMessage).listRowBackground(Color.clear)
            }

            ForEach(indexes) { index in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(index.name).font(.headline.monospaced())
                        Spacer()
                        if index.isUnique {
                            StatusBadge(text: "UNIQUE", systemImage: "seal")
                        }
                    }
                    Text(index.columns.joined(separator: ", "))
                    Text(index.indexType ?? "BTREE").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            indexes = try await session.fetchIndexes(schema: schema, table: table)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CreateTableSQLView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    let schema: String
    let table: String

    @State private var sql = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                Text(sql.isEmpty ? "正在加载..." : sql)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding()
        }
        .task { await load() }
    }

    private func load() async {
        do {
            sql = try await session.showCreateTable(schema: schema, table: table)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
