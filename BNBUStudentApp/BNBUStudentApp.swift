import SwiftUI
import UIKit
import UserNotifications

@main
struct BNBUStudentApp: App {
    @UIApplicationDelegateAdaptor(BNBUAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var languageSettings: BNBULanguageSettings
    @AppStorage(BNBUAppearanceMode.defaultsKey) private var appearanceModeRaw = BNBUAppearanceMode.light.rawValue
    @State private var systemLocaleIdentifier: String
    @State private var showOnboarding = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-reset") {
            AppLocalStore().clearAll()
            BNBUPrivacyConsent.clearAll()
            UserDefaults.standard.set(
                BNBULanguage.defaultMode.rawValue,
                forKey: BNBULanguage.defaultsKey
            )
        }
        if arguments.contains("-ui-testing-language-en") {
            UserDefaults.standard.set(
                BNBULanguage.english.rawValue,
                forKey: BNBULanguage.defaultsKey
            )
        }
        _languageSettings = StateObject(wrappedValue: BNBULanguageSettings())
        _systemLocaleIdentifier = State(initialValue: Self.preferredSystemLocaleIdentifier)
        let repository: StudentRepository = arguments.contains("-ui-testing-empty-state") ? EmptyStudentRepository() : MockStudentRepository()
        let state = AppState(repository: repository)
        if arguments.contains("-ui-testing-reset") {
            // Flow tests must not depend on the wall clock.
            state.enforcesCheckInTimeWindow = false
        }
        if arguments.contains("-ui-testing-authenticated") {
            state.demoLogin()
        }
#if DEBUG
        if arguments.contains("-ui-testing-completed-exercise") {
            state.installCompletedExerciseSessionForUITesting()
        }
        if arguments.contains("-ui-testing-active-exercise") {
            state.installActiveExerciseSessionForUITesting()
        }
#endif
        _appState = StateObject(wrappedValue: state)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    AppRootView()
                        .onAppear {
                            guard !isUITesting else { return }
                            if BNBUOnboarding.completedVersion(
                                studentID: appState.workspace.student.id
                            ) < BNBUOnboarding.currentVersion {
                                showOnboarding = true
                            } else {
                                BNBUNotificationManager.requestAuthorization()
                            }
                        }
                        .fullScreenCover(isPresented: $showOnboarding) {
                            OnboardingView {
                                BNBUOnboarding.markCompleted(
                                    studentID: appState.workspace.student.id
                                )
                                showOnboarding = false
                                BNBUNotificationManager.requestAuthorization()
                            }
                        }
                } else {
                    LoginView()
                }
            }
            .environmentObject(appState)
            .environmentObject(languageSettings)
            .environment(\.locale, resolvedLocale)
            .tint(BNBUTheme.primary)
            .preferredColorScheme(appearanceMode.colorScheme)
            .onChange(of: languageSettings.mode) { _, newMode in
                if newMode == .system {
                    refreshSystemLocale()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                refreshSystemLocale()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshSystemLocale()
                }
            }
        }
    }

    private var appearanceMode: BNBUAppearanceMode {
        BNBUAppearanceMode(rawValue: appearanceModeRaw) ?? .light
    }

    private var resolvedLocale: Locale {
        if languageSettings.mode == .system {
            return Locale(identifier: systemLocaleIdentifier)
        }
        return languageSettings.mode.locale
    }

    private static var preferredSystemLocaleIdentifier: String {
        BNBULanguage.supportedSystemLocaleIdentifier()
    }

    private func refreshSystemLocale() {
        systemLocaleIdentifier = Self.preferredSystemLocaleIdentifier
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-reset")
    }
}

final class BNBUAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = BNBUNotificationManager.route(from: response.notification.request.content.userInfo)
        DispatchQueue.main.async {
            if let route {
                NotificationCenter.default.post(name: .bnbuOpenDestination, object: route)
            }
            completionHandler()
        }
    }
}

enum BNBUNotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    static func route(from userInfo: [AnyHashable: Any]) -> AppTab? {
        let value = (userInfo["route"] ?? userInfo["target"] ?? userInfo["type"]) as? String
        guard let normalized = value?.lowercased() else { return .dashboard }
        switch normalized {
        case "course", "courses": return .courses
        case "checkin", "sport_record", "sport-record": return .checkin
        case "grade", "grades", "score": return .grades
        case "profile", "exemption", "application": return .profile
        default: return .dashboard
        }
    }
}

extension Notification.Name {
    static let bnbuOpenDestination = Notification.Name("bnbu.open-destination")
}
