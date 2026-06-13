import SwiftUI
import SwiftData

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct MySQLClientMobileApp: App {
    #if canImport(MySQLNIO)
    @StateObject private var session = MySQLSessionStore(client: MySQLNIOClientService())
    #else
    @StateObject private var session = MySQLSessionStore(client: MockMySQLClientService())
    #endif
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        }
        .modelContainer(for: [
            ConnectionProfileEntity.self,
            QueryHistoryEntity.self,
            FavoriteSQLEntity.self
        ])
    }
}
