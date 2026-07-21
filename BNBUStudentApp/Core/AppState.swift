import Foundation
import SwiftUI

struct InFlightMutationGate {
    private var keys: Set<String> = []

    mutating func begin(_ key: String) -> Bool {
        keys.insert(key).inserted
    }

    mutating func end(_ key: String) {
        keys.remove(key)
    }

    mutating func removeAll() {
        keys.removeAll()
    }
}

enum RemoteMutationJournalError: Error, LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "无法安全保存待提交操作，已停止网络提交。请确认设备已解锁且存储空间充足，然后重试。"
    }
}

enum RemoteMutationJournalPolicy {
    /// Retain only failures for which the server may have accepted or may still
    /// be processing the operation. Ordinary client errors are deterministic
    /// even when they happen during the proof-upload phase.
    static func shouldRetain(after error: Error) -> Bool {
        if let repositoryError = error as? RepositoryError {
            return repositoryError.isAmbiguousMutationFailure
        }
        if error is URLError {
            return true
        }
        // Decoding and other unknown transport-boundary failures may follow a
        // successful server write. Failing safe keeps the idempotency key.
        return true
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var workspace: StudentWorkspace
    @Published var draft: CheckInDraft?
    @Published var storeHealth: LocalStoreHealth
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isRemoteMode = false
    @Published private(set) var checkInSubmissionPhase: CheckInSubmissionPhase = .idle
    @Published private(set) var canSafelyRetryCheckIn = false
    @Published private(set) var pendingRemoteMutationSummaries: [PendingRemoteMutationSummary] = []

    private let repository: StudentRepository
    private let localStore: AppLocalStore
    private let apiClient = StudentAPIClient()
    private let remoteRepo: RemoteStudentRepository
    private var remoteCacheStudentID: String?
    private var sessionEpoch: UInt64 = 0
    private var isRefreshingWorkspace = false
    private var mutationGate = InFlightMutationGate()
    private var pendingRemoteMutations: [String: PendingRemoteMutationAttempt] = [:]
    let hourRule = SportHourRule.standard

    init(
        repository: StudentRepository,
        localStore: AppLocalStore = AppLocalStore(),
        remoteRepo: RemoteStudentRepository = RemoteStudentRepository()
    ) {
        self.repository = repository
        self.localStore = localStore
        self.remoteRepo = remoteRepo
        let workspaceRead = localStore.readWorkspace()
        let draftRead = localStore.readDraft()
        let pendingMutationRead = localStore.readPendingRemoteMutations()
        var workspace = workspaceRead.value ?? repository.loadWorkspace()
        if workspace.syncOperations.isEmpty {
            workspace.syncOperations = [Self.localWorkspaceLoadedOperation]
        }
        let savedDraft = draftRead.value
        var draftReadStatus = draftRead.status
        var bootEvent = Self.bootEvent(workspaceStatus: workspaceRead.status, draftStatus: draftRead.status)
        var restoredDraft: CheckInDraft?

        if let savedDraft,
           savedDraft.taskId == "self-general" || workspace.tasks.contains(where: { $0.id == savedDraft.taskId && $0.isSubmittable() }) {
            restoredDraft = savedDraft
        } else if savedDraft != nil {
            draftReadStatus = .discarded
            bootEvent = "草稿任务已失效，已自动清理。"
            localStore.clearDraft()
        }

        self.workspace = workspace
        self.draft = restoredDraft
        var restoredMutations = pendingMutationRead.value ?? [:]
        if let draftAttempt = restoredDraft?.pendingRemoteMutation {
            restoredMutations[draftAttempt.scope] = draftAttempt
        }
        self.pendingRemoteMutations = restoredMutations
        if pendingMutationRead.status == .decodeFailed {
            if !localStore.clearPendingRemoteMutations() {
                bootEvent = "待提交操作已损坏，且无法安全清理本地文件。"
            }
        }
        self.storeHealth = LocalStoreHealth(
            workspaceReadStatus: workspaceRead.status,
            draftReadStatus: draftReadStatus,
            lastWriteStatus: .idle,
            lastEvent: bootEvent
        )
        self.pendingRemoteMutationSummaries = Self.pendingMutationSummaries(from: restoredMutations)
    }

    var courseRemaining: Double {
        max(hourRule.courseRequired - workspace.progress.course, 0)
    }

    var generalRemaining: Double {
        max(hourRule.generalRequired - workspace.progress.general, 0)
    }

    var totalCompleted: Double {
        min(workspace.progress.course, hourRule.courseRequired) + min(workspace.progress.general, hourRule.generalRequired)
    }

    var totalRemaining: Double {
        max(hourRule.total - totalCompleted, 0)
    }

    var academicProjection: StudentAcademicProjection {
        StudentAcademicProjection.resolve(profile: workspace.student)
    }

    var completionRatio: Double {
        guard hourRule.total > 0 else { return 0 }
        return min(totalCompleted / hourRule.total, 1)
    }

    var unreadNoticeCount: Int {
        workspace.notices.filter(\.isUnread).count
    }

    var activeTasks: [CourseTask] {
        submittableTasks()
    }

    func submittableTasks(at date: Date = Date()) -> [CourseTask] {
        workspace.tasks.filter { $0.isSubmittable(at: date) }
    }

    var selfCheckInTask: CourseTask {
        CourseTask(
            id: "self-general",
            courseId: "self-general",
            creditType: .general,
            title: "自主运动打卡",
            hours: hourRule.dailyLimit,
            deadline: "",
            proof: ProofUploadRule.summaryText,
            status: .active,
            updatedAt: "",
            isSyntheticSelfGeneral: true
        )
    }

    func hasSubmittedCheckInToday(at date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let fractionalISOFormatter = ISO8601DateFormatter()
        fractionalISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardISOFormatter = ISO8601DateFormatter()
        return workspace.records.contains { record in
            guard record.creditType != .organizationOffset else { return false }
            let value = record.submittedAt.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("刚刚") { return true }

            if let parsed = fractionalISOFormatter.date(from: value) ?? standardISOFormatter.date(from: value) {
                return calendar.isDate(parsed, inSameDayAs: date)
            }

            for format in ["yyyy.MM.dd HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                if let parsed = formatter.date(from: value), calendar.isDate(parsed, inSameDayAs: date) {
                    return true
                }
            }
            return false
        }
    }

    var submittedCheckInRecords: [CheckInRecord] {
        workspace.records.filter {
            $0.creditType != .organizationOffset && $0.status != .offset
        }
    }

    var pendingRecordCount: Int {
        workspace.records.filter { $0.status == .pending }.count
    }

    var supplementRecordCount: Int {
        workspace.records.filter { $0.status == .supplement }.count
    }

    var actionableExemptionCount: Int {
        workspace.exemptions.filter { $0.status == .pending }.count
    }

    var actionableRecordCount: Int {
        pendingRecordCount + supplementRecordCount + actionableExemptionCount
    }

    var queuedSyncCount: Int {
        workspace.syncOperations.filter { $0.status == .queued }.count
    }

    var isSubmittingCheckIn: Bool {
        checkInSubmissionPhase.isActive
    }

    var latestSyncOperation: SyncOperation? {
        workspace.syncOperations.first
    }

    var apiBaseURLDescription: String {
        isRemoteMode ? StudentServerConfig.resolvedBaseURL().absoluteString : apiClient.baseURL.absoluteString
    }

    var dataSourceDescription: String {
        isRemoteMode ? "校园体育服务" : "演示数据"
    }

    var dataIntegritySummary: String {
        let courseIds = Set(workspace.courses.map(\.id))
        var issues: [String] = []

        if containsDuplicates(workspace.courses.map(\.id)) {
            issues.append("课程 ID 重复")
        }
        if containsDuplicates(workspace.tasks.map(\.id)) {
            issues.append("任务 ID 重复")
        }
        if containsDuplicates(workspace.records.map(\.id)) {
            issues.append("记录 ID 重复")
        }
        if containsDuplicates(workspace.exemptions.map(\.id)) {
            issues.append("免测申请 ID 重复")
        }

        let invalidTaskCount = workspace.tasks.filter { task in
            task.courseId != "self-general" && !courseIds.contains(task.courseId)
        }.count
        if invalidTaskCount > 0 {
            issues.append("任务课程引用 \(invalidTaskCount)")
        }

        let invalidRecordCount = workspace.records.filter { record in
            guard let courseId = record.courseId else { return false }
            return !courseIds.contains(courseId)
        }.count
        if invalidRecordCount > 0 {
            issues.append("记录课程引用 \(invalidRecordCount)")
        }

        if let draft,
           draft.taskId != "self-general",
           !workspace.tasks.contains(where: { $0.id == draft.taskId && $0.isSubmittable() }) {
            issues.append("草稿任务失效")
        }

        return issues.isEmpty ? "正常" : issues.joined(separator: " / ")
    }

    func demoLogin() {
        sessionEpoch &+= 1
        mutationGate.removeAll()
        errorMessage = nil
        let journalCleared = clearAllPendingRemoteMutations()
        let localWorkspace = localStore.readWorkspace().value ?? repository.loadWorkspace()
        workspace = localWorkspace
        let localDraft = localStore.readDraft().value
        if let localDraft,
           localDraft.taskId == "self-general" || workspace.tasks.contains(where: { $0.id == localDraft.taskId && $0.isSubmittable() }) {
            draft = localDraft
        } else {
            draft = nil
        }
        isRemoteMode = false
        remoteCacheStudentID = nil
        clearPersistedRemoteAttemptFromDraft()
        if !journalCleared {
            errorMessage = RemoteMutationJournalError.writeFailed.localizedDescription
        }
        isAuthenticated = true
    }

    func logout() async {
        sessionEpoch &+= 1
        let remoteStudentID = remoteCacheStudentID
        let wasRemoteMode = isRemoteMode
        isAuthenticated = false
        isRemoteMode = false
        remoteCacheStudentID = nil
        isLoading = false
        isRefreshingWorkspace = false
        mutationGate.removeAll()
        let journalCleared = clearAllPendingRemoteMutations()
        checkInSubmissionPhase = .idle
        canSafelyRetryCheckIn = false
        draft = nil

        if wasRemoteMode, let remoteStudentID {
            localStore.clearRemoteWorkspace(
                baseURL: StudentServerConfig.resolvedBaseURL(),
                studentID: remoteStudentID
            )
            localStore.clearDraft()
        } else {
            localStore.clearAll()
        }
        workspace = repository.loadWorkspace()
        let securelyCleared = await remoteRepo.logout()
        if !securelyCleared {
            errorMessage = "已退出，但设备未能清理安全存储。请重启 App 后再登录。"
        } else if !journalCleared {
            errorMessage = "已退出，但设备未能清理待提交操作。请释放存储空间后重启 App。"
        } else {
            errorMessage = nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func login(account: String, password: String) async {
        guard !isLoading else { return }
        sessionEpoch &+= 1
        mutationGate.removeAll()
        let loginEpoch = sessionEpoch
        isLoading = true
        errorMessage = nil
        defer {
            if loginEpoch == sessionEpoch {
                isLoading = false
            }
        }
        do {
            let authenticatedStudent = try await remoteRepo.login(account: account, password: password)
            guard loginEpoch == sessionEpoch else { return }
            isRemoteMode = true
            remoteCacheStudentID = authenticatedStudent.id
            sanitizePersistedRemoteMutations(for: authenticatedStudent.id)
            do {
                let remoteWorkspace = try await remoteRepo.loadWorkspace()
                guard loginEpoch == sessionEpoch else { return }
                applyRemoteWorkspace(remoteWorkspace, event: "已从服务器同步工作台")
            } catch {
                guard loginEpoch == sessionEpoch else { return }
                if let cachedWorkspace = localStore.readRemoteWorkspace(
                    baseURL: StudentServerConfig.resolvedBaseURL(),
                    studentID: authenticatedStudent.id
                ).value,
                   !isUnauthorized(error) {
                    applyRemoteWorkspace(cachedWorkspace, event: "服务器暂不可用，已读取最近同步数据")
                    errorMessage = "服务器暂时不可用，当前显示最近同步数据。下拉或重新进入后可再次刷新。"
                } else {
                    throw error
                }
            }
            isAuthenticated = true
        } catch {
            guard loginEpoch == sessionEpoch else { return }
            await handleRemoteError(error, expectedSessionEpoch: loginEpoch)
            _ = await remoteRepo.clearSession()
            isRemoteMode = false
            remoteCacheStudentID = nil
            isAuthenticated = false
        }
    }

    func refreshRemoteWorkspace() async {
        guard isRemoteMode, !isRefreshingWorkspace else { return }
        let refreshEpoch = sessionEpoch
        isRefreshingWorkspace = true
        isLoading = true
        errorMessage = nil
        defer {
            if refreshEpoch == sessionEpoch {
                isRefreshingWorkspace = false
                isLoading = false
            }
        }
        do {
            let remoteWorkspace = try await remoteRepo.loadWorkspace()
            guard refreshEpoch == sessionEpoch, isRemoteMode else { return }
            applyRemoteWorkspace(remoteWorkspace, event: "已从服务器刷新工作台")
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: refreshEpoch)
        }
    }

    func tasks(for course: Course) -> [CourseTask] {
        workspace.tasks.filter { $0.courseId == course.id }
    }

    func records(for course: Course) -> [CheckInRecord] {
        workspace.records.filter { $0.courseId == course.id }
    }

    func markNoticeRead(id: String) {
        guard let index = workspace.notices.firstIndex(where: { $0.id == id }) else { return }
        let notice = workspace.notices[index]
        guard notice.isUnread else { return }

        if isRemoteMode {
            let noticeEpoch = sessionEpoch
            Task {
                await markNoticeReadRemote(id: id, expectedSessionEpoch: noticeEpoch)
            }
            return
        }

        workspace.notices[index].isUnread = false
        enqueueSyncOperation(
            .markNoticeRead,
            title: "标记通知已读",
            detail: notice.title
        )
        saveWorkspace(event: "通知已读状态已保存")
    }

    func markAllNoticesRead() {
        guard unreadNoticeCount > 0 else { return }
        let unreadIDs = workspace.notices.filter(\.isUnread).map(\.id)

        if isRemoteMode {
            let noticeEpoch = sessionEpoch
            Task {
                await markAllNoticesReadRemote(ids: unreadIDs, expectedSessionEpoch: noticeEpoch)
            }
            return
        }

        let count = unreadNoticeCount
        for index in workspace.notices.indices {
            workspace.notices[index].isUnread = false
        }
        enqueueSyncOperation(
            .markNoticeRead,
            title: "批量标记通知已读",
            detail: "\(count) 条通知已切换为已读"
        )
        saveWorkspace(event: "批量通知已读已保存")
    }

    @discardableResult
    func submitCheckIn(
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String? = nil,
        proofAttachments: [ProofAttachment]
    ) async -> Bool {
        guard !isSubmittingCheckIn else { return false }
        canSafelyRetryCheckIn = false
        checkInSubmissionPhase = .submitting
        defer { checkInSubmissionPhase = .idle }

        if let inputMessage = CheckInInputRule.validationMessage(note: note) {
            errorMessage = inputMessage
            return false
        }

        guard let task = currentSubmittableTask(matching: task) else {
            errorMessage = "当前任务不可提交，请刷新任务列表。"
            return false
        }

        if isRemoteMode {
            let submissionEpoch = sessionEpoch
            return await submitCheckInRemote(
                task: task,
                hours: hours,
                note: note,
                sportType: sportType,
                proofAttachments: proofAttachments,
                expectedSessionEpoch: submissionEpoch
            )
        }
        guard !hasSubmittedCheckInToday() else {
            errorMessage = "今日已打卡，每天只能提交一次。"
            return false
        }
        guard !proofAttachments.isEmpty, ProofUploadRule.accepts(proofAttachments) else { return false }
        guard proofAttachments.allSatisfy(\.isValidForUpload) else { return false }
        let submittedHours = normalizedHours(hours, for: task)
        let photoCount = proofAttachments.filter { $0.type == .image }.count
        let videoCount = proofAttachments.filter { $0.type == .video }.count
        let record = CheckInRecord(
            id: UUID().uuidString,
            courseId: task.isSyntheticSelfGeneral ? nil : task.courseId,
            taskTitle: task.title,
            creditType: task.creditType,
            hours: submittedHours,
            submittedAt: "刚刚",
            status: .pending,
            proofSummary: proofSummary(proofAttachments: proofAttachments),
            proofPhotoCount: photoCount,
            proofVideoCount: videoCount,
            proofFiles: proofAttachments,
            teacherFeedback: "记录已提交。",
            note: note.isEmpty ? "学生未填写补充说明。" : note,
            sportType: sportType
        )
        workspace.records.insert(record, at: 0)
        workspace.notices.insert(
            StudentNotice(
                id: UUID().uuidString,
                title: "打卡已提交",
                message: "\(task.title) 已成功提交，可在打卡记录中查看。",
                time: "刚刚",
                category: .system,
                isUnread: true
            ),
            at: 0
        )
        enqueueSyncOperation(
            .submitRecord,
            title: "提交打卡记录",
            detail: "\(task.title) · \(submittedHours.hourText) · \(proofAttachments.count) 个凭证"
        )
        clearDraft()
        saveWorkspace(event: "打卡提交已保存")
        return true
    }

    @discardableResult
    func submitSupplement(for record: CheckInRecord, hours: Double, note: String, proofAttachments: [ProofAttachment]) async -> Bool {
        let mutationKey = "supplement:\(record.id)"
        guard beginMutation(mutationKey) else {
            errorMessage = "补充材料正在提交，请勿重复操作。"
            return false
        }
        defer { endMutation(mutationKey) }
        if let inputMessage = CheckInInputRule.validationMessage(note: note) {
            errorMessage = inputMessage
            return false
        }
        if isRemoteMode {
            return await supplementRemote(
                for: record,
                hours: hours,
                note: note,
                proofAttachments: proofAttachments,
                expectedSessionEpoch: sessionEpoch
            )
        }
        guard let index = workspace.records.firstIndex(where: { $0.id == record.id }) else { return false }
        guard workspace.records[index].status == .supplement || workspace.records[index].status == .rejected else { return false }
        guard !proofAttachments.isEmpty,
              ProofUploadRule.accepts(proofAttachments),
              proofAttachments.allSatisfy(\.isValidForUpload) else { return false }

        let submittedHours = normalizedSubmissionHours(hours)
        let mergedProofs = workspace.records[index].proofFiles + proofAttachments
        guard ProofUploadRule.acceptsAttachmentCounts(mergedProofs) else { return false }
        let photoCount = mergedProofs.filter { $0.type == .image }.count
        let videoCount = mergedProofs.filter { $0.type == .video }.count

        workspace.records[index].hours = submittedHours
        workspace.records[index].submittedAt = "刚刚补交"
        workspace.records[index].status = .pending
        workspace.records[index].proofSummary = proofSummary(proofAttachments: mergedProofs)
        workspace.records[index].proofPhotoCount = photoCount
        workspace.records[index].proofVideoCount = videoCount
        workspace.records[index].proofFiles = mergedProofs
        workspace.records[index].teacherFeedback = "补充材料已提交，等待老师复审。"
        workspace.records[index].note = note.isEmpty ? "学生已按反馈补交材料。" : note

        workspace.notices.insert(
            StudentNotice(
                id: UUID().uuidString,
                title: "补充材料已提交",
                message: "\(record.taskTitle) 的补充材料已进入复审队列。",
                time: "刚刚",
                category: .review,
                isUnread: true
            ),
            at: 0
        )
        enqueueSyncOperation(
            .supplementRecord,
            title: "提交补充材料",
            detail: "\(record.taskTitle) · 新增 \(proofAttachments.count) 个凭证"
        )

        saveWorkspace(event: "补充材料已保存")
        return true
    }

    @discardableResult
    func submitExemption(item: ExemptionItem, reason: String, detail: String, proofAttachments: [ProofAttachment]) async -> Bool {
        let mutationKey = "submit-exemption"
        guard beginMutation(mutationKey) else {
            errorMessage = "免测申请正在提交，请勿重复操作。"
            return false
        }
        defer { endMutation(mutationKey) }
        if isRemoteMode {
            return await submitExemptionRemote(
                item: item,
                reason: reason,
                detail: detail,
                proofAttachments: proofAttachments,
                expectedSessionEpoch: sessionEpoch
            )
        }

        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inputMessage = ExemptionInputRule.validationMessage(reason: normalizedReason, detail: normalizedDetail) {
            errorMessage = inputMessage
            return false
        }
        guard !proofAttachments.isEmpty else { return false }
        guard ExemptionProofRule.accepts(proofAttachments) else { return false }
        guard proofAttachments.allSatisfy(\.isValidForUpload) else { return false }

        let application = ExemptionApplication(
            id: UUID().uuidString,
            studentId: workspace.student.id,
            item: item,
            reason: normalizedReason,
            detail: normalizedDetail,
            submittedAt: "刚刚",
            status: .pending,
            proofFiles: proofAttachments,
            teacherFeedback: "免测申请已提交，等待老师审核。",
            updatedAt: "刚刚"
        )
        workspace.exemptions.insert(application, at: 0)
        workspace.notices.insert(
            StudentNotice(
                id: UUID().uuidString,
                title: "免测申请已提交",
                message: "\(item.rawValue) 已进入审核流程。",
                time: "刚刚",
                category: .review,
                isUnread: true
            ),
            at: 0
        )
        enqueueSyncOperation(
            .submitExemption,
            title: "提交免测申请",
            detail: "\(item.rawValue) · \(proofSummary(proofAttachments: proofAttachments))"
        )
        saveWorkspace(event: "免测申请已保存")
        return true
    }

    @discardableResult
    func submitExemptionSupplement(
        for application: ExemptionApplication,
        reason: String,
        detail: String,
        proofAttachments: [ProofAttachment]
    ) async -> Bool {
        let mutationKey = "supplement-exemption:\(application.id)"
        guard beginMutation(mutationKey) else {
            errorMessage = "免测补充材料正在提交，请勿重复操作。"
            return false
        }
        defer { endMutation(mutationKey) }

        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inputMessage = ExemptionInputRule.validationMessage(reason: normalizedReason, detail: normalizedDetail) {
            errorMessage = inputMessage
            return false
        }
        guard application.status.canSupplement,
              !proofAttachments.isEmpty,
              ExemptionProofRule.accepts(proofAttachments) else {
            return false
        }

        if isRemoteMode {
            return await supplementExemptionRemote(
                application: application,
                reason: normalizedReason,
                detail: normalizedDetail,
                proofAttachments: proofAttachments,
                expectedSessionEpoch: sessionEpoch
            )
        }

        guard proofAttachments.allSatisfy(\.isValidForUpload) else { return false }

        guard let index = workspace.exemptions.firstIndex(where: { $0.id == application.id && $0.status.canSupplement }) else {
            return false
        }
        workspace.exemptions[index].status = .pending
        workspace.exemptions[index].detail = ExemptionInputRule.combinedReason(
            reason: normalizedReason,
            detail: normalizedDetail
        )
        workspace.exemptions[index].proofFiles += proofAttachments
        workspace.exemptions[index].teacherFeedback = "补充材料已提交，等待老师复审。"
        workspace.exemptions[index].updatedAt = "刚刚"
        enqueueSyncOperation(
            .supplementExemption,
            title: "提交免测补充材料",
            detail: "\(application.item.rawValue) · 新增 \(proofAttachments.count) 个凭证"
        )
        saveWorkspace(event: "免测补充材料已保存")
        return true
    }

    func saveDraft(
        task requestedTask: CourseTask,
        hours: Double,
        note: String,
        sportType: String? = nil,
        customSportType: String? = nil,
        proofAttachments: [ProofAttachment]
    ) {
        guard let task = currentSubmittableTask(matching: requestedTask) else {
            clearDraft()
            return
        }
        let submittedHours = normalizedHours(hours, for: task)
        let resolvedSportType = sportType == "other"
            ? customSportType?.trimmingCharacters(in: .whitespacesAndNewlines)
            : sportType
        let existingAttempt = draft?.pendingRemoteMutation
        let fingerprint = checkInFingerprint(
            task: task,
            hours: submittedHours,
            note: note,
            sportType: resolvedSportType,
            proofAttachments: proofAttachments
        )
        let retainedAttempt: PendingRemoteMutationAttempt?
        if let existingAttempt,
           let studentID = remoteCacheStudentID,
           existingAttempt.matches(
                scope: "sport-record:create",
                fingerprint: fingerprint,
                serverIdentity: remoteMutationServerIdentity,
                studentID: studentID
           ) {
            retainedAttempt = existingAttempt
        } else {
            retainedAttempt = nil
        }
        if existingAttempt != nil, retainedAttempt == nil {
            removePendingRemoteMutation(scope: "sport-record:create")
        }
        let draft = CheckInDraft(
            id: draft?.id ?? UUID().uuidString,
            taskId: task.id,
            hours: submittedHours,
            note: note,
            proofAttachments: proofAttachments,
            updatedAt: "刚刚",
            sportType: sportType,
            customSportType: customSportType,
            pendingRemoteMutation: retainedAttempt
        )
        self.draft = draft
        saveDraft(draft, event: "打卡草稿已保存")
    }

    func hourLimit(for task: CourseTask) -> Double {
        min(task.hours, hourRule.dailyLimit)
    }

    func normalizedHours(_ hours: Double, for task: CourseTask) -> Double {
        let allowedHours = [1.0, 2.0].filter { $0 <= hourLimit(for: task) }
        guard let minimum = allowedHours.first else { return 1 }
        return hours >= 1.5 ? (allowedHours.last ?? minimum) : minimum
    }

    func canResumePendingCheckIn(
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment]
    ) -> Bool {
        guard isRemoteMode,
              let studentID = remoteCacheStudentID,
              let attempt = draft?.pendingRemoteMutation,
              attempt.uploadedProofs.count == proofAttachments.count,
              !proofAttachments.isEmpty,
              attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) else {
            return false
        }
        let fingerprint = checkInFingerprint(
            task: task,
            hours: normalizedHours(hours, for: task),
            note: note,
            sportType: sportType,
            proofAttachments: proofAttachments
        )
        return attempt.matches(
            scope: "sport-record:create",
            fingerprint: fingerprint,
            serverIdentity: remoteMutationServerIdentity,
            studentID: studentID
        )
    }

    private func normalizedSubmissionHours(_ hours: Double) -> Double {
        hours >= 1.5 && hourRule.dailyLimit >= 2 ? 2 : 1
    }

    func clearDraft() {
        removePendingRemoteMutation(scope: "sport-record:create")
        draft = nil
        localStore.clearDraft()
        storeHealth.draftReadStatus = .missing
        storeHealth.lastWriteStatus = .cleared
        storeHealth.lastEvent = "打卡草稿已清理"
    }

    func discardCheckInSupplementAttempt(recordID: String) {
        discardPendingRemoteMutation(scope: "sport-record:supplement:\(recordID)")
    }

    func discardExemptionCreationAttempt() {
        discardPendingRemoteMutation(scope: "exemption:create:physical-test")
    }

    func discardExemptionSupplementAttempt(applicationID: String) {
        discardPendingRemoteMutation(scope: "exemption:supplement:\(applicationID)")
    }

    /// Safe, user-facing escape hatch for every persisted mutation scope. The
    /// Profile screen enumerates these summaries and calls this method after an
    /// explicit destructive confirmation.
    func discardPendingRemoteMutation(scope: String) {
        guard pendingRemoteMutations[scope] != nil || draft?.pendingRemoteMutation?.scope == scope else {
            return
        }
        if var updatedDraft = draft, updatedDraft.pendingRemoteMutation?.scope == scope {
            updatedDraft.pendingRemoteMutation = nil
            draft = updatedDraft
            saveDraft(updatedDraft, event: "已放弃待重试操作，保留表单草稿")
        }
        removePendingRemoteMutation(scope: scope)
    }

    func canRetryPendingRemoteMutation(scope: String) -> Bool {
        guard isRemoteMode,
              let studentID = remoteCacheStudentID,
              let attempt = pendingRemoteMutations[scope],
              attempt.matches(
                scope: scope,
                fingerprint: attempt.fingerprint,
                serverIdentity: remoteMutationServerIdentity,
                studentID: studentID
              ) else {
            return false
        }
        // A server-confirmed entry is never a mutation retry. Exposing it as
        // actionable lets Profile retry only the failed local cleanup without
        // requiring the original proof bytes or a still-mutable server target.
        if attempt.isServerConfirmed {
            return true
        }
        guard !attempt.sourceProofs.isEmpty,
              attempt.uploadedProofs.count == attempt.sourceProofs.count,
              attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) else {
            return false
        }
        var fingerprintFields = attempt.requestFields
        if scope == "sport-record:create" {
            fingerprintFields.removeValue(forKey: "taskTitle")
        }
        guard RemoteMutationFingerprint.make(
            scope: scope,
            fields: fingerprintFields,
            attachments: attempt.sourceProofs
        ) == attempt.fingerprint else {
            return false
        }

        if scope == "sport-record:create" {
            let taskID = attempt.requestFields["taskId"] ?? ""
            let task = taskID.isEmpty
                ? selfCheckInTask
                : workspace.tasks.first(where: { $0.id == taskID && $0.isSubmittable() })
            guard let task else { return false }
            return !hasSubmittedCheckInToday() &&
                attempt.requestFields["courseId"] == (task.isSyntheticSelfGeneral ? "" : task.courseId) &&
                attempt.requestFields["creditType"] == task.creditType.apiValue
        }
        if scope.hasPrefix("sport-record:supplement:") {
            guard let recordID = attempt.requestFields["recordId"] else { return false }
            return workspace.records.contains(where: {
                $0.id == recordID && ($0.status == .supplement || $0.status == .rejected)
            })
        }
        if scope == "exemption:create:physical-test" {
            guard let type = attempt.requestFields["type"] else { return false }
            return ExemptionItem.allCases.contains(where: { $0.apiValue == type })
        }
        if scope.hasPrefix("exemption:supplement:") {
            guard let applicationID = attempt.requestFields["exemptionId"] else { return false }
            return workspace.exemptions.contains(where: { $0.id == applicationID && $0.status.canSupplement })
        }
        return false
    }

    /// Retries directly from the protected journal. Profile uses this entry
    /// point so every one of the four scopes has a user-reachable continuation,
    /// including record supplements that do not have a dedicated form route.
    @discardableResult
    func retryPendingRemoteMutation(scope: String) async -> Bool {
        guard canRetryPendingRemoteMutation(scope: scope),
              let attempt = pendingRemoteMutations[scope] else {
            errorMessage = "该待重试操作还缺少原始文件或目标已失效。请核对最新记录，或明确放弃后重新提交。"
            return false
        }
        if attempt.isServerConfirmed {
            do {
                if draft?.pendingRemoteMutation?.scope == scope {
                    try clearPersistedRemoteAttemptFromDraftStrict()
                } else {
                    try removePendingRemoteMutationStrict(scope: scope)
                }
                errorMessage = nil
                return true
            } catch {
                retainServerConfirmedAttemptInMemory(attempt)
                errorMessage = serverConfirmedCleanupWarning
                return false
            }
        }
        let fields = attempt.requestFields
        if scope == "sport-record:create" {
            let taskID = fields["taskId"] ?? ""
            let task = taskID.isEmpty
                ? selfCheckInTask
                : workspace.tasks.first(where: { $0.id == taskID })
            guard let task else { return false }
            let sportType = fields["sportType"].flatMap { $0.isEmpty ? nil : $0 }
            return await submitCheckIn(
                task: task,
                hours: Double(fields["hours"] ?? "") ?? 1,
                note: fields["description"] ?? "",
                sportType: sportType,
                proofAttachments: attempt.sourceProofs
            )
        }
        if scope.hasPrefix("sport-record:supplement:"),
           let recordID = fields["recordId"],
           let record = workspace.records.first(where: { $0.id == recordID }) {
            return await submitSupplement(
                for: record,
                hours: Double(fields["hours"] ?? "") ?? 1,
                note: fields["description"] ?? "",
                proofAttachments: attempt.sourceProofs
            )
        }
        if scope == "exemption:create:physical-test",
           let type = fields["type"],
           let item = ExemptionItem.allCases.first(where: { $0.apiValue == type }) {
            return await submitExemption(
                item: item,
                reason: fields["reason"] ?? "",
                detail: fields["detail"] ?? "",
                proofAttachments: attempt.sourceProofs
            )
        }
        if scope.hasPrefix("exemption:supplement:"),
           let applicationID = fields["exemptionId"],
           let application = workspace.exemptions.first(where: { $0.id == applicationID }) {
            return await submitExemptionSupplement(
                for: application,
                reason: fields["reason"] ?? "",
                detail: fields["detail"] ?? "",
                proofAttachments: attempt.sourceProofs
            )
        }
        errorMessage = "无法识别这项待重试操作；请明确放弃后重新提交。"
        return false
    }

    func pendingExemptionFormRecovery(applicationID: String?) -> PendingExemptionFormRecovery? {
        let scope = applicationID.map { "exemption:supplement:\($0)" }
            ?? "exemption:create:physical-test"
        let existingApplication = applicationID.flatMap { id in
            workspace.exemptions.first(where: { $0.id == id })
        }
        guard isRemoteMode,
              let studentID = remoteCacheStudentID,
              let attempt = pendingRemoteMutations[scope],
              attempt.matches(
                scope: scope,
                fingerprint: attempt.fingerprint,
                serverIdentity: remoteMutationServerIdentity,
                studentID: studentID
              ) else {
            return nil
        }
        let typeValue = attempt.requestFields["type"] ?? existingApplication?.item.apiValue
        guard let item = ExemptionItem.allCases.first(where: { $0.apiValue == typeValue })
            ?? existingApplication?.item else { return nil }
        return PendingExemptionFormRecovery(
            scope: scope,
            item: item,
            reason: attempt.requestFields["reason"] ?? "",
            detail: attempt.requestFields["detail"] ?? "",
            sourceProofs: attempt.sourceProofs,
            uploadedProofCount: attempt.uploadedProofs.count
        )
    }

    func canResumePendingExemption(
        applicationID: String?,
        item: ExemptionItem,
        reason: String,
        detail: String,
        proofAttachments: [ProofAttachment]
    ) -> Bool {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = applicationID.map { "exemption:supplement:\($0)" }
            ?? "exemption:create:physical-test"
        var fields = [
            "reason": normalizedReason,
            "detail": normalizedDetail,
            "combinedReason": ExemptionInputRule.combinedReason(
                reason: normalizedReason,
                detail: normalizedDetail
            ),
            "organization": ""
        ]
        if let applicationID {
            fields["exemptionId"] = applicationID
        } else {
            fields["type"] = item.apiValue
        }
        let fingerprint = RemoteMutationFingerprint.make(
            scope: scope,
            fields: fields,
            attachments: proofAttachments
        )
        guard let studentID = remoteCacheStudentID,
              let attempt = pendingRemoteMutations[scope],
              attempt.uploadedProofs.count == proofAttachments.count,
              !proofAttachments.isEmpty,
              attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) else {
            return false
        }
        return attempt.matches(
            scope: scope,
            fingerprint: fingerprint,
            serverIdentity: remoteMutationServerIdentity,
            studentID: studentID
        )
    }

    func resetLocalDemoData() {
        guard !isRemoteMode else { return }
        localStore.clearAll()
        workspace = repository.loadWorkspace()
        enqueueSyncOperation(
            .resetLocalData,
            title: "重置本地演示数据",
            detail: "已恢复初始 mock 工作台",
            status: .localOnly
        )
        draft = nil
        storeHealth.draftReadStatus = .missing
        storeHealth.lastWriteStatus = .cleared
        storeHealth.lastEvent = "本地演示数据已清理"
        saveWorkspace(event: "本地演示数据已重置")
    }

    func convertEndurance(timeSeconds: Int) async -> EnduranceScoreResult? {
        guard isRemoteMode else {
            errorMessage = "请连接校园体育服务器后使用成绩换算。"
            return nil
        }
        guard let gender = workspace.student.gender.apiValue else {
            errorMessage = "学生性别尚未同步，暂时无法匹配耐力跑项目。"
            return nil
        }
        guard let gradeLevel = workspace.student.gradeLevel, !gradeLevel.isEmpty else {
            errorMessage = "学生年级尚未同步，暂时无法匹配评分组别。"
            return nil
        }

        let conversionEpoch = sessionEpoch
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await remoteRepo.convertEndurance(
                timeSeconds: timeSeconds,
                gender: gender,
                gradeLevel: gradeLevel
            )
            guard conversionEpoch == sessionEpoch, isRemoteMode else { return nil }
            return result
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: conversionEpoch)
            return nil
        }
    }

    private func submitCheckInRemote(
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment],
        expectedSessionEpoch: UInt64
    ) async -> Bool {
        guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
        guard !hasSubmittedCheckInToday() else {
            errorMessage = "今日已打卡，每天只能提交一次。"
            return false
        }
        guard task.isSubmittable() else { return false }
        guard !proofAttachments.isEmpty, ProofUploadRule.accepts(proofAttachments) else { return false }
        let submittedHours = normalizedHours(hours, for: task)
        let submittedNote = note.isEmpty ? "学生未填写补充说明。" : note
        let scope = "sport-record:create"
        let fingerprint = checkInFingerprint(
            task: task,
            hours: submittedHours,
            note: note,
            sportType: sportType,
            proofAttachments: proofAttachments
        )
        var attempt = resolveCheckInAttempt(
            scope: scope,
            fingerprint: fingerprint,
            task: task,
            hours: submittedHours,
            note: note,
            sportType: sportType,
            proofAttachments: proofAttachments
        )
        guard !attempt.isServerConfirmed else {
            retainServerConfirmedAttemptInMemory(attempt)
            errorMessage = serverConfirmedCleanupWarning
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try persistCheckInAttempt(
                attempt,
                task: task,
                hours: submittedHours,
                note: note,
                sportType: sportType,
                proofAttachments: proofAttachments
            )
            let sourceProofs = proofAttachments
            if attempt.uploadedProofs.count > sourceProofs.count ||
                !attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) {
                attempt = replaceCheckInAttempt(
                    scope: scope,
                    fingerprint: fingerprint,
                    task: task,
                    hours: submittedHours,
                    note: note,
                    sportType: sportType,
                    proofAttachments: proofAttachments
                )
                try persistCheckInAttempt(
                    attempt,
                    task: task,
                    hours: submittedHours,
                    note: note,
                    sportType: sportType,
                    proofAttachments: proofAttachments
                )
            }
            guard sourceProofs.dropFirst(attempt.uploadedProofs.count).allSatisfy(\.isValidForUpload) else {
                errorMessage = "尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。"
                return false
            }
            for index in attempt.uploadedProofs.count..<sourceProofs.count {
                let attachment = sourceProofs[index]
                checkInSubmissionPhase = .uploading(
                    fileName: attachment.fileName,
                    completedFiles: index,
                    totalFiles: sourceProofs.count,
                    fileProgress: 0
                )
                if let uploaded = try await remoteRepo.uploadProof(
                    attachment: attachment,
                    progressHandler: { [weak self] fileProgress in
                        Task { @MainActor [weak self] in
                            self?.updateCheckInUploadProgress(
                                fileName: attachment.fileName,
                                completedFiles: index,
                                totalFiles: sourceProofs.count,
                                fileProgress: fileProgress
                            )
                        }
                    }
                ) {
                    guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                    attempt.uploadedProofs.append(uploaded)
                    try persistCheckInAttempt(
                        attempt,
                        task: task,
                        hours: submittedHours,
                        note: note,
                        sportType: sportType,
                        proofAttachments: proofAttachments
                    )
                }
                checkInSubmissionPhase = .uploading(
                    fileName: attachment.fileName,
                    completedFiles: index,
                    totalFiles: sourceProofs.count,
                    fileProgress: 1
                )
            }

            attempt.markFinalMutationPrepared()
            try persistCheckInAttempt(
                attempt,
                task: task,
                hours: submittedHours,
                note: note,
                sportType: sportType,
                proofAttachments: proofAttachments
            )
            checkInSubmissionPhase = .submitting
            var submittedRecord = try await remoteRepo.submitCheckIn(
                taskId: task.id,
                courseId: task.isSyntheticSelfGeneral ? nil : task.courseId,
                creditType: task.creditType.apiValue,
                taskTitle: task.title,
                hours: submittedHours,
                note: submittedNote,
                sportType: sportType,
                proofFiles: attempt.uploadedProofs,
                idempotencyKey: attempt.idempotencyKey
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }

            attempt.markServerConfirmed(resultID: submittedRecord.id)
            var localJournalWarning: String?
            do {
                try persistCheckInAttempt(
                    attempt,
                    task: task,
                    hours: submittedHours,
                    note: note,
                    sportType: sportType,
                    proofAttachments: proofAttachments
                )
                try clearPersistedRemoteAttemptFromDraftStrict()
            } catch {
                retainServerConfirmedAttemptInMemory(attempt)
                localJournalWarning = "打卡已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。"
            }

            submittedRecord.proofFiles = attempt.uploadedProofs
            submittedRecord.proofPhotoCount = attempt.uploadedProofs.filter { $0.type == .image }.count
            submittedRecord.proofVideoCount = attempt.uploadedProofs.filter { $0.type == .video }.count
            submittedRecord.proofSummary = proofSummary(proofAttachments: attempt.uploadedProofs)

            checkInSubmissionPhase = .syncing
            var refreshWarning = localJournalWarning
            var refreshedSubmittedRecord = false
            do {
                let remoteWorkspace = try await remoteRepo.loadWorkspace()
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                refreshedSubmittedRecord = remoteWorkspace.records.contains { $0.id == submittedRecord.id }
                applyRemoteWorkspace(remoteWorkspace, event: "打卡已提交到服务器")
            } catch {
                if isUnauthorized(error) {
                    clearDraft()
                    await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
                    return true
                }
                refreshWarning = combinedWarning(
                    refreshWarning,
                    "记录已提交，但最新列表暂未同步。请稍后下拉刷新，不要重复提交。"
                )
            }

            if !refreshedSubmittedRecord {
                upsertCheckInRecord(submittedRecord)
            }
            workspace.notices.insert(
                StudentNotice(
                    id: UUID().uuidString,
                    title: "打卡已提交",
                    message: "\(task.title) 已成功提交，可在打卡记录中查看。",
                    time: "刚刚",
                    category: .system,
                    isUnread: true
                ),
                at: 0
            )
            if localJournalWarning == nil {
                clearDraft()
            }
            proofAttachments.forEach { ProofTransientFileStore.removeManagedCopy(at: $0.sourceFileURL) }
            saveWorkspace(event: "打卡已提交到服务器")
            errorMessage = refreshWarning
            canSafelyRetryCheckIn = false
            return true
        } catch {
            guard expectedSessionEpoch == sessionEpoch else { return false }
            if error is RemoteMutationJournalError {
                canSafelyRetryCheckIn = pendingRemoteMutations[scope] != nil
                errorMessage = error.localizedDescription
                return false
            }
            let shouldRetainAttempt = RemoteMutationJournalPolicy.shouldRetain(after: error)
            var journalError: Error?
            do {
                if shouldRetainAttempt {
                    try persistCheckInAttempt(
                        attempt,
                        task: task,
                        hours: submittedHours,
                        note: note,
                        sportType: sportType,
                        proofAttachments: proofAttachments
                    )
                } else {
                    try clearPersistedRemoteAttemptFromDraftStrict()
                }
            } catch {
                journalError = error
            }
            canSafelyRetryCheckIn = shouldRetainAttempt
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
            if let journalError, !isUnauthorized(error) {
                errorMessage = journalError.localizedDescription
            }
            return false
        }
    }

    private func supplementRemote(
        for record: CheckInRecord,
        hours: Double,
        note: String,
        proofAttachments: [ProofAttachment],
        expectedSessionEpoch: UInt64
    ) async -> Bool {
        guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
        guard record.status == .supplement || record.status == .rejected else { return false }
        guard !proofAttachments.isEmpty,
              ProofUploadRule.accepts(proofAttachments),
              ProofUploadRule.acceptsAttachmentCounts(record.proofFiles + proofAttachments) else { return false }

        let submittedHours = normalizedSubmissionHours(hours)
        let submittedNote = note.isEmpty ? "学生已按反馈补交材料。" : note
        let scope = "sport-record:supplement:\(record.id)"
        let requestFields = [
            "recordId": record.id,
            "hours": String(format: "%.1f", submittedHours),
            "description": submittedNote
        ]
        let fingerprint = RemoteMutationFingerprint.make(
            scope: scope,
            fields: requestFields,
            attachments: proofAttachments
        )
        var attempt = resolvePersistentAttempt(
            scope: scope,
            fingerprint: fingerprint,
            requestFields: requestFields,
            sourceProofs: proofAttachments
        )
        guard !attempt.isServerConfirmed else {
            retainServerConfirmedAttemptInMemory(attempt)
            errorMessage = serverConfirmedCleanupWarning
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try storePendingRemoteMutation(attempt)
            if attempt.uploadedProofs.count > proofAttachments.count ||
                !attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) {
                attempt = replacePersistentAttempt(
                    scope: scope,
                    fingerprint: fingerprint,
                    requestFields: requestFields,
                    sourceProofs: proofAttachments
                )
                try storePendingRemoteMutation(attempt)
            }
            guard proofAttachments.dropFirst(attempt.uploadedProofs.count).allSatisfy(\.isValidForUpload) else {
                errorMessage = "尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。"
                return false
            }
            for index in attempt.uploadedProofs.count..<proofAttachments.count {
                let attachment = proofAttachments[index]
                if let uploaded = try await remoteRepo.uploadProof(attachment: attachment) {
                    guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                    attempt.uploadedProofs.append(uploaded)
                    try storePendingRemoteMutation(attempt)
                }
            }

            attempt.markFinalMutationPrepared()
            try storePendingRemoteMutation(attempt)
            let supplementedRecord = try await remoteRepo.supplementCheckIn(
                recordId: record.id,
                note: submittedNote,
                hours: submittedHours,
                proofFiles: attempt.uploadedProofs,
                idempotencyKey: attempt.idempotencyKey
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }

            attempt.markServerConfirmed(resultID: supplementedRecord.id)
            var localJournalWarning: String?
            do {
                try storePendingRemoteMutation(attempt)
                try removePendingRemoteMutationStrict(scope: scope)
            } catch {
                retainServerConfirmedAttemptInMemory(attempt)
                localJournalWarning = "补充材料已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。"
            }

            var refreshedRecord = false
            var refreshWarning = localJournalWarning
            do {
                let remoteWorkspace = try await remoteRepo.loadWorkspace()
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                refreshedRecord = remoteWorkspace.records.contains { $0.id == record.id }
                applyRemoteWorkspace(remoteWorkspace, event: "补充材料已提交到服务器")
            } catch {
                if isUnauthorized(error) {
                    await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
                    return true
                }
                refreshWarning = combinedWarning(
                    refreshWarning,
                    "补充材料已提交，但最新列表暂未同步。请稍后下拉刷新，不要重复提交。"
                )
            }
            if !refreshedRecord,
               let index = workspace.records.firstIndex(where: { $0.id == record.id }) {
                let mergedProofs = workspace.records[index].proofFiles + attempt.uploadedProofs
                workspace.records[index].hours = submittedHours
                workspace.records[index].note = submittedNote
                workspace.records[index].status = .pending
                workspace.records[index].proofFiles = mergedProofs
                workspace.records[index].proofPhotoCount = mergedProofs.filter { $0.type == .image }.count
                workspace.records[index].proofVideoCount = mergedProofs.filter { $0.type == .video }.count
                workspace.records[index].proofSummary = proofSummary(proofAttachments: mergedProofs)
            }
            workspace.notices.insert(
                StudentNotice(
                    id: UUID().uuidString,
                    title: "补充材料已提交",
                    message: "\(record.taskTitle) 的补充材料已进入复审队列。",
                    time: "刚刚",
                    category: .review,
                    isUnread: true
                ),
                at: 0
            )
            proofAttachments.forEach { ProofTransientFileStore.removeManagedCopy(at: $0.sourceFileURL) }
            saveWorkspace(event: "补充材料已提交到服务器")
            errorMessage = refreshWarning
            return true
        } catch {
            guard expectedSessionEpoch == sessionEpoch else { return false }
            if error is RemoteMutationJournalError {
                errorMessage = error.localizedDescription
                return false
            }
            let shouldRetainAttempt = RemoteMutationJournalPolicy.shouldRetain(after: error)
            var journalError: Error?
            do {
                if shouldRetainAttempt {
                    try storePendingRemoteMutation(attempt)
                } else {
                    try removePendingRemoteMutationStrict(scope: scope)
                }
            } catch {
                journalError = error
            }
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
            if let journalError, !isUnauthorized(error) {
                errorMessage = journalError.localizedDescription
            }
            return false
        }
    }

    private func submitExemptionRemote(
        item: ExemptionItem,
        reason: String,
        detail: String,
        proofAttachments: [ProofAttachment],
        expectedSessionEpoch: UInt64
    ) async -> Bool {
        guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inputMessage = ExemptionInputRule.validationMessage(reason: normalizedReason, detail: normalizedDetail) {
            errorMessage = inputMessage
            return false
        }
        guard !proofAttachments.isEmpty else { return false }
        guard ExemptionProofRule.accepts(proofAttachments) else { return false }

        let scope = "exemption:create:physical-test"
        let requestFields = [
            "type": item.apiValue,
            "reason": normalizedReason,
            "detail": normalizedDetail,
            "combinedReason": ExemptionInputRule.combinedReason(reason: normalizedReason, detail: normalizedDetail),
            "organization": ""
        ]
        let fingerprint = RemoteMutationFingerprint.make(
            scope: scope,
            fields: requestFields,
            attachments: proofAttachments
        )
        var attempt = resolvePersistentAttempt(
            scope: scope,
            fingerprint: fingerprint,
            requestFields: requestFields,
            sourceProofs: proofAttachments
        )
        guard !attempt.isServerConfirmed else {
            retainServerConfirmedAttemptInMemory(attempt)
            errorMessage = serverConfirmedCleanupWarning
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try storePendingRemoteMutation(attempt)
            if attempt.uploadedProofs.count > proofAttachments.count ||
                !attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) {
                attempt = replacePersistentAttempt(
                    scope: scope,
                    fingerprint: fingerprint,
                    requestFields: requestFields,
                    sourceProofs: proofAttachments
                )
                try storePendingRemoteMutation(attempt)
            }
            guard proofAttachments.dropFirst(attempt.uploadedProofs.count).allSatisfy(\.isValidForUpload) else {
                errorMessage = "尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。"
                return false
            }
            for index in attempt.uploadedProofs.count..<proofAttachments.count {
                let attachment = proofAttachments[index]
                if let uploaded = try await remoteRepo.uploadProof(attachment: attachment) {
                    guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                    attempt.uploadedProofs.append(uploaded)
                    try storePendingRemoteMutation(attempt)
                }
            }

            attempt.markFinalMutationPrepared()
            try storePendingRemoteMutation(attempt)
            let application = try await remoteRepo.submitExemption(
                item: item.apiValue,
                reason: normalizedReason,
                detail: normalizedDetail,
                proofFiles: attempt.uploadedProofs.map { $0.cosKey ?? $0.source },
                idempotencyKey: attempt.idempotencyKey
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }

            attempt.markServerConfirmed(resultID: application.id)
            var localJournalWarning: String?
            do {
                try storePendingRemoteMutation(attempt)
                try removePendingRemoteMutationStrict(scope: scope)
            } catch {
                retainServerConfirmedAttemptInMemory(attempt)
                localJournalWarning = "免测申请已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。"
            }

            var refreshedSubmittedApplication = false
            if let remoteWorkspace = try? await remoteRepo.loadWorkspace() {
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                refreshedSubmittedApplication = remoteWorkspace.exemptions.contains { $0.id == application.id }
                applyRemoteWorkspace(remoteWorkspace, event: "免测申请已提交到服务器")
            }
            if !refreshedSubmittedApplication {
                upsertExemption(application)
            }
            workspace.notices.insert(
                StudentNotice(
                    id: UUID().uuidString,
                    title: "免测申请已提交",
                    message: "\(item.rawValue) 已进入审核流程。",
                    time: "刚刚",
                    category: .review,
                    isUnread: true
                ),
                at: 0
            )
            enqueueSyncOperation(
                .submitExemption,
                title: "提交免测申请",
                detail: "\(item.rawValue) · 已同步服务器",
                status: .synced
            )
            proofAttachments.forEach { ProofTransientFileStore.removeManagedCopy(at: $0.sourceFileURL) }
            saveWorkspace(event: "免测申请已提交到服务器")
            errorMessage = localJournalWarning
            return true
        } catch {
            guard expectedSessionEpoch == sessionEpoch else { return false }
            if error is RemoteMutationJournalError {
                errorMessage = error.localizedDescription
                return false
            }
            let shouldRetainAttempt = RemoteMutationJournalPolicy.shouldRetain(after: error)
            var journalError: Error?
            do {
                if shouldRetainAttempt {
                    try storePendingRemoteMutation(attempt)
                } else {
                    try removePendingRemoteMutationStrict(scope: scope)
                }
            } catch {
                journalError = error
            }
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
            if let journalError, !isUnauthorized(error) {
                errorMessage = journalError.localizedDescription
            }
            return false
        }
    }

    private func supplementExemptionRemote(
        application: ExemptionApplication,
        reason: String,
        detail: String,
        proofAttachments: [ProofAttachment],
        expectedSessionEpoch: UInt64
    ) async -> Bool {
        guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
        guard workspace.exemptions.contains(where: { $0.id == application.id && $0.status.canSupplement }) else {
            return false
        }
        let combinedReason = ExemptionInputRule.combinedReason(reason: reason, detail: detail)
        let scope = "exemption:supplement:\(application.id)"
        let requestFields = [
            "exemptionId": application.id,
            "reason": reason,
            "detail": detail,
            "combinedReason": combinedReason,
            "organization": ""
        ]
        let fingerprint = RemoteMutationFingerprint.make(
            scope: scope,
            fields: requestFields,
            attachments: proofAttachments
        )
        var attempt = resolvePersistentAttempt(
            scope: scope,
            fingerprint: fingerprint,
            requestFields: requestFields,
            sourceProofs: proofAttachments
        )
        guard !attempt.isServerConfirmed else {
            retainServerConfirmedAttemptInMemory(attempt)
            errorMessage = serverConfirmedCleanupWarning
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try storePendingRemoteMutation(attempt)
            if attempt.uploadedProofs.count > proofAttachments.count ||
                !attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) {
                attempt = replacePersistentAttempt(
                    scope: scope,
                    fingerprint: fingerprint,
                    requestFields: requestFields,
                    sourceProofs: proofAttachments
                )
                try storePendingRemoteMutation(attempt)
            }
            guard proofAttachments.dropFirst(attempt.uploadedProofs.count).allSatisfy(\.isValidForUpload) else {
                errorMessage = "尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。"
                return false
            }
            for index in attempt.uploadedProofs.count..<proofAttachments.count {
                let attachment = proofAttachments[index]
                if let uploaded = try await remoteRepo.uploadProof(attachment: attachment) {
                    guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                    attempt.uploadedProofs.append(uploaded)
                    try storePendingRemoteMutation(attempt)
                }
            }

            attempt.markFinalMutationPrepared()
            try storePendingRemoteMutation(attempt)
            var supplemented = try await remoteRepo.supplementExemption(
                application: application,
                reason: combinedReason,
                proofFiles: attempt.uploadedProofs.map { $0.cosKey ?? $0.source },
                idempotencyKey: attempt.idempotencyKey
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }

            attempt.markServerConfirmed(resultID: supplemented.id)
            var localJournalWarning: String?
            do {
                try storePendingRemoteMutation(attempt)
                try removePendingRemoteMutationStrict(scope: scope)
            } catch {
                retainServerConfirmedAttemptInMemory(attempt)
                localJournalWarning = "免测补充材料已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。"
            }
            supplemented.proofFiles = application.proofFiles + attempt.uploadedProofs
            supplemented.status = .pending
            supplemented.detail = combinedReason

            var refreshedApplication = false
            var refreshWarning = localJournalWarning
            do {
                let remoteWorkspace = try await remoteRepo.loadWorkspace()
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                refreshedApplication = remoteWorkspace.exemptions.contains { $0.id == application.id }
                applyRemoteWorkspace(remoteWorkspace, event: "免测补充材料已提交到服务器")
            } catch {
                if isUnauthorized(error) {
                    await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
                    return true
                }
                refreshWarning = combinedWarning(
                    refreshWarning,
                    "补充材料已提交，但最新申请列表暂未同步。请稍后下拉刷新，不要重复提交。"
                )
            }
            if !refreshedApplication {
                upsertExemption(supplemented)
            }
            workspace.notices.insert(
                StudentNotice(
                    id: UUID().uuidString,
                    title: "免测补充材料已提交",
                    message: "\(application.item.rawValue) 的补充材料已进入复审队列。",
                    time: "刚刚",
                    category: .review,
                    isUnread: true
                ),
                at: 0
            )
            enqueueSyncOperation(
                .supplementExemption,
                title: "提交免测补充材料",
                detail: "\(application.item.rawValue) · 已同步服务器",
                status: .synced
            )
            proofAttachments.forEach { ProofTransientFileStore.removeManagedCopy(at: $0.sourceFileURL) }
            saveWorkspace(event: "免测补充材料已提交到服务器")
            errorMessage = refreshWarning
            return true
        } catch {
            guard expectedSessionEpoch == sessionEpoch else { return false }
            if error is RemoteMutationJournalError {
                errorMessage = error.localizedDescription
                return false
            }
            let shouldRetainAttempt = RemoteMutationJournalPolicy.shouldRetain(after: error)
            var journalError: Error?
            do {
                if shouldRetainAttempt {
                    try storePendingRemoteMutation(attempt)
                } else {
                    try removePendingRemoteMutationStrict(scope: scope)
                }
            } catch {
                journalError = error
            }
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
            if let journalError, !isUnauthorized(error) {
                errorMessage = journalError.localizedDescription
            }
            return false
        }
    }

    private func handleRemoteError(_ error: Error, expectedSessionEpoch: UInt64? = nil) async {
        if let expectedSessionEpoch, expectedSessionEpoch != sessionEpoch {
            return
        }
        if let repositoryError = error as? RepositoryError,
           case .sessionChanged = repositoryError {
            return
        }

        if error is DecodingError {
            errorMessage = "服务器数据格式发生变化，请稍后重试或联系技术支持。"
        } else {
            errorMessage = error.localizedDescription
        }

        if let repositoryError = error as? RepositoryError,
           case .unauthorized = repositoryError {
            let expiredStudentID = remoteCacheStudentID
            sessionEpoch &+= 1
            let securelyCleared = await remoteRepo.clearSession()
            if let expiredStudentID {
                localStore.clearRemoteWorkspace(
                    baseURL: StudentServerConfig.resolvedBaseURL(),
                    studentID: expiredStudentID
                )
            }
            localStore.clearDraft()
            isAuthenticated = false
            isRemoteMode = false
            remoteCacheStudentID = nil
            isLoading = false
            isRefreshingWorkspace = false
            workspace = repository.loadWorkspace()
            draft = nil
            checkInSubmissionPhase = .idle
            canSafelyRetryCheckIn = false
            mutationGate.removeAll()
            let journalCleared = clearAllPendingRemoteMutations()
            if !securelyCleared {
                errorMessage = "登录已过期，且设备未能清理安全存储。请重启 App 后再登录。"
            } else if !journalCleared {
                errorMessage = "登录已过期，且设备未能清理待提交操作。请释放存储空间后重启 App。"
            }
        }
    }

    private func markNoticeReadRemote(id: String, expectedSessionEpoch: UInt64) async {
        let mutationKey = "notice:\(id)"
        guard expectedSessionEpoch == sessionEpoch, beginMutation(mutationKey) else { return }
        defer { endMutation(mutationKey) }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await remoteRepo.markNoticeRead(noticeId: id)
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return }
            guard let index = workspace.notices.firstIndex(where: { $0.id == id }) else { return }
            workspace.notices[index].isUnread = false
            saveWorkspace(event: "通知已读状态已同步服务器")
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
        }
    }

    private func markAllNoticesReadRemote(ids: [String], expectedSessionEpoch: UInt64) async {
        let mutationKey = "notice:all"
        guard expectedSessionEpoch == sessionEpoch, beginMutation(mutationKey) else { return }
        defer { endMutation(mutationKey) }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            for id in ids {
                try await remoteRepo.markNoticeRead(noticeId: id)
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return }
            }
            for index in workspace.notices.indices where ids.contains(workspace.notices[index].id) {
                workspace.notices[index].isUnread = false
            }
            saveWorkspace(event: "批量通知已读已同步服务器")
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch)
        }
    }

    private func applyRemoteWorkspace(_ remoteWorkspace: StudentWorkspace, event: String) {
        workspace = remoteWorkspace
        if workspace.syncOperations.isEmpty {
            workspace.syncOperations = [
                SyncOperation(
                    id: "sync-remote-load",
                    type: .resetLocalData,
                    title: "服务器同步",
                    detail: "从 \(StudentServerConfig.resolvedBaseURL().absoluteString) 读取学生端数据。",
                    createdAt: "刚刚",
                    status: .synced
                )
            ]
        }
        if let currentDraft = draft,
           currentDraft.taskId != "self-general",
           !workspace.tasks.contains(where: { $0.id == currentDraft.taskId && $0.isSubmittable() }) {
            clearDraft()
        }
        saveWorkspace(event: event)
    }

    private func upsertExemption(_ application: ExemptionApplication) {
        if let index = workspace.exemptions.firstIndex(where: { $0.id == application.id }) {
            workspace.exemptions[index] = application
        } else {
            workspace.exemptions.insert(application, at: 0)
        }
    }

    private func upsertCheckInRecord(_ record: CheckInRecord) {
        if let index = workspace.records.firstIndex(where: { $0.id == record.id }) {
            workspace.records[index] = record
        } else {
            workspace.records.insert(record, at: 0)
        }
    }

    private func updateCheckInUploadProgress(
        fileName: String,
        completedFiles: Int,
        totalFiles: Int,
        fileProgress: Double
    ) {
        guard case .uploading(let activeFileName, _, _, _) = checkInSubmissionPhase,
              activeFileName == fileName else {
            return
        }
        checkInSubmissionPhase = .uploading(
            fileName: fileName,
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            fileProgress: min(max(fileProgress, 0), 1)
        )
    }

    private func proofSummary(proofAttachments: [ProofAttachment]) -> String {
        let photoCount = proofAttachments.filter { $0.type == .image }.count
        let videoCount = proofAttachments.filter { $0.type == .video }.count
        var parts: [String] = []
        if photoCount > 0 {
            parts.append("\(photoCount) 张图片")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) 个短视频")
        }
        return parts.isEmpty ? "未添加凭证" : parts.joined(separator: "，")
    }

    private func enqueueSyncOperation(
        _ type: SyncOperationType,
        title: String,
        detail: String,
        status: SyncOperationStatus = .queued
    ) {
        workspace.syncOperations.insert(
            SyncOperation(
                id: UUID().uuidString,
                type: type,
                title: title,
                detail: detail,
                createdAt: "刚刚",
                status: status
            ),
            at: 0
        )
        if workspace.syncOperations.count > 12 {
            workspace.syncOperations = Array(workspace.syncOperations.prefix(12))
        }
    }

    private func saveWorkspace(event: String) {
        let saved = isRemoteMode
            ? localStore.saveRemoteWorkspace(
                workspace,
                baseURL: StudentServerConfig.resolvedBaseURL(),
                studentID: remoteCacheStudentID ?? workspace.student.id
            )
            : localStore.saveWorkspace(workspace)
        storeHealth.workspaceReadStatus = saved ? .loaded : storeHealth.workspaceReadStatus
        storeHealth.lastWriteStatus = saved ? .saved : .failed
        storeHealth.lastEvent = saved ? event : "\(event)失败"
    }

    @discardableResult
    private func saveDraft(_ draft: CheckInDraft, event: String) -> Bool {
        let saved = localStore.saveDraft(draft)
        storeHealth.draftReadStatus = saved ? .loaded : storeHealth.draftReadStatus
        storeHealth.lastWriteStatus = saved ? .saved : .failed
        storeHealth.lastEvent = saved ? event : "\(event)失败"
        return saved
    }

    private var remoteMutationServerIdentity: String {
        remoteRepo.serverIdentity
    }

    private func checkInFingerprint(
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment]
    ) -> String {
        var fields = checkInRequestFields(task: task, hours: hours, note: note, sportType: sportType)
        fields.removeValue(forKey: "taskTitle")
        return RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: fields,
            attachments: proofAttachments
        )
    }

    private func checkInRequestFields(
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String?
    ) -> [String: String] {
        [
            "taskId": task.isSyntheticSelfGeneral ? "" : task.id,
            "taskTitle": task.title,
            "courseId": task.isSyntheticSelfGeneral ? "" : task.courseId,
            "creditType": task.creditType.apiValue,
            "hours": String(format: "%.1f", hours),
            "description": note.isEmpty ? "学生未填写补充说明。" : note,
            "sportType": sportType ?? ""
        ]
    }

    private func resolveCheckInAttempt(
        scope: String,
        fingerprint: String,
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment]
    ) -> PendingRemoteMutationAttempt {
        let studentID = remoteCacheStudentID ?? workspace.student.id
        if let existing = pendingRemoteMutations[scope],
           existing.matches(
                scope: scope,
                fingerprint: fingerprint,
                serverIdentity: remoteMutationServerIdentity,
                studentID: studentID
           ) {
            return existing
        }
        if let existing = draft?.pendingRemoteMutation,
           existing.matches(
                scope: scope,
                fingerprint: fingerprint,
                serverIdentity: remoteMutationServerIdentity,
                studentID: studentID
           ) {
            return existing
        }
        return replaceCheckInAttempt(
            scope: scope,
            fingerprint: fingerprint,
            task: task,
            hours: hours,
            note: note,
            sportType: sportType,
            proofAttachments: proofAttachments
        )
    }

    private func replaceCheckInAttempt(
        scope: String,
        fingerprint: String,
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment]
    ) -> PendingRemoteMutationAttempt {
        let attempt = PendingRemoteMutationAttempt.create(
            scope: scope,
            fingerprint: fingerprint,
            serverIdentity: remoteMutationServerIdentity,
            studentID: remoteCacheStudentID ?? workspace.student.id,
            requestFields: checkInRequestFields(
                task: task,
                hours: hours,
                note: note,
                sportType: sportType
            ),
            sourceProofs: proofAttachments
        )
        return attempt
    }

    private func persistCheckInAttempt(
        _ attempt: PendingRemoteMutationAttempt,
        task: CourseTask,
        hours: Double,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment]
    ) throws {
        let knownSportTypes: Set<String> = [
            "running", "basketball", "football", "badminton",
            "swimming", "fitness", "cycling"
        ]
        let persistedSportType: String?
        let persistedCustomSportType: String?
        if let sportType, knownSportTypes.contains(sportType) {
            persistedSportType = sportType
            persistedCustomSportType = nil
        } else if let sportType, !sportType.isEmpty {
            persistedSportType = "other"
            persistedCustomSportType = sportType
        } else {
            persistedSportType = nil
            persistedCustomSportType = nil
        }
        let updatedDraft = CheckInDraft(
            id: draft?.id ?? UUID().uuidString,
            taskId: task.id,
            hours: hours,
            note: note,
            proofAttachments: proofAttachments,
            updatedAt: "刚刚",
            sportType: persistedSportType,
            customSportType: persistedCustomSportType,
            pendingRemoteMutation: attempt
        )
        draft = updatedDraft
        guard saveDraft(updatedDraft, event: "打卡重试状态已安全保存") else {
            throw RemoteMutationJournalError.writeFailed
        }
        try storePendingRemoteMutation(attempt)
    }

    private func resolvePersistentAttempt(
        scope: String,
        fingerprint: String,
        requestFields: [String: String],
        sourceProofs: [ProofAttachment]
    ) -> PendingRemoteMutationAttempt {
        let studentID = remoteCacheStudentID ?? workspace.student.id
        if let existing = pendingRemoteMutations[scope],
           existing.matches(
                scope: scope,
                fingerprint: fingerprint,
                serverIdentity: remoteMutationServerIdentity,
                studentID: studentID
           ) {
            return existing
        }
        return replacePersistentAttempt(
            scope: scope,
            fingerprint: fingerprint,
            requestFields: requestFields,
            sourceProofs: sourceProofs
        )
    }

    private func replacePersistentAttempt(
        scope: String,
        fingerprint: String,
        requestFields: [String: String],
        sourceProofs: [ProofAttachment]
    ) -> PendingRemoteMutationAttempt {
        let attempt = PendingRemoteMutationAttempt.create(
            scope: scope,
            fingerprint: fingerprint,
            serverIdentity: remoteMutationServerIdentity,
            studentID: remoteCacheStudentID ?? workspace.student.id,
            requestFields: requestFields,
            sourceProofs: sourceProofs
        )
        return attempt
    }

    private func sanitizePersistedRemoteMutations(for studentID: String) {
        pendingRemoteMutations = pendingRemoteMutations.filter { scope, attempt in
            scope == attempt.scope &&
                attempt.serverIdentity == remoteMutationServerIdentity &&
                attempt.studentID == studentID &&
                IdempotencyKeyPolicy.isValid(attempt.idempotencyKey)
        }

        if let attempt = draft?.pendingRemoteMutation {
            guard attempt.serverIdentity == remoteMutationServerIdentity,
                  attempt.studentID == studentID else {
                clearDraft()
                if !persistPendingRemoteMutationJournal() {
                    errorMessage = RemoteMutationJournalError.writeFailed.localizedDescription
                }
                return
            }
            guard IdempotencyKeyPolicy.isValid(attempt.idempotencyKey) else {
                clearPersistedRemoteAttemptFromDraft()
                if !persistPendingRemoteMutationJournal() {
                    errorMessage = RemoteMutationJournalError.writeFailed.localizedDescription
                }
                return
            }
            pendingRemoteMutations[attempt.scope] = attempt

            if attempt.isServerConfirmed, var updatedDraft = draft {
                updatedDraft.pendingRemoteMutation = nil
                if saveDraft(updatedDraft, event: "已清理服务器确认成功的打卡重试状态") {
                    draft = updatedDraft
                } else {
                    // Keep this confirmed marker available for cleanup-only
                    // recovery. It must never fall through to a network retry.
                    pendingRemoteMutationSummaries = Self.pendingMutationSummaries(from: pendingRemoteMutations)
                    errorMessage = serverConfirmedCleanupWarning
                    return
                }
            }
        }

        let confirmedAttempts = pendingRemoteMutations.filter { $0.value.isServerConfirmed }
        for scope in confirmedAttempts.keys {
            pendingRemoteMutations.removeValue(forKey: scope)
        }
        if !persistPendingRemoteMutationJournal() {
            // The durable journal still contains these entries. Restore only
            // their in-memory summaries so any user action remains cleanup-only
            // and the next login can safely attempt the deletion again.
            for (scope, attempt) in confirmedAttempts {
                pendingRemoteMutations[scope] = attempt
            }
            pendingRemoteMutationSummaries = Self.pendingMutationSummaries(from: pendingRemoteMutations)
            errorMessage = confirmedAttempts.isEmpty
                ? RemoteMutationJournalError.writeFailed.localizedDescription
                : serverConfirmedCleanupWarning
        }
    }

    private func clearPersistedRemoteAttemptFromDraft() {
        do {
            try clearPersistedRemoteAttemptFromDraftStrict()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearPersistedRemoteAttemptFromDraftStrict() throws {
        guard var updatedDraft = draft, let attempt = updatedDraft.pendingRemoteMutation else { return }
        updatedDraft.pendingRemoteMutation = nil
        draft = updatedDraft
        guard saveDraft(updatedDraft, event: "已清理失效的打卡重试状态") else {
            throw RemoteMutationJournalError.writeFailed
        }
        try removePendingRemoteMutationStrict(scope: attempt.scope)
    }

    private func storePendingRemoteMutation(_ attempt: PendingRemoteMutationAttempt) throws {
        let previous = pendingRemoteMutations[attempt.scope]
        pendingRemoteMutations[attempt.scope] = attempt
        guard persistPendingRemoteMutationJournal() else {
            if let previous {
                pendingRemoteMutations[attempt.scope] = previous
            } else {
                pendingRemoteMutations.removeValue(forKey: attempt.scope)
            }
            pendingRemoteMutationSummaries = Self.pendingMutationSummaries(from: pendingRemoteMutations)
            storeHealth.lastWriteStatus = .failed
            storeHealth.lastEvent = "待提交操作安全保存失败"
            throw RemoteMutationJournalError.writeFailed
        }
    }

    private func retainServerConfirmedAttemptInMemory(_ attempt: PendingRemoteMutationAttempt) {
        pendingRemoteMutations[attempt.scope] = attempt
        pendingRemoteMutationSummaries = Self.pendingMutationSummaries(from: pendingRemoteMutations)
    }

    private func combinedWarning(_ existing: String?, _ additional: String) -> String {
        guard let existing, !existing.isEmpty else { return additional }
        return "\(existing)\n\(additional)"
    }

    private var serverConfirmedCleanupWarning: String {
        "该操作已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。"
    }

    private func removePendingRemoteMutation(scope: String) {
        do {
            try removePendingRemoteMutationStrict(scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePendingRemoteMutationStrict(scope: String) throws {
        guard let removed = pendingRemoteMutations.removeValue(forKey: scope) else { return }
        guard persistPendingRemoteMutationJournal() else {
            pendingRemoteMutations[scope] = removed
            pendingRemoteMutationSummaries = Self.pendingMutationSummaries(from: pendingRemoteMutations)
            storeHealth.lastWriteStatus = .failed
            storeHealth.lastEvent = "待提交操作清理失败"
            throw RemoteMutationJournalError.writeFailed
        }
    }

    private func clearAllPendingRemoteMutations() -> Bool {
        pendingRemoteMutations.removeAll()
        pendingRemoteMutationSummaries = []
        if !localStore.clearPendingRemoteMutations() {
            storeHealth.lastWriteStatus = .failed
            storeHealth.lastEvent = "待提交操作清理失败"
            errorMessage = RemoteMutationJournalError.writeFailed.localizedDescription
            return false
        }
        return true
    }

    private func persistPendingRemoteMutationJournal() -> Bool {
        pendingRemoteMutationSummaries = Self.pendingMutationSummaries(from: pendingRemoteMutations)
        if pendingRemoteMutations.isEmpty {
            return localStore.clearPendingRemoteMutations()
        }
        return localStore.savePendingRemoteMutations(pendingRemoteMutations)
    }

    private func beginMutation(_ key: String) -> Bool {
        mutationGate.begin(key)
    }

    private func currentSubmittableTask(matching task: CourseTask, at date: Date = Date()) -> CourseTask? {
        if task.isSyntheticSelfGeneral {
            return selfCheckInTask.isSubmittable(at: date) ? selfCheckInTask : nil
        }
        return workspace.tasks.first { candidate in
            candidate.id == task.id && candidate.isSubmittable(at: date)
        }
    }

    private func endMutation(_ key: String) {
        mutationGate.end(key)
    }

    private func containsDuplicates(_ ids: [String]) -> Bool {
        Set(ids).count != ids.count
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        guard let repositoryError = error as? RepositoryError else { return false }
        if case .unauthorized = repositoryError {
            return true
        }
        return false
    }

    private static var localWorkspaceLoadedOperation: SyncOperation {
        SyncOperation(
            id: "sync-local-load",
            type: .resetLocalData,
            title: "读取本地工作台",
            detail: "从受保护的本地文件或 mock repository 加载学生端数据。",
            createdAt: "启动时",
            status: .localOnly
        )
    }

    private static func pendingMutationSummaries(
        from attempts: [String: PendingRemoteMutationAttempt]
    ) -> [PendingRemoteMutationSummary] {
        attempts.values
            .map(PendingRemoteMutationSummary.init)
            .sorted { lhs, rhs in lhs.scope < rhs.scope }
    }

    private static func bootEvent(
        workspaceStatus: LocalStoreReadStatus,
        draftStatus: LocalStoreReadStatus
    ) -> String {
        if workspaceStatus == .decodeFailed {
            return "工作台本地数据解码失败，已回退到 mock 数据。"
        }
        if draftStatus == .decodeFailed {
            return "草稿本地数据解码失败，已忽略本地草稿。"
        }
        if workspaceStatus == .loaded || draftStatus == .loaded {
            return "本地数据读取完成。"
        }
        return "未发现本地数据，已使用 mock 初始数据。"
    }
}
