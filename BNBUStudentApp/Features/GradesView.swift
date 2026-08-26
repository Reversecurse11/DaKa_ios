import SwiftUI
import UIKit

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
                        rule: appState.workspace.hourRule,
                        isRemoteMode: appState.isRemoteMode
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
    let isRemoteMode: Bool

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                GradeCardTitle(
                    systemImage: "checkmark.circle.fill",
                    title: BNBUL10n.text("打卡学时"),
                    supportingText: supportingText
                )

                HStack(alignment: .bottom, spacing: 0) {
                    Text(verbatim: primaryHoursText)
                        .font(BNBUFont.headlineMedium.weight(.semibold))
                        .foregroundStyle(BNBUTheme.onSurface)
                    if !isRemoteMode {
                        Text(verbatim: BNBUL10n.formatted(" / %@ 小时", GradeHourFormatter.number(required)))
                            .font(BNBUFont.bodyLarge)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            .padding(.leading, BNBUSpacing.space4)
                            .padding(.bottom, 3)
                    }
                }

                if !isRemoteMode, required > 0 {
                    HourProgressBar(value: completed, total: required)
                }

                HStack(alignment: .top, spacing: BNBUSpacing.space16) {
                    GradeHourBreakdown(
                        label: BNBUL10n.text("课程相关"),
                        completed: progress.course,
                        required: isRemoteMode ? nil : rule.courseRequired
                    )
                    GradeHourBreakdown(
                        label: BNBUL10n.text("其他运动"),
                        completed: progress.general,
                        required: isRemoteMode ? nil : rule.generalRequired
                    )
                }
            }
        }
    }

    private var completed: Double {
        if isRemoteMode {
            return max(progress.authoritativeTotalHours ?? 0, 0)
        }
        return max(progress.course + progress.general, 0)
    }
    private var required: Double { max(rule.total, 0) }
    private var remaining: Double { max(required - completed, 0) }
    private var isComplete: Bool { required > 0 && completed >= required }

    private var primaryHoursText: String {
        guard !isRemoteMode else {
            let total = progress.authoritativeTotalHours ?? (progress.course + progress.general)
            return BNBUL10n.formatted("%@ 小时", GradeHourFormatter.number(total))
        }
        return GradeHourFormatter.number(completed)
    }

    private var supportingText: String {
        if isRemoteMode {
            switch progress.authoritativeQualificationStatus {
            case "QUALIFIED":
                return BNBUL10n.text("已按有效打卡累计；服务端已确认达标")
            case "NOT_QUALIFIED":
                return BNBUL10n.text("已按有效打卡累计；服务端确认进行中")
            default:
                return BNBUL10n.text("已按有效打卡记录累计")
            }
        }
        return isComplete
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
    let required: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(verbatim: required.map {
                BNBUL10n.formatted(
                    "%@ / %@ 小时",
                    GradeHourFormatter.number(completed),
                    GradeHourFormatter.number($0)
                )
            } ?? BNBUL10n.formatted("%@ 小时（仅分类）", GradeHourFormatter.number(completed)))
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

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(application.item.rawValue))
                            .font(BNBUFont.titleSmall)
                            .foregroundStyle(BNBUTheme.ink)
                        Spacer()
                        StatusBadge(text: application.status.rawValue, filled: application.status == .approved)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(BNBUFont.labelMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        Text(application.reason)
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let proofCountSummary = application.proofCountSummary {
                        Text(verbatim: proofCountSummary)
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.primary)
                    }

                    if !application.teacherFeedback.isEmpty {
                        reviewNote
                    }
                }
            }

            Text(verbatim: submissionFooter)
                .font(BNBUFont.bodySmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

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

    private var reviewNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("审核意见")
                    .font(BNBUFont.titleSmall)
                    .foregroundStyle(BNBUTheme.onSurface)
                Text(application.teacherFeedback)
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
    }

    private var submissionFooter: String {
        let time = application.submittedAt.isEmpty
            ? BNBUL10n.text("待同步时间")
            : application.submittedAt
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "提交时间：\(time) · 点击查看详情"
        }
        return "Submitted \(time) · Tap for details"
    }
}

/// Mirrors Android `ExemptionTypeSelector`: a two-column grid of 56pt cells,
/// `primaryContainer` when picked and `surfaceVariant` otherwise.
private struct ExemptionTypeSelector: View {
    @Binding var selected: ExemptionItem
    let items: [ExemptionItem]
    let isDisabled: Bool
    let title: (ExemptionItem) -> String

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row) { item in
                        cell(for: item)
                    }
                    // Keeps a trailing odd cell at half width like the baseline.
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var rows: [[ExemptionItem]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }

    private func cell(for item: ExemptionItem) -> some View {
        let isSelected = item == selected
        return Button {
            selected = item
        } label: {
            Text(verbatim: title(item))
                .font(BNBUFont.bodyMedium)
                .fontWeight(isSelected ? .semibold : .regular)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isSelected ? BNBUTheme.onPrimaryContainer : BNBUTheme.onSurfaceVariant)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(isSelected ? BNBUTheme.primaryContainer : BNBUTheme.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
        }
        .buttonStyle(BNBUPressStyle())
        .disabled(isDisabled)
        .animation(.easeInOut(duration: BNBUMotion.standard), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("exemption.type.\(item.apiValue)")
    }
}

struct ExemptionApplicationSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let mode: ExemptionSheetMode
    @FocusState private var organizationFocused: Bool
    @FocusState private var reasonFocused: Bool
    @FocusState private var detailFocused: Bool
    @State private var selectedItem: ExemptionItem
    @State private var reason: String
    @State private var detail: String
    @State private var organization: String
    @State private var proofAttachments: [ProofAttachment]
    @State private var recoveryNotice: String?
    @State private var submittedForm = false
    private let livePhotoPolicy = ExemptionLivePhotoPolicy(
        maxAttachmentCount: ExemptionProofRule.maxAttachmentCount
    )

    init(mode: ExemptionSheetMode) {
        self.mode = mode
        _selectedItem = State(initialValue: mode.application?.item ?? .run800m)
        _reason = State(initialValue: "")
        _detail = State(initialValue: "")
        _organization = State(initialValue: mode.application?.organization ?? "")
        _proofAttachments = State(initialValue: [])
        _recoveryNotice = State(initialValue: nil)
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
                        livePhotoPanel

                        if let validationHint {
                            Text(verbatim: validationHint)
                                .font(BNBUFont.labelMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(BNBUTheme.surfaceVariant)
                                .bnbuOutlinedSurface()
                                .accessibilityIdentifier("exemption.validation.message")
                        }

                        DisabledAwareButton(
                            title: appState.isSubmittingExemption
                                ? exemptionText("提交中…", "Submitting…")
                                : mode.submitTitle,
                            systemImage: mode.systemImage,
                            isDisabled: !canAttemptSubmit || appState.isSubmittingExemption,
                            accessibilityIdentifier: "exemption.submit.button"
                        ) {
                            submittedForm = true
                            if needsOrganization {
                                organizationFocused = true
                                return
                            }
                            if trimmedReason.count < 2 {
                                reasonFocused = true
                                return
                            }
                            if trimmedDetail.isEmpty {
                                detailFocused = true
                                return
                            }
                            organizationFocused = false
                            reasonFocused = false
                            detailFocused = false
                            dismissBNBUKeyboard()
                            Task {
                                if await submit() {
                                    dismiss()
                                }
                            }
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
                        organizationFocused = false
                        reasonFocused = false
                        detailFocused = false
                        dismissBNBUKeyboard()
                        dismiss()
                    }
                    .disabled(appState.isSubmittingExemption)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        organizationFocused = false
                        reasonFocused = false
                        detailFocused = false
                        dismissBNBUKeyboard()
                    }
                    .font(BNBUFont.titleSmall)
                }
            }
        }
        .interactiveDismissDisabled(appState.isSubmittingExemption)
        .onAppear {
            restorePendingAttemptIfAvailable()
            normalizeSelectedItemForStudent()
        }
        .onChange(of: appState.workspace.student.gender) { _, _ in
            normalizeSelectedItemForStudent()
        }
    }

    private var formPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    if mode.application == nil {
                        Text("选择申请类型")
                            .font(BNBUFont.labelMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        ExemptionTypeSelector(
                            selected: $selectedItem,
                            items: ExemptionItem.selectableItems(
                                gender: appState.workspace.student.gender
                            ),
                            isDisabled: appState.isSubmittingExemption,
                            title: itemTitle
                        )
                        // Container first, otherwise the identifier collapses
                        // the grid into one element and hides the type buttons.
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("exemption.item.picker")
                    } else {
                        Text("申请项目")
                            .font(BNBUFont.titleSmall)
                        HStack(spacing: 10) {
                            Image(systemName: selectedItem.symbolName)
                                .font(BNBUFont.titleLarge)
                                .foregroundStyle(BNBUTheme.primary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: itemTitle(selectedItem))
                                    .font(BNBUFont.titleSmall)
                                    .foregroundStyle(BNBUTheme.onSurface)
                                Text(verbatim: exemptionText(
                                    "补充材料沿用原申请项目",
                                    "Additional documents keep the original application item"
                                ))
                                .font(BNBUFont.bodySmall)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(BNBUTheme.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
                        .accessibilityIdentifier("exemption.item.picker")
                    }

                    if selectedItem.isCheckInExemption {
                        BNBUFormField(
                            label: "组织名称",
                            placeholder: "填写校队或社团名称",
                            text: $organization,
                            required: true,
                            helperText: "填写当前校队或社团的正式名称。",
                            errorText: submittedForm && needsOrganization ? "请填写校队或社团名称。" : nil,
                            characterLimit: ExemptionItem.maximumOrganizationLength,
                            enabled: !appState.isSubmittingExemption,
                            submitLabel: .next,
                            focusBinding: $organizationFocused,
                            accessibilityIdentifier: "exemption.organization.field"
                        )
                        .padding(.top, 4)
                    }

                    if hasPendingSameType {
                        Text(verbatim: exemptionText(
                            "你已有相同类型的待审核申请，请等待教师处理后再提交。",
                            "You already have a pending application of this type. Wait for the teacher's decision before submitting another."
                        ))
                            .font(BNBUFont.bodySmall)
                            .foregroundStyle(BNBUTheme.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("exemption.pending.sameType")
                    }
                }

                BNBUFormField(
                    label: "申请原因",
                    placeholder: "例如：膝关节运动损伤",
                    text: $reason,
                    required: true,
                    helperText: "至少 2 个字符；与情况说明合计最多 2000 个字符。",
                    errorText: submittedForm && trimmedReason.count < 2 ? "申请原因至少需要 2 个字符。" : nil,
                    characterLimit: 2000,
                    enabled: !appState.isSubmittingExemption,
                    submitLabel: .next,
                    onSubmit: { detailFocused = true },
                    focusBinding: $reasonFocused,
                    accessibilityIdentifier: "exemption.reason.field"
                )

                BNBUTextArea(
                    label: "情况说明",
                    text: $detail,
                    placeholder: "说明申请情况和需要审核的事实",
                    required: true,
                    helperText: proofHint(selectedItem),
                    errorText: submittedForm && trimmedDetail.isEmpty ? "请填写情况说明。" : nil,
                    characterLimit: 2000,
                    enabled: !appState.isSubmittingExemption,
                    focusBinding: $detailFocused,
                    accessibilityIdentifier: "exemption.detail.editor"
                )
            }
        }
    }

    private var livePhotoPanel: some View {
        ProofAttachmentPanel(
            attachments: $proofAttachments,
            maxAttachmentCount: ExemptionProofRule.maxAttachmentCount,
            summaryText: ExemptionProofRule.summaryText
        )
        .disabled(appState.isSubmittingExemption)
    }

    @ViewBuilder
    private func proofThumbnail(_ attachment: ProofAttachment) -> some View {
        if let data = attachment.thumbnailData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
        } else {
            Image(systemName: "doc.richtext")
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 52, height: 52)
                .background(BNBUTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
        }
    }

    private var canSubmit: Bool {
        let hasValidProof = !proofAttachments.isEmpty
            && ExemptionProofRule.accepts(proofAttachments)
            && proofAttachments.allSatisfy(\.isValidForUpload)
        return appState.isRemoteMode
            && appState.isWriteAllowed
            && !hasPendingSameType
            && !needsOrganization
            && ExemptionInputRule.validationMessage(reason: trimmedReason, detail: trimmedDetail) == nil
            && (hasValidProof || canResumePendingAttempt)
    }

    private var canAttemptSubmit: Bool {
        let hasValidProof = !proofAttachments.isEmpty
            && ExemptionProofRule.accepts(proofAttachments)
            && proofAttachments.allSatisfy(\.isValidForUpload)
        return appState.isRemoteMode
            && appState.isWriteAllowed
            && !hasPendingSameType
            && (hasValidProof || canResumePendingAttempt)
    }

    private var validationHint: String? {
        if !appState.isWriteAllowed {
            return appState.systemMode == .maintenance
                ? BNBUL10n.text("系统当前处于维护模式，暂不能提交或修改内容。")
                : BNBUL10n.text("系统当前处于只读模式，暂不能提交或修改内容。")
        }
        guard appState.isRemoteMode else {
            return exemptionText(
                "演示账号仅用于查看界面，不能提交免测申请或补充材料。",
                "The demo account is for interface preview only and cannot submit exemption requests or supplements."
            )
        }
        if let recoveryNotice {
            return recoveryNotice
        }
        if canResumePendingAttempt {
            return exemptionText(
                "已恢复上次未确认的提交。继续提交会复用同一幂等键和已上传凭证，不会重复上传。",
                "Your unconfirmed submission was restored. Retrying reuses the same idempotency key and uploaded proof."
            )
        }
        if hasPendingSameType {
            return nil
        }
        if needsOrganization {
            return exemptionText("请填写校队或社团名称", "Enter the team or club name.")
        }
        if proofAttachments.isEmpty {
            return exemptionText(
                "请至少通过相机或文件选择添加 1 项证明材料。",
                "Add at least one supporting document using the camera or file picker."
            )
        }
        if proofAttachments.contains(where: { !$0.isValidForUpload }) {
            return exemptionText(
                "有照片无效或超过 8MB，请删除后重新拍摄。",
                "A photo is invalid or larger than 8 MB. Remove it and take another photo."
            )
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

    private var trimmedOrganization: String {
        organization.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var needsOrganization: Bool {
        selectedItem.isCheckInExemption && trimmedOrganization.isEmpty
    }

    private func submit() async -> Bool {
        guard canSubmit else { return false }
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
            organization: trimmedOrganization,
            proofAttachments: proofAttachments
        )
    }

    private var canResumePendingAttempt: Bool {
        appState.canResumePendingExemption(
            applicationID: mode.application?.id,
            item: selectedItem,
            reason: trimmedReason,
            detail: trimmedDetail,
            organization: trimmedOrganization,
            proofAttachments: proofAttachments
        )
    }

    private var hasPendingSameType: Bool {
        mode.application == nil && appState.hasPendingExemption(for: selectedItem)
    }

    private var isAtPhotoLimit: Bool {
        proofAttachments.count >= livePhotoPolicy.maxAttachmentCount
    }

    private func isLiveCameraPhoto(_ attachment: ProofAttachment) -> Bool {
        attachment.type == .image && attachment.source == "摄像头"
    }

    private func remove(_ attachment: ProofAttachment) {
        proofAttachments.removeAll { $0.id == attachment.id }
        ProofTransientFileStore.removeManagedCopy(at: attachment.sourceFileURL)
    }

    private func formattedByteCount(_ byteCount: Int?) -> String {
        guard let byteCount else {
            return exemptionText("大小待确认", "Size unavailable")
        }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// Only the endurance run follows gender; a team or club choice is the
    /// student's and must survive a profile refresh.
    private func normalizeSelectedItemForStudent() {
        guard mode.application == nil, !selectedItem.isCheckInExemption else { return }
        selectedItem = appState.workspace.student.gender == .male ? .run1000m : .run800m
    }

    private func itemTitle(_ item: ExemptionItem) -> String {
        switch item {
        case .run800m:
            return exemptionText("800m 免测", "800 m test exemption")
        case .run1000m:
            return exemptionText("1000m 免测", "1000 m test exemption")
        case .enduranceRun:
            return exemptionText("800/1000 米耐力跑", "800/1000 m run")
        case .physicalTest:
            return exemptionText("体测免测", "Physical-test exemption")
        case .singlePhysicalItem:
            return exemptionText("体测单项免测", "Single-item exemption")
        case .team:
            return exemptionText("校队免打卡", "Team check-in exemption")
        case .club:
            return exemptionText("社团免打卡", "Club check-in exemption")
        }
    }

    private func proofHint(_ item: ExemptionItem) -> String {
        switch item {
        case .run800m:
            return exemptionText(
                "请现场拍摄医院或校医室证明，说明不适合参加 800 米耐力跑测试。",
                "Take a live photo of a hospital or campus-clinic certificate showing that the 800 m run is unsuitable."
            )
        case .run1000m:
            return exemptionText(
                "请现场拍摄医院或校医室证明，说明不适合参加 1000 米耐力跑测试。",
                "Take a live photo of a hospital or campus-clinic certificate showing that the 1000 m run is unsuitable."
            )
        default:
            return item.proofHint
        }
    }

    private func exemptionText(_ chinese: String, _ english: String) -> String {
        BNBUL10n.locale.identifier.hasPrefix("zh") ? chinese : english
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
        organization = recovery.organization
        proofAttachments = recovery.sourceProofs
    }
}

private struct ExemptionLivePhotoPolicy {
    let maxAttachmentCount: Int
}
