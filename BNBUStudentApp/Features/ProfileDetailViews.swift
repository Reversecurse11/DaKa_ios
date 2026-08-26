import SwiftUI

/// Android's `AccountDetailsScreen`, opened from the profile header card.
struct AccountDetailsView: View {
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void

    var body: some View {
        let student = appState.workspace.student

        return ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    BNBUBackRow(action: onBack)
                    Text("账户资料")
                        .font(BNBUFont.headlineSmall)
                        .tracking(BNBUFont.Tracking.headlineSmall)
                        .foregroundStyle(BNBUTheme.onSurface)

                    SwissPanel {
                        HStack(spacing: 14) {
                            BrandMark(compact: true)
                            Text(student.name)
                                .font(BNBUFont.titleLarge)
                                .foregroundStyle(BNBUTheme.onSurface)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StatusBadge(text: student.status, filled: true)
                        }
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            AccountDetailRow(label: "学生姓名", value: student.name)
                            AccountDetailRow(label: "学号", value: student.displayStudentNumber)
                            AccountDetailRow(label: "班级", value: fallback(student.className))
                            AccountDetailRow(
                                label: "入学年份",
                                value: student.enrollmentYear.map(String.init) ?? BNBUL10n.text("待完善")
                            )
                            AccountDetailRow(
                                label: "当前年级",
                                value: gradeLabel
                            )
                            if !appState.academicProjection.academicYear.isEmpty {
                                AccountDetailRow(
                                    label: "计算年份",
                                    value: appState.academicProjection.academicYear
                                )
                            }
                        }
                    }
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .accessibilityIdentifier("screen.accountDetails")
    }

    private var gradeLabel: String {
        let grade = BNBUL10n.dynamicText(appState.academicProjection.grade)
        return grade.isEmpty ? BNBUL10n.text("待计算") : grade
    }

    private func fallback(_ value: String) -> String {
        value.isEmpty ? BNBUL10n.text("待完善") : value
    }
}
private struct AccountDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: BNBUSpacing.space12) {
                rowLabel
                Spacer(minLength: BNBUSpacing.space12)
                rowValue
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: BNBUSpacing.space4) {
                rowLabel
                rowValue
            }
        }
    }

    private var rowLabel: some View {
        Text(LocalizedStringKey(label))
            .font(BNBUFont.bodyMedium)
            .foregroundStyle(BNBUTheme.onSurfaceVariant)
    }

    private var rowValue: some View {
        Text(verbatim: value)
            .font(BNBUFont.bodyMedium)
            .foregroundStyle(BNBUTheme.onSurface)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// Android's `ProfileSettingsScreen`, opened from the gear button in the
/// profile header. The profile tab itself keeps only account, services,
/// teacher, and identity content.
struct ProfileSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageSettings: BNBULanguageSettings
    @AppStorage(BNBUAppearanceMode.defaultsKey) private var appearanceModeRaw = BNBUAppearanceMode.light.rawValue

    let onBack: () -> Void

    @State private var showPrivacyPolicy = false
    @State private var showHelpCenter = false
    @State private var showAbout = false
    @State private var showFeedback = false
    @State private var showContactManagement = false
    @State private var showLogoutConfirmation = false
    @State private var showAccountDeletion = false

    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    BNBUBackRow(action: onBack)
                    Text("设置")
                        .font(BNBUFont.headlineSmall)
                        .tracking(BNBUFont.Tracking.headlineSmall)
                        .foregroundStyle(BNBUTheme.onSurface)

                    accountSecurityPanel
                    preferencesPanel
                    helpAndSupportPanel
                    logoutCard
                    Spacer(minLength: 40)
                }
                .padding(BNBUSpacing.screen)
            }
        }
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
        .sheet(isPresented: $showHelpCenter) {
            HelpCenterView()
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack {
                AboutView { showAbout = false }
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
        .sheet(isPresented: $showContactManagement) {
            ContactManagementView()
        }
        .sheet(isPresented: $showAccountDeletion) {
            NavigationStack {
                AccountDeletionView {
                    showAccountDeletion = false
                }
            }
        }
        .confirmationDialog(
            "退出登录？",
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                Task { await appState.logout() }
            }
            .accessibilityIdentifier("profile.logout.confirm")
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清理本机登录凭据、当前账号缓存、未提交草稿和全部待重试操作。")
        }
        .accessibilityIdentifier("screen.profileSettings")
    }

    private var accountSecurityPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 0) {
                BNBUGroupLabel("账户与安全")
                    .padding(.bottom, 4)
                BNBUNavigationSettingRow(
                    title: "绑定或更换登录邮箱",
                    systemImage: "envelope.fill",
                    accessibilityIdentifier: "settings.contactBinding"
                ) {
                    showContactManagement = true
                }
                settingsDivider
                BNBUNavigationSettingRow(
                    title: "注销账户",
                    systemImage: "trash.fill",
                    accessibilityIdentifier: "settings.accountDeletion"
                ) {
                    showAccountDeletion = true
                }
            }
        }
    }

    private var preferencesPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                BNBUGroupLabel("偏好设置")

                Text("外观模式")
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                BNBUSegmentedControl(
                    values: BNBUAppearanceMode.displayOrder.map(\.rawValue),
                    selection: $appearanceModeRaw,
                    title: { raw in
                        BNBUAppearanceMode(rawValue: raw).map(shortAppearanceTitle) ?? raw
                    },
                    identifier: { "profile.appearance.\($0)" }
                )
                Text("默认使用浅色模式；选择跟随系统后会随设备设置切换。")
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)

                Divider()
                    .overlay(BNBUTheme.outlineVariant.opacity(0.45))

                Text("界面语言 / Language")
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                BNBUSegmentedControl(
                    values: BNBULanguage.allCases.map(\.rawValue),
                    selection: languageSelection,
                    title: { raw in
                        BNBULanguage(rawValue: raw)?.title ?? raw
                    },
                    identifier: { "profile.language.\($0)" }
                )
                .accessibilityIdentifier("profile.language.picker")
                Text("更改后将立即更新界面语言。课程名称等由教师或管理员录入的数据内容保持原文。")
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
        }
    }

    private var helpAndSupportPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 0) {
                BNBUGroupLabel("帮助与支持")
                    .padding(.bottom, 4)
                BNBUNavigationSettingRow(
                    title: "帮助中心",
                    systemImage: "questionmark.circle",
                    accessibilityIdentifier: "settings.helpCenter"
                ) {
                    showHelpCenter = true
                }
                settingsDivider
                BNBUNavigationSettingRow(
                    title: "隐私政策",
                    systemImage: "hand.raised",
                    accessibilityIdentifier: "settings.privacy"
                ) {
                    showPrivacyPolicy = true
                }
                settingsDivider
                BNBUNavigationSettingRow(
                    title: "问题反馈",
                    systemImage: "exclamationmark.bubble",
                    accessibilityIdentifier: "settings.feedback"
                ) {
                    showFeedback = true
                }
                settingsDivider
                BNBUNavigationSettingRow(
                    title: "关于",
                    systemImage: "info.circle",
                    accessibilityIdentifier: "settings.about"
                ) {
                    showAbout = true
                }
            }
        }
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(BNBUTheme.outlineVariant.opacity(0.45))
    }

    private var logoutCard: some View {
        Button {
            showLogoutConfirmation = true
        } label: {
            HStack(spacing: BNBUSpacing.space12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(BNBUFont.titleMedium)
                Text("退出登录")
                    .font(BNBUFont.titleMedium)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(BNBUFont.labelMedium)
            }
            .foregroundStyle(BNBUTheme.onErrorContainer)
            .padding(BNBUSpacing.panel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BNBUTheme.errorContainer)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.large, style: .continuous))
        }
        .buttonStyle(BNBUPressStyle())
        .accessibilityIdentifier("profile.logout.button")
    }

    private func shortAppearanceTitle(_ mode: BNBUAppearanceMode) -> String {
        switch mode {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { languageSettings.mode.rawValue },
            set: { languageSettings.select(rawValue: $0) }
        )
    }
}

/// Student account deletion is deliberately separate from ordinary logout.
/// It requires an explanation, an initial confirmation, a verified-email OTP,
/// and a final destructive confirmation before Backend performs the atomic
/// de-identification and session revocation.
struct AccountDeletionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale

    let onClose: () -> Void

    @State private var challenge: ContractAccountDeletionChallenge?
    @State private var verificationCode = ""
    @State private var showInitialConfirmation = false
    @State private var showFinalConfirmation = false
    @FocusState private var verificationCodeFocused: Bool

    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    BNBUBackRow(action: onClose)
                    Text("注销账户")
                        .font(BNBUFont.headlineSmall)
                        .foregroundStyle(BNBUTheme.onSurface)

                    if let userError = appState.userFacingError {
                        BNBUErrorPanel(error: userError)
                    } else if let errorMessage = appState.errorMessage {
                        BNBUErrorPanel(message: errorMessage)
                    }

                    if let challenge {
                        verificationPanel(challenge)
                    } else {
                        explanationPanel
                    }
                }
                .padding(BNBUSpacing.screen)
                .padding(.bottom, BNBUSpacing.bottomSpacer)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationBarHidden(true)
        .confirmationDialog(
            "开始账户注销？",
            isPresented: $showInitialConfirmation,
            titleVisibility: .visible
        ) {
            Button("获取邮箱验证码", role: .destructive) {
                Task {
                    let requested = await appState.requestAccountDeletionChallenge(locale: apiLocale)
                    challenge = requested
                    verificationCodeFocused = requested != nil
                }
            }
            .accessibilityIdentifier("accountDeletion.request.confirm")
            Button("取消", role: .cancel) {}
        } message: {
            Text("下一步会向已验证邮箱发送一次性验证码；此时尚不会注销账户。")
        }
        .confirmationDialog(
            "最终确认注销账户？",
            isPresented: $showFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久注销账户", role: .destructive) {
                guard let challenge else { return }
                verificationCodeFocused = false
                dismissBNBUKeyboard()
                Task {
                    let deleted = await appState.confirmAccountDeletion(
                        challenge: challenge,
                        verificationCode: verificationCode
                    )
                    if deleted { onClose() }
                }
            }
            .accessibilityIdentifier("accountDeletion.final.confirm")
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后账号立即不可登录，全部设备会话和 Token 失效。再次注册会被视为一个新账户，不会恢复旧账户。")
        }
        .accessibilityIdentifier("screen.accountDeletion")
    }

    private var explanationPanel: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
            SwissPanel {
                VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                    Label("这是不可逆操作", systemImage: "exclamationmark.triangle.fill")
                        .font(BNBUFont.titleMedium)
                        .foregroundStyle(BNBUTheme.error)
                    Text("注销成功后，本账号立即不能继续登录，所有设备上的 Access Session、Refresh Token、设备和推送关联都会失效。")
                        .font(BNBUFont.bodyMedium)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                    BNBUGroupLabel("数据如何处理")
                    deletionFact(
                        icon: "person.fill.xmark",
                        title: "可识别个人信息",
                        detail: "按规则删除或匿名化，不再用于登录或识别你的账号。"
                    )
                    deletionFact(
                        icon: "doc.text.magnifyingglass",
                        title: "业务与审计记录",
                        detail: "为课程完整性和审计必须保留的记录会去标识化保留，不会被篡改。"
                    )
                    deletionFact(
                        icon: "person.badge.plus",
                        title: "以后重新注册",
                        detail: "必须作为新账户注册；系统不会偷偷恢复本账号的旧资料。"
                    )
                }
            }

            DisabledAwareButton(
                title: appState.isProcessingAccountDeletion ? "处理中…" : "继续注销账户",
                systemImage: "trash",
                isDisabled: appState.isProcessingAccountDeletion,
                accessibilityIdentifier: "accountDeletion.start"
            ) {
                showInitialConfirmation = true
            }
        }
    }

    private func verificationPanel(_ challenge: ContractAccountDeletionChallenge) -> some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
            SwissPanel {
                VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                    Label("重新验证身份", systemImage: "envelope.badge.shield.half.filled")
                        .font(BNBUFont.titleMedium)
                        .foregroundStyle(BNBUTheme.primary)
                    Text("验证码已发送到账号的已验证邮箱。输入验证码后，还会再显示一次最终确认。")
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    DetailFactRow(label: "验证方式", value: "邮箱一次性验证码")
                    DetailFactRow(label: "有效期至", value: challenge.expiresAt)
                }
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    BNBUFormField(
                        label: "邮箱验证码",
                        placeholder: "4–10 位数字",
                        text: $verificationCode,
                        required: true,
                        helperText: "验证码仅用于本次注销确认，不会写入日志。",
                        errorText: verificationCode.isEmpty || isValidCode
                            ? nil
                            : "请输入 4 到 10 位数字验证码。",
                        characterLimit: 10,
                        keyboardType: .numberPad,
                        textContentType: .oneTimeCode,
                        enabled: !appState.isProcessingAccountDeletion,
                        submitLabel: .done,
                        onSubmit: {
                            if isValidCode && !appState.isProcessingAccountDeletion {
                                verificationCodeFocused = false
                                dismissBNBUKeyboard()
                                showFinalConfirmation = true
                            }
                        },
                        focusBinding: $verificationCodeFocused,
                        accessibilityIdentifier: "accountDeletion.verificationCode"
                    )
                    .onChange(of: verificationCode) { _, value in
                        verificationCode = String(value.filter(\.isNumber).prefix(10))
                    }

                    DisabledAwareButton(
                        title: appState.isProcessingAccountDeletion ? "处理中…" : "已填写验证码，继续最终确认",
                        systemImage: "checkmark.shield",
                        isDisabled: !isValidCode || appState.isProcessingAccountDeletion,
                        accessibilityIdentifier: "accountDeletion.verify"
                    ) {
                        verificationCodeFocused = false
                        dismissBNBUKeyboard()
                        showFinalConfirmation = true
                    }

                    Button("重新开始注销验证") {
                        verificationCodeFocused = false
                        verificationCode = ""
                        self.challenge = nil
                        appState.clearError()
                    }
                    .font(BNBUFont.labelMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .accessibilityIdentifier("accountDeletion.restart")
                }
            }
        }
    }

    private func deletionFact(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: BNBUSpacing.space12) {
            Image(systemName: icon)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(BNBUFont.titleSmall)
                Text(verbatim: detail)
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var apiLocale: String {
        locale.identifier.lowercased().hasPrefix("en") ? "en" : "zh-CN"
    }

    private var isValidCode: Bool {
        ContactBindingRule.isValidStudentSignInCode(
            verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// Android's `AboutScreen`: product name, version, and a route to the changelog.
struct AboutView: View {
    let onBack: () -> Void

    @State private var showChangelog = false

    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    BNBUBackRow(action: onBack)
                    Text("关于")
                        .font(BNBUFont.headlineSmall)
                        .tracking(BNBUFont.Tracking.headlineSmall)
                        .foregroundStyle(BNBUTheme.onSurface)

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BNBU 体育")
                                .font(BNBUFont.titleLarge)
                                .foregroundStyle(BNBUTheme.onSurface)
                            Text(verbatim: "\(BNBUL10n.text("App 版本")) \(BNBUAppVersion.displayName)")
                                .font(BNBUFont.bodyMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        showChangelog = true
                    } label: {
                        SwissPanel {
                            HStack(spacing: BNBUSpacing.space12) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(BNBUFont.bodyLarge)
                                    .foregroundStyle(BNBUTheme.primary)
                                Text("更新日志")
                                    .font(BNBUFont.titleMedium)
                                    .foregroundStyle(BNBUTheme.onSurface)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(BNBUFont.bodyMedium)
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            }
                        }
                    }
                    .buttonStyle(BNBUPressStyle())
                    .accessibilityIdentifier("about.changelog")
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .sheet(isPresented: $showChangelog) {
            NavigationStack {
                ChangelogView { showChangelog = false }
            }
        }
        .accessibilityIdentifier("screen.about")
    }
}

/// Android's `ChangelogScreen`.
struct ChangelogView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    BNBUBackRow(action: onBack)
                    Text("更新日志")
                        .font(BNBUFont.headlineSmall)
                        .tracking(BNBUFont.Tracking.headlineSmall)
                        .foregroundStyle(BNBUTheme.onSurface)

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: BNBUAppVersion.displayName)
                                .font(BNBUFont.titleLarge)
                                .foregroundStyle(BNBUTheme.onSurface)
                                .padding(.bottom, 4)
                            Text("首个可用版本")
                                .font(BNBUFont.labelLarge)
                                .foregroundStyle(BNBUTheme.primary)
                                .padding(.bottom, 14)
                            ChangelogItem("支持课程、打卡、成绩和服务申请等核心功能。")
                            ChangelogItem("提供帮助中心、隐私政策和问题反馈入口。")
                            ChangelogItem("支持离线缓存和系统通知，便于及时查看业务状态。")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 24)
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .accessibilityIdentifier("screen.changelog")
    }
}

private struct ChangelogItem: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: BNBUSpacing.space8) {
            Text(verbatim: "•")
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.primary)
            Text(LocalizedStringKey(text))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 10)
    }
}
