import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageSettings: BNBULanguageSettings
    @AppStorage(BNBUAppearanceMode.defaultsKey) private var appearanceModeRaw = BNBUAppearanceMode.light.rawValue
    @State private var showExemptionCenter = false
    @State private var showEnduranceScoring = false
    @State private var showPendingDiscardConfirmation = false
    @State private var pendingScopeToDiscard: String?
    @State private var showAccountDetails = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileHeader
                    applicationPanel
                    pendingMutationPanel
                    teacherPanel
                    identityPanel
                    Spacer(minLength: 40)
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .sheet(isPresented: $showAccountDetails) {
            NavigationStack {
                AccountDetailsView { showAccountDetails = false }
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ProfileSettingsView { showSettings = false }
                    .environmentObject(appState)
                    .environmentObject(languageSettings)
            }
        }
        .accessibilityIdentifier("screen.profile")
        .sheet(isPresented: $showExemptionCenter) {
            ExemptionCenterSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showEnduranceScoring) {
            EnduranceScoringSheet()
                .environmentObject(appState)
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

    /// Android's `ProfileHeader`: a page title with a gear button, then a
    /// tappable account card that opens the full account page. The three facts
    /// (student ID / class / grade) sit in a tinted strip inside the card.
    private var profileHeader: some View {
        let student = appState.workspace.student

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Text("我的")
                    .font(BNBUFont.headlineLarge)
                    .tracking(BNBUFont.Tracking.headlineLarge)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(BNBUFont.titleLarge)
                        .foregroundStyle(BNBUTheme.onSurface)
                        .frame(width: BNBUSpacing.touchTarget, height: BNBUSpacing.touchTarget)
                }
                .buttonStyle(BNBUPressStyle())
                .accessibilityLabel("设置")
                .accessibilityIdentifier("profile.settings.button")
            }

            Button {
                showAccountDetails = true
            } label: {
                SwissPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) {
                            BrandMark(compact: true)
                            Text(student.name)
                                .font(BNBUFont.headlineSmall)
                                .foregroundStyle(BNBUTheme.onSurface)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StatusBadge(text: student.status, filled: true)
                            Image(systemName: "chevron.right")
                                .font(BNBUFont.bodyMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }
                        profileFacts(student: student)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(BNBUPressStyle())
            .accessibilityLabel("账户资料")
            .accessibilityIdentifier("profile.accountDetails.button")
        }
    }

    private func profileFacts(student: StudentProfile) -> some View {
        HStack(alignment: .top, spacing: BNBUSpacing.space8) {
            profileFact(label: "学号", value: student.displayStudentNumber)
            profileFact(label: "班级", value: student.className.isEmpty ? "—" : student.className)
            profileFact(
                label: "年级",
                value: {
                    let grade = BNBUL10n.dynamicText(appState.academicProjection.grade)
                    return grade.isEmpty ? BNBUL10n.text("待计算") : grade
                }()
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
    }

    private func profileFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label))
                .font(BNBUFont.labelSmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(verbatim: value)
                .font(BNBUFont.titleSmall)
                .foregroundStyle(BNBUTheme.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(BNBUFont.bodySmall)
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
                                    Text(verbatim: BNBUL10n.dynamicText(summary.title))
                                        .font(BNBUFont.titleMedium)
                                    if let target = summary.target, !target.isEmpty {
                                        Text("对象：\(target)")
                                            .font(BNBUFont.bodySmall)
                                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                    }
                                    Text(verbatim: pendingMutationDetail(summary))
                                        .font(BNBUFont.bodySmall)
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
                                    Label {
                                        Text(LocalizedStringKey(
                                            summary.isServerConfirmed ? "仅清理本地标记" : "继续安全重试"
                                        ))
                                    } icon: {
                                        Image(systemName: summary.isServerConfirmed ? "trash.slash" : "arrow.clockwise")
                                    }
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(appState.isLoading)
                                .accessibilityIdentifier("profile.pending.retry.\(summary.scope)")
                            } else {
                                Text("当前不能自动重试：可能仍缺原始文件，或服务器中的目标状态已经变化。请核对后选择放弃并重新提交。")
                                    .font(BNBUFont.bodySmall)
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

    private func pendingMutationDetail(_ summary: PendingRemoteMutationSummary) -> String {
        if summary.isServerConfirmed {
            return BNBUL10n.text("服务器已确认成功；当前仅需清理本地标记，请勿重新提交。")
        }
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "已安全保留 \(summary.uploadedProofCount) 个上传凭证引用"
        }
        let noun = summary.uploadedProofCount == 1 ? "proof reference" : "proof references"
        return "\(summary.uploadedProofCount) uploaded \(noun) safely retained"
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
                                .font(BNBUFont.titleLarge)
                                .foregroundStyle(BNBUTheme.primary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(teacher)
                                    .font(BNBUFont.titleMedium)
                                Text("任课教师")
                                    .font(BNBUFont.labelMedium)
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
                                .font(BNBUFont.titleMedium)
                            Text("有效至 \(membership.validUntil)")
                                .font(BNBUFont.labelMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            HStack(spacing: 8) {
                                StatusBadge(text: membership.status, filled: membership.status == "认证有效")
                                Text("抵扣: \(membership.offset)")
                                    .font(BNBUFont.labelMedium)
                                    .foregroundStyle(BNBUTheme.primary)
                            }
                            if !membership.comment.isEmpty && membership.comment != "offset" {
                                Label(membership.comment, systemImage: "bell")
                                    .font(BNBUFont.bodyMedium)
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
                HStack(alignment: .top, spacing: 12) {
                    navigationIdentity
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var navigationIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(BNBUFont.titleLarge)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LocalizedStringKey(detail))
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingLine: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                Text(LocalizedStringKey(label))
                    .font(BNBUFont.titleSmall)
                Spacer(minLength: 12)
                Text(verbatim: value)
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(label))
                    .font(BNBUFont.titleSmall)
                Text(verbatim: value)
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
        }
    }
}

private enum ExemptionCenterTab: Hashable {
    case applications
    case submit
}

private struct ExemptionCenterSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ExemptionCenterTab = .applications
    @State private var showApplicationForm = false
    @State private var supplementApplication: ExemptionApplication?
    @State private var selectedApplication: ExemptionApplication?

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let selectedApplication {
                            detailContent(selectedApplication)
                        } else {
                            mainContent
                        }
                    }
                    .padding(BNBUSpacing.screen)
                }
            }
            .navigationTitle(exemptionCenterText("免测与免打卡", "Exemptions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .disabled(appState.isSubmittingExemption)
                }
            }
            .sheet(isPresented: $showApplicationForm, onDismiss: refreshAfterFormDismissal) {
                ExemptionApplicationSheet(mode: .create)
                    .environmentObject(appState)
            }
            .sheet(item: $supplementApplication) { application in
                ExemptionApplicationSheet(mode: .supplement(application))
                    .environmentObject(appState)
                    .onDisappear(perform: refreshAfterFormDismissal)
            }
        }
        .interactiveDismissDisabled(appState.isSubmittingExemption)
        .task {
            guard appState.isRemoteMode else { return }
            await appState.refreshRemoteExemptions()
        }
    }

    private var mainContent: some View {
        Group {
            SectionTitle(eyebrow: "APPLICATION", title: "免测与免打卡")

            SwissPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: appState.isRemoteMode
                        ? exemptionCenterText("申请说明", "Application information")
                        : exemptionCenterText("演示数据", "Demo data"))
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.primary)
                    Text(verbatim: exemptionCenterText(
                        "耐力跑免测仅适用于 800m / 1000m；通过后由任课教师单独评定耐力跑成绩。",
                        "Endurance-run exemptions apply only to 800 m / 1000 m. After approval, the instructor assigns the endurance-run result."
                    ))
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    if !appState.isRemoteMode {
                        Text(verbatim: exemptionCenterText(
                            "演示账号可查看申请状态，但不会伪造提交结果。正式提交请使用已连接服务器的学生账号。",
                            "The demo account can preview application states but does not fake submissions. Use a server-connected student account to submit."
                        ))
                            .font(BNBUFont.bodySmall)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            BNBUSegmentedControl(
                values: [.applications, .submit],
                selection: $selectedTab,
                title: {
                    $0 == .applications
                        ? exemptionCenterText("我的申请", "My applications")
                        : exemptionCenterText("提交申请", "Submit")
                },
                identifier: {
                    $0 == .applications
                        ? "exemption.tab.applications"
                        : "exemption.tab.submit"
                }
            )
            .disabled(appState.isSubmittingExemption)

            if selectedTab == .applications {
                applicationsContent
            } else {
                submitLauncher
            }
        }
    }

    @ViewBuilder
    private var applicationsContent: some View {
        if let errorMessage = appState.errorMessage {
            BNBUErrorPanel(message: errorMessage)
                .accessibilityIdentifier("exemption.applications.error")
            Button {
                Task { await appState.refreshRemoteExemptions() }
            } label: {
                Label(
                    exemptionCenterText("重新加载", "Retry"),
                    systemImage: "arrow.clockwise"
                )
                    .font(BNBUFont.titleSmall)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(appState.isLoadingExemptions)
            .accessibilityIdentifier("exemption.applications.retry")
        }

        if appState.isLoadingExemptions && appState.workspace.exemptions.isEmpty {
            ProgressView()
                .tint(BNBUTheme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .accessibilityIdentifier("exemption.applications.loading")
        } else if appState.workspace.exemptions.isEmpty {
            EmptyPlaceholder(
                title: exemptionCenterText("暂无申请", "No applications"),
                message: exemptionCenterText(
                    "你还没有提交过免测或免打卡申请。",
                    "You have not submitted a test- or check-in-exemption application."
                )
            )
        } else {
            ForEach(appState.workspace.exemptions) { application in
                Button {
                    selectedApplication = application
                } label: {
                    SwissPanel {
                        ExemptionApplicationRow(application: application)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exemption.application.\(application.id)")
            }
        }
    }

    private var submitLauncher: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    exemptionCenterText("新建免测申请", "New exemption request"),
                    systemImage: "doc.badge.plus"
                )
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                Text(verbatim: exemptionCenterText(
                    "申请项目会依据学生资料自动匹配为女生 800m 或男生 1000m。证明材料必须使用本机相机现场拍摄。",
                    "The item is matched automatically to 800 m for female students or 1000 m for male students. Proof must be photographed live with this device."
                ))
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryActionButton(
                    title: exemptionCenterText("填写申请", "Open application form"),
                    systemImage: "plus"
                ) {
                    showApplicationForm = true
                }
                .disabled(appState.isSubmittingExemption)
            }
        }
    }

    private func detailContent(_ application: ExemptionApplication) -> some View {
        Group {
            BNBUBackRow(
                title: exemptionCenterText("返回我的申请", "Back to applications")
            ) {
                selectedApplication = nil
            }
            .disabled(appState.isSubmittingExemption)
            .accessibilityIdentifier("exemption.detail.back")

            SectionTitle(eyebrow: "APPLICATION", title: application.item.rawValue)

            SwissPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(verbatim: exemptionCenterText("申请状态", "Application status"))
                            .font(BNBUFont.titleMedium)
                        Spacer()
                        StatusBadge(
                            text: application.status.rawValue,
                            filled: application.status == .approved
                        )
                    }
                    detailLine(
                        title: exemptionCenterText("申请理由", "Application reason"),
                        value: application.reason
                    )
                    if !application.detail.isEmpty {
                        detailLine(
                            title: exemptionCenterText("详细说明", "Details"),
                            value: application.detail
                        )
                    }
                    detailLine(
                        title: exemptionCenterText("提交时间", "Submitted"),
                        value: application.submittedAt.isEmpty
                            ? exemptionCenterText("待同步", "Pending sync")
                            : application.submittedAt
                    )
                }
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: exemptionCenterText("证明材料", "Supporting documents"))
                        .font(BNBUFont.titleMedium)
                    if application.proofFiles.isEmpty {
                        Text(verbatim: exemptionCenterText(
                            "尚未上传证明材料",
                            "No supporting documents uploaded"
                        ))
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    } else {
                        ForEach(Array(application.proofFiles.enumerated()), id: \.offset) { index, proof in
                            Label {
                                Text(verbatim: "\(index + 1). \(proof.fileName)")
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "doc.fill")
                            }
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }
                    }
                }
            }

            if !application.teacherFeedback.isEmpty {
                SwissPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: exemptionCenterText("处理意见", "Review comments"))
                            .font(BNBUFont.titleMedium)
                        Text(application.teacherFeedback)
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if application.status.canSupplement {
                PrimaryActionButton(
                    title: exemptionCenterText("补交证明材料", "Submit additional documents"),
                    systemImage: "arrow.up.doc.fill",
                    accessibilityIdentifier: "exemption.detail.supplement"
                ) {
                    supplementApplication = application
                }
                .disabled(appState.isSubmittingExemption)
            }
        }
    }

    private func detailLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(value)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshAfterFormDismissal() {
        guard appState.isRemoteMode else { return }
        Task {
            await appState.refreshRemoteExemptions()
            if let selectedApplication,
               let refreshed = appState.workspace.exemptions.first(where: { $0.id == selectedApplication.id }) {
                self.selectedApplication = refreshed
            }
        }
    }
}

private func exemptionCenterText(_ chinese: String, _ english: String) -> String {
    BNBUL10n.locale.identifier.hasPrefix("zh") ? chinese : english
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
                                    .font(BNBUFont.titleLarge)
                                    .foregroundStyle(BNBUTheme.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("测试项目: \(runType)")
                                        .font(BNBUFont.titleMedium)
                                    Text("\(appState.workspace.student.gender.title) · \(appState.academicProjection.grade)")
                                        .font(BNBUFont.bodyMedium)
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
                                                .font(BNBUFont.labelMedium)
                                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                            Text("\(result.score)")
                                                .font(.system(size: 48, weight: .medium))
                                                .foregroundStyle(scoreColor(result.tier))
                                        }
                                        Spacer()
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("等级")
                                                .font(BNBUFont.labelMedium)
                                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                            StatusBadge(text: result.tierTitle, filled: true)
                                        }
                                    }

                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(BNBUTheme.primary)
                                        Text("输入时间: \(result.timeSeconds / 60)′\(result.timeSeconds % 60)″")
                                            .font(BNBUFont.titleSmall)
                                        Spacer()
                                        Text("\(appState.workspace.student.gender.title) · \(appState.academicProjection.grade)")
                                            .font(BNBUFont.bodySmall)
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
                .font(BNBUFont.labelMedium)
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
