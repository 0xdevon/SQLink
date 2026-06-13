import SwiftUI

enum AppTheme {
    static let cardCornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 14
    static let pagePadding: CGFloat = 16
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(32)
    }
}

struct StatusBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }
}

struct ActiveIndicatorBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.green.opacity(0.12), in: Capsule())
    }
}

struct TopToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.green)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 16, height: 16)
            .layoutPriority(1)

            Text(message)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.footnote)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
    }
}

struct DataGridView: View {
    let result: SQLQueryResult

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
