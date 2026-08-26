import Foundation
import SwiftUI

private enum LoginRoute: Hashable {
    case chooser
    case emailVerification
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
            // OpenAPI 2.0.13 exposes EMAIL only; the old smoke argument now
            // lands on the supported flow instead of simulating SMS.
            _route = State(initialValue: .emailVerification)
        } else {
            _route = State(initialValue: .chooser)
        }
    }

    var body: some View {
        Group {
            switch route {
            case .chooser:
                LoginMethodChooser(
                    onEmail: { route = .emailVerification },
                    onJoin: { showCourseJoin = true },
                    onLocalReview: localDemoLoginAction
                )
            case .emailVerification:
                VerificationLoginView(
                    initialMethod: .email,
                    onBack: { route = .chooser }
                )
            }
        }
        .sheet(isPresented: $showCourseJoin) {
            CourseJoinSheet()
                .environmentObject(appState)
        }
    }

    private var localDemoLoginAction: (() -> Void)? {
#if DEBUG
        guard LocalDemoAccess.showsLoginOption else { return nil }
        return { appState.demoLogin() }
#else
        return nil
#endif
    }
}

private struct LoginMethodChooser: View {
    @Environment(\.locale) private var locale

    let onEmail: () -> Void
    let onJoin: () -> Void
    let onLocalReview: (() -> Void)?

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
                                title: copy("邮箱验证码登录", "Sign in with email code"),
                                subtitle: copy("使用学校邮箱", "Use your university email"),
                                systemImage: "envelope.fill",
                                isPrimary: true,
                                action: onEmail
                            )
                            .accessibilityIdentifier("login.email")

                            Divider()
                                .overlay(BNBUTheme.outlineVariant)
                                .padding(.vertical, BNBUSpacing.space4)

                            Text(copy("其他方式", "Other options"))
                                .font(BNBUFont.labelMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)

                            LoginMethodRow(
                                title: copy("扫码加入课程", "Join a course by scanning"),
                                subtitle: copy("预览课程并直接加入 ACTIVE Enrollment", "Preview the course and join an ACTIVE enrollment"),
                                systemImage: "qrcode.viewfinder",
                                action: onJoin
                            )
                            .accessibilityIdentifier("login.courseJoin")

#if DEBUG
                            if let onLocalReview {
                                Divider()
                                    .overlay(BNBUTheme.outlineVariant)
                                    .padding(.vertical, BNBUSpacing.space4)

                                Text(copy("免登录测试入口", "Password-free review access"))
                                    .font(BNBUFont.labelMedium)
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)

                                Text(copy(
                                    "仅使用本地合成数据，不登录账号，也不会向真实 Backend 发送业务请求。",
                                    "Uses local synthetic data only, without signing in or sending business requests to the real Backend."
                                ))
                                .font(BNBUFont.bodySmall)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)

                                LoginMethodRow(
                                    title: copy("以测试学生身份进入", "Enter as test student"),
                                    subtitle: copy("演示学生 · demo-student-001", "Demo student · demo-student-001"),
                                    systemImage: "person.crop.circle.badge.checkmark",
                                    action: onLocalReview
                                )
                                .accessibilityIdentifier("login.localReview")
                            }
#endif
                        }
                    }

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
    @State private var contactTouched = false
    @State private var codeTouched = false

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

                }
                .frame(maxWidth: 520)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.bottom, BNBUSpacing.space32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier("screen.login.email")
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
        copy("使用邮箱登录", "Sign in with email")
    }

    private var subtitle: String {
        copy(
            "输入学校邮箱后，我们会向你发送登录验证码。",
            "Enter your university email and we will send you a sign-in code."
        )
    }

    private var contactField: some View {
        BNBUFormField(
            label: copy("学校邮箱", "University email"),
            placeholder: "name@bnbu.edu.cn",
            text: $contact,
            required: true,
            helperText: copy("请输入学校分配的邮箱。", "Enter your university-issued email."),
            errorText: contactTouched && !isContactValid
                ? copy("请输入有效的学校邮箱。", "Enter a valid university email.")
                : nil,
            characterLimit: 254,
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            enabled: !appState.isLoading,
            submitLabel: .next,
            onSubmit: { if canSend { sendCode() } },
            onFocusChanged: { focused in if !focused { contactTouched = true } },
            accessibilityIdentifier: "verification.contact"
        )
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
            BNBUFormField(
                label: copy("验证码", "Verification code"),
                placeholder: copy("4–10 位数字", "4–10 digits"),
                text: $code,
                required: true,
                helperText: codeSent
                    ? copy("验证码已发送，请查看邮箱。", "The code was sent to your email.")
                    : copy("请先获取验证码。", "Request a code first."),
                errorText: codeTouched && !code.isEmpty && !ContactBindingRule.isValidStudentSignInCode(code)
                    ? copy("请输入 4–10 位数字验证码。", "Enter a 4–10 digit code.")
                    : nil,
                characterLimit: 10,
                keyboardType: .numberPad,
                textContentType: .oneTimeCode,
                enabled: !appState.isLoading,
                submitLabel: .done,
                onSubmit: { if canSubmit { signIn() } },
                onFocusChanged: { focused in if !focused { codeTouched = true } },
                accessibilityIdentifier: "verification.code"
            )
            .onChange(of: code) { _, value in
                code = String(value.filter(\.isNumber).prefix(10))
            }

            Button(sendTitle) { sendCode() }
                .font(BNBUFont.labelMedium)
                .foregroundStyle(canSend ? BNBUTheme.primary : BNBUTheme.onSurfaceVariant.opacity(0.55))
                .disabled(!canSend)
                .buttonStyle(.plain)
                .frame(minHeight: BNBUSpacing.touchTarget)
                .accessibilityIdentifier("verification.sendCode")
        }
    }

    private var channel: ContactChannel {
        .email
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
        isContactValid && ContactBindingRule.isValidStudentSignInCode(code) && !appState.isLoading
    }

    private func sendCode() {
        Task {
            dismissBNBUKeyboard()
            let contractLocale = locale.identifier.hasPrefix("zh") ? "zh-CN" : "en"
            guard await appState.requestEmailLoginCode(to: contact, locale: contractLocale) else {
                notice = appState.errorMessage
                return
            }
            codeSent = true
            resendSeconds = ContactBindingRule.resendInterval
            notice = nil
        }
    }

    private func signIn() {
        Task {
            dismissBNBUKeyboard()
            guard codeSent else {
                notice = copy("请先获取验证码。", "Request a code first.")
                return
            }
            guard await appState.verifyEmailLoginCode(code, account: contact) else {
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

#if false // STUDENT password authentication is not part of OpenAPI 2.0.13.
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
#endif

#if false // No account-recovery mutation exists in OpenAPI 2.0.13.
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

    @ViewBuilder
    var body: some View {
        if axis == .vertical {
            BNBUTextArea(
                label: title,
                text: $text,
                placeholder: placeholder,
                required: true,
                accessibilityIdentifier: "recovery.\(fieldIdentifier)"
            )
        } else {
            BNBUFormField(
                label: title,
                placeholder: placeholder,
                text: $text,
                required: true,
                accessibilityIdentifier: "recovery.\(fieldIdentifier)"
            )
        }
    }

    private var fieldIdentifier: String {
        title.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
    }
}
#endif

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
