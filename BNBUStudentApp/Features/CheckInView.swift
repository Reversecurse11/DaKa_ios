import SwiftUI

enum CheckInSegment: String, CaseIterable, Identifiable {
    case submit = "提交"
    case records = "记录"

    var id: String { rawValue }
}

private extension ExerciseSportType {
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
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedField: CheckInFormField?
    @State private var selectedSegment: CheckInSegment = .submit
    @State private var selectedCategory: ExerciseCategory = .general
    @State private var hours = 1.0
    @State private var note = ""
    @State private var selectedSportType: ExerciseSportType?
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
            appState.reconcileExerciseSession()
            restoreDraftIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.reconcileExerciseSession()
            }
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

            if let session = appState.exerciseSession {
                exerciseSessionPanel(session)
                if session.status == .completed, session.creditedHours() > 0 {
                    evidenceSubmissionForm(session)
                }
            } else {
                exerciseStartForm
            }
        }
    }

    private var exerciseStartForm: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("运动类型")
                        .font(.headline.weight(.medium))
                    Picker("运动类型", selection: $selectedCategory) {
                        ForEach(ExerciseCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let course = appState.currentExerciseCourse {
                    Label(course.displayTitle, systemImage: "book.closed")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                } else {
                    Text("当前没有在读体育课程，暂时不能开始运动。")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BNBUTheme.muted)
                }

                SportTypeSelector(selected: $selectedSportType, customValue: $customSportType)

                Text("开始后将按实际经过时间计时：不足 1 小时不计入，满 1 小时计 1 小时，满 2 小时自动结束并计 2 小时。")
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)

                if let startValidationMessage {
                    Text(startValidationMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.muted)
                }

                DisabledAwareButton(
                    title: "开始运动",
                    systemImage: "play.fill",
                    isDisabled: startValidationMessage != nil,
                    accessibilityIdentifier: "checkin.exercise.start"
                ) {
                    startExercise()
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseSessionPanel(_ session: ExerciseSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let displayedSession = session.reconciled(at: context.date)
            SwissPanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(
                            displayedSession.status == .active ? "运动进行中" : "运动已结束",
                            systemImage: displayedSession.status == .active ? "figure.run.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.headline.weight(.medium))
                        .foregroundStyle(BNBUTheme.primary)
                        Spacer()
                        StatusBadge(text: displayedSession.category.title, filled: true)
                    }

                    Text(formatDuration(displayedSession.elapsed(at: context.date)))
                        .font(.system(size: 42, weight: .medium, design: .monospaced))
                        .contentTransition(.numericText())
                        .accessibilityLabel("已运动 \(formatDurationForVoiceOver(displayedSession.elapsed(at: context.date)))")

                    VStack(alignment: .leading, spacing: 8) {
                        sessionDetailRow(title: "运动项目", value: displayedSession.resolvedSportName)
                        sessionDetailRow(title: "开始时间", value: displayedSession.startTime.formatted(date: .omitted, time: .shortened))
                        sessionDetailRow(
                            title: "位置记录",
                            value: displayedSession.locationStatus == .available ? "已获取" : "未获取（不影响计时）"
                        )
                        if displayedSession.status == .completed {
                            sessionDetailRow(title: "可计学时", value: displayedSession.creditedHours().hourText)
                        }
                    }

                    if displayedSession.status == .active {
                        SecondaryActionButton(title: "结束运动", systemImage: "stop.fill") {
                            _ = appState.endExerciseSession()
                        }
                        .accessibilityIdentifier("checkin.exercise.end")
                    } else if displayedSession.creditedHours() == 0 {
                        Text("本次运动不足 1 小时，不计入体育学时，也不能提交凭证。")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BNBUTheme.muted)
                        SecondaryActionButton(title: "完成并返回", systemImage: "arrow.counterclockwise") {
                            appState.discardExerciseSession()
                            resetFormAfterSubmit()
                        }
                    }
                }
            }
            .task(id: displayedSession.status) {
                if displayedSession.status == .completed, session.status == .active {
                    appState.reconcileExerciseSession(at: context.date)
                }
            }
        }
    }

    private func evidenceSubmissionForm(_ session: ExerciseSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let draft = appState.draft {
                DraftBanner(draft: draft) {
                    restoreDraft(draft)
                } clearAction: {
                    clearDraftAndForm()
                }
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: 18) {
                    Text("提交运动凭证")
                        .font(.headline.weight(.medium))

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
                        SecondaryActionButton(title: "清空凭证", systemImage: "trash") {
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
        .onAppear {
            hours = session.creditedHours()
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

    private var submissionContext: (creditType: CreditType, courseId: String?)? {
        guard let session = appState.exerciseSession else { return nil }
        return appState.submissionContext(for: session)
    }

    private var canSubmit: Bool {
        guard let session = appState.exerciseSession,
              session.status == .completed,
              submissionContext != nil else { return false }
        let creditedHours = session.creditedHours()
        return !appState.hasSubmittedCheckInToday() &&
            (creditedHours == 1 || creditedHours == 2) &&
            CheckInInputRule.validationMessage(note: note) == nil &&
            !proofAttachments.isEmpty &&
            ProofUploadRule.accepts(proofAttachments) &&
            (proofAttachments.allSatisfy(\.isValidForUpload) || canResumePendingUpload)
    }

    private var validationMessage: String? {
        guard let session = appState.exerciseSession else { return nil }
        if appState.hasSubmittedCheckInToday() {
            return "今日已打卡，每天只能提交一次。"
        }
        if submissionContext == nil {
            return "本次运动关联的课程已失效，请刷新课程后重试。"
        }
        if session.creditedHours() != 1 && session.creditedHours() != 2 {
            return "运动不足 1 小时，不能提交。"
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
        guard let session = appState.exerciseSession, submissionContext != nil else {
            return "请先完成运动后再提交。"
        }
        return "\(session.category.title) · \(session.creditedHours().hourText) · \(proofAttachments.count) 个凭证。提交后可在打卡记录中查看。"
    }

    private var canResumePendingUpload: Bool {
        guard let submissionContext, let session = appState.exerciseSession else { return false }
        return appState.canResumePendingCheckIn(
            creditType: submissionContext.creditType,
            courseId: submissionContext.courseId,
            hours: session.creditedHours(),
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
            return "本地草稿损坏，已自动忽略；可以重新填写并保存草稿。"
        case .discarded:
            return "本地草稿已失效，已自动清理。"
        default:
            return nil
        }
    }

    private func restoreDraftIfNeeded() {
        guard !draftRestored else { return }
        draftRestored = true
        guard appState.exerciseSession?.status == .completed,
              let draft = appState.draft else { return }
        restoreDraft(draft)
    }

    private func restoreDraft(_ draft: CheckInDraft) {
        guard let submissionContext,
              draft.creditType == submissionContext.creditType,
              draft.courseId == submissionContext.courseId else {
            clearDraftAndForm()
            return
        }
        hours = draft.hours
        note = draft.note
        proofAttachments = draft.proofAttachments
        selectedSegment = .submit
        draftSaved = false
    }

    private func saveDraft() {
        guard let submissionContext, let session = appState.exerciseSession else { return }
        appState.saveDraft(
            creditType: submissionContext.creditType,
            courseId: submissionContext.courseId,
            hours: session.creditedHours(),
            note: note,
            sportType: session.sportType.rawValue,
            customSportType: session.customSportName ?? "",
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
        selectedCategory = .general
        customSportType = ""
        proofAttachments = []
        draftSaved = false
    }

    private func performSubmit() {
        guard canSubmit,
              !appState.isSubmittingCheckIn,
              let submissionContext,
              let session = appState.exerciseSession else { return }
        Task {
            let success = await appState.submitCheckIn(
                creditType: submissionContext.creditType,
                courseId: submissionContext.courseId,
                hours: session.creditedHours(),
                note: note,
                sportType: resolvedSportType,
                proofAttachments: proofAttachments,
                exerciseSession: session
            )
            guard success else { return }
            appState.markExerciseSessionSubmitted()
            resetFormAfterSubmit()
            submitted = true
        }
    }

    private var startValidationMessage: String? {
        if appState.hasSubmittedCheckInToday() {
            return "今日已打卡，每天只能开始一次计时。"
        }
        if appState.currentExerciseCourse == nil {
            return "当前学期没有在读体育课程。"
        }
        return ExerciseSessionInputRule.validationMessage(
            sportType: selectedSportType,
            customSportName: customSportType
        )
    }

    private func startExercise() {
        guard startValidationMessage == nil else { return }
        appState.clearDraft()
        proofAttachments = []
        note = ""
        draftSaved = false
        _ = appState.startExerciseSession(
            category: selectedCategory,
            sportType: selectedSportType,
            customSportName: customSportType
        )
    }

    private var resolvedSportType: String? {
        guard let session = appState.exerciseSession else { return nil }
        if session.sportType == .other {
            return session.customSportName
        }
        return session.sportType.rawValue
    }

    @ViewBuilder
    private func sessionDetailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(BNBUTheme.onSurface)
        }
        .font(.subheadline.weight(.regular))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration), 0)
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    private func formatDurationForVoiceOver(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration), 0)
        return "\(seconds / 3_600) 小时 \((seconds % 3_600) / 60) 分 \(seconds % 60) 秒"
    }
}

private struct SportTypeSelector: View {
    @Binding var selected: ExerciseSportType?
    @Binding var customValue: String
    @State private var showAll = false

    private var visibleOptions: [ExerciseSportType] {
        let needsExpandedSelection = selected.map { ExerciseSportType.allCases.dropFirst(4).contains($0) } ?? false
        return showAll || needsExpandedSelection
            ? ExerciseSportType.allCases
            : Array(ExerciseSportType.allCases.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("运动项目")
                .font(.headline.weight(.medium))
            Text("请选择本次运动项目。")
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

            if selected == nil || ExerciseSportType.allCases.prefix(4).contains(selected!) {
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
