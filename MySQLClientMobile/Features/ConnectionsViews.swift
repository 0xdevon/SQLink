import SwiftUI
import SwiftData

private enum ConnectionEditorDestination: Identifiable {
    case new
    case edit(ConnectionProfileEntity)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let connection):
            return "edit-\(connection.id.uuidString)"
        }
    }

    var connection: ConnectionProfileEntity? {
        switch self {
        case .new:
            return nil
        case .edit(let connection):
            return connection
        }
    }
}

struct ConnectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: MySQLSessionStore
    @Query(sort: \ConnectionProfileEntity.updatedAt, order: .reverse) private var connections: [ConnectionProfileEntity]

    var embedInNavigation: Bool = true
    @State private var editorDestination: ConnectionEditorDestination?
    @State private var toastMessage: String?

    var body: some View {
        Group {
            if embedInNavigation {
                NavigationStack { mainList }
            } else {
                mainList
            }
        }
        .sheet(item: $editorDestination) { destination in
            ConnectionEditView(connection: destination.connection)
        }
    }

    private var mainList: some View {
        List {
            if let toastMessage {
                Text(toastMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if connections.isEmpty {
                EmptyStateView(systemImage: "server.rack", title: "还没有连接", message: "新建一个 MySQL 连接后，即可浏览数据库、表结构和执行 SQL。")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(connections) { connection in
                    ConnectionRowView(connection: connection, isActive: isCurrentConnection(connection))
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(connection) } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button { edit(connection) } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                        }
                        .contextMenu {
                            Button { connect(connection) } label: {
                                Label("连接", systemImage: "link")
                            }
                            Button(role: .destructive) { disconnect(connection) } label: {
                                Label("断开连接", systemImage: "power")
                            }
                            .disabled(!isCurrentConnection(connection))
                            Button { test(connection) } label: {
                                Label("测试连接", systemImage: "checkmark.circle")
                            }
                            Button { edit(connection) } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                        }
                        .onTapGesture { connect(connection) }
                }
            }
        }
        .navigationTitle("连接")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorDestination = .new
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
    }

    private func edit(_ connection: ConnectionProfileEntity) {
        editorDestination = .edit(connection)
    }

    private func connect(_ connection: ConnectionProfileEntity) {
        Task {
            let password = (try? KeychainService.shared.readPassword(for: connection.passwordKey)) ?? ""
            await session.connect(profile: connection.toProfile(), password: password)
            toastMessage = session.isConnected ? "已连接：\(connection.name)" : session.lastErrorMessage
        }
    }

    private func disconnect(_ connection: ConnectionProfileEntity) {
        Task {
            await session.disconnect()
            toastMessage = "已断开连接：\(connection.name)"
        }
    }

    private func test(_ connection: ConnectionProfileEntity) {
        Task {
            do {
                let password = (try? KeychainService.shared.readPassword(for: connection.passwordKey)) ?? ""
                let version = try await session.testConnection(profile: connection.toProfile(), password: password)
                toastMessage = "测试成功：\(version)"
            } catch {
                toastMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ connection: ConnectionProfileEntity) {
        try? KeychainService.shared.deletePassword(for: connection.passwordKey)
        modelContext.delete(connection)
        try? modelContext.save()
    }

    private func isCurrentConnection(_ connection: ConnectionProfileEntity) -> Bool {
        session.isConnected && session.currentConnection?.id == connection.id
    }
}

struct ConnectionRowView: View {
    let connection: ConnectionProfileEntity
    let isActive: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: connection.isFavorite ? "star.circle.fill" : "server.rack")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(connection.isFavorite ? .yellow : .secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text(connection.name).font(.headline)
                Text("\(connection.host):\(connection.port) · \(connection.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    if let db = connection.defaultDatabase, !db.isEmpty {
                        StatusBadge(text: db, systemImage: "cylinder.split.1x2")
                    }
                    if connection.readOnlyMode {
                        StatusBadge(text: "只读", systemImage: "lock")
                    }
                    if connection.useTLS {
                        StatusBadge(text: "TLS", systemImage: "checkmark.shield")
                    }
                }
            }

            Spacer()

            if isActive {
                ActiveIndicatorBadge(text: "已连接")
            }
        }
        .padding(.vertical, 6)
    }
}

struct ConnectionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: MySQLSessionStore

    let connection: ConnectionProfileEntity?

    @State private var name: String
    @State private var groupName: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var defaultDatabase: String
    @State private var useTLS: Bool
    @State private var readOnlyMode: Bool
    @State private var isFavorite: Bool
    @State private var message: String?

    init(connection: ConnectionProfileEntity?) {
        self.connection = connection
        _name = State(initialValue: connection?.name ?? "")
        _groupName = State(initialValue: connection?.groupName ?? "")
        _host = State(initialValue: connection?.host ?? "")
        _port = State(initialValue: String(connection?.port ?? 3306))
        _username = State(initialValue: connection?.username ?? "")
        _password = State(initialValue: "")
        _defaultDatabase = State(initialValue: connection?.defaultDatabase ?? "")
        _useTLS = State(initialValue: connection?.useTLS ?? true)
        _readOnlyMode = State(initialValue: connection?.readOnlyMode ?? false)
        _isFavorite = State(initialValue: connection?.isFavorite ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }

                Section("基础信息") {
                    TextField("连接名称", text: $name)
                    TextField("分组，可选", text: $groupName)
                    TextField("主机地址", text: $host)
                        .textInputAutocapitalization(.never)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }

                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField(connection == nil ? "密码" : "密码，留空则保持不变", text: $password)
                    TextField("默认数据库，可选", text: $defaultDatabase)
                        .textInputAutocapitalization(.never)
                }

                Section("安全") {
                    Toggle("使用 TLS", isOn: $useTLS)
                    Toggle("只读模式", isOn: $readOnlyMode)
                    Toggle("收藏连接", isOn: $isFavorite)
                }

                Section {
                    Button("测试连接") { testConnection() }
                }
            }
            .navigationTitle(connection == nil ? "新建连接" : "编辑连接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty && Int(port) != nil
    }

    private func save() {
        do {
            if let connection {
                connection.update(
                    name: name,
                    groupName: groupName.nilIfBlank,
                    host: host,
                    port: Int(port) ?? 3306,
                    username: username,
                    defaultDatabase: defaultDatabase.nilIfBlank,
                    useTLS: useTLS,
                    readOnlyMode: readOnlyMode,
                    isFavorite: isFavorite
                )
                if !password.isEmpty {
                    try KeychainService.shared.savePassword(password, for: connection.passwordKey)
                }
            } else {
                let entity = ConnectionProfileEntity(
                    name: name,
                    groupName: groupName.nilIfBlank,
                    host: host,
                    port: Int(port) ?? 3306,
                    username: username,
                    defaultDatabase: defaultDatabase.nilIfBlank,
                    useTLS: useTLS,
                    readOnlyMode: readOnlyMode,
                    isFavorite: isFavorite
                )
                modelContext.insert(entity)
                if !password.isEmpty {
                    try KeychainService.shared.savePassword(password, for: entity.passwordKey)
                }
            }
            try modelContext.save()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func testConnection() {
        Task {
            do {
                let profile = DBConnectionProfile(
                    id: connection?.id ?? UUID(),
                    name: name,
                    groupName: groupName.nilIfBlank,
                    host: host,
                    port: Int(port) ?? 3306,
                    username: username,
                    defaultDatabase: defaultDatabase.nilIfBlank,
                    useTLS: useTLS,
                    readOnlyMode: readOnlyMode,
                    isFavorite: isFavorite
                )
                let stored = connection.flatMap { try? KeychainService.shared.readPassword(for: $0.passwordKey) } ?? ""
                let version = try await session.testConnection(profile: profile, password: password.isEmpty ? stored : password)
                message = "测试成功：\(version)"
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
