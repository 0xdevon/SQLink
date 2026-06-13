import SwiftUI

struct TableDesignerView: View {
    let schema: String
    let table: String

    @State private var columns: [DBColumn] = []
    @State private var showingColumnEditor = false

    var body: some View {
        List {
            Section("字段") {
                if columns.isEmpty {
                    Text("新增或修改字段后，会在下方生成 ALTER SQL 预览。")
                        .foregroundStyle(.secondary)
                }

                ForEach(columns) { column in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(column.name).font(.headline.monospaced())
                        Text(column.displayType).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("ALTER SQL 预览") {
                Text(generatedSQL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .toolbar {
            Button { showingColumnEditor = true } label: {
                Label("新增字段", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingColumnEditor) {
            ColumnEditorSheet { column in
                columns.append(column)
            }
        }
    }

    private var generatedSQL: String {
        guard !columns.isEmpty else {
            return "-- 修改字段后将在这里预览 ALTER TABLE SQL"
        }
        return columns.map { column in
            "ALTER TABLE \(SQLBuilder.quotedIdentifier(schema)).\(SQLBuilder.quotedIdentifier(table)) ADD COLUMN \(SQLBuilder.quotedIdentifier(column.name)) \(column.columnType);"
        }.joined(separator: "\n")
    }
}

struct ColumnEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (DBColumn) -> Void

    @State private var name = ""
    @State private var type = "varchar(255)"
    @State private var nullable = true
    @State private var primaryKey = false
    @State private var autoIncrement = false
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("字段名", text: $name)
                TextField("字段类型，例如 varchar(255)", text: $type)
                Toggle("允许 NULL", isOn: $nullable)
                Toggle("主键", isOn: $primaryKey)
                Toggle("自增", isOn: $autoIncrement)
                TextField("注释", text: $comment)
            }
            .navigationTitle("字段")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(DBColumn(
                            name: name,
                            dataType: type.components(separatedBy: "(").first ?? type,
                            columnType: type,
                            isNullable: nullable,
                            isPrimaryKey: primaryKey,
                            isAutoIncrement: autoIncrement,
                            defaultValue: nil,
                            comment: comment.isEmpty ? nil : comment,
                            ordinalPosition: 0
                        ))
                        dismiss()
                    }
                    .disabled(name.isEmpty || type.isEmpty)
                }
            }
        }
    }
}
