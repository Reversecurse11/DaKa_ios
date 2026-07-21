import SwiftUI

@main
struct BNBUStudentApp: App {
    @StateObject private var appState: AppState
    @AppStorage(BNBUAppearanceMode.defaultsKey) private var appearanceModeRaw = BNBUAppearanceMode.light.rawValue

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-reset") {
            AppLocalStore().clearAll()
        }
        let repository: StudentRepository = arguments.contains("-ui-testing-empty-state") ? EmptyStudentRepository() : MockStudentRepository()
        let state = AppState(repository: repository)
        if arguments.contains("-ui-testing-authenticated") {
            state.demoLogin()
        }
        _appState = StateObject(wrappedValue: state)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    AppRootView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(appState)
            .tint(BNBUTheme.primary)
            .preferredColorScheme(appearanceMode.colorScheme)
        }
    }

    private var appearanceMode: BNBUAppearanceMode {
        BNBUAppearanceMode(rawValue: appearanceModeRaw) ?? .light
    }
}
