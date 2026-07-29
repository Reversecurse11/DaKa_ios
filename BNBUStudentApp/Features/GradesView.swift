import SwiftUI

struct GradesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: "Grade Progress", title: "成绩进度")

                    statePanel
                    if gradeState.showsOfficialTotal {
                        totalPanel
                    }
                    if gradeState.showsComponents {
                        components
                        formulaPanel
                    }
                    missingPanel
                    tracePanel
                }
                .padding(BNBUSpacing.screen)
            }
            .refreshable {
                await appState.refreshRemoteWorkspace()
            }
        }
        .accessibilityIdentifier("screen.grades")
    }

    private var gradeState: CourseGradeState {
        appState.workspace.grades.state
    }

    private var statePanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("成绩状态")
                            .font(BNBUFont.titleMedium)
                        Spacer()
                        StatusBadge(text: gradeState.title, filled: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("成绩状态")
                            .font(BNBUFont.titleMedium)
                        StatusBadge(text: gradeState.title, filled: true)
                    }
                }
                Text(verbatim: BNBUL10n.dynamicText(gradeState.studentNotice))
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("grades.state.panel")
    }

    private var totalPanel: some View {
        SwissPanel {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    totalDescription
                    Spacer(minLength: 8)
                    totalScore
                }
                VStack(alignment: .leading, spacing: 12) {
                    totalDescription
                    totalScore
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var totalDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("总分预估")
                .font(BNBUFont.titleMedium)
            Text(verbatim: BNBUL10n.formatted(
                "基于当前已录入的 %lld 项成绩与权重规则展示，最终结果以教务汇总为准。",
                gradeComponents.count
            ))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var totalScore: some View {
        Text("\(appState.workspace.grades.total)")
            .font(.system(size: 54, weight: .regular))
            .foregroundStyle(BNBUTheme.ink)
    }

    private var components: some View {
        LazyVGrid(columns: componentColumns, spacing: 12) {
            ForEach(gradeComponents) { component in
                GradeComponentCard(component: component)
            }
        }
    }

    private var componentColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var formulaPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("总分计算")
                            .font(BNBUFont.titleMedium)
                        Spacer()
                        StatusBadge(text: "透明预估")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("总分计算")
                            .font(BNBUFont.titleMedium)
                        StatusBadge(text: "透明预估")
                    }
                }

                ForEach(gradeComponents) { component in
                    GradeContributionRow(component: component)
                }

                Divider()

                DetailFactRow(label: "加权合计", value: String(format: "%.1f", weightedTotal))
                if gradeState.showsOfficialTotal {
                    DetailFactRow(label: "四舍五入", value: "\(appState.workspace.grades.total)")
                }

                if !unrecordedComponents.isEmpty {
                    Text(verbatim: BNBUL10n.formatted(
                        "尚有 %lld 项成绩未录入，预估分会在教师录入后更新。",
                        unrecordedComponents.count
                    ))
                    .font(BNBUFont.labelMedium)
                    .foregroundStyle(BNBUTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("grades.items.unrecorded")
                }

                if !weightsAreComplete {
                    Text(verbatim: BNBUL10n.formatted(
                        "当前成绩构成的权重合计为 %@，尚未覆盖满分，预估分仅供参考。",
                        GradeWeightFormatter.percentText(weightSum)
                    ))
                    .font(BNBUFont.labelMedium)
                    .foregroundStyle(BNBUTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("grades.weights.incomplete")
                }
            }
        }
    }

    private var missingPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("缺失项 / 风险")
                            .font(BNBUFont.titleMedium)
                        Spacer()
                        StatusBadge(text: missingCountText)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("缺失项 / 风险")
                            .font(BNBUFont.titleMedium)
                        StatusBadge(text: missingCountText)
                    }
                }

                if appState.workspace.grades.missingItems.isEmpty {
                    Text("当前没有阻塞项。")
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.muted)
                } else {
                    ForEach(appState.workspace.grades.missingItems, id: \.self) { item in
                        Label(localizedMissingItem(item), systemImage: "exclamationmark.circle")
                            .font(BNBUFont.titleSmall)
                            .foregroundStyle(BNBUTheme.ink)
                    }
                }
            }
        }
    }

    private var tracePanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("来源追溯", systemImage: "scope")
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.primary)
                Text(verbatim: localizedSourceTrace(appState.workspace.grades.sourceTrace))
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var gradeComponents: [GradeComponent] {
        appState.workspace.grades.resolvedComponents
    }

    private var weightedTotal: Double {
        gradeComponents.reduce(0) { partialResult, component in
            partialResult + component.contribution
        }
    }

    private var weightSum: Double {
        gradeComponents.reduce(0) { $0 + $1.weight }
    }

    private var unrecordedComponents: [GradeComponent] {
        gradeComponents.filter { !$0.countsTowardEstimate }
    }

    /// A teacher-configured breakdown can be published before every slice is
    /// weighted, in which case the estimate is not comparable to a full score.
    private var weightsAreComplete: Bool {
        abs(weightSum - 1) < 0.005
    }

    private var missingCountText: String {
        let count = appState.workspace.grades.missingItems.count
        if count == 0 {
            return BNBUL10n.text("无缺失")
        }
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "\(count) 项"
        }
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func localizedMissingItem(_ item: String) -> String {
        let coursePrefix = "打卡未满：课程相关还差 "
        if item.hasPrefix(coursePrefix) {
            let rawHours = String(item.dropFirst(coursePrefix.count))
            return BNBUL10n.formatted(
                "打卡未满：课程相关还差 %@",
                localizedHourValue(rawHours)
            )
        }
        return BNBUL10n.dynamicText(item)
    }

    private func localizedHourValue(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "小时", with: "")
            .replacingOccurrences(of: "h", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hours = Double(normalized) else { return value }
        return hours.localizedHourText
    }

    private func localizedSourceTrace(_ trace: String) -> String {
        switch trace {
        case "server:grades-missing":
            return BNBUL10n.text("服务器：成绩尚未返回")
        case "API: /student/grades":
            return BNBUL10n.text("服务器：学生成绩接口")
        default:
            return BNBUL10n.dynamicText(trace)
        }
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

/// Server-configured weights are not necessarily whole percentages, so they
/// are rounded for display without inventing precision.
enum GradeWeightFormatter {
    static func percentText(_ weight: Double) -> String {
        let percent = weight * 100
        if abs(percent.rounded() - percent) < 0.05 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

private struct GradeComponentCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let component: GradeComponent

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: component.symbolName)
                        .font(BNBUFont.titleLarge)
                        .foregroundStyle(BNBUTheme.blue)
                    Spacer()
                    StatusBadge(text: GradeWeightFormatter.percentText(component.weight))
                }

                Text(verbatim: BNBUL10n.dynamicText(component.title))
                    .font(BNBUFont.titleMedium)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 68,
                        alignment: .topLeading
                    )

                if component.entryState == .recorded {
                    Text("\(component.score)")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(BNBUTheme.ink)
                } else {
                    Text(verbatim: BNBUL10n.dynamicText(component.entryState.title))
                        .font(BNBUFont.titleLarge)
                        .foregroundStyle(BNBUTheme.muted)
                        .frame(height: 50, alignment: .bottomLeading)
                }

                HourProgressBar(
                    value: component.entryState == .recorded ? Double(component.score) : 0,
                    total: 100
                )

                Text(verbatim: BNBUL10n.dynamicText(component.note))
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 52,
                        alignment: .topLeading
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct GradeContributionRow: View {
    let component: GradeComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: BNBUL10n.dynamicText(component.title))
                        .font(BNBUFont.titleSmall)
                    Spacer(minLength: 8)
                    contributionFormula
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: BNBUL10n.dynamicText(component.title))
                        .font(BNBUFont.titleSmall)
                    contributionFormula
                }
            }
            HourProgressBar(value: component.contribution, total: 30)
        }
    }

    private var contributionText: String {
        let weight = GradeWeightFormatter.percentText(component.weight)
        guard component.entryState != .notRecorded else {
            return "\(BNBUL10n.dynamicText(component.entryState.title)) × \(weight)"
        }
        return "\(component.score) × \(weight) = \(String(format: "%.1f", component.contribution))"
    }

    private var contributionFormula: some View {
        Text(verbatim: contributionText)
            .font(BNBUFont.bodyMedium)
            .foregroundStyle(BNBUTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
