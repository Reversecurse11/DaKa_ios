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

private enum ExerciseAutoEndAlert: Identifiable {
    /// Active exercise time reached the 2-hour daily cap.
    case dailyCap
    /// An open pause exceeded 6 hours and the session was closed.
    case pauseTimeout

    var id: String {
        switch self {
        case .dailyCap: return "dailyCap"
        case .pauseTimeout: return "pauseTimeout"
        }
    }
}

struct CheckInView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @FocusState private var focusedField: CheckInFormField?
    @State private var selectedSegment: CheckInSegment = .submit
    @State private var selectedCategory: ExerciseCategory = .general
    @State private var note = ""
    @State private var selectedSportType: ExerciseSportType?
    @State private var customSportType = ""
    /// Draft-pool captures the student picked as proof for this submission.
    @State private var selectedDraftIDs: Set<String> = []
    /// Materialized attachments for the current selection. Rebuilt when the
    /// selection or the draft pool changes, so render passes stay cheap.
    @State private var proofAttachments: [ProofAttachment] = []
    @State private var submitted = false
    @State private var draftSaved = false
    @State private var draftRestored = false
    @State private var confirmSubmit = false
    @State private var confirmEndExercise = false
    @State private var endWillBeUncredited = false
    @State private var showUnderHourNotice = false
    @State private var confirmAbandon = false
    @State private var autoEndAlert: ExerciseAutoEndAlert?
    @State private var showHealthReminder = false

    var body: some View {
        scaffoldWithSubmitDialogs
            .modifier(sessionDialogs)
    }

    private var scaffoldWithSubmitDialogs: some View {
        ZStack {
            BNBUPageBackground()

            VStack(spacing: 0) {
                Picker("打卡", selection: $selectedSegment) {
                    ForEach(CheckInSegment.allCases) { segment in
                        Text(LocalizedStringKey(segment.rawValue)).tag(segment)
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
            rebuildProofAttachments()
            // Business rule 5.4: one-time health reminder per account.
            // Suppressed under UI testing so dialogs stay deterministic.
            if !ProcessInfo.processInfo.arguments.contains("-ui-testing-reset"),
               !UserDefaults.standard.bool(forKey: healthReminderKey) {
                showHealthReminder = true
            }
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
        .onChange(of: selectedDraftIDs) { _, _ in
            rebuildProofAttachments()
        }
        .onChange(of: appState.exerciseMediaDrafts) { _, drafts in
            let validIDs = Set(drafts.map(\.id))
            let pruned = selectedDraftIDs.intersection(validIDs)
            if pruned != selectedDraftIDs {
                selectedDraftIDs = pruned
            } else {
                rebuildProofAttachments()
            }
        }
    }

    private var sessionDialogs: CheckInSessionDialogs {
        CheckInSessionDialogs(
            confirmEndExercise: $confirmEndExercise,
            showUnderHourNotice: $showUnderHourNotice,
            confirmAbandon: $confirmAbandon,
            autoEndAlert: $autoEndAlert,
            showHealthReminder: $showHealthReminder,
            endWillBeUncredited: endWillBeUncredited,
            healthReminderKey: healthReminderKey,
            confirmEndAction: { performConfirmedEndExercise() },
            abandonAction: {
                appState.discardExerciseSession()
                resetFormAfterSubmit()
            }
        )
    }

    private var healthReminderKey: String {
        "bnbu.health.reminder.shown.\(appState.workspace.student.id)"
    }

    private func rebuildProofAttachments() {
        proofAttachments = appState.exerciseMediaDrafts
            .filter { selectedDraftIDs.contains($0.id) }
            .compactMap { appState.proofAttachment(from: $0) }
        draftSaved = false
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
                            Text(LocalizedStringKey(category.title)).tag(category)
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

                Text("每日开放时段 \(CheckInTimeWindowRule.displayText) 内可开始运动；开始后即使超出时段也可正常结束和提交。开始后按实际运动时间计时，可随时暂停（暂停不计入时长）：不足 1 小时不计入，满 1 小时计 1 小时，满 2 小时自动结束并计 2 小时。凭证只能通过相机实时拍摄。开始时会尝试获取一次位置，获取失败不影响打卡。")
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
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label(
                            sessionStatusTitle(displayedSession),
                            systemImage: sessionStatusIcon(displayedSession)
                        )
                        .font(.headline.weight(.medium))
                        .foregroundStyle(BNBUTheme.primary)
                        Spacer()
                        StatusBadge(text: displayedSession.category.title, filled: true)
                    }

                    // Business rule 3.5: the check-in page centres on the
                    // timer. No distance, pace, calories or map in v1.
                    VStack(spacing: 8) {
                        Text(formatDuration(displayedSession.elapsed(at: context.date)))
                            .font(.system(size: 56, weight: .medium, design: .monospaced))
                            .contentTransition(.numericText())
                            .accessibilityLabel("已运动 \(formatDurationForVoiceOver(displayedSession.elapsed(at: context.date)))")

                        Text(creditSummary(for: displayedSession, at: context.date))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)

                        if displayedSession.isPaused {
                            Text("运动已暂停 · 暂停时间不计入运动时长")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BNBUTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        sessionDetailRow(title: "运动项目", value: displayedSession.resolvedSportName)
                        sessionDetailRow(title: "开始时间", value: formattedTime(displayedSession.startTime))
                        if displayedSession.pausedDuration(at: context.date) > 0 {
                            sessionDetailRow(title: "暂停累计", value: formatDuration(displayedSession.pausedDuration(at: context.date)))
                        }
                        sessionDetailRow(
                            title: "位置记录",
                            value: displayedSession.locationStatus == .available ? "已获取" : "未获取（不影响计时）"
                        )
                        if displayedSession.status == .completed {
                            sessionDetailRow(title: "结束时间", value: formattedTime(displayedSession.endTime ?? context.date))
                            sessionDetailRow(title: "可计学时", value: displayedSession.creditedHours().hourText)
                        }
                    }

                    if displayedSession.status == .active {
                        // Camera stays available while exercising and paused
                        // (business rule 5.5); captures land in the draft pool.
                        exerciseCaptureSection

                        HStack(spacing: 10) {
                            if displayedSession.isPaused {
                                SecondaryActionButton(title: "继续运动", systemImage: "play.fill") {
                                    appState.resumeExerciseSession()
                                }
                                .accessibilityIdentifier("checkin.exercise.resume")
                            } else {
                                SecondaryActionButton(title: "暂停", systemImage: "pause.fill") {
                                    appState.pauseExerciseSession()
                                }
                                .accessibilityIdentifier("checkin.exercise.pause")
                            }

                            SecondaryActionButton(title: "结束运动", systemImage: "stop.fill") {
                                requestEndExercise(displayedSession, at: context.date)
                            }
                            .accessibilityIdentifier("checkin.exercise.end")
                        }

                        Button {
                            confirmAbandon = true
                        } label: {
                            Text("放弃本次运动")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BNBUTheme.muted)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("checkin.exercise.abandon")
                    } else if displayedSession.creditedHours() == 0 {
                        Text("本次运动不足 1 小时，不计入体育学时，不占用今日打卡次数。已拍摄的照片/视频草稿已保留，今天继续运动后仍可选用。")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BNBUTheme.muted)
                        SecondaryActionButton(title: "完成并返回", systemImage: "arrow.counterclockwise") {
                            appState.finishUncreditedExerciseSession()
                            resetFormAfterSubmit()
                        }
                        .accessibilityIdentifier("checkin.exercise.finish.uncredited")
                    }
                }
            }
            .task(id: displayedSession.status) {
                if displayedSession.status == .completed, session.status == .active {
                    autoEndAlert = session.reachedDailyCap(at: context.date) ? .dailyCap : .pauseTimeout
                    appState.reconcileExerciseSession(at: context.date)
                }
            }
        }
    }

    private var exerciseCaptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("运动过程拍摄")
                    .font(.headline.weight(.medium))
                Spacer()
                StatusBadge(text: "照片草稿 \(appState.exercisePhotoDraftCount)/\(ExerciseMediaDraftRule.maximumPhotoDrafts)")
            }
            Text("凭证只能通过相机实时拍摄，照片和视频先保存为本地草稿，结束打卡时可选择作为凭证。")
                .font(.caption.weight(.regular))
                .foregroundStyle(BNBUTheme.muted)

            ExerciseCameraCaptureButton(
                title: "拍摄照片 / 录制视频",
                accessibilityIdentifier: "checkin.capture.camera"
            ) { attachment in
                handleCapturedAttachment(attachment, autoSelect: false)
            }

        }
    }

    private func sessionStatusTitle(_ session: ExerciseSession) -> String {
        if session.status == .completed { return "运动已结束" }
        return session.isPaused ? "运动已暂停" : "运动进行中"
    }

    private func sessionStatusIcon(_ session: ExerciseSession) -> String {
        if session.status == .completed { return "checkmark.circle.fill" }
        return session.isPaused ? "pause.circle.fill" : "figure.run.circle.fill"
    }

    private func creditSummary(for session: ExerciseSession, at date: Date) -> String {
        switch session.creditedHours(at: date) {
        case 2: return "当前可计学时：2 小时（已达今日上限）"
        case 1: return "当前可计学时：1 小时 · 满 2 小时自动结束"
        default: return "不足 1 小时不计入 · 满 1 小时计 1 小时"
        }
    }

    /// Business rule 5.6: every manual end first passes the anti-mistap
    /// confirmation dialog. Duration handling only runs after 「确认结束」.
    private func requestEndExercise(_ session: ExerciseSession, at date: Date) {
        endWillBeUncredited = session.creditedHours(at: date) == 0
        confirmEndExercise = true
    }

    /// Runs after 「确认结束」: an under-one-hour end closes the session with a
    /// notice, without a record or quota usage, keeping drafts for later today.
    private func performConfirmedEndExercise() {
        guard appState.endExerciseSession() else { return }
        if appState.exerciseSession?.creditedHours() == 0 {
            appState.finishUncreditedExerciseSession()
            resetFormAfterSubmit()
            showUnderHourNotice = true
        }
    }

    private func handleCapturedAttachment(_ attachment: ProofAttachment, autoSelect: Bool) {
        let added: Bool
        switch attachment.type {
        case .image:
            guard let data = attachment.uploadData else { return }
            added = appState.addExercisePhotoDraft(
                imageData: data,
                thumbnailData: attachment.thumbnailData
            )
        case .video:
            guard let fileURL = attachment.sourceFileURL else { return }
            added = appState.addExerciseVideoDraft(
                fileURL: fileURL,
                byteCount: attachment.byteCount ?? 0,
                durationSeconds: attachment.durationSeconds,
                thumbnailData: attachment.thumbnailData
            )
        }
        guard added, autoSelect, let newDraft = appState.exerciseMediaDrafts.last else { return }
        let selectedImages = appState.exerciseMediaDrafts
            .filter { selectedDraftIDs.contains($0.id) && $0.type == .image }.count
        let selectedVideos = appState.exerciseMediaDrafts
            .filter { selectedDraftIDs.contains($0.id) && $0.type == .video }.count
        if newDraft.type == .image, selectedImages < ProofUploadRule.maxImageCount {
            selectedDraftIDs.insert(newDraft.id)
        } else if newDraft.type == .video, selectedVideos < ProofUploadRule.maxVideoCount {
            selectedDraftIDs.insert(newDraft.id)
        }
    }

    private func deleteDraft(_ mediaDraft: ExerciseMediaDraft) {
        selectedDraftIDs.remove(mediaDraft.id)
        appState.removeExerciseMediaDraft(id: mediaDraft.id)
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
                            Text("运动说明")
                                .font(.headline.weight(.medium))
                            Text("必填")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BNBUTheme.muted)
                            Spacer()
                            Text("\(note.count)/\(CheckInInputRule.maximumDescriptionLength)")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                .accessibilityLabel("已输入 \(note.count) 个字符，共可输入 \(CheckInInputRule.maximumDescriptionLength) 个字符")
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
                            .accessibilityLabel("运动说明")
                            .accessibilityHint("必填，最多 \(CheckInInputRule.maximumDescriptionLength) 个字符")
                            .focused($focusedField, equals: .note)
                            .frame(minHeight: 100)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(BNBUTheme.pale)
                            .bnbuOutlinedSurface()
                            .onChange(of: note) { _, value in
                                if value.count > CheckInInputRule.maximumDescriptionLength {
                                    note = String(value.prefix(CheckInInputRule.maximumDescriptionLength))
                                }
                            }
                    }

                    evidenceProofSection

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
    }

    private var evidenceProofSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("打卡凭证")
                    .font(.headline.weight(.medium))
                Text("至少选择 1 张照片或 1 个视频；\(ProofUploadRule.summaryText) 凭证只能通过相机实时拍摄，不支持从相册选择。")
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
            }

            ExerciseCameraCaptureButton(
                title: "现场拍摄照片 / 视频",
                accessibilityIdentifier: "checkin.capture.camera"
            ) { attachment in
                handleCapturedAttachment(attachment, autoSelect: true)
            }

            ExerciseProofSelectionPanel(
                drafts: appState.exerciseMediaDrafts,
                selectedDraftIDs: $selectedDraftIDs
            ) { mediaDraft in
                deleteDraft(mediaDraft)
            }
        }
        .padding(16)
        .background(BNBUTheme.blueSoft)
        .overlay(
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(BNBUTheme.line)
        )
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
            CheckInInputRule.validationMessage(note: submissionNote(for: session)) == nil &&
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
        if let inputMessage = CheckInInputRule.validationMessage(note: submissionNote(for: session)) {
            return inputMessage
        }
        if proofAttachments.isEmpty {
            return "请至少选择或拍摄 1 张照片或 1 个视频作为凭证。"
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

    // Business rule 5.8: the confirmation summary shows category, sport,
    // start/end time, actual duration, credited hours and proof count.
    private var submitConfirmationMessage: String {
        guard let session = appState.exerciseSession, submissionContext != nil else {
            return "请先完成运动后再提交。"
        }
        let startText = formattedTime(session.startTime)
        let endText = formattedTime(session.endTime ?? Date())
        return "\(session.category.title) · \(session.resolvedSportName)\n运动时间 \(startText) – \(endText)，实际运动 \(formatDuration(session.elapsed()))，计入 \(session.creditedHours().hourText)。\n\(proofAttachments.count) 个凭证。提交后可在打卡记录中查看。"
    }

    private var canResumePendingUpload: Bool {
        guard let submissionContext, let session = appState.exerciseSession else { return false }
        return appState.canResumePendingCheckIn(
            creditType: submissionContext.creditType,
            courseId: submissionContext.courseId,
            hours: session.creditedHours(),
            note: submissionNote(for: session),
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
        note = appState.exerciseSession.map { submissionNote(draft.note, for: $0) } ?? ""
        // Proof bytes live in the media draft pool; restore the selection by
        // intersecting the saved attachment ids with what is still on disk.
        let poolIDs = Set(appState.exerciseMediaDrafts.map(\.id))
        selectedDraftIDs = Set(draft.proofAttachments.map(\.id)).intersection(poolIDs)
        rebuildProofAttachments()
        selectedSegment = .submit
        draftSaved = false
    }

    private func saveDraft() {
        guard let submissionContext, let session = appState.exerciseSession else { return }
        appState.saveDraft(
            creditType: submissionContext.creditType,
            courseId: submissionContext.courseId,
            hours: session.creditedHours(),
            note: submissionNote(for: session),
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
        selectedDraftIDs = []
        proofAttachments = []
        draftSaved = false
    }

    private func resetFormAfterSubmit() {
        note = ""
        selectedSportType = nil
        selectedCategory = .general
        customSportType = ""
        selectedDraftIDs = []
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
                note: submissionNote(for: session),
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
        if appState.enforcesCheckInTimeWindow, !CheckInTimeWindowRule.canStartExercise(at: Date()) {
            return CheckInTimeWindowRule.startBlockedMessage
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
        // Retained media drafts from an earlier <1h attempt stay in the pool;
        // only the form selection resets for the new session.
        selectedDraftIDs = []
        proofAttachments = []
        note = ""
        draftSaved = false
        guard appState.startExerciseSession(
            category: selectedCategory,
            sportType: selectedSportType,
            customSportName: customSportType
        ) else { return }
        // Business rule 5.5: the timer starts immediately; a single location
        // fix is fetched in the background and attached if it arrives while
        // the session is still running. Failure just leaves "未获取位置".
        // UI tests skip the fetch (permission alerts break determinism)
        // except the dedicated GPS test, which opts back in.
        let arguments = ProcessInfo.processInfo.arguments
        if !arguments.contains("-ui-testing-reset") || arguments.contains("-ui-testing-location-check") {
            Task {
                if let fix = await ExerciseLocationProvider.shared.requestCurrentLocation() {
                    appState.attachExerciseSessionLocation(latitude: fix.latitude, longitude: fix.longitude)
                }
            }
        }
    }

    private var resolvedSportType: String? {
        guard let session = appState.exerciseSession else { return nil }
        if session.sportType == .other {
            return session.customSportName
        }
        return session.sportType.rawValue
    }

    private func submissionNote(for session: ExerciseSession) -> String {
        submissionNote(note, for: session)
    }

    private func submissionNote(_ value: String, for session: ExerciseSession) -> String {
        CheckInInputRule.normalizedDescription(value, for: session.category)
    }

    @ViewBuilder
    private func sessionDetailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(title))
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

    private func formattedTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .hour()
                .minute()
                .locale(locale)
        )
    }

    private func formatDurationForVoiceOver(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration), 0)
        return "\(seconds / 3_600) 小时 \((seconds % 3_600) / 60) 分 \(seconds % 60) 秒"
    }
}

/// Session-lifecycle dialogs, split out so the compiler can type-check the
/// main body in reasonable time.
private struct CheckInSessionDialogs: ViewModifier {
    @Binding var confirmEndExercise: Bool
    @Binding var showUnderHourNotice: Bool
    @Binding var confirmAbandon: Bool
    @Binding var autoEndAlert: ExerciseAutoEndAlert?
    @Binding var showHealthReminder: Bool
    let endWillBeUncredited: Bool
    let healthReminderKey: String
    let confirmEndAction: () -> Void
    let abandonAction: () -> Void

    func body(content: Content) -> some View {
        content
            // Business rule 5.6: anti-mistap confirmation before any manual
            // end;「取消」returns to the running session with the timer intact.
            // An alert (not confirmationDialog) guarantees both buttons render
            // on every device idiom; popover-style dialogs drop cancel roles.
            .alert("结束运动", isPresented: $confirmEndExercise) {
                Button("取消", role: .cancel) {}
                Button("确认结束", role: .destructive) {
                    confirmEndAction()
                }
                .accessibilityIdentifier("checkin.exercise.end.confirm")
            } message: {
                Text(endWillBeUncredited
                    ? "你确定要结束本次运动吗？当前运动时长不足 1 小时，结束后本次不计入有效打卡时长。"
                    : "你确定要结束本次运动吗？")
            }
            .alert("运动时长未满 1 小时", isPresented: $showUnderHourNotice) {
                Button("好") {}
            } message: {
                Text("本次不计入有效打卡时长，也不占用今日打卡次数。已拍摄的照片/视频草稿已保留，今天继续运动后仍可选用。")
            }
            .confirmationDialog(
                "放弃本次运动",
                isPresented: $confirmAbandon,
                titleVisibility: .visible
            ) {
                Button("放弃并清除草稿", role: .destructive) {
                    abandonAction()
                }
                .accessibilityIdentifier("checkin.exercise.abandon.confirm")
                Button("继续运动", role: .cancel) {}
            } message: {
                Text("放弃后本次计时不保留，不占用今日打卡次数；本次运动中拍摄的照片/视频草稿将被清除。")
            }
            .alert(item: $autoEndAlert) { alert in
                switch alert {
                case .dailyCap:
                    return Alert(
                        title: Text("您已完成两小时打卡"),
                        message: Text("您已完成两小时打卡。计时已自动结束并按 2 小时计入，请上传材料并提交运动打卡。"),
                        dismissButton: .default(Text("好"))
                    )
                case .pauseTimeout:
                    return Alert(
                        title: Text("运动已自动结束"),
                        message: Text("暂停超过 6 小时未恢复，本次计时已自动结束，按暂停前的实际运动时长处理。"),
                        dismissButton: .default(Text("好"))
                    )
                }
            }
            .alert("健康提醒", isPresented: $showHealthReminder) {
                Button("我知道了") {
                    UserDefaults.standard.set(true, forKey: healthReminderKey)
                }
            } message: {
                Text("请根据自身身体状况适量运动。如感不适应立即停止，必要时及时就医。")
            }
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
                            Text(LocalizedStringKey(option.title))
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
                    .accessibilityLabel(Text(LocalizedStringKey(option.title)))
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
                Text(LocalizedStringKey(phaseTitle))
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

            phaseDetailText
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

    @ViewBuilder
    private var phaseDetailText: some View {
        switch phase {
        case .idle:
            Text("正在准备本次打卡。")
        case .uploading(let fileName, let completedFiles, let totalFiles, _):
            Text("第 \(min(completedFiles + 1, totalFiles)) / \(totalFiles) 个文件：\(fileName)")
        case .submitting:
            Text("凭证已上传，正在等待服务器保存打卡记录。")
        case .syncing:
            Text("服务器已接受记录，正在读取最新打卡列表。")
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
