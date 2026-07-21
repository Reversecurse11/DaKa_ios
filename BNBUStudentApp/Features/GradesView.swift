import SwiftUI

struct GradesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: "Grade Progress", title: "成绩进度")

                    totalPanel
                    components
                    formulaPanel
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

    private var totalPanel: some View {
        SwissPanel {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("总分预估")
                        .font(.headline.weight(.medium))
                    Text("基于当前已录入的四块成绩与权重规则展示，最终结果以教务汇总为准。")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                }
                Spacer()
                Text("\(appState.workspace.grades.total)")
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(BNBUTheme.ink)
            }
        }
    }

    private var components: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(gradeComponents) { component in
                GradeComponentCard(component: component)
            }
        }
    }

    private var formulaPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("总分计算")
                        .font(.headline.weight(.medium))
                    Spacer()
                    StatusBadge(text: "透明预估")
                }

                ForEach(gradeComponents) { component in
                    GradeContributionRow(component: component)
                }

                Divider()

                DetailFactRow(label: "加权合计", value: String(format: "%.1f", weightedTotal))
                DetailFactRow(label: "四舍五入", value: "\(appState.workspace.grades.total)")
            }
        }
    }

    private var missingPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("缺失项 / 风险")
                        .font(.headline.weight(.medium))
                    Spacer()
                    StatusBadge(text: appState.workspace.grades.missingItems.isEmpty ? "无缺失" : "\(appState.workspace.grades.missingItems.count) 项")
                }

                if appState.workspace.grades.missingItems.isEmpty {
                    Text("当前没有阻塞项。")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                } else {
                    ForEach(appState.workspace.grades.missingItems, id: \.self) { item in
                        Label(item, systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.medium))
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
                    .font(.headline.weight(.medium))
                    .foregroundStyle(BNBUTheme.primary)
                Text(appState.workspace.grades.sourceTrace)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
                    .lineSpacing(4)
            }
        }
    }

    private var gradeComponents: [GradeComponentSummary] {
        [
            GradeComponentSummary(title: "体育打卡", score: appState.workspace.grades.checkinScore, weight: 0.25, systemImage: "checklist", note: "以服务器当前已计入的有效小时为准"),
            GradeComponentSummary(title: "专项考试", score: appState.workspace.grades.exam, weight: 0.30, systemImage: "figure.badminton", note: "由任课老师录入专项成绩"),
            GradeComponentSummary(title: "平时表现 / 签到", score: appState.workspace.grades.attendance, weight: 0.20, systemImage: "person.crop.rectangle.stack", note: "课堂签到与平时表现"),
            GradeComponentSummary(title: "体测", score: appState.workspace.grades.physical, weight: 0.25, systemImage: "stopwatch", note: "体测数据录入后参与计算")
        ]
    }

    private var weightedTotal: Double {
        gradeComponents.reduce(0) { partialResult, component in
            partialResult + component.contribution
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

private struct GradeComponentSummary: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let score: Int
    let weight: Double
    let systemImage: String
    let note: String

    var weightText: String {
        "\(Int(weight * 100))%"
    }

    var contribution: Double {
        Double(score) * weight
    }

    var contributionText: String {
        String(format: "%.1f", contribution)
    }
}

private struct GradeComponentCard: View {
    let component: GradeComponentSummary

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: component.systemImage)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(BNBUTheme.blue)
                    Spacer()
                    StatusBadge(text: component.weightText)
                }

                Text(component.title)
                    .font(.headline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(component.score)")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(BNBUTheme.ink)

                HourProgressBar(value: Double(component.score), total: 100)

                Text(component.note)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GradeContributionRow: View {
    let component: GradeComponentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(component.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(component.score) x \(component.weightText) = \(component.contributionText)")
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
            }
            HourProgressBar(value: component.contribution, total: 30)
        }
    }
}

struct ExemptionApplicationRow: View {
    let application: ExemptionApplication
    var onSupplement: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: application.item.symbolName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(BNBUTheme.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(application.item.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BNBUTheme.ink)
                        Spacer()
                        StatusBadge(text: application.status.rawValue, filled: application.status == .approved)
                    }

                    Text(application.reason)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.ink)

                    Text(application.teacherFeedback)
                        .font(.caption.weight(.regular))
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
                            .font(.subheadline.weight(.medium))
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
                                .font(.caption.weight(.medium))
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
            .navigationTitle(mode.title)
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
                    .font(.subheadline.weight(.medium))
                }
            }
            .confirmationDialog(
                mode.title,
                isPresented: $isConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(mode.submitTitle) {
                    focusedField = nil
                    dismissBNBUKeyboard()
                    Task {
                        if await submit() {
                            dismiss()
                        }
                    }
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
                        .font(.subheadline.weight(.medium))
                    Picker("申请项目", selection: $selectedItem) {
                        ForEach(ExemptionItem.allCases) { item in
                            Label(item.rawValue, systemImage: item.symbolName).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(mode.application != nil)
                    .accessibilityIdentifier("exemption.item.picker")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("申请原因")
                        .font(.subheadline.weight(.medium))
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
                        .font(.subheadline.weight(.medium))
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
                    Text(selectedItem.proofHint)
                        .font(.caption.weight(.regular))
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
