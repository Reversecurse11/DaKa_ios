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
        HStack(alignment: .top, spacing: BNBUSpacing.space12) {
            Text(LocalizedStringKey(label))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(verbatim: value)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurface)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    @State private var showLogoutConfirmation = false

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
                // The contact-binding page needs the passwordless auth endpoints,
                // so the row states why it cannot be opened yet instead of
                // navigating to an empty screen.
                BNBUNavigationSettingRow(
                    title: "绑定或更换邮箱、手机号",
                    systemImage: "phone",
                    detail: "验证码登录接口发布后开放",
                    enabled: false
                ) {}
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
                // Android's feedback form uploads screenshots as COS keys and
                // reads a ticket list; both endpoints are still unpublished, so
                // the row states that instead of opening an empty form.
                BNBUNavigationSettingRow(
                    title: "问题反馈",
                    systemImage: "exclamationmark.bubble",
                    detail: "反馈工单接口发布后开放",
                    enabled: false,
                    accessibilityIdentifier: "settings.feedback"
                ) {}
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

enum BNBUAppVersion {
    static var displayName: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        guard let build, !build.isEmpty, build != short else { return short }
        return "\(short) (\(build))"
    }
}
