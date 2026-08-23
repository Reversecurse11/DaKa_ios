import Foundation
import SwiftUI

private enum LoginFormField: Hashable {
    case account
    case password
}

private enum LoginRoute: Hashable {
    case chooser
    case emailVerification
    case accountPassword
    case recovery
}

enum BNBUPrivacyConsent {
    static let currentVersion = "2026-08-06"
    static let defaultsKeyPrefix = "bnbu.privacy.consent.v1."

    static func normalizedAccount(_ account: String) -> String {
        account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func hasAccepted(account: String, defaults: UserDefaults = .standard) -> Bool {
        // The device-level gate runs before sign-in, so a student who already
        // agreed there must not be asked a second time on the login form.
        if BNBUDevicePrivacyConsent.hasAccepted(defaults: defaults) { return true }
        let normalized = normalizedAccount(account)
        guard !normalized.isEmpty,
              let record = defaults.dictionary(forKey: defaultsKeyPrefix + normalized) else {
            return false
        }
        return record["version"] as? String == currentVersion &&
            record["acceptedAt"] as? String != nil
    }

    static func recordAcceptance(account: String, defaults: UserDefaults = .standard) {
        let normalized = normalizedAccount(account)
        guard !normalized.isEmpty else { return }
        defaults.set(
            [
                "version": currentVersion,
                "acceptedAt": ISO8601DateFormatter().string(from: Date())
            ],
            forKey: defaultsKeyPrefix + normalized
        )
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(defaultsKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var route: LoginRoute
    let onInitialCourseJoin: () -> Void

    init(onInitialCourseJoin: @escaping () -> Void = {}) {
        self.onInitialCourseJoin = onInitialCourseJoin
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-login-email") {
            _route = State(initialValue: .emailVerification)
        } else if arguments.contains("-ui-testing-login-recovery") {
            _route = State(initialValue: .recovery)
        } else if arguments.contains("-ui-testing-login-password") {
            // Students no longer see this route; it stays reachable only for the
            // remote end-to-end harness, which has no other way to authenticate
            // against a real server until the verification-code API ships.
            _route = State(initialValue: .accountPassword)
        } else {
            _route = State(initialValue: .chooser)
        }
    }

    var body: some View {
        Group {
            switch route {
            case .chooser:
                LoginMethodChooser(
                    onInitialCourseJoin: onInitialCourseJoin,
                    onEmail: { route = .emailVerification },
                    onRecovery: { route = .recovery },
                    onMockLogin: { appState.mockAccountLogin() }
                )
            case .emailVerification:
                VerificationLoginView(
                    initialMethod: .email,
                    onBack: { route = .chooser }
                )
            case .accountPassword:
                AccountPasswordLoginView(onBack: { route = .chooser })
            case .recovery:
                RecoveryRequestView(onBack: { route = .chooser })
            }
        }
    }
}

private struct LoginMethodChooser: View {
    @Environment(\.locale) private var locale

    let onInitialCourseJoin: () -> Void
    let onEmail: () -> Void
    let onRecovery: () -> Void
    let onMockLogin: () -> Void

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                    HStack(spacing: BNBUSpacing.space12) {
                        BrandMark(compact: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(copy(
                                "北师香港浸会大学",
                                "Beijing Normal-Hong Kong Baptist University"
                            ))
                            .font(BNBUFont.titleMedium)
                            .foregroundStyle(BNBUTheme.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            Text(copy("BNBU · 学生体育", "BNBU · STUDENT SPORTS"))
                                .font(BNBUFont.labelSmall)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }
                    }

                    VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                        Text(copy("登录 BNBU 体育", "Sign in to BNBU Sports"))
                            .font(BNBUFont.headlineLarge)
                            .tracking(BNBUFont.Tracking.headlineLarge)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text(copy(
                            "查看体育打卡、学时进度与成绩，一处完成。",
                            "Check activities, hour progress, and grades in one place."
                        ))
                        .font(BNBUFont.bodyLarge)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                            Text(copy("选择登录方式", "Choose a sign-in method"))
                                .font(BNBUFont.headlineSmall)
                                .foregroundStyle(BNBUTheme.onSurface)

                            LoginMethodRow(
                                title: copy("首次加入课程", "Join a course for the first time"),
                                subtitle: copy("先扫码或输入老师提供的邀请", "Scan or enter the invite from your teacher first"),
                                systemImage: "qrcode.viewfinder",
                                isPrimary: true,
                                action: onInitialCourseJoin
                            )
                            .accessibilityIdentifier("login.initialCourseJoin")

                            LoginMethodRow(
                                title: copy("邮箱验证码登录", "Sign in with email code"),
                                subtitle: copy("使用学校邮箱", "Use your university email"),
                                systemImage: "envelope.fill",
                                action: onEmail
                            )
                            .accessibilityIdentifier("login.email")

#if BNBU_FIXTURES && DEBUG
                            LoginMethodRow(
                                title: copy("使用 Mock 用户", "Use Mock user"),
                                subtitle: copy("仅用于本地演示与调试", "Local demo and debugging only"),
                                systemImage: "hammer.fill",
                                action: onMockLogin
                            )
                            .accessibilityIdentifier("login.mockUser")
#endif
                        }
                    }

                    Button(action: onRecovery) {
                        Text(copy(
                            "无法使用绑定的邮箱？",
                            "Can't use your linked email?"
                        ))
                        .font(BNBUFont.labelLarge)
                        .foregroundStyle(BNBUTheme.primary)
                        .frame(maxWidth: .infinity, minHeight: BNBUSpacing.touchTarget)
                    }
                    .buttonStyle(BNBUPressStyle())
                    .accessibilityIdentifier("login.recoveryRequest")
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.top, BNBUSpacing.space20)
                .padding(.bottom, BNBUSpacing.space32)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("screen.login")
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        locale.identifier.hasPrefix("zh") ? chinese : english
    }
}

private struct LoginMethodRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BNBUSpacing.space12) {
                Image(systemName: systemImage)
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(isPrimary ? BNBUTheme.onPrimary : BNBUTheme.primary)
                    .frame(width: 38, height: 38)
                    .background(isPrimary ? BNBUTheme.onPrimary.opacity(0.13) : BNBUTheme.primaryContainer)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BNBUFont.titleMedium)
                    Text(subtitle)
                        .font(BNBUFont.bodySmall)
                        .opacity(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(BNBUFont.bodyMedium.weight(.semibold))
                    .opacity(0.72)
            }
            .foregroundStyle(isPrimary ? BNBUTheme.onPrimary : BNBUTheme.onSurface)
            .padding(.horizontal, BNBUSpacing.space16)
            .frame(minHeight: 66)
            .background(isPrimary ? BNBUTheme.primary : BNBUTheme.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.large, style: .continuous))
        }
        .buttonStyle(BNBUPressStyle())
    }
}

private enum VerificationMethod {
    case email
    case phone
}

private struct VerificationLoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    let onBack: () -> Void

    @State private var method: VerificationMethod
    @State private var contact = ""
    @State private var code = ""
    @State private var notice: String?
    @State private var codeSent = false
    @State private var resendSeconds = 0
    @State private var isRequestingCode = false
    @State private var isSigningIn = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(initialMethod: VerificationMethod, onBack: @escaping () -> Void) {
        _method = State(initialValue: initialMethod)
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                    BNBUBackRow(action: onBack)
                    BrandMark(compact: true)

                    VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                        Text(title)
                            .font(BNBUFont.headlineLarge)
                            .tracking(BNBUFont.Tracking.headlineLarge)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text(subtitle)
                            .font(BNBUFont.bodyLarge)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }

                    if let account = appState.mockTestAccount {
                        SwissPanel {
                            VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                                Text(copy("Mock 测试账号", "Mock test account"))
                                    .font(BNBUFont.labelMedium)
                                    .foregroundStyle(BNBUTheme.primary)
                                Text(verbatim: method == .email ? account.email : account.phone)
                                    .font(BNBUFont.titleSmall)
                                    .textSelection(.enabled)
                                Text(verbatim: copy(
                                    "固定验证码：\(account.verificationCode)",
                                    "Fixed code: \(account.verificationCode)"
                                ))
                                    .font(BNBUFont.bodySmall)
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                Button {
                                    contact = method == .email ? account.email : account.phone
                                    code = account.verificationCode
                                    notice = nil
                                } label: {
                                    Label(
                                        copy("填入测试账号", "Fill test account"),
                                        systemImage: "square.and.pencil"
                                    )
                                    .font(BNBUFont.labelLarge)
                                    .frame(maxWidth: .infinity, minHeight: BNBUSpacing.touchTarget)
                                }
                                .buttonStyle(BNBUPressStyle())
                                .foregroundStyle(BNBUTheme.primary)
                                .accessibilityIdentifier("verification.fillMockAccount")
                            }
                        }
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                            contactField
                            codeField

                            Label(
                                codeSent
                                    ? copy(
                                        "验证码已发送，10 分钟内有效，且仅可使用一次。",
                                        "Code sent. It is valid for 10 minutes and can only be used once."
                                    )
                                    : copy(
                                        "验证码 10 分钟内有效，且仅可使用一次。",
                                        "The code is valid for 10 minutes and can only be used once."
                                    ),
                                systemImage: "info.circle"
                            )
                            .font(BNBUFont.bodySmall)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)

                            if let notice {
                                BNBUErrorPanel(message: notice)
                            }

                            PrimaryActionButton(
                                title: isSigningIn
                                    ? copy("登录中…", "Signing in…")
                                    : copy("登录", "Sign in"),
                                systemImage: "arrow.right",
                                accessibilityIdentifier: "verification.submit"
                            ) {
                                signIn()
                            }
                            .disabled(!canSubmit)
                            .opacity(canSubmit ? 1 : 0.55)
                        }
                    }

                }
                .frame(maxWidth: 520)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.bottom, BNBUSpacing.space32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier(method == .email ? "screen.login.email" : "screen.login.phone")
        .onReceive(ticker) { _ in
            if resendSeconds > 0 { resendSeconds -= 1 }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(copy("完成", "Done")) { dismissBNBUKeyboard() }
            }
        }
    }

    private var title: String {
        method == .email
            ? copy("使用邮箱登录", "Sign in with email")
            : copy("使用手机号登录", "Sign in with mobile")
    }

    private var subtitle: String {
        method == .email
            ? copy(
                "输入学校邮箱后，我们会向你发送登录验证码。",
                "Enter your university email and we will send you a sign-in code."
            )
            : copy(
                "输入手机号后，我们会向你发送短信验证码。",
                "Enter your mobile number and we will send you a verification code."
            )
    }

    private var contactField: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
            Text(method == .email ? copy("学校邮箱", "University email") : copy("手机号", "Mobile number"))
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            HStack(spacing: BNBUSpacing.space12) {
                Image(systemName: method == .email ? "envelope" : "iphone")
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                if method == .phone {
                    Text(verbatim: "+86")
                        .font(BNBUFont.titleSmall)
                    Divider().frame(height: 28)
                }
                TextField(
                    method == .email
                        ? "name@bnbu.edu.cn"
                        : copy("请输入 11 位手机号", "11-digit mobile number"),
                    text: $contact
                )
                .textContentType(method == .email ? .emailAddress : .telephoneNumber)
                .keyboardType(method == .email ? .emailAddress : .phonePad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("verification.contact")
                .onChange(of: contact) { _, _ in
                    guard codeSent else { return }
                    codeSent = false
                    code = ""
                    resendSeconds = 0
                    notice = nil
                }
            }
            .padding(.horizontal, BNBUSpacing.space16)
            .frame(height: 56)
            .background(BNBUTheme.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
        }
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
            Text(copy("验证码", "Verification code"))
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            HStack(spacing: BNBUSpacing.space12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                TextField(copy("6 位数字", "6 digits"), text: $code)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("verification.code")
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                    }
                Button(sendTitle) { sendCode() }
                    .font(BNBUFont.labelMedium)
                    .foregroundStyle(canSend ? BNBUTheme.primary : BNBUTheme.onSurfaceVariant.opacity(0.55))
                    .disabled(!canSend)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("verification.sendCode")
            }
            .padding(.horizontal, BNBUSpacing.space16)
            .frame(height: 56)
            .background(BNBUTheme.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
        }
    }

    private var channel: ContactChannel {
        method == .email ? .email : .phone
    }

    private var sendTitle: String {
        if isRequestingCode {
            return copy("发送中…", "Sending…")
        }
        return resendSeconds > 0
            ? BNBUL10n.formatted("%lld 秒后可重发", resendSeconds)
            : copy("获取验证码", "Get code")
    }

    private var canSend: Bool {
        !isRequestingCode && !isSigningIn && resendSeconds == 0 && isContactValid
    }

    private var isContactValid: Bool {
        ContactBindingRule.isValid(contact, for: channel)
    }

    private var canSubmit: Bool {
        !isRequestingCode && !isSigningIn && isContactValid && ContactBindingRule.isValidCode(code)
    }

    private func sendCode() {
        dismissBNBUKeyboard()
        guard !isRequestingCode, !isSigningIn else { return }
        isRequestingCode = true
        notice = nil
        Task { @MainActor in
            defer { isRequestingCode = false }
            guard await appState.sendLoginCode(
                to: contact,
                channel: channel,
                locale: locale.identifier
            ) else {
                notice = appState.errorMessage
                return
            }
            codeSent = true
            resendSeconds = ContactBindingRule.resendInterval
            notice = nil
        }
    }

    private func signIn() {
        dismissBNBUKeyboard()
        guard !isRequestingCode, !isSigningIn else { return }
        guard codeSent else {
            notice = copy("请先获取验证码。", "Request a code first.")
            return
        }
        isSigningIn = true
        notice = nil
        Task { @MainActor in
            defer { isSigningIn = false }
            guard await appState.signInWithCode(code, contact: contact, channel: channel) else {
                notice = appState.errorMessage
                return
            }
            notice = nil
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        locale.identifier.hasPrefix("zh") ? chinese : english
    }
}

private struct AccountPasswordLoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    @FocusState private var focusedField: LoginFormField?
    let onBack: () -> Void

    @State private var account = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        ZStack {
            GridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                    BNBUBackRow(action: onBack)
                    universityBrandLockup
                    headerBlock
                    loginPanel
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.bottom, BNBUSpacing.space32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .accessibilityIdentifier("screen.login.password")
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showPrivacyPolicy = false }
                                .accessibilityIdentifier("privacy.done")
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                    dismissBNBUKeyboard()
                }
                .font(BNBUFont.titleSmall)
            }
        }
    }

    private var universityBrandLockup: some View {
        HStack(spacing: 12) {
            BrandMark(compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("北师香港浸会大学")
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                Text("BNBU · STUDENT SPORTS")
                    .font(BNBUFont.labelSmall)
                    .tracking(0.6)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BNBU")
                .font(.system(size: 57, weight: .regular))
                .foregroundStyle(BNBUTheme.onSurface)
            Text("体育打卡与成绩进度")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(BNBUTheme.onSurface)
            Text("课程相关 10 小时 + 其他运动 10 小时，进度、缺口与打卡记录一次看清。")
                .font(BNBUFont.bodyLarge)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .lineSpacing(4)
        }
    }

    private var loginPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "SIGN IN", title: "学生登录")

                if let errorMessage = appState.errorMessage {
                    BNBUErrorPanel(message: errorMessage)
                }

                loginField(title: "学号 / 邮箱") {
                    TextField("请输入学号或校园邮箱", text: $account)
                        .accessibilityLabel("学号或邮箱")
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .account)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityIdentifier("login.email.field")
                }

                loginField(title: "密码") {
                    HStack(spacing: 8) {
                        Group {
                            if passwordVisible {
                                TextField("请输入密码", text: $password)
                            } else {
                                SecureField("请输入密码", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .accessibilityLabel("密码")
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { submitLogin() }
                        .accessibilityIdentifier("login.password.field")

                        Button {
                            passwordVisible.toggle()
                        } label: {
                            Image(systemName: passwordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(passwordVisible ? "隐藏密码" : "显示密码")
                    }
                }

                PrimaryActionButton(
                    title: appState.isLoading
                        ? copy("登录中…", "Signing in…")
                        : copy("登录", "Sign in"),
                    systemImage: "arrow.right",
                    accessibilityIdentifier: "login.submit.button"
                ) {
                    submitLogin()
                }
                .disabled(!canLogin)
                .opacity(canLogin ? 1 : 0.55)

                Button(copy("查看《隐私政策》", "Read the Privacy Policy")) {
                    showPrivacyPolicy = true
                }
                .font(BNBUFont.titleSmall)
                .foregroundStyle(BNBUTheme.primary)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
    }

    private func loginField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(BNBUFont.labelSmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            content()
                .bnbuInputText()
                .padding(12)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(lineWidth: 1)
        }
    }

    private var canLogin: Bool {
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty &&
            !appState.isLoading
    }

    private func submitLogin() {
        guard canLogin else { return }
        focusedField = nil
        dismissBNBUKeyboard()
        BNBUPrivacyConsent.recordAcceptance(account: account)
        Task {
            await appState.login(
                account: account.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        locale.identifier.hasPrefix("zh") ? chinese : english
    }
}

private struct RecoveryRequestView: View {
    @Environment(\.locale) private var locale
    let onBack: () -> Void

    var body: some View {
        studentRecoveryInformation
    }

    /// Backend 2.0.2 recovery endpoints intentionally reject STUDENT accounts.
    /// This page therefore provides an honest handoff instead of a local form
    /// that could claim a request was filed when no server write occurred.
    private var studentRecoveryInformation: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                    BNBUBackRow(title: copy("账号帮助", "Account help"), action: onBack)

                    SwissPanel {
                        VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                            Image(systemName: "envelope.badge.shield.half.filled")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(BNBUTheme.primary)
                            Text(copy("学生账号使用邮箱验证码登录", "Students sign in with an email code"))
                                .font(BNBUFont.headlineSmall)
                                .foregroundStyle(BNBUTheme.onSurface)
                                .accessibilityIdentifier("recovery.studentUnsupported")
                            Text(copy(
                                "学生端没有密码，也不支持在 App 内提交密码恢复申请。请返回后使用已绑定的学校邮箱获取验证码。",
                                "Student accounts do not use passwords, and this app cannot file a password-recovery request. Go back and request a code using your linked university email."
                            ))
                                .font(BNBUFont.bodyMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                            Text(copy("无法使用原邮箱？", "Can't use your linked email?"))
                                .font(BNBUFont.titleMedium)
                            Text(copy(
                                "请联系任课教师或系统管理员，由学校线下核验身份并处理邮箱账号。不要把验证码、Token 或密码发送给他人。",
                                "Contact your course teacher or a system administrator. The university must verify your identity offline before changing the email account. Never share a verification code, token, or password."
                            ))
                                .font(BNBUFont.bodyMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    PrimaryActionButton(
                        title: copy("返回邮箱登录", "Back to email sign-in"),
                        systemImage: "arrow.left",
                        accessibilityIdentifier: "recovery.done"
                    ) {
                        onBack()
                    }
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.vertical, BNBUSpacing.space20)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("screen.recoveryRequest")
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        locale.identifier.hasPrefix("zh") ? chinese : english
    }
}

/// Renders the complete policy bundled with the app, mirroring Android's
/// `PrivacyPolicyScreen`. Keeping the legal copy in a resource file lets
/// compliance review it without reading UI code.
struct PrivacyPolicyView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    let document = BNBUPrivacyPolicyDocument.load(locale: locale)
                    Text(verbatim: "PRIVACY")
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.primary)
                    Text(verbatim: document.title)
                        .font(BNBUFont.headlineSmall)
                        .foregroundStyle(BNBUTheme.onSurface)
                        .padding(.bottom, 2)
                    ForEach(document.sections) { section in
                        privacySection(section)
                    }
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.privacyPolicy")
    }

    private func privacySection(_ section: BNBUPrivacyPolicyDocument.Section) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: section.title)
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .font(section.isSubheading(paragraph) ? BNBUFont.titleSmall : BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Parses the bundled policy markdown into panels: `#` is the document title,
/// `##` starts a panel, `###` becomes a subheading inside the current panel.
enum BNBUPrivacyPolicyDocument {
    struct Section: Identifiable {
        let id: Int
        let title: String
        let paragraphs: [String]

        func isSubheading(_ paragraph: String) -> Bool {
            paragraph.range(of: "^\\d{1,2}\\.\\d{1,2} .+", options: .regularExpression) != nil
        }
    }

    struct Document {
        let title: String
        let sections: [Section]
    }

    static func load(locale: Locale) -> Document {
        let isEnglish = locale.identifier.hasPrefix("en")
        let name = isEnglish ? "privacy_policy_en" : "privacy_policy_zh_cn"
        let fallbackTitle = isEnglish ? "BNBU Sports Privacy Policy" : "BNBU Sports 用户隐私政策"
        let preambleTitle = isEnglish ? "Version and scope" : "版本与适用说明"
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return Document(
                title: fallbackTitle,
                sections: [
                    Section(
                        id: 0,
                        title: fallbackTitle,
                        paragraphs: [
                            isEnglish
                                ? "The bundled policy text could not be read. Contact the sports teaching administration for a copy."
                                : "未能读取随应用打包的隐私政策全文，请联系体育教学管理部门获取副本。"
                        ]
                    )
                ]
            )
        }
        return parse(markdown, fallbackTitle: fallbackTitle, preambleTitle: preambleTitle)
    }

    static func parse(
        _ markdown: String,
        fallbackTitle: String,
        preambleTitle: String = "版本与适用说明"
    ) -> Document {
        var documentTitle = fallbackTitle
        var sections: [Section] = []
        var currentTitle = fallbackTitle
        var paragraphs: [String] = []
        var hasSeenSection = false

        func commit() {
            guard !paragraphs.isEmpty else { return }
            sections.append(Section(id: sections.count, title: currentTitle, paragraphs: paragraphs))
            paragraphs = []
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("# "), !hasSeenSection, paragraphs.isEmpty {
                documentTitle = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                // The version and scope lines ahead of the first article are their
                // own panel, as on Android.
                currentTitle = preambleTitle
            } else if line.hasPrefix("## ") {
                commit()
                hasSeenSection = true
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("### ") {
                paragraphs.append(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            } else {
                paragraphs.append(line)
            }
        }
        commit()
        return Document(title: documentTitle, sections: sections)
    }
}
