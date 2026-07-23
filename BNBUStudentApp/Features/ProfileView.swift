import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageSettings: BNBULanguageSettings
    @AppStorage(BNBUAppearanceMode.defaultsKey) private var appearanceModeRaw = BNBUAppearanceMode.light.rawValue
    @State private var showExemptionCenter = false
    @State private var showPrivacyPolicy = false
    @State private var showEnduranceScoring = false
    @State private var showHelpCenter = false
    @State private var showOnboarding = false
    @State private var showLogoutConfirmation = false
    @State private var showPendingDiscardConfirmation = false
    @State private var pendingScopeToDiscard: String?

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileHeader
                    applicationPanel
                    pendingMutationPanel
                    teacherPanel
                    identityPanel
                    settingsPanel
                    // Keep the last action fully above the custom bottom bar
                    // after the settings section grows.
                    Spacer(minLength: 120)
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .accessibilityIdentifier("screen.profile")
        .sheet(isPresented: $showExemptionCenter) {
            ExemptionCenterSheet()
                .environmentObject(appState)
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
        .sheet(isPresented: $showEnduranceScoring) {
            EnduranceScoringSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showHelpCenter) {
            HelpCenterView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
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
        .confirmationDialog(
            "放弃这次待重试操作？",
            isPresented: $showPendingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("放弃待重试操作", role: .destructive) {
                if let pendingScopeToDiscard {
                    appState.discardPendingRemoteMutation(scope: pendingScopeToDiscard)
                }
                self.pendingScopeToDiscard = nil
            }
            Button("继续保留", role: .cancel) {
                pendingScopeToDiscard = nil
            }
        } message: {
            Text("放弃后将删除本机保存的幂等键和已上传凭证引用；如仍需提交，请从对应页面重新开始。")
        }
    }

    private var profileHeader: some View {
        let student = appState.workspace.student
        let tags = [
            student.className,
            student.gender.title,
            appState.academicProjection.grade
        ].filter { !$0.isEmpty }.joined(separator: " · ")

        return SwissPanel {
            HStack(alignment: .center, spacing: 14) {
                BrandMark(compact: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(student.name)
                        .font(.title2.weight(.medium))
                    Text("\(student.displayStudentNumber) · \(student.college)")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    if !tags.isEmpty {
                        Text(tags)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }
                }
                Spacer()
                StatusBadge(text: student.status, filled: true)
            }
        }
    }

    private var applicationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(eyebrow: "APPLICATIONS", title: "申请与审核")

            ProfileNavigationCard(
                title: "免测与免打卡",
                detail: "查看申请进度、提交新申请",
                systemImage: "figure.strengthtraining.traditional",
                accessibilityIdentifier: "profile.exemption.button"
            ) {
                showExemptionCenter = true
            }

            ProfileNavigationCard(
                title: "耐力跑成绩换算",
                detail: "按服务器规则换算 800m / 1000m 成绩",
                systemImage: "gauge.with.dots.needle.67percent",
                accessibilityIdentifier: "profile.endurance.button"
            ) {
                showEnduranceScoring = true
            }
        }
    }

    @ViewBuilder
    private var pendingMutationPanel: some View {
        if !appState.pendingRemoteMutationSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(eyebrow: "RECOVERY", title: "本地恢复操作")
                Text("未确认的提交可沿用原请求安全重试；服务器已确认成功的条目只会清理本地标记，绝不会再次提交。")
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                if let errorMessage = appState.errorMessage {
                    BNBUErrorPanel(message: errorMessage)
                }

                ForEach(appState.pendingRemoteMutationSummaries) { summary in
                    SwissPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: summary.isServerConfirmed ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill")
                                    .foregroundStyle(BNBUTheme.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.title)
                                        .font(.headline.weight(.medium))
                                    if let target = summary.target, !target.isEmpty {
                                        Text("对象：\(target)")
                                            .font(.caption.weight(.regular))
                                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                    }
                                    Text(summary.isServerConfirmed
                                        ? "服务器已确认成功；当前仅需清理本地标记，请勿重新提交。"
                                        : "已安全保留 \(summary.uploadedProofCount) 个上传凭证引用")
                                        .font(.caption.weight(.regular))
                                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                }
                                Spacer()
                            }

                            if appState.canRetryPendingRemoteMutation(scope: summary.scope) {
                                Button {
                                    Task {
                                        _ = await appState.retryPendingRemoteMutation(scope: summary.scope)
                                    }
                                } label: {
                                    Label(
                                        summary.isServerConfirmed ? "仅清理本地标记" : "继续安全重试",
                                        systemImage: summary.isServerConfirmed ? "trash.slash" : "arrow.clockwise"
                                    )
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(appState.isLoading)
                                .accessibilityIdentifier("profile.pending.retry.\(summary.scope)")
                            } else {
                                Text("当前不能自动重试：可能仍缺原始文件，或服务器中的目标状态已经变化。请核对后选择放弃并重新提交。")
                                    .font(.caption.weight(.regular))
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            }

                            Button("放弃这次操作", role: .destructive) {
                                pendingScopeToDiscard = summary.scope
                                showPendingDiscardConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("profile.pending.discard.\(summary.scope)")
                        }
                    }
                }
            }
            .accessibilityIdentifier("profile.pending.mutations")
        }
    }

    @ViewBuilder
    private var teacherPanel: some View {
        let teachers = Array(Set(appState.workspace.courses.map(\.teacher).filter { !$0.isEmpty })).sorted()
        if !teachers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(eyebrow: "MY TEACHER", title: "我的老师")
                ForEach(teachers, id: \.self) { teacher in
                    SwissPanel {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(BNBUTheme.primary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(teacher)
                                    .font(.headline.weight(.medium))
                                Text("任课教师")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(eyebrow: "IDENTITY", title: "组织认证与抵扣记录")

            if appState.workspace.memberships.isEmpty {
                EmptyPlaceholder(
                    title: "暂无认证记录",
                    message: "当前没有校队或社团抵扣认证。认证生效后，只能抵扣其他运动小时，不能替代课程相关小时。"
                )
            } else {
                ForEach(appState.workspace.memberships) { membership in
                    SwissPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(membership.typeTitle) · \(membership.organization)")
                                .font(.headline.weight(.medium))
                            Text("有效至 \(membership.validUntil)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            HStack(spacing: 8) {
                                StatusBadge(text: membership.status, filled: membership.status == "认证有效")
                                Text("抵扣: \(membership.offset)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(BNBUTheme.primary)
                            }
                            if !membership.comment.isEmpty && membership.comment != "offset" {
                                Label(membership.comment, systemImage: "bell")
                                    .font(.subheadline.weight(.regular))
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(BNBUTheme.surfaceVariant)
                                    .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    private var settingsPanel: some View {
        let student = appState.workspace.student
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(eyebrow: "SETTINGS", title: "设置")

            SwissPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SettingLine(label: "学生姓名", value: student.name)
                    SettingLine(label: "学号", value: student.displayStudentNumber)
                    SettingLine(label: "学院", value: student.college)
                    SettingLine(label: "班级", value: student.className.isEmpty ? "待完善" : student.className)
                    SettingLine(label: "入学年份", value: student.enrollmentYear.map(String.init) ?? "待完善")
                    SettingLine(label: "当前年级", value: appState.academicProjection.grade)
                    SettingLine(label: "计算年份", value: appState.academicProjection.academicYear)
                    SettingLine(label: "App 版本", value: "BNBU Student MVP 1.0")
                }
            }

            SwissPanel {
                VStack(spacing: 10) {
                    SecondaryActionButton(title: "帮助中心", systemImage: "questionmark.circle") {
                        showHelpCenter = true
                    }
                    SecondaryActionButton(title: "重新查看新手引导", systemImage: "sparkles.rectangle.stack") {
                        showOnboarding = true
                    }
                    SecondaryActionButton(title: "隐私政策", systemImage: "hand.raised") {
                        showPrivacyPolicy = true
                    }
                    PrimaryActionButton(
                        title: "退出登录",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        accessibilityIdentifier: "profile.logout.button"
                    ) {
                        showLogoutConfirmation = true
                    }
                }
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观模式")
                        .font(.headline.weight(.medium))
                    Picker("外观模式", selection: $appearanceModeRaw) {
                        ForEach(BNBUAppearanceMode.allCases) { mode in
                            Text(LocalizedStringKey(shortAppearanceTitle(mode))).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("默认使用浅色模式；选择跟随系统后会随设备设置切换。")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("语言")
                        .font(.headline.weight(.medium))
                    Picker("语言", selection: languageSelection) {
                        ForEach(BNBULanguage.allCases) { language in
                            Text(LocalizedStringKey(language.title)).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("profile.language.picker")
                    Text("切换后立即生效；选择跟随系统后会随设备语言更新。课程名称等由教师或管理员录入的数据内容保持原文。")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
            }

        }
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
            set: { newValue in
                languageSettings.select(rawValue: newValue)
            }
        )
    }
}

private struct ProfileNavigationCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SwissPanel {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(BNBUTheme.primary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(title))
                            .font(.headline.weight(.medium))
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text(LocalizedStringKey(detail))
                            .font(.caption.weight(.regular))
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct SettingLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(LocalizedStringKey(label))
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ExemptionCenterSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showApplicationForm = false
    @State private var supplementApplication: ExemptionApplication?

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(eyebrow: "APPLICATION", title: "免测与免打卡")

                        if appState.workspace.exemptions.isEmpty {
                            EmptyPlaceholder(title: "暂无申请", message: "提交后的免测申请会显示在这里。")
                        } else {
                            ForEach(appState.workspace.exemptions) { application in
                                SwissPanel {
                                    ExemptionApplicationRow(application: application) {
                                        supplementApplication = application
                                    }
                                }
                            }
                        }

                        PrimaryActionButton(title: "提交新申请", systemImage: "plus") {
                            showApplicationForm = true
                        }
                    }
                    .padding(BNBUSpacing.screen)
                }
            }
            .navigationTitle("免测与免打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showApplicationForm) {
                ExemptionApplicationSheet(mode: .create)
                    .environmentObject(appState)
            }
            .sheet(item: $supplementApplication) { application in
                ExemptionApplicationSheet(mode: .supplement(application))
                    .environmentObject(appState)
            }
        }
    }
}

private struct EnduranceScoringSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = ""
    @State private var seconds = ""
    @State private var validationMessage: String?
    @State private var result: EnduranceScoreResult?

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(eyebrow: "ENDURANCE SCORING", title: "耐力跑成绩换算")

                        SwissPanel {
                            HStack(spacing: 10) {
                                Image(systemName: "figure.run")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(BNBUTheme.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("测试项目: \(runType)")
                                        .font(.headline.weight(.medium))
                                    Text("\(appState.workspace.student.gender.title) · \(appState.academicProjection.grade)")
                                        .font(.subheadline.weight(.regular))
                                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                }
                            }
                        }

                        SwissPanel {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .bottom, spacing: 12) {
                                    durationField(title: "分钟", placeholder: "0", text: $minutes)
                                    Text("′")
                                        .font(.system(size: 28, weight: .medium))
                                    durationField(title: "秒", placeholder: "00", text: $seconds)
                                    Text("″")
                                        .font(.system(size: 28, weight: .medium))
                                }

                                PrimaryActionButton(
                                    title: appState.isLoading ? "换算中…" : "开始换算",
                                    systemImage: "timer"
                                ) {
                                    convert()
                                }
                                .disabled(appState.isLoading)
                            }
                        }

                        if let message = validationMessage ?? appState.errorMessage {
                            BNBUErrorPanel(message: message)
                        }

                        if let result {
                            SectionTitle(eyebrow: "RESULT", title: "换算结果")
                            SwissPanel {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("单项得分")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                            Text("\(result.score)")
                                                .font(.system(size: 48, weight: .medium))
                                                .foregroundStyle(scoreColor(result.tier))
                                        }
                                        Spacer()
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("等级")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                            StatusBadge(text: result.tierTitle, filled: true)
                                        }
                                    }

                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(BNBUTheme.primary)
                                        Text("输入时间: \(result.timeSeconds / 60)′\(result.timeSeconds % 60)″")
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text("\(appState.workspace.student.gender.title) · \(appState.academicProjection.grade)")
                                            .font(.caption.weight(.regular))
                                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                    }
                                    .padding(12)
                                    .background(BNBUTheme.primaryContainer)
                                    .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(BNBUSpacing.screen)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("耐力跑成绩换算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { dismissBNBUKeyboard() }
                }
            }
        }
    }

    private var runType: String {
        appState.workspace.student.gender == .male ? "1000m" : "800m"
    }

    private func durationField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .bnbuInputText()
                .padding(12)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(lineWidth: 1)
                .onChange(of: text.wrappedValue) { _, value in
                    text.wrappedValue = String(value.filter(\.isNumber).prefix(2))
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func convert() {
        let minuteValue = Int(minutes) ?? 0
        let secondValue = Int(seconds) ?? 0
        guard secondValue >= 0 && secondValue <= 59 else {
            validationMessage = "秒数请输入 0-59 之间的数字。"
            result = nil
            return
        }
        let totalSeconds = minuteValue * 60 + secondValue
        guard totalSeconds > 0 else {
            validationMessage = "请输入有效的跑步时间。"
            result = nil
            return
        }

        validationMessage = nil
        dismissBNBUKeyboard()
        Task {
            result = await appState.convertEndurance(timeSeconds: totalSeconds)
        }
    }

    private func scoreColor(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "excellent": return BNBUTheme.primary
        case "good": return BNBUTheme.tertiary
        case "pass": return BNBUTheme.secondary
        case "fail": return BNBUTheme.error
        default: return BNBUTheme.onSurfaceVariant
        }
    }
}
