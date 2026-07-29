import SwiftUI

/// Replicates the Android baseline `GradesScreen.kt`: a header plus exactly two
/// cards. 业务流程 v6.0 §1.4 limits the student view to the endurance-run result
/// and check-in hour completion — component names, weights, and weighted
/// contributions are teacher-side grading rules and must not be shown here.
struct GradesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    completionHeader
                    EnduranceRunCard(
                        gender: appState.workspace.student.gender,
                        timeSeconds: grades.enduranceRunTimeSeconds,
                        status: grades.enduranceRunStatus,
                        score: grades.enduranceRunScore
                    )
                    CheckInHoursCard(
                        progress: appState.workspace.progress,
                        rule: appState.workspace.hourRule
                    )
                }
                .padding(BNBUSpacing.screen)
            }
            .refreshable {
                await appState.refreshRemoteWorkspace()
            }
        }
        .accessibilityIdentifier("screen.grades")
    }

    private var grades: GradeRow {
        appState.workspace.grades
    }

    private var completionHeader: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space4) {
            SectionTitle(eyebrow: "", title: "体测与打卡")
            Text(verbatim: semesterProgressText)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var semesterProgressText: String {
        let calculatedAt = appState.workspace.student.gradeCalculatedAt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !calculatedAt.isEmpty else {
            return BNBUL10n.text("本学期完成情况")
        }
        return BNBUL10n.formatted("本学期完成情况 · 更新于 %@", GradeTimeFormatter.compact(calculatedAt))
    }
}

/// 800m/1000m outcome. An exemption or an absence carries a teacher-assigned
/// score, so those two states show the score line; a measured or missing result
/// does not.
private struct EnduranceRunCard: View {
    let gender: StudentGender
    let timeSeconds: Int?
    let status: EnduranceRunStatus
    let score: Int?

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                GradeCardTitle(
                    systemImage: "figure.run",
                    title: BNBUL10n.formatted("%@ 跑步", distanceText),
                    supportingText: supportingText
                )
                Text(verbatim: primaryText)
                    .font(BNBUFont.headlineMedium.weight(.semibold))
                    .foregroundStyle(BNBUTheme.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .exempt || status == .absent {
                    Text(verbatim: scoreText)
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var distanceText: String {
        switch gender {
        case .male: return BNBUL10n.text("1000 米")
        case .female: return BNBUL10n.text("800 米")
        case .unknown: return BNBUL10n.text("800 米 / 1000 米")
        }
    }

    private var recordedTime: String? {
        guard let timeSeconds, timeSeconds > 0 else { return nil }
        return GradeTimeFormatter.runTime(timeSeconds)
    }

    private var primaryText: String {
        switch status {
        case .recorded, .notRecorded:
            return recordedTime ?? BNBUL10n.text("暂未记录")
        case .exempt:
            return BNBUL10n.text("免测")
        case .absent:
            return BNBUL10n.text("缺考（计 0 分）")
        }
    }

    private var supportingText: String {
        switch status {
        case .recorded, .notRecorded:
            return BNBUL10n.text("耐力跑测试用时")
        case .exempt:
            return BNBUL10n.text("耐力跑免测 · 教师评分")
        case .absent:
            return BNBUL10n.text("耐力跑缺考状态")
        }
    }

    /// An absence always displays as zero regardless of what the server sends.
    private var scoreText: String {
        let resolved = status == .absent ? 0 : score
        guard let resolved else { return BNBUL10n.text("成绩：暂未评分") }
        return BNBUL10n.formatted("成绩：%lld 分", resolved)
    }
}

private struct CheckInHoursCard: View {
    let progress: StudentProgress
    let rule: SportHourRule

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                GradeCardTitle(
                    systemImage: "checkmark.circle.fill",
                    title: BNBUL10n.text("打卡学时"),
                    supportingText: supportingText
                )

                HStack(alignment: .bottom, spacing: 0) {
                    Text(verbatim: GradeHourFormatter.number(completed))
                        .font(BNBUFont.headlineMedium.weight(.semibold))
                        .foregroundStyle(BNBUTheme.onSurface)
                    Text(verbatim: BNBUL10n.formatted(" / %@ 小时", GradeHourFormatter.number(required)))
                        .font(BNBUFont.bodyLarge)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .padding(.leading, BNBUSpacing.space4)
                        .padding(.bottom, 3)
                }

                if required > 0 {
                    HourProgressBar(value: completed, total: required)
                }

                HStack(alignment: .top, spacing: BNBUSpacing.space16) {
                    GradeHourBreakdown(
                        label: BNBUL10n.text("课程相关"),
                        completed: progress.course,
                        required: rule.courseRequired
                    )
                    GradeHourBreakdown(
                        label: BNBUL10n.text("其他运动"),
                        completed: progress.general,
                        required: rule.generalRequired
                    )
                }
            }
        }
    }

    private var completed: Double { max(progress.course + progress.general, 0) }
    private var required: Double { max(rule.total, 0) }
    private var remaining: Double { max(required - completed, 0) }
    private var isComplete: Bool { required > 0 && completed >= required }

    private var supportingText: String {
        isComplete
            ? BNBUL10n.text("已完成本学期打卡要求")
            : BNBUL10n.formatted("还需 %@ 小时", GradeHourFormatter.number(remaining))
    }
}

private struct GradeCardTitle: View {
    let systemImage: String
    let title: String
    let supportingText: String

    var body: some View {
        HStack(spacing: BNBUSpacing.space12) {
            Image(systemName: systemImage)
                .font(.system(size: 21))
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 40, height: 40)
                .background(
                    BNBUTheme.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                Text(verbatim: supportingText)
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GradeHourBreakdown: View {
    let label: String
    let completed: Double
    let required: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(verbatim: BNBUL10n.formatted(
                "%@ / %@ 小时",
                GradeHourFormatter.number(completed),
                GradeHourFormatter.number(required)
            ))
                .font(BNBUFont.bodyMedium.weight(.medium))
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bare hour numbers; the unit belongs to the surrounding localized string so
/// that Chinese and English can place it differently.
enum GradeHourFormatter {
    static func number(_ value: Double) -> String {
        if value.rounded(.down) == value {
            return String(Int(value))
        }
        return String(format: "%.1f", locale: BNBUL10n.locale, value)
    }
}

enum GradeTimeFormatter {
    static func runTime(_ totalSeconds: Int) -> String {
        String(format: "%d′%02d″", totalSeconds / 60, totalSeconds % 60)
    }

    /// Server timestamps arrive as ISO-8601; the baseline trims them to minute
    /// precision rather than reformatting into a locale-specific style.
    static func compact(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "T", with: " ")
        if normalized.count >= 16 {
            return String(normalized.prefix(16))
        }
        if normalized.count >= 10 {
            return String(normalized.prefix(10))
        }
        return normalized
    }
}

enum ExemptionSheetMode {
    case create
    case supplement(ExemptionApplication)

    var title: String {
        switch self {
        case .create: return "提交免测申请"
        case .supplement: return "补充免测材料"
        }
    }

    var submitTitle: String {
        switch self {
        case .create: return "提交申请"
        case .supplement: return "提交补充材料"
        }
    }

    var systemImage: String {
        switch self {
        case .create: return "paperplane.fill"
        case .supplement: return "arrow.up.doc.fill"
        }
    }

    var application: ExemptionApplication? {
        if case .supplement(let application) = self { return application }
        return nil
    }
}

struct ExemptionApplicationRow: View {
    let application: ExemptionApplication
    var onSupplement: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: application.item.symbolName)
                    .font(BNBUFont.titleLarge)
                    .foregroundStyle(BNBUTheme.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(application.item.rawValue))
                            .font(BNBUFont.titleSmall)
                            .foregroundStyle(BNBUTheme.ink)
                        Spacer()
                        StatusBadge(text: application.status.rawValue, filled: application.status == .approved)
                    }

                    Text(application.reason)
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.ink)

                    Text(application.teacherFeedback)
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                StatusBadge(text: application.submittedAt.isEmpty ? "待同步时间" : application.submittedAt)
                StatusBadge(text: application.proofSummary)
                Spacer()
            }

            if application.status.canSupplement {
                if let onSupplement {
                    Button(action: onSupplement) {
                        Label("补充材料", systemImage: "arrow.up.doc")
                            .font(BNBUFont.titleSmall)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("exemption.supplement.\(application.id)")
                }
            }
        }
    }
}

struct ExemptionApplicationSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let mode: ExemptionSheetMode
    @FocusState private var focusedField: ExemptionFormField?
    @State private var selectedItem: ExemptionItem
    @State private var reason: String
    @State private var detail: String
    @State private var proofAttachments: [ProofAttachment]
    @State private var isConfirmationPresented = false

    init(mode: ExemptionSheetMode) {
        self.mode = mode
        _selectedItem = State(initialValue: mode.application?.item ?? .run800m)
        _reason = State(initialValue: "")
        _detail = State(initialValue: "")
        _proofAttachments = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(eyebrow: "Exemption", title: mode.title)

                        if let errorMessage = appState.errorMessage {
                            BNBUErrorPanel(message: errorMessage)
                        }

                        formPanel
                        ProofAttachmentPanel(
                            attachments: $proofAttachments,
                            maxAttachmentCount: ExemptionProofRule.maxAttachmentCount,
                            summaryText: ExemptionProofRule.summaryText
                        )

                        if let validationHint {
                            Text(validationHint)
                                .font(BNBUFont.labelMedium)
                                .foregroundStyle(BNBUTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(BNBUTheme.blueSoft)
                                .bnbuOutlinedSurface()
                        }

                        DisabledAwareButton(
                            title: mode.submitTitle,
                            systemImage: mode.systemImage,
                            isDisabled: !canSubmit || appState.isLoading,
                            accessibilityIdentifier: "exemption.submit.button"
                        ) {
                            focusedField = nil
                            dismissBNBUKeyboard()
                            isConfirmationPresented = true
                        }
                    }
                    .padding(BNBUSpacing.screen)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle(LocalizedStringKey(mode.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        focusedField = nil
                        dismissBNBUKeyboard()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedField = nil
                        dismissBNBUKeyboard()
                    }
                    .font(BNBUFont.titleSmall)
                }
            }
            .confirmationDialog(
                mode.title,
                isPresented: $isConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button {
                    focusedField = nil
                    dismissBNBUKeyboard()
                    Task {
                        if await submit() {
                            dismiss()
                        }
                    }
                } label: {
                    Text(LocalizedStringKey(mode.submitTitle))
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(mode.application == nil
                    ? "确认提交后将进入老师审核流程。"
                    : "确认提交后，补充凭证将进入老师复审流程。")
            }
        }
        .onAppear {
            restorePendingAttemptIfAvailable()
        }
    }

    private var formPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("申请项目")
                        .font(BNBUFont.titleSmall)
                    Picker("申请项目", selection: $selectedItem) {
                        ForEach(ExemptionItem.allCases) { item in
                            Label {
                                Text(LocalizedStringKey(item.rawValue))
                            } icon: {
                                Image(systemName: item.symbolName)
                            }
                            .tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(mode.application != nil)
                    .accessibilityIdentifier("exemption.item.picker")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("申请原因")
                        .font(BNBUFont.titleSmall)
                    TextField("例如：膝关节运动损伤", text: $reason)
                        .bnbuInputText()
                        .accessibilityLabel("申请原因")
                        .accessibilityHint("至少 2 个字符，与情况说明合计最多 2000 个字符")
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(BNBUTheme.surface)
                        .bnbuOutlinedSurface(lineWidth: 1.5)
                        .focused($focusedField, equals: .reason)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = .detail
                        }
                        .accessibilityIdentifier("exemption.reason.field")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("情况说明")
                        .font(BNBUFont.titleSmall)
                    TextEditor(text: $detail)
                        .bnbuInputText()
                        .accessibilityLabel("情况说明")
                        .accessibilityHint("必填，与申请原因合计最多 2000 个字符")
                        .frame(minHeight: 118)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(BNBUTheme.surface)
                        .bnbuOutlinedSurface(lineWidth: 1.5)
                        .focused($focusedField, equals: .detail)
                        .accessibilityIdentifier("exemption.detail.editor")
                    Text(LocalizedStringKey(selectedItem.proofHint))
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.muted)
                }
            }
        }
    }

    private var canSubmit: Bool {
        let hasValidProof = !proofAttachments.isEmpty &&
            ExemptionProofRule.accepts(proofAttachments) &&
            proofAttachments.allSatisfy(\.isValidForUpload)
        return ExemptionInputRule.validationMessage(reason: trimmedReason, detail: trimmedDetail) == nil &&
            (hasValidProof || canResumePendingAttempt)
    }

    private var validationHint: String? {
        if canResumePendingAttempt {
            return "已恢复上次未确认的提交。继续提交会复用同一幂等键和已上传凭证，不会重复上传。"
        }
        if proofAttachments.isEmpty {
            return "请至少添加 1 个医院证明、校医室证明或相关材料。"
        }
        if proofAttachments.contains(where: { !$0.isValidForUpload }) {
            return "有凭证超过大小限制，请删除或替换后再提交。"
        }
        if let proofLimitMessage = ExemptionProofRule.validationMessage(for: proofAttachments) {
            return proofLimitMessage
        }
        if let inputMessage = ExemptionInputRule.validationMessage(reason: trimmedReason, detail: trimmedDetail) {
            return inputMessage
        }
        return nil
    }

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDetail: String {
        detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async -> Bool {
        if let application = mode.application {
            return await appState.submitExemptionSupplement(
                for: application,
                reason: trimmedReason,
                detail: trimmedDetail,
                proofAttachments: proofAttachments
            )
        }
        return await appState.submitExemption(
            item: selectedItem,
            reason: trimmedReason,
            detail: trimmedDetail,
            proofAttachments: proofAttachments
        )
    }

    private var canResumePendingAttempt: Bool {
        appState.canResumePendingExemption(
            applicationID: mode.application?.id,
            item: selectedItem,
            reason: trimmedReason,
            detail: trimmedDetail,
            proofAttachments: proofAttachments
        )
    }

    private func restorePendingAttemptIfAvailable() {
        guard reason.isEmpty,
              detail.isEmpty,
              proofAttachments.isEmpty,
              let recovery = appState.pendingExemptionFormRecovery(
                applicationID: mode.application?.id
              ) else {
            return
        }
        selectedItem = recovery.item
        reason = recovery.reason
        detail = recovery.detail
        proofAttachments = recovery.sourceProofs
    }
}

private enum ExemptionFormField: Hashable {
    case reason
    case detail
}
