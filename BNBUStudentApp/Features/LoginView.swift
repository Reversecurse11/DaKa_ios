import Foundation
import SwiftUI

private enum LoginFormField: Hashable {
    case account
    case password
}

private enum LoginRoute: Hashable {
    case chooser
    case emailVerification
    case phoneVerification
    case accountPassword
    case recovery
}

enum BNBUPrivacyConsent {
    static let currentVersion = "2026-07-23"
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
    @State private var showCourseJoin = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-login-email") {
            _route = State(initialValue: .emailVerification)
        } else if arguments.contains("-ui-testing-login-phone") {
            _route = State(initialValue: .phoneVerification)
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
                    // An application under review is the student's only way in,
                    // so the sign-in screen reports it until a teacher decides.
                    joinRequest: appState.courseJoinRequest.flatMap {
                        $0.status == .active ? nil : $0
                    },
                    onEmail: { route = .emailVerification },
                    onPhone: { route = .phoneVerification },
                    onJoin: { showCourseJoin = true },
                    onRecovery: { route = .recovery },
                    onMockLogin: { appState.demoLogin() }
                )
            case .emailVerification:
                VerificationLoginView(
                    initialMethod: .email,
                    onBack: { route = .chooser }
                )
            case .phoneVerification:
                VerificationLoginView(
                    initialMethod: .phone,
                    onBack: { route = .chooser }
                )
            case .accountPassword:
                AccountPasswordLoginView(onBack: { route = .chooser })
            case .recovery:
                RecoveryRequestView(onBack: { route = .chooser })
            }
        }
        .sheet(isPresented: $showCourseJoin) {
            CourseJoinSheet()
                .environmentObject(appState)
        }
    }
}

private struct LoginMethodChooser: View {
    @Environment(\.locale) private var locale

    var joinRequest: CourseJoinRequest?
    let onEmail: () -> Void
    let onPhone: () -> Void
    let onJoin: () -> Void
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

                    if let joinRequest {
                        JoinRequestEntryPanel(
                            request: joinRequest,
                            identifier: "login.joinRequest.entry",
                            onOpen: onJoin
                        )
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                            Text(copy("选择登录方式", "Choose a sign-in method"))
                                .font(BNBUFont.headlineSmall)
                                .foregroundStyle(BNBUTheme.onSurface)

                            LoginMethodRow(
                                title: copy("邮箱验证码登录", "Sign in with email code"),
                                subtitle: copy("使用学校邮箱", "Use your university email"),
                                systemImage: "envelope.fill",
                                isPrimary: true,
                                action: onEmail
                            )
                            .accessibilityIdentifier("login.email")

                            LoginMethodRow(
                                title: copy("手机验证码登录", "Sign in with mobile code"),
                                subtitle: copy("使用已绑定的手机号", "Use your linked mobile number"),
                                systemImage: "iphone",
                                action: onPhone
                            )
                            .accessibilityIdentifier("login.phone")

                            Divider()
                                .overlay(BNBUTheme.outlineVariant)
                                .padding(.vertical, BNBUSpacing.space4)

                            Text(copy("其他方式", "Other options"))
                                .font(BNBUFont.labelMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)

                            LoginMethodRow(
                                title: copy("扫码加入课程", "Join a course by scanning"),
                                subtitle: copy("打开课程邀请并提交加入申请", "Open a course invitation and apply to join"),
                                systemImage: "qrcode.viewfinder",
                                action: onJoin
                            )
                            .accessibilityIdentifier("login.courseJoin")

                            LoginMethodRow(
                                title: copy("使用 Mock 用户", "Use Mock user"),
                                subtitle: copy("仅用于本地演示与调试", "Local demo and debugging only"),
                                systemImage: "hammer.fill",
                                action: onMockLogin
                            )
                            .accessibilityIdentifier("login.mockUser")
                        }
                    }

                    Button(action: onRecovery) {
                        Text(copy(
                            "无法使用绑定的手机号或邮箱？",
                            "Can't use your linked mobile number or email?"
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
                                title: copy("登录", "Sign in"),
                                systemImage: "arrow.right",
                                accessibilityIdentifier: "verification.submit"
                            ) {
                                signIn()
                            }
                            .disabled(!canSubmit)
                            .opacity(canSubmit ? 1 : 0.55)
                        }
                    }

                    Button {
                        method = method == .email ? .phone : .email
                        contact = ""
                        code = ""
                        notice = nil
                        codeSent = false
                        resendSeconds = 0
                    } label: {
                        Label(
                            method == .email
                                ? copy("改用手机验证码登录", "Use mobile verification instead")
                                : copy("改用邮箱验证码登录", "Use email verification instead"),
                            systemImage: method == .email ? "iphone" : "envelope"
                        )
                        .font(BNBUFont.labelLarge)
                        .foregroundStyle(BNBUTheme.primary)
                        .frame(maxWidth: .infinity, minHeight: BNBUSpacing.touchTarget)
                    }
                    .buttonStyle(BNBUPressStyle())
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
            }
            .padding(.horizontal, BNBUSpacing.space16)
            .frame(height: 56)
            .background(BNBUTheme.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
            .accessibilityIdentifier("verification.contact")
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
            .accessibilityIdentifier("verification.code")
        }
    }

    private var channel: ContactChannel {
        method == .email ? .email : .phone
    }

    private var sendTitle: String {
        resendSeconds > 0
            ? BNBUL10n.formatted("%lld 秒后可重发", resendSeconds)
            : copy("获取验证码", "Get code")
    }

    private var canSend: Bool {
        resendSeconds == 0 && isContactValid
    }

    private var isContactValid: Bool {
        ContactBindingRule.isValid(contact, for: channel)
    }

    private var canSubmit: Bool {
        isContactValid && ContactBindingRule.isValidCode(code)
    }

    private func sendCode() {
        dismissBNBUKeyboard()
        guard appState.sendLoginCode(to: contact, channel: channel) else {
            notice = appState.errorMessage
            return
        }
        codeSent = true
        resendSeconds = ContactBindingRule.resendInterval
        notice = nil
    }

    private func signIn() {
        dismissBNBUKeyboard()
        guard codeSent else {
            notice = copy("请先获取验证码。", "Request a code first.")
            return
        }
        guard appState.signInWithCode(code, contact: contact, channel: channel) else {
            notice = appState.errorMessage
            return
        }
        notice = nil
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    let onBack: () -> Void

    @State private var isSubmitted = false
    @State private var studentID = ""
    @State private var name = ""
    @State private var explanation = ""
    @State private var newPhone = ""
    @State private var newEmail = ""
    @State private var notice: String?

    var body: some View {
        if isSubmitted {
            recoverySubmitted
        } else {
            form
        }
    }

    /// Recovery is reviewed by a person, so the only honest confirmation is
    /// that the request was filed and what happens next.
    private var recoverySubmitted: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                    BNBUBackRow(title: copy("账号恢复", "Account recovery"), action: onBack)
                    VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                        Text(copy("恢复申请已提交", "Recovery request submitted"))
                            .font(BNBUFont.headlineSmall)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text(copy(
                            "老师或系统管理员会核对你的身份，通过后会把账号换绑到你填写的新联系方式。请留意新手机号或邮箱的通知。",
                            "A teacher or administrator will verify your identity and then rebind the account to the new contact you provided. Watch for a notice there."
                        ))
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                            DetailFactRow(label: copy("学号", "Student ID"), value: studentID)
                            DetailFactRow(label: copy("姓名", "Name"), value: name)
                            if !newPhone.isEmpty {
                                DetailFactRow(label: copy("新手机号", "New mobile"), value: newPhone)
                            }
                            if !newEmail.isEmpty {
                                DetailFactRow(label: copy("新邮箱", "New email"), value: newEmail)
                            }
                        }
                    }

                    PrimaryActionButton(
                        title: copy("返回登录", "Back to sign-in"),
                        systemImage: "arrow.left",
                        accessibilityIdentifier: "recovery.done"
                    ) {
                        onBack()
                    }
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.bottom, BNBUSpacing.space32)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("screen.recoverySubmitted")
    }

    private var form: some View {
        ZStack(alignment: .bottom) {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                    BNBUBackRow(title: copy("账号恢复", "Account recovery"), action: onBack)

                    VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                        Text(copy("换手机后无法登录？", "Can't sign in after changing phones?"))
                            .font(BNBUFont.headlineSmall)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text(copy(
                            "填写身份和情况说明，并留下一个当前可用的联系方式。老师或管理员核验后会协助换绑。",
                            "Provide your identity, an explanation and a contact you can currently use. Staff will verify it and help rebind your account."
                        ))
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }

                    if let notice {
                        BNBUErrorPanel(message: notice)
                    }

                    recoverySection(
                        title: copy("身份信息", "Identity details"),
                        detail: copy("请填写与校园账号一致的信息", "Use the same details as your campus account.")
                    ) {
                        RecoveryField(
                            title: copy("学号", "Student ID"),
                            placeholder: copy("请输入学号", "Enter your student ID"),
                            text: $studentID
                        )
                        RecoveryField(
                            title: copy("姓名", "Name"),
                            placeholder: copy("请输入姓名", "Enter your name"),
                            text: $name
                        )
                    }

                    recoverySection(
                        title: copy("情况说明", "What happened"),
                        detail: copy(
                            "简要说明原联系方式无法使用的情况",
                            "Briefly explain why the original contact details cannot be used."
                        )
                    ) {
                        RecoveryField(
                            title: copy("说明", "Description"),
                            placeholder: copy("请描述遇到的问题", "Describe what happened"),
                            text: $explanation,
                            axis: .vertical
                        )
                    }

                    recoverySection(
                        title: copy("新的联系方式", "New contact details"),
                        detail: copy(
                            "至少填写一项，供老师换绑",
                            "Provide at least one so staff can rebind the account."
                        )
                    ) {
                        RecoveryField(
                            title: copy("新手机号", "New mobile number"),
                            placeholder: copy("请输入新手机号", "Enter a new mobile number"),
                            text: $newPhone
                        )
                        RecoveryField(
                            title: copy("新邮箱", "New email"),
                            placeholder: copy("请输入新邮箱", "Enter a new email"),
                            text: $newEmail
                        )
                    }

                    Spacer(minLength: 88)
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.bottom, BNBUSpacing.space32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryActionButton(
                title: copy("提交恢复申请", "Submit recovery request"),
                systemImage: "paperplane.fill",
                accessibilityIdentifier: "recovery.submit"
            ) {
                submit()
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.55)
            .padding(.horizontal, BNBUSpacing.screen)
            .padding(.vertical, BNBUSpacing.space12)
            .background(.ultraThinMaterial)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.recoveryRequest")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(copy("完成", "Done")) { dismissBNBUKeyboard() }
            }
        }
    }

    private func recoverySection<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                Text(title)
                    .font(BNBUFont.titleMedium)
                Text(detail)
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                content()
            }
        }
    }

    private var canSubmit: Bool {
        !studentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        dismissBNBUKeyboard()
        guard appState.submitRecoveryRequest(
            studentNumber: studentID,
            name: name,
            description: explanation,
            newPhone: newPhone,
            newEmail: newEmail
        ) else {
            notice = appState.errorMessage
            return
        }
        notice = nil
        isSubmitted = true
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        locale.identifier.hasPrefix("zh") ? chinese : english
    }
}

private struct RecoveryField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
            Text(title)
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 4...7 : 1...1)
                .padding(BNBUSpacing.space12)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface()
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: "PRIVACY", title: "隐私政策")
                    privacySection("一、信息收集", paragraphs: [
                        "本应用仅收集校园体育服务所需的账户、课程、学时、成绩和申请信息。",
                        "提交打卡或免测申请时，只有经您主动选择或拍摄的图片、视频及说明会被上传。"
                    ])
                    privacySection("二、信息使用", paragraphs: [
                        "相关信息仅用于体育学时计算、成绩展示、打卡记录、免测申请和校园通知，不用于商业广告。"
                    ])
                    privacySection("三、本地存储与安全", paragraphs: [
                        "密码仅用于登录请求，不写入本地持久化状态。短期登录令牌保存在本机 Keychain；工作台缓存和未提交草稿使用完整文件保护并排除云备份。退出登录会清理当前账号凭据、缓存和草稿。",
                        "从相册选择凭证使用系统照片选择器，App 只接收您明确选中的项目；直接拍摄仅在您操作时申请摄像头及录音权限。",
                        "正式环境应使用受信任的 HTTPS 服务；调试环境的 HTTP 地址仅用于联调，不应承载真实敏感数据。"
                    ])
                    privacySection("四、用户权利", paragraphs: [
                        "您可以查看自己的学时、成绩和打卡记录；如需更正或删除服务器数据，请联系体育老师或系统管理员。"
                    ])
                    privacySection("五、政策更新", paragraphs: [
                        "重大变更将通过 App 内通知或学校公告告知。最新修订日期：2026 年 7 月 23 日。"
                    ])
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacySection(_ title: String, paragraphs: [String]) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedStringKey(title))
                    .font(BNBUFont.titleMedium)
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(LocalizedStringKey(paragraph))
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .lineSpacing(3)
                }
            }
        }
    }
}
