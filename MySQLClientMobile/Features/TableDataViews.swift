import SwiftUI

struct TableDataView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    let schema: String
    let table: String

    @State private var result = SQLQueryResult.empty
    @State private var tableColumns: [DBColumn] = []
    @State private var errorMessage: String?
    @State private var offset = 0
    @State private var limit = 50
    @State private var cardMode = false
    @State private var filters: [TableFilter] = []
    @State private var sort: TableSortDescriptor?
    @State private var showingFilterSheet = false
    @State private var showingSortSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("显示", selection: $cardMode) {
                    Text("表格").tag(false)
                    Text("卡片").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Spacer()

                Button { Task { await load(offset: max(0, offset - limit)) } } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(offset == 0)

                Text(result.rows.isEmpty ? "0" : "\(offset + 1)-\(offset + result.rows.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button { Task { await load(offset: offset + limit) } } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(result.rows.count < limit)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if sort != nil || !filters.isEmpty {
                TableActiveConditionBar(sort: sort, filters: filters) {
                    sort = nil
                    filters.removeAll()
                    Task { await load(offset: 0) }
                }
            }

            if let errorMessage {
                ErrorBanner(message: errorMessage).padding(.horizontal)
            }

            if cardMode {
                TableRowCardList(schema: schema, table: table, result: result) {
                    Task { await load(offset: offset) }
                }
            } else {
                TableDataGridView(schema: schema, table: table, result: result) {
                    Task { await load(offset: offset) }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingFilterSheet = true
                } label: {
                    Label("筛选", systemImage: filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }

                Button {
                    showingSortSheet = true
                } label: {
                    Label("排序", systemImage: sort == nil ? "arrow.up.arrow.down.circle" : "arrow.up.arrow.down.circle.fill")
                }

                NavigationLink {
                    RowEditView(schema: schema, table: table, row: nil, providedColumns: result.columns) {
                        Task { await load(offset: 0) }
                    }
                } label: {
                    Label("新增", systemImage: "plus")
                }

                Button {
                    showingImportSheet = true
                } label: {
                    Label("导入", systemImage: "tray.and.arrow.down")
                }

                Button {
                    showingExportSheet = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(result.columns.isEmpty)

                Button {
                    Task { await load(offset: offset) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            NavigationStack {
                TableFilterSheet(columns: tableColumns, filters: $filters) {
                    Task { await load(offset: 0) }
                }
            }
        }
        .sheet(isPresented: $showingSortSheet) {
            NavigationStack {
                TableSortSheet(columns: tableColumns, sort: $sort) {
                    Task { await load(offset: 0) }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            NavigationStack {
                ExportResultSheet(title: "导出表数据", result: result, baseFilename: "\(schema)_\(table)")
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            NavigationStack {
                CSVImportView(schema: schema, table: table, initialColumns: tableColumns) {
                    Task { await load(offset: 0) }
                }
            }
        }
        .task {
            await loadColumns()
            await load(offset: 0)
        }
    }

    private func loadColumns() async {
        do {
            tableColumns = try await session.fetchColumns(schema: schema, table: table)
        } catch {
            tableColumns = result.columns.enumerated().map { index, name in
                DBColumn(name: name, dataType: "text", columnType: "text", isNullable: true, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil, comment: nil, ordinalPosition: index + 1)
            }
        }
    }

    private func load(offset newOffset: Int) async {
        do {
            result = try await session.fetchTableData(schema: schema, table: table, limit: limit, offset: newOffset, sort: sort, filters: filters)
            if tableColumns.isEmpty {
                tableColumns = result.columns.enumerated().map { index, name in
                    DBColumn(name: name, dataType: "text", columnType: "text", isNullable: true, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil, comment: nil, ordinalPosition: index + 1)
                }
            }
            offset = newOffset
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TableActiveConditionBar: View {
    let sort: TableSortDescriptor?
    let filters: [TableFilter]
    let clearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let sort {
                    StatusBadge(text: "排序：\(sort.column) \(sort.direction.title)", systemImage: "arrow.up.arrow.down")
                }
                ForEach(filters) { filter in
                    StatusBadge(text: "\(filter.column) \(filter.op.title) \(filter.op.requiresValue ? filter.value : "")", systemImage: "line.3.horizontal.decrease")
                }
                Button("清空") { clearAll() }
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

private struct TableFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let columns: [DBColumn]
    @Binding var filters: [TableFilter]
    let onApply: () -> Void

    @State private var selectedColumn = ""
    @State private var selectedOperator: TableFilterOperator = .contains
    @State private var value = ""

    var body: some View {
        Form {
            if columns.isEmpty {
                Section {
                    Text("正在加载字段信息...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("新增筛选条件") {
                    Picker("字段", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column.name)
                        }
                    }

                    Picker("条件", selection: $selectedOperator) {
                        ForEach(TableFilterOperator.allCases) { op in
                            Text(op.title).tag(op)
                        }
                    }

                    if selectedOperator.requiresValue {
                        TextField("筛选值", text: $value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Button("添加条件") { addFilter() }
                        .disabled(selectedColumn.isEmpty || (selectedOperator.requiresValue && value.isEmpty))
                }

                if !filters.isEmpty {
                    Section("当前条件") {
                        ForEach(filters) { filter in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(filter.column)
                                        .font(.headline.monospaced())
                                    Text("\(filter.op.title) \(filter.op.requiresValue ? filter.value : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    filters.removeAll { $0.id == filter.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }

                        Button("清空全部", role: .destructive) {
                            filters.removeAll()
                        }
                    }
                }
            }
        }
        .navigationTitle("筛选")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("应用") {
                    onApply()
                    dismiss()
                }
            }
        }
        .onAppear {
            if selectedColumn.isEmpty {
                selectedColumn = columns.first?.name ?? ""
            }
        }
    }

    private func addFilter() {
        filters.append(TableFilter(column: selectedColumn, op: selectedOperator, value: value))
        value = ""
    }
}

private struct TableSortSheet: View {
    @Environment(\.dismiss) private var dismiss
    let columns: [DBColumn]
    @Binding var sort: TableSortDescriptor?
    let onApply: () -> Void

    @State private var selectedColumn = ""
    @State private var direction: TableSortDirection = .ascending

    var body: some View {
        Form {
            if columns.isEmpty {
                Section {
                    Text("正在加载字段信息...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("排序规则") {
                    Picker("字段", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column.name)
                        }
                    }

                    Picker("方向", selection: $direction) {
                        ForEach(TableSortDirection.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .navigationTitle("排序")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button("清除") {
                    sort = nil
                    onApply()
                    dismiss()
                }
                Button("应用") {
                    if !selectedColumn.isEmpty {
                        sort = TableSortDescriptor(column: selectedColumn, direction: direction)
                    }
                    onApply()
                    dismiss()
                }
                .disabled(selectedColumn.isEmpty)
            }
        }
        .onAppear {
            selectedColumn = sort?.column ?? columns.first?.name ?? ""
            direction = sort?.direction ?? .ascending
        }
    }
}

private struct TableDataGridView: View {
    let schema: String
    let table: String
    let result: SQLQueryResult
    let onChanged: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                headerGrid
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(.regularMaterial)

                Divider()
                    .padding(.horizontal)

                ScrollView(.vertical) {
                    rowGrid
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("操作")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .leading)

                ForEach(result.columns, id: \.self) { column in
                    Text(column)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 110, alignment: .leading)
                }
            }
        }
    }

    private var rowGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    NavigationLink {
                        RowDetailView(schema: schema, table: table, columns: result.columns, row: row, onChanged: onChanged)
                    } label: {
                        Text("详情")
                            .font(.caption.weight(.medium))
                    }
                    .frame(minWidth: 70, alignment: .leading)

                    ForEach(result.columns, id: \.self) { column in
                        Text(row[column].flatMap { $0 } ?? "NULL")
                            .font(.callout.monospaced())
                            .lineLimit(2)
                            .frame(minWidth: 110, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct TableRowCardList: View {
    let schema: String
    let table: String
    let result: SQLQueryResult
    let onChanged: () -> Void

    var body: some View {
        List {
            ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                NavigationLink {
                    RowDetailView(schema: schema, table: table, columns: result.columns, row: row, onChanged: onChanged)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.columns.prefix(4), id: \.self) { column in
                            HStack(alignment: .top) {
                                Text(column)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 92, alignment: .leading)
                                Text(row[column].flatMap { $0 } ?? "NULL")
                                    .font(.callout.monospaced())
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

struct RowDetailView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    @Environment(\.dismiss) private var dismiss

    let schema: String
    let table: String
    let columns: [String]
    let row: [String: String?]
    let onChanged: () -> Void

    @State private var tableColumns: [DBColumn] = []
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        List {
            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .listRowBackground(Color.clear)
            }

            ForEach(columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: 8) {
                    Text(column)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row[column].flatMap { $0 } ?? "NULL")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("行详情")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    RowEditView(schema: schema, table: table, row: row, providedColumns: columns) {
                        onChanged()
                    }
                } label: {
                    Label("编辑", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(isDeleting)
            }
        }
        .confirmationDialog("确认删除当前行？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await deleteCurrentRow() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除会直接写入当前数据库，建议确认当前连接和数据库后再继续。")
        }
        .task { await loadColumns() }
    }

    private func loadColumns() async {
        do {
            tableColumns = try await session.fetchColumns(schema: schema, table: table)
        } catch {
            tableColumns = fallbackColumns()
        }
    }

    private func deleteCurrentRow() async {
        do {
            isDeleting = true
            let metadata = tableColumns.isEmpty ? fallbackColumns() : tableColumns
            _ = try await session.deleteRow(schema: schema, table: table, row: row, columns: metadata)
            errorMessage = nil
            isDeleting = false
            onChanged()
            dismiss()
        } catch {
            isDeleting = false
            errorMessage = error.localizedDescription
        }
    }

    private func fallbackColumns() -> [DBColumn] {
        columns.enumerated().map { index, name in
            DBColumn(name: name, dataType: "text", columnType: "text", isNullable: true, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil, comment: nil, ordinalPosition: index + 1)
        }
    }
}

struct RowEditView: View {
    @EnvironmentObject private var session: MySQLSessionStore
    @Environment(\.dismiss) private var dismiss

    let schema: String
    let table: String
    let row: [String: String?]?
    let providedColumns: [String]
    let onSaved: () -> Void

    @State private var columns: [DBColumn] = []
    @State private var values: [String: String] = [:]
    @State private var nullColumns = Set<String>()
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSaving = false
    @State private var didInitialize = false

    private var formColumns: [DBColumn] {
        let source = columns.isEmpty ? fallbackColumns() : columns
        if row == nil {
            return source.filter { !$0.isAutoIncrement }
        }
        return source
    }

    var body: some View {
        Form {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }
            }

            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            Section {
                if formColumns.isEmpty {
                    Text("正在加载字段元数据...")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(formColumns) { column in
                        RowValueEditor(
                            column: column,
                            text: Binding(
                                get: { values[column.name] ?? "" },
                                set: { values[column.name] = $0 }
                            ),
                            isNull: Binding(
                                get: { nullColumns.contains(column.name) },
                                set: { isNull in
                                    if isNull {
                                        nullColumns.insert(column.name)
                                    } else {
                                        nullColumns.remove(column.name)
                                    }
                                }
                            )
                        )
                    }
                }
            } header: {
                Text(row == nil ? "新增数据" : "编辑数据")
            } footer: {
                Text("空字符串会按空字符串保存；需要保存数据库 NULL 时，请打开对应字段的「存为 NULL」。日期、数字、JSON 等字段会给出输入提示，但当前版本仍按 SQL 字面量提交。")
            }
        }
        .navigationTitle(row == nil ? "新增行" : "编辑行")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "保存中..." : "保存") {
                    Task { await save() }
                }
                .disabled(isSaving || formColumns.isEmpty)
            }
        }
        .task { await loadColumnsAndInitialize() }
    }

    private func loadColumnsAndInitialize() async {
        do {
            columns = try await session.fetchColumns(schema: schema, table: table)
            errorMessage = nil
        } catch {
            columns = fallbackColumns()
            errorMessage = "字段元数据加载失败，已使用当前结果集字段生成表单。\n\(error.localizedDescription)"
        }
        initializeValuesIfNeeded()
    }

    private func initializeValuesIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true

        let source = formColumns
        if let row {
            for column in source {
                if let value = row[column.name] ?? nil {
                    values[column.name] = value
                } else {
                    values[column.name] = defaultValueForEditor(column)
                    if column.isNullable {
                        nullColumns.insert(column.name)
                    }
                }
            }
        } else {
            for column in source {
                values[column.name] = defaultValueForEditor(column)
                if column.isNullable && column.defaultValue == nil {
                    nullColumns.insert(column.name)
                }
            }
        }
    }

    private func defaultValueForEditor(_ column: DBColumn) -> String {
        if column.valueKind == .boolean { return "0" }
        if column.valueKind == .enumeration { return column.enumValues.first ?? "" }
        return ""
    }

    private func save() async {
        do {
            isSaving = true
            let metadata = columns.isEmpty ? fallbackColumns() : columns
            let payload = makePayload(columns: formColumns)
            let result: SQLQueryResult

            if let row {
                result = try await session.updateRow(schema: schema, table: table, originalRow: row, values: payload, columns: metadata)
            } else {
                result = try await session.insertRow(schema: schema, table: table, values: payload, columns: metadata)
            }

            successMessage = result.message ?? "保存成功"
            errorMessage = nil
            isSaving = false
            onSaved()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private func makePayload(columns: [DBColumn]) -> [String: String?] {
        var payload: [String: String?] = [:]
        for column in columns {
            if row == nil && column.isAutoIncrement { continue }

            if nullColumns.contains(column.name) {
                payload.updateValue(nil, forKey: column.name)
                continue
            }

            let value = values[column.name] ?? ""
            if row == nil && value.isEmpty && column.defaultValue != nil {
                continue
            }
            payload.updateValue(value, forKey: column.name)
        }
        return payload
    }

    private func fallbackColumns() -> [DBColumn] {
        providedColumns.enumerated().map { index, name in
            DBColumn(name: name, dataType: "text", columnType: "text", isNullable: true, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil, comment: nil, ordinalPosition: index + 1)
        }
    }
}

private struct RowValueEditor: View {
    let column: DBColumn
    @Binding var text: String
    @Binding var isNull: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name)
                    .font(.headline.monospaced())
                Spacer()
                Text(column.columnType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if column.isNullable {
                Toggle("存为 NULL", isOn: $isNull)
                    .font(.caption)
            }

            inputControl
                .disabled(isNull || column.valueKind == .binary)

            Text(column.valueKind.inputHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let comment = column.comment, !comment.isEmpty {
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var inputControl: some View {
        switch column.valueKind {
        case .boolean:
            Picker("值", selection: $text) {
                Text("0 / false").tag("0")
                Text("1 / true").tag("1")
            }
            .pickerStyle(.segmented)

        case .enumeration:
            Picker("值", selection: $text) {
                ForEach(column.enumValues, id: \.self) { value in
                    Text(value).tag(value)
                }
            }

        case .integer:
            TextField(column.defaultValue.map { "默认：\($0)" } ?? column.valueKind.inputHint, text: $text)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

        case .decimal:
            TextField(column.defaultValue.map { "默认：\($0)" } ?? column.valueKind.inputHint, text: $text)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

        case .longText, .json:
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .binary:
            TextField("二进制字段暂不支持直接编辑", text: $text)
                .disabled(true)

        default:
            TextField(column.defaultValue.map { "默认：\($0)" } ?? column.valueKind.inputHint, text: $text, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        }
    }
}
