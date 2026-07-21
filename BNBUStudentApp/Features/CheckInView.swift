import SwiftUI

enum CheckInSegment: String, CaseIterable, Identifiable {
    case submit = "提交"
    case records = "记录"

    var id: String { rawValue }
}

private enum SportTypeOption: String, CaseIterable, Identifiable {
    case running
    case basketball
    case football
    case badminton
    case swimming
    case fitness
    case cycling
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return "跑步"
        case .basketball: return "篮球"
        case .football: return "足球"
        case .badminton: return "羽毛球"
        case .swimming: return "游泳"
        case .fitness: return "健身"
        case .cycling: return "骑行"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .basketball: return "basketball"
        case .football: return "soccerball"
        case .badminton: return "figure.badminton"
        case .swimming: return "figure.pool.swim"
        case .fitness: return "dumbbell"
        case .cycling: return "bicycle"
        case .other: return "ellipsis"
        }
    }
}

private enum CheckInFormField: Hashable {
    case note
}

struct CheckInView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: CheckInFormField?
    @State private var selectedSegment: CheckInSegment = .submit
    @State private var hours = 1.0
    @State private var note = ""
    @State private var selectedSportType: SportTypeOption?
    @State private var customSportType = ""
    @State private var proofAttachments: [ProofAttachment] = []
    @State private var submitted = false
    @State private var draftSaved = false
    @State private var draftRestored = false
    @State private var confirmSubmit = false

    var body: some View {
        ZStack {
            BNBUPageBackground()

            VStack(spacing: 0) {
                Picker("打卡", selection: $selectedSegment) {
                    ForEach(CheckInSegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 18)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(BNBUSpacing.screen)
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable {
                    await appState.refreshRemoteWorkspace()
                }
            }
        }
        .accessibilityIdentifier("screen.checkin")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                    dismissBNBUKeyboard()
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .alert("提交成功", isPresented: $submitted) {
            Button("查看记录") {
                selectedSegment = .records
            }
        } message: {
            Text("本次打卡记录已提交并保存。")
        }
        .confirmationDialog(
            "确认提交打卡",
            isPresented: $confirmSubmit,
            titleVisibility: .visible
        ) {
            Button("确认提交") {
                performSubmit()
            }
            .accessibilityIdentifier("checkin.confirm.button")
            Button("取消", role: .cancel) {}
        } message: {
            Text(submitConfirmationMessage)
        }
        .onAppear {
            restoreDraftIfNeeded()
        }
        .onChange(of: selectedSegment) { _, _ in
            focusedField = nil
            dismissBNBUKeyboard()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSegment {
        case .submit:
            submitForm
        case .records:
            recordList
        }
    }

    private var submitForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(eyebrow: "Submit", title: "提交打卡")

            if let localRecoveryMessage {
                LocalRecoveryBanner(message: localRecoveryMessage)
            }

            if let errorMessage = appState.errorMessage {
                BNBUErrorPanel(
                    message: errorMessage,
                    retryTitle: appState.canSafelyRetryCheckIn ? "重试上传" : "刷新记录"
                ) {
                    if appState.canSafelyRetryCheckIn {
                        performSubmit()
                    } else {
                        Task {
                            await appState.refreshRemoteWorkspace()
                        }
                    }
                }
            }

            if let draft = appState.draft {
                DraftBanner(draft: draft) {
                    restoreDraft(draft)
                } clearAction: {
                    clearDraftAndForm()
                }
            }

            SwissPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("本次学时")
                                .font(.headline.weight(.medium))
                            CheckInHoursControl(value: $hours, maximum: selectedTaskHourLimit)
                        }

                        SportTypeSelector(selected: $selectedSportType, customValue: $customSportType)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("补充说明")
                                    .font(.headline.weight(.medium))
                                Spacer()
                                if focusedField == .note {
                                    Button {
                                        focusedField = nil
                                        dismissBNBUKeyboard()
                                    } label: {
                                        Image(systemName: "keyboard.chevron.compact.down")
                                            .font(.headline.weight(.medium))
                                            .foregroundStyle(BNBUTheme.blue)
                                            .frame(width: 34, height: 34)
                                    }
                                    .accessibilityLabel("收起键盘")
                                    .buttonStyle(.plain)
                                }
                            }
                            TextEditor(text: $note)
                                .bnbuInputText()
                                .accessibilityLabel("补充说明")
                                .accessibilityHint("可选，最多 2000 个字符")
                                .focused($focusedField, equals: .note)
                                .frame(minHeight: 100)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(BNBUTheme.pale)
                                .bnbuOutlinedSurface()
                                .onChange(of: note) { _, value in
                                    if value.count > 2_000 {
                                        note = String(value.prefix(2_000))
                                    }
                                }
                        }

                        ProofAttachmentPanel(attachments: $proofAttachments)

                        if appState.isSubmittingCheckIn {
                            CheckInSubmissionProgressPanel(phase: appState.checkInSubmissionPhase)
                        }

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BNBUTheme.muted)
                        }

                        HStack(spacing: 10) {
                            SecondaryActionButton(title: draftSaved ? "草稿已保存" : "保存草稿", systemImage: "tray.and.arrow.down") {
                                saveDraft()
                            }
                            SecondaryActionButton(title: "清空草稿", systemImage: "trash") {
                                clearDraftAndForm()
                            }
                        }

                        DisabledAwareButton(
                            title: submissionButtonTitle,
                            systemImage: submissionButtonSystemImage,
                            isDisabled: !canSubmit || appState.isLoading || appState.isSubmittingCheckIn,
                            accessibilityIdentifier: "checkin.submit.button"
                        ) {
                            focusedField = nil
                            dismissBNBUKeyboard()
                            confirmSubmit = true
                        }
                    }
                }
        }
    }

    private var recordList: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(eyebrow: "Records", title: "打卡记录")

            if appState.submittedCheckInRecords.isEmpty {
                EmptyPlaceholder(title: "暂无记录", message: "已提交的打卡记录会显示在这里。")
            }

            ForEach(appState.submittedCheckInRecords) { record in
                NavigationLink {
                    RecordDetailView(record: record)
                } label: {
                    RecordCard(record: record)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedTask: CourseTask {
        appState.selfCheckInTask
    }

    private var selectedTaskHourLimit: Double {
        return appState.hourLimit(for: selectedTask)
    }

    private var canSubmit: Bool {
        !appState.hasSubmittedCheckInToday() &&
            (hours == 1 || hours == 2) &&
            hours <= selectedTaskHourLimit &&
            !(selectedSportType == .other && customSportType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            CheckInInputRule.validationMessage(note: note) == nil &&
            !proofAttachments.isEmpty &&
            ProofUploadRule.accepts(proofAttachments) &&
            (proofAttachments.allSatisfy(\.isValidForUpload) || canResumePendingUpload)
    }

    private var validationMessage: String? {
        if appState.hasSubmittedCheckInToday() {
            return "今日已打卡，每天只能提交一次。"
        }
        if hours != 1 && hours != 2 {
            return "本次打卡只能选择 1h 或 2h。"
        }
        if hours > selectedTaskHourLimit {
            return "当前任务最多可提交 \(selectedTaskHourLimit.hourText)。"
        }
        if selectedSportType == .other && customSportType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写其他运动项目。"
        }
        if let inputMessage = CheckInInputRule.validationMessage(note: note) {
            return inputMessage
        }
        if proofAttachments.isEmpty {
            return "请至少添加 1 个图片或视频凭证。"
        }
        if let proofLimitMessage = ProofUploadRule.validationMessage(for: proofAttachments) {
            return proofLimitMessage
        }
        if !canResumePendingUpload,
           let invalidProof = proofAttachments.first(where: { !$0.isValidForUpload }) {
            return "\(invalidProof.fileName) 不符合要求：\(invalidProof.validationMessage ?? "凭证无效")。"
        }
        return nil
    }

    private var submitConfirmationMessage: String {
        return "\(selectedTask.title) · \(hours.hourText) · \(proofAttachments.count) 个凭证。提交后可在打卡记录中查看。"
    }

    private var canResumePendingUpload: Bool {
        appState.canResumePendingCheckIn(
            task: selectedTask,
            hours: hours,
            note: note,
            sportType: resolvedSportType,
            proofAttachments: proofAttachments
        )
    }

    private var submissionButtonTitle: String {
        switch appState.checkInSubmissionPhase {
        case .idle:
            return appState.isLoading ? "处理中..." : "提交打卡"
        case .uploading:
            let percentage = Int((appState.checkInSubmissionPhase.overallProgress ?? 0) * 100)
            return "上传中 \(percentage)%"
        case .submitting:
            return "正在提交..."
        case .syncing:
            return "正在同步..."
        }
    }

    private var submissionButtonSystemImage: String {
        appState.isSubmittingCheckIn || appState.isLoading ? "hourglass" : "paperplane.fill"
    }

    private var localRecoveryMessage: String? {
        if appState.storeHealth.workspaceReadStatus == .decodeFailed {
            return "本地工作台数据异常，已自动回退到可用的 Mock 工作台。"
        }
        switch appState.storeHealth.draftReadStatus {
        case .decodeFailed:
            return "本地草稿损坏，已自动忽略；可以重新选择任务并保存草稿。"
        case .discarded:
            return "本地草稿关联的任务已失效，已自动清理。"
        default:
            return nil
        }
    }

    private func restoreDraftIfNeeded() {
        guard !draftRestored else { return }
        draftRestored = true
        guard let draft = appState.draft else { return }
        restoreDraft(draft)
    }

    private func restoreDraft(_ draft: CheckInDraft) {
        guard draft.taskId == appState.selfCheckInTask.id else {
            clearDraftAndForm()
            return
        }
        hours = draft.hours
        note = draft.note
        selectedSportType = draft.sportType.flatMap(SportTypeOption.init(rawValue:))
        customSportType = draft.customSportType ?? ""
        proofAttachments = draft.proofAttachments
        selectedSegment = .submit
        draftSaved = false
        clampHoursForSelectedTask()
    }

    private func saveDraft() {
        appState.saveDraft(
            task: selectedTask,
            hours: hours,
            note: note,
            sportType: selectedSportType?.rawValue,
            customSportType: customSportType,
            proofAttachments: proofAttachments
        )
        draftSaved = true
    }

    private func clearDraftAndForm() {
        appState.clearDraft()
        note = ""
        selectedSportType = nil
        customSportType = ""
        proofAttachments = []
        draftSaved = false
    }

    private func resetFormAfterSubmit() {
        note = ""
        selectedSportType = nil
        customSportType = ""
        proofAttachments = []
        draftSaved = false
    }

    private func performSubmit() {
        guard canSubmit, !appState.isSubmittingCheckIn else { return }
        Task {
            let success = await appState.submitCheckIn(
                task: selectedTask,
                hours: hours,
                note: note,
                sportType: resolvedSportType,
                proofAttachments: proofAttachments
            )
            guard success else { return }
            resetFormAfterSubmit()
            submitted = true
        }
    }

    private func clampHoursForSelectedTask() {
        hours = appState.normalizedHours(hours, for: selectedTask)
    }

    private var resolvedSportType: String? {
        guard let selectedSportType else { return nil }
        if selectedSportType == .other {
            return customSportType.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedSportType.rawValue
    }
}

private struct CheckInHoursControl: View {
    @Binding var value: Double
    let maximum: Double

    var body: some View {
        HStack {
            hourButton(
                systemImage: "minus.circle.fill",
                accessibilityLabel: "减少学时",
                enabled: value > 1
            ) {
                value = 1
            }

            VStack(spacing: 4) {
                Text(value.hourText)
                    .font(.system(size: 30, weight: .medium))
                    .contentTransition(.numericText())
                Text("单次最多 \(maximum.hourText)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)

            hourButton(
                systemImage: "plus.circle.fill",
                accessibilityLabel: "增加学时",
                enabled: value < maximum && maximum >= 2
            ) {
                value = min(2, maximum)
            }
        }
        .padding(10)
        .background(BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
        .animation(.easeInOut(duration: 0.24), value: value)
    }

    private func hourButton(
        systemImage: String,
        accessibilityLabel: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(enabled ? BNBUTheme.onPrimaryContainer : BNBUTheme.onSurfaceVariant)
                .frame(width: 48, height: 48)
                .background(enabled ? BNBUTheme.primaryContainer : BNBUTheme.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SportTypeSelector: View {
    @Binding var selected: SportTypeOption?
    @Binding var customValue: String
    @State private var showAll = false

    private var visibleOptions: [SportTypeOption] {
        let needsExpandedSelection = selected.map { SportTypeOption.allCases.dropFirst(4).contains($0) } ?? false
        return showAll || needsExpandedSelection
            ? SportTypeOption.allCases
            : Array(SportTypeOption.allCases.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("运动项目（可选）")
                .font(.headline.weight(.medium))
            Text("请选择本次运动；再次点击已选项目可取消。")
                .font(.caption.weight(.regular))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(visibleOptions) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            selected = selected == option ? nil : option
                            if selected != .other {
                                customValue = ""
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.systemImage)
                                .font(.headline.weight(.medium))
                                .foregroundStyle(selected == option ? BNBUTheme.primary : BNBUTheme.onSurfaceVariant)
                            Text(option.title)
                                .font(.subheadline.weight(selected == option ? .semibold : .regular))
                                .foregroundStyle(BNBUTheme.onSurface)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(selected == option ? BNBUTheme.primaryContainer : BNBUTheme.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityValue(selected == option ? "已选择" : "未选择")
                    .accessibilityHint(selected == option ? "双击取消选择" : "双击选择")
                    .accessibilityAddTraits(selected == option ? .isSelected : [])
                }
            }

            if selected == nil || SportTypeOption.allCases.prefix(4).contains(selected!) {
                Button(showAll ? "收起运动项目" : "查看更多运动项目") {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        showAll.toggle()
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BNBUTheme.primary)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }

            if selected == .other {
                TextField("填写其他运动项目", text: $customValue)
                    .bnbuInputText()
                    .accessibilityLabel("其他运动项目")
                    .accessibilityHint("最多 32 个字符")
                    .padding(14)
                    .background(BNBUTheme.surfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
                    .onChange(of: customValue) { _, value in
                        if value.count > 32 {
                            customValue = String(value.prefix(32))
                        }
                    }
            }
        }
    }
}

private struct CheckInSubmissionProgressPanel: View {
    let phase: CheckInSubmissionPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: phaseSymbolName)
                    .foregroundStyle(BNBUTheme.primary)
                Text(phaseTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BNBUTheme.onSurface)
                Spacer()
                if let progress = phase.overallProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.primary)
                }
            }

            if let progress = phase.overallProgress {
                ProgressView(value: progress)
                    .tint(BNBUTheme.primary)
                    .accessibilityValue("\(Int(progress * 100))%")
            }

            Text(phaseDetail)
                .font(.caption.weight(.regular))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .lineSpacing(2)
        }
        .padding(14)
        .background(BNBUTheme.primaryContainer.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
        .accessibilityIdentifier("checkin.upload.progress")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var phaseTitle: String {
        switch phase {
        case .idle:
            return "准备提交"
        case .uploading:
            return "正在上传凭证"
        case .submitting:
            return "正在提交记录"
        case .syncing:
            return "正在同步结果"
        }
    }

    private var phaseDetail: String {
        switch phase {
        case .idle:
            return "正在准备本次打卡。"
        case .uploading(let fileName, let completedFiles, let totalFiles, _):
            return "第 \(min(completedFiles + 1, totalFiles)) / \(totalFiles) 个文件：\(fileName)"
        case .submitting:
            return "凭证已上传，正在等待服务器保存打卡记录。"
        case .syncing:
            return "服务器已接受记录，正在读取最新打卡列表。"
        }
    }

    private var phaseSymbolName: String {
        switch phase {
        case .idle:
            return "clock"
        case .uploading:
            return "arrow.up.circle"
        case .submitting:
            return "paperplane"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        }
    }
}

private struct DraftBanner: View {
    let draft: CheckInDraft
    let restoreAction: () -> Void
    let clearAction: () -> Void

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Label("有未提交草稿", systemImage: "doc.badge.clock")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(BNBUTheme.ink)
                    Spacer()
                    StatusBadge(text: draft.updatedAt)
                }

                Text("已保存 \(draft.hours.hourText)，包含 \(draft.proofAttachments.count) 个凭证。")
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)

                HStack(spacing: 10) {
                    SecondaryActionButton(title: "恢复草稿", systemImage: "arrow.clockwise", action: restoreAction)
                    SecondaryActionButton(title: "丢弃", systemImage: "xmark", action: clearAction)
                }
            }
        }
    }
}

private struct LocalRecoveryBanner: View {
    let message: String

    var body: some View {
        SwissPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(BNBUTheme.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text("已恢复本地状态")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(BNBUTheme.ink)
                    Text(message)
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                        .lineSpacing(2)
                }
            }
        }
    }
}

private struct TaskActionCard: View {
    let task: CourseTask
    let course: Course?
    let submitAction: () -> Void

    private var isSubmittable: Bool {
        task.isSubmittable()
    }

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Label(task.creditType.rawValue, systemImage: task.creditType.symbolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.blue)
                    Spacer()
                    StatusBadge(text: task.status.rawValue, filled: isSubmittable)
                }

                Text(task.title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(BNBUTheme.ink)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("可获小时")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BNBUTheme.muted)
                        Text(task.hours.hourText)
                            .font(.headline.weight(.medium))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("截止时间")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BNBUTheme.muted)
                        Text(task.deadline)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                    }
                }

                Text("证明要求：\(task.proof)")
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)

                DisabledAwareButton(
                    title: isSubmittable ? "提交这个任务" : "任务不可提交",
                    systemImage: isSubmittable ? "square.and.pencil" : "lock",
                    isDisabled: !isSubmittable,
                    action: submitAction
                )

                NavigationLink {
                    TaskDetailView(task: task, course: course)
                } label: {
                    Label("查看任务详情", systemImage: "info.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
