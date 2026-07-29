import SwiftUI

/// Device-level privacy acceptance. Android gates the whole app on this before
/// authentication (`AuthUiState.PrivacyConsent`), so the record cannot be keyed
/// by account: there is no account yet when the gate is shown.
enum BNBUDevicePrivacyConsent {
    static let currentVersion = BNBUPrivacyConsent.currentVersion
    static let defaultsKey = "bnbu.privacy.consent.device.v1"

    static func hasAccepted(defaults: UserDefaults = .standard) -> Bool {
        guard let record = defaults.dictionary(forKey: defaultsKey) else { return false }
        return record["version"] as? String == currentVersion &&
            record["acceptedAt"] as? String != nil
    }

    static func recordAcceptance(defaults: UserDefaults = .standard) {
        defaults.set(
            [
                "version": currentVersion,
                "acceptedAt": ISO8601DateFormatter().string(from: Date())
            ],
            forKey: defaultsKey
        )
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// Tracks whether this device has already seen the pre-login course guide, so
/// the guide only interrupts a genuinely first launch.
enum BNBUPreLoginGuide {
    static let defaultsKey = "bnbu.guide.pre-login.seen.v1"

    static func hasSeen(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// Mirrors Android's `AuthUiState` gate order: restore the session, ask for
/// privacy consent, then show the first-launch course guide before the sign-in
/// page.
enum AppShellStage: Equatable {
    case restoring
    case privacyConsent
    case preLoginGuide
    case login
    case authenticated

    /// Evaluated before the first frame so a launch whose state is already known
    /// renders its destination directly. Swapping the root view one frame later
    /// made the tab bar drop the accessibility identifiers set on its items.
    /// `restoring` stays for the asynchronous token restore that lands with the
    /// remote session work.
    static func resolved(
        isAuthenticated: Bool,
        isUITesting: Bool,
        showsStartupGates: Bool,
        defaults: UserDefaults = .standard
    ) -> AppShellStage {
        if isAuthenticated { return .authenticated }
        // Flow tests start on the sign-in page so they do not have to walk the
        // gates every time; `-ui-testing-startup-gates` opts back in.
        guard !isUITesting || showsStartupGates else { return .login }
        guard BNBUDevicePrivacyConsent.hasAccepted(defaults: defaults) else {
            return .privacyConsent
        }
        return BNBUPreLoginGuide.hasSeen(defaults: defaults) ? .login : .preLoginGuide
    }
}

struct AppShellView: View {
    @EnvironmentObject private var appState: AppState

    let isUITesting: Bool
    @Binding var stage: AppShellStage

    @State private var presentsCourseJoin = false

    private var showsStartupGatesInUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-startup-gates")
    }

    var body: some View {
        Group {
            switch stage {
            case .restoring:
                StartupSplashView()
            case .privacyConsent:
                PrivacyConsentView(
                    onAgree: {
                        BNBUDevicePrivacyConsent.recordAcceptance()
                        advanceFromConsent()
                    },
                    onDecline: { stage = .privacyConsent }
                )
            case .preLoginGuide:
                PreLoginCourseGuideView(
                    onStartJoin: {
                        BNBUPreLoginGuide.markSeen()
                        stage = .login
                        presentsCourseJoin = true
                    },
                    onSkipToLogin: {
                        BNBUPreLoginGuide.markSeen()
                        stage = .login
                    }
                )
            case .login:
                LoginView()
                    // Android reaches `ScanJoinScreen` from the pre-login guide,
                    // so scanning works before sign-in; submitting still requires
                    // an account.
                    .sheet(isPresented: $presentsCourseJoin) {
                        CourseJoinSheet()
                            .environmentObject(appState)
                    }
            case .authenticated:
                AuthenticatedShellView(isUITesting: isUITesting)
            }
        }
        .animation(.easeInOut(duration: BNBUMotion.standard), value: stage)
        .onAppear(perform: resolveInitialStage)
        .onChange(of: appState.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                stage = .authenticated
            } else if stage == .authenticated {
                stage = .login
            }
        }
    }

    private func resolveInitialStage() {
        guard stage == .restoring else { return }
        stage = .resolved(
            isAuthenticated: appState.isAuthenticated,
            isUITesting: isUITesting,
            showsStartupGates: showsStartupGatesInUITesting
        )
    }

    private func advanceFromConsent() {
        stage = BNBUPreLoginGuide.hasSeen() ? .login : .preLoginGuide
    }
}

/// The authenticated shell keeps the onboarding cover and notification
/// permission prompt attached to the tab shell, matching Android's
/// `AuthenticatedAppContent`.
private struct AuthenticatedShellView: View {
    @EnvironmentObject private var appState: AppState

    let isUITesting: Bool
    @State private var showOnboarding = false

    var body: some View {
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
    }
}

// MARK: - Startup

/// Android's `StartupSplashScreen`: brand lockup, spinner, and a single status
/// line while the stored session is restored.
struct StartupSplashView: View {
    var body: some View {
        ZStack {
            BNBUPageBackground()
            VStack(spacing: 28) {
                BNBUBrandLockup()
                VStack(spacing: BNBUSpacing.space12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在恢复登录状态…")
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
            }
        }
        .accessibilityIdentifier("screen.startup")
    }
}

// MARK: - Privacy consent gate

/// Android's `PrivacyConsentScreen`. Declining cannot terminate an iOS app the
/// way `finishAndRemoveTask()` does on Android, so the decline action explains
/// that the app stays unusable instead of silently doing nothing.
struct PrivacyConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    @State private var showFullPolicy = false
    @State private var showDeclineNotice = false

    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("BNBU SPORTS")
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.primary)
                        .padding(.bottom, 20)

                    Text("开始使用前，请确认")
                        .font(BNBUFont.headlineLarge)
                        .tracking(BNBUFont.Tracking.headlineLarge)
                        .foregroundStyle(BNBUTheme.onBackground)
                        .padding(.bottom, BNBUSpacing.space12)

                    Text("请阅读并同意隐私政策。我们会以清晰、必要的方式处理信息，为你提供体育教学服务。")
                        .font(BNBUFont.bodyLarge)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .lineSpacing(BNBUFont.LineSpacing.bodyLarge)
                        .padding(.bottom, BNBUSpacing.space32)

                    summaryPanel
                        .padding(.bottom, BNBUSpacing.space32)

                    Button(action: onAgree) {
                        Text("同意并继续")
                            .font(BNBUFont.labelLarge)
                            .frame(maxWidth: .infinity)
                            .frame(height: BNBUSpacing.primaryControlHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: BNBURadius.medium))
                    .accessibilityIdentifier("privacy.consent.agree")

                    Button {
                        showDeclineNotice = true
                        onDecline()
                    } label: {
                        Text("不同意并退出")
                            .font(BNBUFont.labelLarge)
                            .frame(maxWidth: .infinity)
                            .frame(height: BNBUSpacing.touchTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BNBUTheme.primary)
                    .accessibilityIdentifier("privacy.consent.decline")

                    Text("同意后，你仍可在“我的 — 设置 — 隐私政策”中随时查看最新版本。")
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .padding(.top, BNBUSpacing.space12)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.top, BNBUSpacing.space32)
                .padding(.bottom, BNBUSpacing.space24)
            }
        }
        .sheet(isPresented: $showFullPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("返回") { showFullPolicy = false }
                                .accessibilityIdentifier("privacy.consent.policy.back")
                        }
                    }
            }
        }
        .alert("需要同意后才能使用", isPresented: $showDeclineNotice) {
            Button("我知道了", role: .cancel) {}
        } message: {
            Text("未同意隐私政策时无法进入应用。你可以直接关闭 App，或在同意后继续使用。")
        }
        .accessibilityIdentifier("screen.privacy.consent")
    }

    private var summaryPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 0) {
                Text("我们如何处理你的信息")
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .padding(.bottom, BNBUSpacing.space12)

                // Deliberately not a copy of Android's wording: it promises no
                // audio recording and names an Android-only push service. This
                // build declares NSMicrophoneUsageDescription for in-app video and
                // has no remote push registration yet, so the disclosure has to
                // describe what iOS actually does.
                Text("为完成体育教学服务，我们会处理学号、姓名、课程、成绩和运动打卡记录。仅在你主动使用相关功能时调用相机、读取你选择的图片或视频，并在前台单次获取位置。录制现场视频会同时使用麦克风记录声音。系统通知目前在本机生成，不上传推送标识。上述信息不用于广告或个性化推荐。")
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(BNBUFont.LineSpacing.bodyMedium)
                    .padding(.bottom, BNBUSpacing.space16)

                Button {
                    showFullPolicy = true
                } label: {
                    Text("查看完整隐私政策")
                        .font(BNBUFont.labelLarge)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BNBUTheme.primary)
                .accessibilityIdentifier("privacy.consent.full-policy")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Pre-login course guide

/// Android's `PreLoginCourseGuideScreen`: a two-step pager explaining that a
/// course QR code or invitation code is needed before signing in.
struct PreLoginCourseGuideView: View {
    let onStartJoin: () -> Void
    let onSkipToLogin: () -> Void

    var body: some View {
        BNBUGuideFlow(
            headerTitle: "加入课程",
            steps: Self.steps,
            skipLabel: "直接登录",
            skipDescription: "跳过加入课程指引并进入登录页",
            finalActionLabel: "开始加入课程",
            onSkip: onSkipToLogin,
            onFinish: onStartJoin,
            screenIdentifier: "screen.guide.pre-login"
        )
    }

    static let steps: [BNBUGuideStep] = [
        BNBUGuideStep(
            eyebrow: "准备课程二维码或邀请码",
            title: "先加入课程",
            detail: "老师会提供课程二维码或邀请码。扫码或手动输入后，即可找到对应课程。",
            artwork: .courseJoin
        ),
        BNBUGuideStep(
            eyebrow: "核对信息后再加入",
            title: "确认并提交申请",
            detail: "核对课程和个人资料后提交加入申请；如需补正或等待审核，按页面提示处理。",
            artwork: .joinRequest
        )
    ]
}

struct BNBUGuideStep: Identifiable {
    enum Artwork {
        case courseJoin
        case joinRequest
    }

    let id = UUID()
    let eyebrow: String
    let title: String
    let detail: String
    let artwork: Artwork
}

/// Android's `GuidePagerScreen`: a fixed 64pt header (back / centred title /
/// skip), a horizontal pager, and a footer with page dots plus the primary
/// action.
struct BNBUGuideFlow: View {
    let headerTitle: String
    let steps: [BNBUGuideStep]
    let skipLabel: String
    let skipDescription: String
    let finalActionLabel: String
    let onSkip: () -> Void
    let onFinish: () -> Void
    /// Applied to the backdrop rather than to the flow: an identifier on the
    /// container overwrites the identifiers of the buttons inside it.
    let screenIdentifier: String

    @State private var page = 0

    private var isLastPage: Bool { page >= steps.count - 1 }

    var body: some View {
        ZStack {
            BNBUPageBackground()
                .accessibilityIdentifier(screenIdentifier)
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepContent(step, isActive: page == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                footer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            if page > 0 {
                Button {
                    withAnimation { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(BNBUFont.titleMedium)
                        .foregroundStyle(BNBUTheme.onSurface)
                        .frame(width: 96, height: BNBUSpacing.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一步")
            } else {
                Spacer()
                    .frame(width: 96, height: BNBUSpacing.touchTarget)
            }

            Text(LocalizedStringKey(headerTitle))
                .font(BNBUFont.titleMedium)
                .foregroundStyle(BNBUTheme.onSurface)
                .frame(maxWidth: .infinity)

            Button(action: onSkip) {
                Text(LocalizedStringKey(skipLabel))
                    .font(BNBUFont.labelLarge)
                    .foregroundStyle(BNBUTheme.primary)
                    .frame(width: 96, height: BNBUSpacing.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedStringKey(skipDescription))
            .accessibilityIdentifier("guide.skip")
        }
        .frame(height: 64)
        .padding(.horizontal, BNBUSpacing.screen)
    }

    private func stepContent(_ step: BNBUGuideStep, isActive: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            BNBUGuideArtwork(artwork: step.artwork)
                .frame(maxWidth: 360)
                .frame(height: 254)
                .scaleEffect(isActive ? 1 : 0.97)
                .opacity(isActive ? 1 : 0.45)
                .animation(.easeInOut(duration: BNBUMotion.emphasized), value: isActive)
                .accessibilityLabel(Text(LocalizedStringKey(step.title)) + Text(verbatim: " ") + Text("引导插图"))
                .padding(.bottom, 36)

            VStack(spacing: 0) {
                Text(LocalizedStringKey(step.eyebrow))
                    .font(BNBUFont.labelMedium.weight(.semibold))
                    .foregroundStyle(BNBUTheme.primary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, BNBUSpacing.space8)

                Text(LocalizedStringKey(step.title))
                    .font(BNBUFont.headlineLarge)
                    .tracking(BNBUFont.Tracking.headlineLarge)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, BNBUSpacing.space12)

                Text(LocalizedStringKey(step.detail))
                    .font(BNBUFont.bodyLarge)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(BNBUFont.LineSpacing.bodyLarge)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: BNBUMotion.emphasized), value: isActive)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BNBUSpacing.screen)
        .padding(.vertical, BNBUSpacing.space16)
    }

    private var footer: some View {
        VStack(spacing: BNBUSpacing.space16) {
            HStack(spacing: BNBUSpacing.space8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? BNBUTheme.primary : BNBUTheme.outlineVariant)
                        .frame(width: index == page ? 22 : 8, height: 8)
                        .animation(.easeInOut(duration: BNBUMotion.standard), value: page)
                }
            }
            .accessibilityHidden(true)

            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLastPage ? LocalizedStringKey(finalActionLabel) : LocalizedStringKey("下一步"))
                    .font(BNBUFont.labelLarge)
                    .frame(maxWidth: .infinity)
                    .frame(height: BNBUSpacing.primaryControlHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: BNBURadius.medium))
            .accessibilityIdentifier(isLastPage ? "guide.finish" : "guide.next")
        }
        .padding(.horizontal, BNBUSpacing.screen)
        .padding(.top, BNBUSpacing.space16)
        .padding(.bottom, BNBUSpacing.space24)
    }
}

/// Android draws these guide illustrations with Compose primitives; the iOS
/// versions reuse the same card-over-surface composition and icon set.
struct BNBUGuideArtwork: View {
    let artwork: BNBUGuideStep.Artwork

    var body: some View {
        VStack(spacing: BNBUSpacing.space16) {
            switch artwork {
            case .courseJoin:
                artworkCard(
                    systemImage: "qrcode.viewfinder",
                    title: "课程二维码或邀请码",
                    detail: "由老师提供"
                )
                Spacer(minLength: 0)
                HStack(spacing: BNBUSpacing.space16) {
                    codeMark
                    VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                        Text("扫码或手动输入")
                            .font(BNBUFont.titleSmall)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text("PE1024")
                            .font(BNBUFont.bodySmall.monospaced())
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .joinRequest:
                artworkCard(
                    systemImage: "checkmark.seal",
                    title: "核对课程与个人资料",
                    detail: "确认后提交加入申请"
                )
                Spacer(minLength: 0)
                VStack(spacing: BNBUSpacing.space8) {
                    artworkStatusRow(text: "已提交，等待老师审核", tint: BNBUTheme.secondary)
                    artworkStatusRow(text: "审核通过后即可开始打卡", tint: BNBUTheme.tertiary)
                }
            }
        }
        .padding(BNBUSpacing.space20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BNBUTheme.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.extraLarge, style: .continuous))
    }

    private func artworkCard(systemImage: String, title: String, detail: String) -> some View {
        HStack(spacing: BNBUSpacing.space12) {
            Image(systemName: systemImage)
                .font(BNBUFont.titleLarge)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 40, height: 40)
                .background(BNBUTheme.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(BNBUFont.titleSmall)
                    .foregroundStyle(BNBUTheme.onSurface)
                Text(LocalizedStringKey(detail))
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BNBUSpacing.space12)
        .background(BNBUTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.large, style: .continuous))
    }

    private func artworkStatusRow(text: String, tint: Color) -> some View {
        HStack(spacing: BNBUSpacing.space8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(LocalizedStringKey(text))
                .font(BNBUFont.bodySmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BNBUSpacing.space12)
        .padding(.vertical, 10)
        .background(BNBUTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
    }

    private var codeMark: some View {
        Image(systemName: "qrcode")
            .font(.system(size: 34))
            .foregroundStyle(BNBUTheme.officialBlue)
            .frame(width: 64, height: 64)
            .background(BNBUTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
    }
}

/// Android's `BnbuSportsBrandLockup`: emblem, "BNBU" in official blue, then the
/// sports seal beside "SPORTS".
struct BNBUBrandLockup: View {
    var emblemSize: CGFloat = 84

    var body: some View {
        VStack(spacing: 10) {
            Image("bnbu_emblem")
                .resizable()
                .scaledToFit()
                .frame(width: emblemSize, height: emblemSize)
                .accessibilityLabel("BNBU 校徽")
            Text(verbatim: "BNBU")
                .font(BNBUFont.displaySmall.weight(.black))
                .tracking(4)
                .foregroundStyle(BNBUTheme.officialBlue)
            HStack(spacing: 10) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(BNBUTheme.officialBlue)
                Text(verbatim: "SPORTS")
                    .font(BNBUFont.labelLarge.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(BNBUTheme.officialBlue)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
