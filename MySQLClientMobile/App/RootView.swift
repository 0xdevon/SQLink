import SwiftUI
import LocalAuthentication

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("requireBiometrics") private var requireBiometrics = false
    @State private var isUnlocked = false
    @State private var authenticationMessage: String?

    var body: some View {
        ZStack {
            mainContent
                .blur(radius: shouldLock ? 16 : 0)
                .disabled(shouldLock)

            if shouldLock {
                BiometricLockView(message: authenticationMessage) {
                    authenticateIfNeeded()
                }
            }
        }
        .task {
            authenticateIfNeeded()
        }
        .onChange(of: requireBiometrics) { _, requiresAuthentication in
            if requiresAuthentication {
                lock()
                authenticateIfNeeded()
            } else {
                unlock()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lock()
            } else if phase == .active {
                authenticateIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                ConnectionListView(embedInNavigation: false)
            } content: {
                DatabaseListView(embedInNavigation: false)
            } detail: {
                SQLEditorView(embedInNavigation: false)
            }
        } else {
            TabView {
                ConnectionListView()
                    .tabItem { Label("连接", systemImage: "server.rack") }

                DatabaseListView()
                    .tabItem { Label("浏览", systemImage: "square.stack.3d.up") }

                SQLEditorView()
                    .tabItem { Label("查询", systemImage: "terminal") }

                QueryHistoryView()
                    .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }

                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
        }
    }

    private var shouldLock: Bool {
        requireBiometrics && !isUnlocked
    }

    private func authenticateIfNeeded() {
        guard requireBiometrics else {
            unlock()
            return
        }
        guard !isUnlocked else { return }

        Task {
            do {
                try await BiometricAuthenticator.authenticate(reason: "验证身份以打开 SQLink")
                unlock()
            } catch BiometricAuthenticationError.unavailable {
                requireBiometrics = false
                unlock()
            } catch {
                authenticationMessage = error.localizedDescription
            }
        }
    }

    private func lock() {
        guard requireBiometrics else { return }
        isUnlocked = false
    }

    private func unlock() {
        isUnlocked = true
        authenticationMessage = nil
    }
}

private struct BiometricLockView: View {
    let message: String?
    let authenticate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("需要验证身份")
                    .font(.title3.weight(.semibold))
                Text(message ?? "请使用 Face ID、Touch ID 或设备密码解锁应用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: authenticate) {
                Label("验证身份", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding()
    }
}

private enum BiometricAuthenticator {
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw BiometricAuthenticationError.unavailable(error)
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            throw BiometricAuthenticationError.failed(error)
        }
    }
}

private enum BiometricAuthenticationError: LocalizedError {
    case unavailable(NSError?)
    case failed(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "当前设备未设置可用的身份验证方式。"
        case .failed:
            "身份验证未通过，请重试。"
        }
    }
}
