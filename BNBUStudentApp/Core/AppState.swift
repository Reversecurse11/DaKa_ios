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
        BNBUL10n.text("无法安全保存待提交操作，已停止网络提交。请确认设备已解锁且存储空间充足，然后重试。")
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

enum CourseJoinCompletion {
    case active
    case requiresFirstEmailBinding(expectedVersion: Int)
}

struct ExerciseRecordResubmissionSelection: Hashable {
    let previousRecordId: String
    let nextAttemptNumber: Int
    let creditType: CreditType
}

enum LocalDemoAccess {
    static let launchArgument = "-bnbu-local-demo"

    static var showsLoginOption: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    static var permitsMockWorkspace: Bool {
#if DEBUG
        let process = ProcessInfo.processInfo
        let arguments = process.arguments
        let explicitUITestFixture = arguments.contains("-ui-testing-reset") &&
            arguments.contains("-ui-testing-authenticated")
        let nativeXCTestFixture = process.environment["XCTestConfigurationFilePath"] != nil
        return showsLoginOption || explicitUITestFixture || nativeXCTestFixture
#else
        false
#endif
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published private(set) var isLocalReviewMode = false
    @Published var workspace: StudentWorkspace
    @Published var draft: CheckInDraft?
    @Published private(set) var exerciseSession: ExerciseSession?
    @Published private(set) var existingRemoteExerciseSession: ExistingRemoteExerciseSession? = nil
    @Published private(set) var exerciseRecordResubmission: ExerciseRecordResubmissionSelection? = nil
    @Published private(set) var exerciseMediaDrafts: [ExerciseMediaDraft] = []
    @Published var storeHealth: LocalStoreHealth
    @Published var isLoading = false
    @Published var errorMessage: String? {
        didSet {
            if errorMessage != userFacingError?.displayText {
                userFacingError = nil
            }
        }
    }
    @Published private(set) var userFacingError: UserFacingError? = nil
    @Published private(set) var isRemoteMode = false
    @Published private(set) var checkInSubmissionPhase: CheckInSubmissionPhase = .idle
    @Published private(set) var canSafelyRetryCheckIn = false
    @Published private(set) var isAdvancingExerciseTestDuration = false
    @Published private(set) var exerciseTestToolCapabilities: Set<String> = []
    @Published private(set) var isProcessingAccountDeletion = false
    @Published private(set) var isSubmittingExemption = false
    @Published private(set) var isLoadingExemptions = false
    @Published private(set) var isSubmittingFeedback = false
    @Published private(set) var isLoadingFeedback = false
    @Published private(set) var pendingRemoteMutationSummaries: [PendingRemoteMutationSummary] = []
    /// The student's own join application. It is filed before sign-in, so it
    /// lives outside the workspace and survives until the teacher decides.
    @Published var courseJoinRequest: CourseJoinRequest?
    /// A review notice routes to the application it is about. The intent is held
    /// here rather than sent as a one-shot signal, so it survives the profile tab
    /// not being on screen yet.
    @Published var opensExemptionCentre = false
    /// Set to the new academic year when the semester has rolled over since the
    /// student last opened the app, so the dashboard can say so once.
    @Published var newSemesterWelcomeAcademicYear: String?
    @Published var feedbackTickets: [FeedbackTicket] = []
    /// Why the ticket list is empty, when the reason is not "no tickets yet".
    @Published var feedbackNotice: String?
    /// Server-controlled availability policy. Read-only and maintenance modes are
    /// announced by the health endpoint and block every write.
    @Published private(set) var systemModeStatus = SystemModeStatus()
    /// Set when the installed build is below the published minimum, which blocks
    /// the app until the student updates.
    @Published private(set) var updateRequirement: AppUpdateRequirement?
    /// Administrator-published help articles, with the load state the help centre
    /// shows: a spinner, a cached-copy notice, or a failure it can retry.
    @Published private(set) var helpArticles: [HelpArticle] = []
    @Published private(set) var isLoadingHelpArticles = false
    @Published private(set) var helpArticlesError: String?
    @Published private(set) var isShowingCachedHelpArticles = false

    private let repository: StudentRepository
    private let localStore: AppLocalStore
    private let apiClient = StudentAPIClient()
    private let remoteRepo: RemoteStudentRepository
    private var remoteCacheStudentID: String?
    private var studentSignInChallengeID: String?
    private var studentSignInChallengeAccount: String?
    private var studentSignInChallengeExpiresAt: String?
    private var firstEmailBindingChallengeID: String?
    private var firstEmailBindingExpectedVersion: Int?
    private var sessionEpoch: UInt64 = 0
    private var isRefreshingWorkspace = false
    private var mutationGate = InFlightMutationGate()
    private var pendingRemoteMutations: [String: PendingRemoteMutationAttempt] = [:]
    /// Local/demo targets remain available for fixture compatibility. A remote
    /// student workspace deliberately carries `.unavailable` because the
    /// student role cannot read ScoreRule targets.
    var hourRule: SportHourRule { workspace.hourRule }
    var showsExerciseTestTools: Bool {
        isRemoteMode &&
            StudentTestToolsConfig.isEnabled &&
            exerciseTestToolCapabilities.contains(StudentTestToolsConfig.durationAdvanceCapability) &&
            (exerciseSession?.serverVersion ?? 0) > 0
    }
    /// Business rule 3.3 gate on starting a session. Production keeps this
    /// on; UI tests disable it so flow tests are not wall-clock sensitive.
    var enforcesCheckInTimeWindow = true

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
        let exerciseSessionRead = localStore.readExerciseSession()
        let pendingMutationRead = localStore.readPendingRemoteMutations()
        var workspace = workspaceRead.value ?? repository.loadWorkspace()
        if workspace.syncOperations.isEmpty {
            workspace.syncOperations = [Self.localWorkspaceLoadedOperation]
        }
        let savedDraft = draftRead.value
        var draftReadStatus = draftRead.status
        var bootEvent = Self.bootEvent(workspaceStatus: workspaceRead.status, draftStatus: draftRead.status)
        var restoredDraft: CheckInDraft?

        if let savedDraft, savedDraft.creditType != .organizationOffset {
            restoredDraft = savedDraft
        } else if savedDraft != nil {
            draftReadStatus = .discarded
            bootEvent = "草稿数据已失效，已自动清理。"
            localStore.clearDraft()
        }

        self.workspace = workspace
        self.draft = restoredDraft
        self.exerciseSession = exerciseSessionRead.value?.reconciled()
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
        // Legacy local approval requests are not authoritative and are never
        // surfaced by the 2.0.13 direct-ACTIVE join flow.
        self.courseJoinRequest = nil
    }

    var courseRemaining: Double {
        guard !isRemoteMode, hourRule.isAvailable else { return 0 }
        return max(hourRule.courseRequired - workspace.progress.course, 0)
    }

    var generalRemaining: Double {
        guard !isRemoteMode, hourRule.isAvailable else { return 0 }
        return max(hourRule.generalRequired - workspace.progress.general, 0)
    }

    var totalCompleted: Double {
        if isRemoteMode {
            return max(workspace.progress.authoritativeTotalHours ?? 0, 0)
        }
        return min(workspace.progress.course, hourRule.courseRequired) + min(workspace.progress.general, hourRule.generalRequired)
    }

    var totalRemaining: Double {
        guard !isRemoteMode, hourRule.isAvailable else { return 0 }
        return max(hourRule.total - totalCompleted, 0)
    }

    var hasAuthoritativeRemoteProgress: Bool {
        !isRemoteMode || workspace.progress.authoritativeTotalHours != nil
    }

    var academicProjection: StudentAcademicProjection {
        StudentAcademicProjection.resolve(profile: workspace.student)
    }

    var completionRatio: Double {
        guard !isRemoteMode, hourRule.isAvailable, hourRule.total > 0 else { return 0 }
        return min(totalCompleted / hourRule.total, 1)
    }

    var unreadNoticeCount: Int {
        workspace.notices.filter(\.isUnread).count
    }

    /// Only an ACTIVE enrollment returned by the server backs a check-in.
    var currentExerciseCourse: Course? {
        workspace.courses
            .filter { $0.isCurrent && $0.allowsCheckIn }
            .sorted { $0.displayTitle < $1.displayTitle }
            .first
    }

    func hasPendingExemption(for item: ExemptionItem) -> Bool {
        workspace.exemptions.contains {
            $0.status == .pending && $0.item.apiValue == item.apiValue
        }
    }

    /// Kept only so older tests/callers fail closed instead of manufacturing a
    /// local course. The live UI uses `previewCourseInvite` below.
    func lookupCourseInvite(rawCode: String) -> CourseInvite? {
        if let validationMessage = CourseJoinCodeRule.validationMessage(for: rawCode) {
            errorMessage = validationMessage
            return nil
        }
        errorMessage = BNBUL10n.text("课程邀请必须由服务器预览确认，不能使用本地数据代替。")
        return nil
    }

    func previewCourseInvite(rawToken: String) async -> CourseInvite? {
        guard !isLoading else { return nil }
        if let validationMessage = CourseJoinCodeRule.validationMessage(for: rawToken) {
            errorMessage = validationMessage
            return nil
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let invite = try await remoteRepo.previewCourseInvite(token: rawToken)
            if workspace.courses.contains(where: { $0.id == invite.classSectionID }) {
                errorMessage = BNBUL10n.text("你已加入该课程，无需重复加入。")
                return nil
            }
            return invite
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: sessionEpoch, context: .join)
            return nil
        }
    }

    /// Restores a persisted rotating AuthSession. A pending first-email bind
    /// deliberately stops before protected workspace calls and returns the UI
    /// to the only routes the backend permits for that principal.
    func restoreRemoteSessionIfAvailable() async -> CourseJoinCompletion? {
        guard !isAuthenticated else { return .active }
        let restoreEpoch = sessionEpoch &+ 1
        sessionEpoch = restoreEpoch
        exerciseTestToolCapabilities = []
        do {
            guard let outcome = try await remoteRepo.restoreStudentSession() else { return nil }
            guard restoreEpoch == sessionEpoch else { return nil }
            if outcome.requiresFirstEmailBinding {
                isRemoteMode = true
                remoteCacheStudentID = outcome.student.id
                firstEmailBindingExpectedVersion = outcome.userVersion
                firstEmailBindingChallengeID = nil
                isAuthenticated = false
                return .requiresFirstEmailBinding(expectedVersion: outcome.userVersion)
            }
            try await activateRemoteStudent(outcome.student, expectedEpoch: restoreEpoch)
            isAuthenticated = true
            return .active
        } catch {
            guard restoreEpoch == sessionEpoch else { return nil }
            await handleRemoteError(error, expectedSessionEpoch: restoreEpoch)
            isAuthenticated = false
            isRemoteMode = false
            remoteCacheStudentID = nil
            return nil
        }
    }

    /// The academic year rolls over on 1 September. The first time the app runs
    /// in a new one, last term's cached workspace no longer applies, so the
    /// dashboard says so rather than showing stale progress without comment.
    func evaluateNewSemesterWelcome() {
        let currentYear = StudentAcademicProjection
            .resolve(profile: workspace.student)
            .academicYear
        guard !currentYear.isEmpty else { return }
        let cachedYear = localStore.loadCachedAcademicYear()
        guard !cachedYear.isEmpty else {
            localStore.saveCachedAcademicYear(currentYear)
            return
        }
        guard cachedYear != currentYear else { return }
        newSemesterWelcomeAcademicYear = currentYear
    }

    func dismissNewSemesterWelcome() {
        if let year = newSemesterWelcomeAcademicYear {
            localStore.saveCachedAcademicYear(year)
        }
        newSemesterWelcomeAcademicYear = nil
    }

    /// Compatibility entry: there is no local OTP success path.
    @discardableResult
    func sendLoginCode(to value: String, channel: ContactChannel) -> Bool {
        if let validationMessage = ContactBindingRule.validationMessage(value, for: channel) {
            errorMessage = validationMessage
            return false
        }
        errorMessage = BNBUL10n.text("验证码必须由服务器发送。")
        return false
    }

    /// Compatibility entry: never maps a code to the demo workspace.
    @discardableResult
    func signInWithCode(_ code: String, contact: String, channel: ContactChannel) -> Bool {
        guard ContactBindingRule.isValidCode(code) else {
            errorMessage = BNBUL10n.text("请输入 6 位数字验证码")
            return false
        }
        guard ContactBindingRule.isValid(contact, for: channel) else {
            errorMessage = ContactBindingRule.validationMessage(contact, for: channel)
            return false
        }
        errorMessage = BNBUL10n.text("验证码必须由服务器验证。")
        return false
    }

    func requestEmailLoginCode(to account: String, locale: String) async -> Bool {
        guard !isLoading else { return false }
        guard ContactBindingRule.isValid(account, for: .email) else {
            errorMessage = ContactBindingRule.validationMessage(account, for: .email)
            return false
        }
        guard let organizationCode = StudentServerConfig.resolvedOrganizationCode() else {
            errorMessage = BNBUL10n.text("CONTRACT DECISION REQUIRED：本地环境尚未显式配置 BNBU organizationCode。")
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let challenge = try await remoteRepo.requestStudentSignInCode(
                account: account,
                organizationCode: organizationCode,
                locale: locale
            )
            studentSignInChallengeID = challenge.challengeId
            studentSignInChallengeAccount = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            studentSignInChallengeExpiresAt = challenge.expiresAt
            return true
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: sessionEpoch, context: .otp)
            return false
        }
    }

    func verifyEmailLoginCode(_ code: String, account: String) async -> Bool {
        guard !isLoading else { return false }
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ContactBindingRule.isValidStudentSignInCode(code) else {
            errorMessage = BNBUL10n.text("请输入 4 到 10 位数字验证码")
            return false
        }
        guard let challengeID = studentSignInChallengeID,
              studentSignInChallengeAccount == normalizedAccount else {
            errorMessage = BNBUL10n.text("请先为当前邮箱获取验证码。")
            return false
        }
        sessionEpoch &+= 1
        mutationGate.removeAll()
        let loginEpoch = sessionEpoch
        isLoading = true
        errorMessage = nil
        defer {
            if loginEpoch == sessionEpoch { isLoading = false }
        }
        do {
            let authenticatedStudent = try await remoteRepo.verifyStudentSignInCode(
                challengeId: challengeID,
                code: code
            )
            guard loginEpoch == sessionEpoch else { return false }
            try await activateRemoteStudent(authenticatedStudent, expectedEpoch: loginEpoch)
            studentSignInChallengeID = nil
            studentSignInChallengeAccount = nil
            studentSignInChallengeExpiresAt = nil
            isAuthenticated = true
            return true
        } catch {
            guard loginEpoch == sessionEpoch else { return false }
            await handleRemoteError(error, expectedSessionEpoch: loginEpoch, context: .otp)
            _ = await remoteRepo.clearSession()
            isRemoteMode = false
            remoteCacheStudentID = nil
            isAuthenticated = false
            return false
        }
    }

    /// Compatibility entry for the retired local account-recovery form. No
    /// matching mutation is published by OpenAPI 2.0.13, so it must fail closed.
    @discardableResult
    func submitRecoveryRequest(
        studentNumber: String,
        name: String,
        description: String,
        newPhone: String,
        newEmail: String
    ) -> Bool {
        _ = (studentNumber, name, description, newPhone, newEmail)
        errorMessage = BNBUL10n.text("账号恢复接口未在当前合同中发布；本地不会创建假申请。")
        return false
    }

    var systemMode: SystemMode { systemModeStatus.mode }

    var isWriteAllowed: Bool { !systemMode.blocksWrites }

    /// Startup availability check. A failure or a missing field leaves the app in
    /// `normal`, so a staged backend never blocks the student.
    func refreshSystemStatus() async {
        if isRemoteMode {
            systemModeStatus = await remoteRepo.loadSystemMode()
            updateRequirement = await remoteRepo.loadUpdateRequirement()
        } else {
            systemModeStatus = repository.loadSystemMode()
            updateRequirement = repository.loadUpdateRequirement()
        }
    }

    /// Loads help articles, mirroring Android's help centre: the cached copy is
    /// shown first so the page is never blank, then the server result replaces it
    /// and is cached. A failure keeps the cached copy under a notice, or reports
    /// an error the page can retry.
    func refreshHelpArticles() async {
        isLoadingHelpArticles = helpArticles.isEmpty
        helpArticlesError = nil
        isShowingCachedHelpArticles = false

        let cached = HelpArticle.displayOrdered(localStore.loadHelpArticles())
        if helpArticles.isEmpty, !cached.isEmpty {
            helpArticles = cached
            isLoadingHelpArticles = false
        }

        do {
            let fetched: [HelpArticle]
            if isRemoteMode {
                fetched = try await remoteRepo.loadHelpArticles()
            } else {
                fetched = HelpArticle.displayOrdered(try repository.loadHelpArticles())
            }
            helpArticles = fetched
            localStore.saveHelpArticles(fetched)
        } catch is CancellationError {
            isLoadingHelpArticles = false
            return
        } catch {
            if isRemoteMode, isUnauthorized(error) {
                await handleRemoteError(error)
            }
            let fallback = cached.isEmpty ? helpArticles : cached
            if fallback.isEmpty {
                helpArticlesError = BNBUL10n.text("帮助内容暂时无法加载，请稍后重试。")
            } else {
                helpArticles = fallback
                isShowingCachedHelpArticles = true
            }
        }

        isLoadingHelpArticles = false
    }

    /// Refuses a write while the server is read-only or under maintenance, and
    /// reports why, mirroring Android's `allowWrite`.
    @discardableResult
    func allowWrite() -> Bool {
        guard !isWriteAllowed else { return true }
        errorMessage = systemMode == .maintenance
            ? BNBUL10n.text("系统当前处于维护模式，暂不能提交或修改内容。")
            : BNBUL10n.text("系统当前处于只读模式，暂不能提交或修改内容。")
        return false
    }

    /// Problem reports the student has filed. Loaded lazily the first time the
    /// feedback page opens its list tab.
    func refreshFeedbackTickets() async {
        guard isRemoteMode else {
            feedbackNotice = nil
            feedbackTickets = repository.loadFeedbackTickets()
            return
        }
        guard !isLoadingFeedback else { return }
        let expectedSessionEpoch = sessionEpoch
        isLoadingFeedback = true
        defer { isLoadingFeedback = false }
        do {
            let tickets = try await remoteRepo.listFeedback()
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return }
            feedbackTickets = tickets
            feedbackNotice = nil
            errorMessage = nil
        } catch {
            await handleRemoteError(
                error,
                expectedSessionEpoch: expectedSessionEpoch,
                context: .feedback
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode,
                  feedbackTickets.isEmpty else { return }
            feedbackNotice = BNBUL10n.text("反馈记录暂时无法刷新，请按错误提示稍后重试。")
        }
    }

    /// Files a problem report. Returns the accepted ticket so the caller can
    /// show its number, mirroring the Android confirmation screen.
    func submitFeedback(
        category: FeedbackCategory,
        description: String
    ) async -> FeedbackTicket? {
        if let validationMessage = FeedbackRule.validationMessage(description: description) {
            errorMessage = validationMessage
            return nil
        }
        guard allowWrite() else { return nil }
        guard !isSubmittingFeedback else { return nil }

        if isRemoteMode {
            let expectedSessionEpoch = sessionEpoch
            isSubmittingFeedback = true
            defer { isSubmittingFeedback = false }
            do {
                let ticket = try await remoteRepo.createFeedback(
                    category: category,
                    content: description
                )
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return nil }
                feedbackTickets.removeAll { $0.id == ticket.id }
                feedbackTickets.insert(ticket, at: 0)
                feedbackNotice = nil
                errorMessage = nil
                return ticket
            } catch {
                await handleRemoteError(
                    error,
                    expectedSessionEpoch: expectedSessionEpoch,
                    context: .feedback
                )
                return nil
            }
        }

        errorMessage = nil
        let ticket = FeedbackTicket(
            id: UUID().uuidString,
            ticketNumber: "FB-\(Int(Date().timeIntervalSince1970) % 100000)",
            category: category.title,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .pending,
            createdAt: BNBUDateFormat.writtenDateTime(Date()),
            reply: nil
        )
        feedbackTickets.insert(ticket, at: 0)
        return ticket
    }

    /// Sends a verification code to a contact the student is binding. Both
    /// contacts are bound during registration so a reinstall can be recovered
    /// with a code rather than a password.
    @discardableResult
    func sendContactVerificationCode(to value: String, channel: ContactChannel) -> Bool {
        if let validationMessage = ContactBindingRule.validationMessage(value, for: channel) {
            errorMessage = validationMessage
            return false
        }
        errorMessage = BNBUL10n.text("当前合同只支持 EMAIL，且已验证邮箱变更需要新旧邮箱双验证码；本地不会模拟成功。")
        return false
    }

    @discardableResult
    func verifyContactCode(_ code: String, for value: String, channel: ContactChannel) -> Bool {
        guard ContactBindingRule.isValidCode(code) else {
            errorMessage = BNBUL10n.text("请输入 6 位数字验证码")
            return false
        }
        errorMessage = BNBUL10n.text("联系方式验证码必须由服务器验证；本地不会模拟成功。")
        return false
    }

    /// Compatibility entry for the removed approval-request flow. It always
    /// fails closed; the live UI calls the atomic join operation below.
    @discardableResult
    func submitCourseJoinRequest(
        invite: CourseInvite,
        name: String,
        studentNumber: String,
        phone: String,
        email: String
    ) -> Bool {
        if let validationMessage = CourseJoinRequestRule.validationMessage(
            name: name,
            studentNumber: studentNumber
        ) {
            errorMessage = validationMessage
            return false
        }
        errorMessage = BNBUL10n.text("课程必须通过服务器 Join Capability 原子加入，不能创建本地待审核记录。")
        return false
    }

    func joinCourseInvite(
        _ invite: CourseInvite,
        name: String,
        studentNumber: String,
        gender: StudentGender,
        gradeYear: Int
    ) async -> CourseJoinCompletion? {
        guard !isLoading else { return nil }
        if let validationMessage = CourseJoinRequestRule.validationMessage(
            name: name,
            studentNumber: studentNumber
        ) {
            errorMessage = validationMessage
            return nil
        }
        guard gender.courseJoinAPIValue != nil, (1000...9999).contains(gradeYear) else {
            errorMessage = BNBUL10n.text("请选择性别并填写四位入学年份。")
            return nil
        }
        sessionEpoch &+= 1
        let joinEpoch = sessionEpoch
        exerciseTestToolCapabilities = []
        isLoading = true
        errorMessage = nil
        defer {
            if joinEpoch == sessionEpoch { isLoading = false }
        }
        do {
            let outcome = try await remoteRepo.joinCourseInvite(
                invite,
                fullName: name,
                studentNumber: studentNumber,
                gender: gender,
                gradeYear: gradeYear
            )
            guard joinEpoch == sessionEpoch else { return nil }
            if outcome.requiresFirstEmailBinding {
                isRemoteMode = true
                remoteCacheStudentID = outcome.student.id
                firstEmailBindingExpectedVersion = outcome.userVersion
                firstEmailBindingChallengeID = nil
                isAuthenticated = false
                return .requiresFirstEmailBinding(expectedVersion: outcome.userVersion)
            }
            try await activateRemoteStudent(outcome.student, expectedEpoch: joinEpoch)
            courseJoinRequest = nil
            localStore.clearCourseJoinRequest()
            isAuthenticated = true
            return .active
        } catch {
            guard joinEpoch == sessionEpoch else { return nil }
            await handleRemoteError(error, expectedSessionEpoch: joinEpoch, context: .join)
            _ = await remoteRepo.clearSession()
            isRemoteMode = false
            remoteCacheStudentID = nil
            isAuthenticated = false
            return nil
        }
    }

    func requestFirstEmailBinding(email: String, locale: String) async -> Bool {
        guard !isLoading,
              let expectedVersion = firstEmailBindingExpectedVersion else { return false }
        guard ContactBindingRule.isValid(email, for: .email) else {
            errorMessage = ContactBindingRule.validationMessage(email, for: .email)
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let challenge = try await remoteRepo.requestFirstEmailBinding(
                email: email,
                locale: locale,
                expectedVersion: expectedVersion
            )
            firstEmailBindingChallengeID = challenge.challengeId
            return true
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: sessionEpoch, context: .otp)
            return false
        }
    }

    func verifyFirstEmailBinding(code: String) async -> Bool {
        guard !isLoading, let challengeID = firstEmailBindingChallengeID else { return false }
        guard ContactBindingRule.isValidStudentSignInCode(code) else {
            errorMessage = BNBUL10n.text("请输入 4 到 10 位数字验证码。")
            return false
        }
        let bindingEpoch = sessionEpoch
        isLoading = true
        errorMessage = nil
        defer {
            if bindingEpoch == sessionEpoch { isLoading = false }
        }
        do {
            let student = try await remoteRepo.verifyFirstEmailBinding(
                challengeId: challengeID,
                newEmailCode: code
            )
            guard bindingEpoch == sessionEpoch else { return false }
            try await activateRemoteStudent(student, expectedEpoch: bindingEpoch)
            firstEmailBindingChallengeID = nil
            firstEmailBindingExpectedVersion = nil
            courseJoinRequest = nil
            localStore.clearCourseJoinRequest()
            isAuthenticated = true
            return true
        } catch {
            guard bindingEpoch == sessionEpoch else { return false }
            await handleRemoteError(error, expectedSessionEpoch: bindingEpoch, context: .otp)
            return false
        }
    }

    func startExerciseSession(
        category: ExerciseCategory,
        sportType: ExerciseSportType?,
        customSportName: String,
        at startTime: Date = Date()
    ) -> Bool {
        guard exerciseSession == nil else {
            errorMessage = BNBUL10n.text("已有进行中或待提交的运动，请先完成当前记录。")
            return false
        }
        if let validationMessage = ExerciseSessionInputRule.validationMessage(
            sportType: sportType,
            customSportName: customSportName
        ) {
            errorMessage = validationMessage
            return false
        }
        guard !hasSubmittedCheckInToday(at: startTime) else {
            errorMessage = BNBUL10n.text("今日已打卡，不能再次开始运动。")
            return false
        }
        if enforcesCheckInTimeWindow,
           let message = currentExerciseCourse?.checkInTimeWindow.blockingMessage(at: startTime) {
            errorMessage = message
            return false
        }
        guard let currentCourse = currentExerciseCourse else {
            errorMessage = BNBUL10n.text("当前学期没有 ACTIVE 体育课程，请使用有效邀请码加入或联系体育部。")
            return false
        }
        guard let sportType else { return false }
        let normalizedCustomName = customSportName.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ExerciseSession(
            id: UUID().uuidString,
            studentID: workspace.student.id,
            category: category,
            sportType: sportType,
            customSportName: sportType == .other ? normalizedCustomName : nil,
            courseID: category == .courseRelated ? currentCourse.id : nil,
            startTime: startTime,
            endTime: nil,
            status: .active,
            locationStatus: .unavailable,
            latitude: nil,
            longitude: nil
        )
        guard localStore.saveExerciseSession(session) else {
            errorMessage = BNBUL10n.text("无法安全保存运动开始时间，请确认设备存储空间后重试。")
            return false
        }
        exerciseSession = session
        errorMessage = nil
        return true
    }

    /// Remote mode must receive an authoritative ExerciseSession id before the
    /// local timer is persisted. Local/demo mode keeps the existing behavior.
    func startExerciseSessionAuthoritatively(
        category: ExerciseCategory,
        sportType: ExerciseSportType?,
        customSportName: String,
        at startTime: Date = Date()
    ) async -> Bool {
        guard isRemoteMode else {
            return startExerciseSession(
                category: category,
                sportType: sportType,
                customSportName: customSportName,
                at: startTime
            )
        }
        guard exerciseSession == nil else {
            errorMessage = BNBUL10n.text("已有进行中或待提交的运动，请先完成当前记录。")
            return false
        }
        if let validationMessage = ExerciseSessionInputRule.validationMessage(
            sportType: sportType,
            customSportName: customSportName
        ) {
            errorMessage = validationMessage
            return false
        }
        if enforcesCheckInTimeWindow,
           let message = currentExerciseCourse?.checkInTimeWindow.blockingMessage(at: startTime) {
            errorMessage = message
            return false
        }
        guard let currentCourse = currentExerciseCourse, let sportType else {
            errorMessage = BNBUL10n.text("当前学期没有 ACTIVE 体育课程，请使用有效邀请码加入或联系体育部。")
            return false
        }
        let expectedSessionEpoch = sessionEpoch
        let recoverableLocalSession = localStore.readExerciseSession().value.flatMap { stored in
            let courseContextMatches = stored.category != .courseRelated || stored.courseID == currentCourse.id
            return stored.studentID == workspace.student.id &&
                stored.status == .active &&
                courseContextMatches ? stored : nil
        }
        do {
            let outcome = try await remoteRepo.startOrRecoverExerciseSession(
                preferredClassSectionId: currentCourse.id,
                recoverableLocalSessionId: recoverableLocalSession?.id,
                clientObservedAt: startTime
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
            let remote: ContractExerciseSession
            let recoveredContext: ExerciseSession?
            switch outcome {
            case .created(let session, _):
                remote = session
                recoveredContext = nil
                existingRemoteExerciseSession = nil
            case .recovered(let session, _):
                guard let localSession = recoverableLocalSession,
                      localSession.id == session.id else {
                    errorMessage = BNBUL10n.text("本机运动上下文已失效，请刷新状态后重试。")
                    return false
                }
                remote = session
                recoveredContext = localSession
                existingRemoteExerciseSession = nil
            case .alreadyActive(let session, let requestId):
                guard let authoritativeStart = Self.contractDate(session.startedAt) else {
                    errorMessage = BNBUL10n.text("服务器返回了无效的运动开始时间。")
                    return false
                }
                existingRemoteExerciseSession = ExistingRemoteExerciseSession(
                    sessionID: session.id,
                    startedAt: authoritativeStart,
                    status: Self.safeRemoteSessionStatus(session.status),
                    requestId: ClientErrorMapper.safeRequestId(requestId)
                )
                // Do not materialize a local ExerciseSession here. It may have
                // been created on another device and this client has neither a
                // takeover contract nor the original business context.
                exerciseSession = nil
                errorMessage = nil
                return false
            }
            guard remote.studentId == workspace.student.id else {
                errorMessage = BNBUL10n.text("服务器返回的运动会话不属于当前学生，已停止恢复。")
                return false
            }
            guard let authoritativeStart = Self.contractDate(remote.startedAt) else {
                errorMessage = BNBUL10n.text("服务器返回了无效的运动开始时间。")
                return false
            }
            let normalizedCustomName = customSportName.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = ExerciseSession(
                id: remote.id,
                studentID: workspace.student.id,
                category: recoveredContext?.category ?? category,
                sportType: recoveredContext?.sportType ?? sportType,
                customSportName: recoveredContext?.customSportName
                    ?? (sportType == .other ? normalizedCustomName : nil),
                courseID: recoveredContext?.courseID
                    ?? (category == .courseRelated ? currentCourse.id : nil),
                startTime: authoritativeStart,
                status: .active,
                locationStatus: .unavailable,
                latitude: nil,
                longitude: nil,
                pauses: recoveredContext?.pauses ?? [],
                serverVersion: remote.version,
                authoritativeDurationSeconds: remote.actualDurationSeconds,
                authoritativeDurationObservedAt: Date()
            )
            guard localStore.saveExerciseSession(session) else {
                errorMessage = BNBUL10n.text("无法安全保存运动开始时间，请确认设备存储空间后重试。")
                return false
            }
            exerciseSession = session
            errorMessage = nil
            return true
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .session)
            return false
        }
    }

    /// Refreshes only the read-only cross-device conflict. It cannot create or
    /// control a Session and therefore cannot cancel work on another device.
    func refreshExistingRemoteExerciseSession() async {
        guard isRemoteMode, let currentCourse = currentExerciseCourse else { return }
        let expectedSessionEpoch = sessionEpoch
        do {
            let outcome = try await remoteRepo.readActiveExerciseSession(
                preferredClassSectionId: currentCourse.id
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return }
            guard case .alreadyActive(let remote, let requestId)? = outcome else {
                existingRemoteExerciseSession = nil
                errorMessage = BNBUL10n.text("服务器已没有进行中的运动，可以重新开始。")
                return
            }
            guard let authoritativeStart = Self.contractDate(remote.startedAt) else {
                errorMessage = BNBUL10n.text("服务器返回了无效的运动开始时间。")
                return
            }
            existingRemoteExerciseSession = ExistingRemoteExerciseSession(
                sessionID: remote.id,
                startedAt: authoritativeStart,
                status: Self.safeRemoteSessionStatus(remote.status),
                requestId: ClientErrorMapper.safeRequestId(requestId)
            )
            errorMessage = nil
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .session)
        }
    }

    private static func safeRemoteSessionStatus(_ rawValue: String) -> String {
        switch rawValue {
        case "IN_PROGRESS", "PAUSED": return rawValue
        default: return "ACTIVE"
        }
    }

    func reconcileExerciseSession(at date: Date = Date()) {
        guard let session = exerciseSession else { return }
        guard session.studentID == workspace.student.id else {
            exerciseSession = nil
            _ = localStore.clearExerciseSession()
            return
        }
        let reconciled = session.reconciled(at: date)
        guard reconciled != session else { return }
        guard localStore.saveExerciseSession(reconciled) else {
            errorMessage = BNBUL10n.text("运动已达到 2 小时，但自动结束状态未能安全保存。请保持 App 打开并重试。")
            return
        }
        exerciseSession = reconciled
    }

    func endExerciseSession(at date: Date = Date(), serverVersion: Int? = nil) -> Bool {
        guard let session = exerciseSession, session.status == .active else { return false }
        var ended = session.ended(at: date)
        if let serverVersion, serverVersion > 0 { ended.serverVersion = serverVersion }
        guard localStore.saveExerciseSession(ended) else {
            errorMessage = BNBUL10n.text("无法安全保存运动结束时间，请释放存储空间后重试。")
            return false
        }
        exerciseSession = ended
        errorMessage = nil
        return true
    }

    @discardableResult
    func pauseExerciseSession(at date: Date = Date(), serverVersion: Int? = nil) -> Bool {
        guard let session = exerciseSession, var updated = session.paused(at: date) else { return false }
        if let serverVersion, serverVersion > 0 { updated.serverVersion = serverVersion }
        guard localStore.saveExerciseSession(updated) else {
            errorMessage = BNBUL10n.text("无法安全保存暂停时间，请释放存储空间后重试。")
            return false
        }
        exerciseSession = updated
        errorMessage = nil
        return true
    }

    @discardableResult
    func resumeExerciseSession(at date: Date = Date(), serverVersion: Int? = nil) -> Bool {
        guard let session = exerciseSession, var updated = session.resumed(at: date) else { return false }
        if let serverVersion, serverVersion > 0 { updated.serverVersion = serverVersion }
        guard localStore.saveExerciseSession(updated) else {
            errorMessage = BNBUL10n.text("无法安全保存恢复时间，请释放存储空间后重试。")
            return false
        }
        exerciseSession = updated
        errorMessage = nil
        return true
    }

    func pauseExerciseSessionAuthoritatively(at date: Date = Date()) async -> Bool {
        guard isRemoteMode else { return pauseExerciseSession(at: date) }
        guard let session = exerciseSession, session.status == .active, !session.isPaused else { return false }
        let expectedSessionEpoch = sessionEpoch
        do {
            let remote = try await remoteRepo.controlExerciseSession(
                sessionId: session.id,
                action: "pause",
                clientObservedAt: date
            )
            guard expectedSessionEpoch == sessionEpoch, remote.id == session.id, remote.status == "PAUSED" else {
                return false
            }
            return pauseExerciseSession(at: date, serverVersion: remote.version)
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .session)
            return false
        }
    }

    func resumeExerciseSessionAuthoritatively(at date: Date = Date()) async -> Bool {
        guard isRemoteMode else { return resumeExerciseSession(at: date) }
        guard let session = exerciseSession, session.status == .active, session.isPaused else { return false }
        let expectedSessionEpoch = sessionEpoch
        do {
            let remote = try await remoteRepo.controlExerciseSession(
                sessionId: session.id,
                action: "resume",
                clientObservedAt: date
            )
            guard expectedSessionEpoch == sessionEpoch, remote.id == session.id, remote.status == "IN_PROGRESS" else {
                return false
            }
            return resumeExerciseSession(at: date, serverVersion: remote.version)
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .session)
            return false
        }
    }

    func endExerciseSessionAuthoritatively(at date: Date = Date()) async -> Bool {
        guard isRemoteMode else { return endExerciseSession(at: date) }
        guard let session = exerciseSession, session.status == .active else { return false }
        let expectedSessionEpoch = sessionEpoch
        do {
            let remote = try await remoteRepo.controlExerciseSession(
                sessionId: session.id,
                action: "finish",
                clientObservedAt: date
            )
            guard expectedSessionEpoch == sessionEpoch,
                  remote.id == session.id,
                  remote.status == "COMPLETED",
                  let endedAt = remote.endedAt.flatMap(Self.contractDate) else { return false }
            return endExerciseSession(at: endedAt, serverVersion: remote.version)
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .session)
            return false
        }
    }

    private static func contractDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func recordSportSelection(
        persistedValue: String?,
        localSession: ExerciseSession?
    ) -> (type: ExerciseSportType, customName: String?)? {
        if let localSession {
            return (localSession.sportType, localSession.customSportName)
        }
        guard let normalized = persistedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty else {
            return nil
        }
        if let known = ExerciseSportType(rawValue: normalized), known != .other {
            return (known, nil)
        }
        return (.other, normalized)
    }

    /// Business rule 5.6: an under-one-hour exercise ends without forming a
    /// record and without using the daily quota, but captured media drafts
    /// are retained for a later attempt on the same day.
    func finishUncreditedExerciseSession() {
        guard let session = exerciseSession, session.creditedHours() == 0 else { return }
        guard localStore.clearExerciseSession() else {
            errorMessage = BNBUL10n.text("无法清理本地运动会话，请稍后重试。")
            return
        }
        exerciseSession = nil
        errorMessage = nil
    }

    // MARK: - Exercise media drafts (business rules 5.5/6.4/7)

    /// Confirmed-retained evidence is scoped to the authoritative Session that
    /// produced it. Earlier under-one-hour attempts remain local orphans and
    /// cannot consume this Session's quota or enter its Record.
    var currentExerciseMediaDrafts: [ExerciseMediaDraft] {
        guard let sessionID = exerciseSession?.id else { return [] }
        return exerciseMediaDrafts.filter { $0.sessionID == sessionID }
    }

    /// Adds one formal 60-minute block through the Backend and installs only
    /// the subsequent authoritative projection.
    @discardableResult
    func addSixtyMinutesToExerciseSession() async -> Bool {
        guard !isAdvancingExerciseTestDuration,
              let localSession = exerciseSession,
              localSession.status == .active,
              let expectedVersion = localSession.serverVersion,
              expectedVersion > 0,
              localSession.studentID == workspace.student.id else {
            return false
        }
        let expectedSessionEpoch = sessionEpoch
        isAdvancingExerciseTestDuration = true
        defer { isAdvancingExerciseTestDuration = false }
        do {
            let remote = try await remoteRepo.addSixtyMinutesToExerciseSession(
                sessionId: localSession.id,
                expectedVersion: expectedVersion
            )
            guard expectedSessionEpoch == sessionEpoch,
                  isRemoteMode,
                  remote.id == localSession.id,
                  remote.studentId == workspace.student.id else {
                return false
            }
            let observedAt = Date()
            let updated = localSession.applyingAuthoritativeDuration(
                seconds: remote.actualDurationSeconds,
                observedAt: observedAt,
                remoteStatus: remote.status,
                remoteEndedAt: remote.endedAt.flatMap(Self.contractDate),
                serverVersion: remote.version
            )
            guard localStore.saveExerciseSession(updated) else {
                presentUserFacingError(RemoteMutationJournalError.writeFailed, context: .session)
                return false
            }
            exerciseSession = updated
            errorMessage = nil
            return true
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .session)
            return false
        }
    }

    var exercisePhotoDraftCount: Int {
        currentExerciseMediaDrafts.filter { $0.type == .image }.count
    }

    var exerciseVideoDraftCount: Int {
        currentExerciseMediaDrafts.filter { $0.type == .video }.count
    }

    var canAddExercisePhotoDraft: Bool {
        ExerciseMediaDraftRule.canAddPhoto(to: currentExerciseMediaDrafts)
    }

    /// Stores a camera photo as a local draft. Capture is only offered while a
    /// check-in lifecycle exists (active, paused or completed session).
    @discardableResult
    func addExercisePhotoDraft(
        imageData: Data,
        thumbnailData: Data?,
        at date: Date = Date()
    ) -> Bool {
        guard let session = exerciseSession else {
            errorMessage = BNBUL10n.text("请先开始运动，再拍摄打卡凭证。")
            return false
        }
        guard canAddExercisePhotoDraft else {
            errorMessage = BNBUL10n.text("最多保存 \(ExerciseMediaDraftRule.maximumPhotoDrafts) 张照片草稿。")
            return false
        }
        let draftID = UUID().uuidString
        let displayName = "exercise-photo-\(String(draftID.prefix(6))).jpg"
        var storedFileName: String?
        var inlineData: Data?
        if localStore.exerciseMediaDirectoryURL != nil {
            guard localStore.writeExerciseMediaFile(data: imageData, fileName: displayName) else {
                errorMessage = BNBUL10n.text("照片草稿无法安全保存，请检查设备存储空间。")
                return false
            }
            storedFileName = displayName
        } else {
            inlineData = imageData
        }
        let mediaDraft = ExerciseMediaDraft(
            id: draftID,
            studentID: session.studentID,
            sessionID: session.id,
            type: .image,
            fileName: displayName,
            storedFileName: storedFileName,
            inlineData: inlineData,
            thumbnailData: thumbnailData,
            byteCount: imageData.count,
            durationSeconds: nil,
            capturedAt: date
        )
        return appendExerciseMediaDraft(mediaDraft)
    }

    /// Adopts a camera video file into durable draft storage.
    @discardableResult
    func addExerciseVideoDraft(
        fileURL: URL,
        byteCount: Int,
        durationSeconds: Double?,
        thumbnailData: Data?,
        at date: Date = Date()
    ) -> Bool {
        guard let session = exerciseSession else {
            errorMessage = BNBUL10n.text("请先开始运动，再拍摄打卡凭证。")
            return false
        }
        let draftID = UUID().uuidString
        let displayName = "exercise-video-\(String(draftID.prefix(6))).mov"
        guard localStore.exerciseMediaDirectoryURL != nil,
              localStore.adoptExerciseMediaFile(from: fileURL, fileName: displayName) else {
            errorMessage = BNBUL10n.text("视频草稿无法安全保存，请检查设备存储空间。")
            return false
        }
        let mediaDraft = ExerciseMediaDraft(
            id: draftID,
            studentID: session.studentID,
            sessionID: session.id,
            type: .video,
            fileName: displayName,
            storedFileName: displayName,
            inlineData: nil,
            thumbnailData: thumbnailData,
            byteCount: byteCount,
            durationSeconds: durationSeconds,
            capturedAt: date
        )
        return appendExerciseMediaDraft(mediaDraft)
    }

#if DEBUG
    /// Test-only: registers an inline video draft without touching the file
    /// system, mirroring the photo inline path used by unit tests.
    @discardableResult
    func addInlineExerciseVideoDraftForTesting(
        videoData: Data,
        durationSeconds: Double?,
        at date: Date = Date()
    ) -> Bool {
        guard let session = exerciseSession else { return false }
        let draftID = UUID().uuidString
        let mediaDraft = ExerciseMediaDraft(
            id: draftID,
            studentID: session.studentID,
            sessionID: session.id,
            type: .video,
            fileName: "exercise-video-\(String(draftID.prefix(6))).mov",
            storedFileName: nil,
            inlineData: videoData,
            thumbnailData: nil,
            byteCount: videoData.count,
            durationSeconds: durationSeconds,
            capturedAt: date
        )
        return appendExerciseMediaDraft(mediaDraft)
    }
#endif

    /// Abandoning a session clears only the drafts it produced; drafts
    /// retained from an earlier under-one-hour attempt stay usable.
    private func clearExerciseMediaDrafts(sessionID: String) {
        let (removed, remaining) = exerciseMediaDrafts.partitioned { $0.sessionID == sessionID }
        guard !removed.isEmpty else { return }
        guard localStore.saveExerciseMediaDrafts(remaining) else {
            errorMessage = BNBUL10n.text("草稿列表无法安全更新，请稍后重试。")
            return
        }
        for draft in removed {
            if let storedFileName = draft.storedFileName {
                localStore.removeExerciseMediaFile(fileName: storedFileName)
            }
        }
        exerciseMediaDrafts = remaining
    }

    private func clearAllExerciseMediaDrafts() {
        _ = localStore.clearExerciseMediaDraftIndex()
        localStore.removeAllExerciseMediaFiles()
        exerciseMediaDrafts = []
    }

    /// Loads persisted drafts for the current student, dropping drafts that
    /// belong to another account or were captured on a previous Shanghai day
    /// (retention only covers same-day continuation, business rule 5.6).
    private func restoreExerciseMediaDrafts(for studentID: String, at date: Date = Date()) {
        let stored = localStore.readExerciseMediaDrafts().value ?? []
        guard !stored.isEmpty else {
            exerciseMediaDrafts = []
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let (kept, dropped) = stored.partitioned {
            $0.studentID == studentID && calendar.isDate($0.capturedAt, inSameDayAs: date)
        }
        if !dropped.isEmpty {
            _ = localStore.saveExerciseMediaDrafts(kept)
            for draft in dropped {
                if let storedFileName = draft.storedFileName {
                    localStore.removeExerciseMediaFile(fileName: storedFileName)
                }
            }
        }
        exerciseMediaDrafts = kept
    }

    private func appendExerciseMediaDraft(_ mediaDraft: ExerciseMediaDraft) -> Bool {
        var updated = exerciseMediaDrafts
        updated.append(mediaDraft)
        guard localStore.saveExerciseMediaDrafts(updated) else {
            if let storedFileName = mediaDraft.storedFileName {
                localStore.removeExerciseMediaFile(fileName: storedFileName)
            }
            errorMessage = BNBUL10n.text("草稿列表无法安全更新，请检查设备存储空间。")
            return false
        }
        exerciseMediaDrafts = updated
        errorMessage = nil
        return true
    }

    /// Materialises a draft into an uploadable proof attachment. Photo bytes
    /// are loaded into memory (≤8MB by rule); videos stay file-backed.
    func proofAttachment(from mediaDraft: ExerciseMediaDraft) -> ProofAttachment? {
        let fileURL = mediaDraft.storedFileName.flatMap { localStore.exerciseMediaFileURL(fileName: $0) }
        switch mediaDraft.type {
        case .image:
            let data = mediaDraft.inlineData ?? fileURL.flatMap { try? Data(contentsOf: $0) }
            guard let data else { return nil }
            return ProofAttachment(
                id: mediaDraft.id,
                type: .image,
                fileName: mediaDraft.fileName,
                byteCount: data.count,
                thumbnailData: mediaDraft.thumbnailData,
                uploadData: data,
                source: "运动拍摄",
                mimeType: "image/jpeg"
            )
        case .video:
            if let fileURL {
                return ProofAttachment(
                    id: mediaDraft.id,
                    type: .video,
                    fileName: mediaDraft.fileName,
                    byteCount: mediaDraft.byteCount,
                    durationSeconds: mediaDraft.durationSeconds,
                    thumbnailData: mediaDraft.thumbnailData,
                    sourceFileURL: fileURL,
                    source: "运动拍摄"
                )
            }
            guard let data = mediaDraft.inlineData else { return nil }
            return ProofAttachment(
                id: mediaDraft.id,
                type: .video,
                fileName: mediaDraft.fileName,
                byteCount: data.count,
                durationSeconds: mediaDraft.durationSeconds,
                thumbnailData: mediaDraft.thumbnailData,
                uploadData: data,
                source: "运动拍摄"
            )
        }
    }

    func discardExerciseSession() {
        guard localStore.clearExerciseSession() else {
            errorMessage = BNBUL10n.text("无法清理本地运动会话，请稍后重试。")
            return
        }
        // Business rule 5.6: abandoning clears the media captured during this
        // session, but keeps drafts retained from earlier attempts today.
        if let sessionID = exerciseSession?.id {
            clearExerciseMediaDrafts(sessionID: sessionID)
        }
        exerciseSession = nil
        errorMessage = nil
    }

    /// Remote mode must cancel the authoritative server session before any
    /// local timer or media is removed. If cancellation or local persistence
    /// fails, the local evidence stays available for an explicit retry.
    @discardableResult
    func discardExerciseSessionAuthoritatively() async -> Bool {
        guard isRemoteMode else {
            let previousSessionID = exerciseSession?.id
            discardExerciseSession()
            return previousSessionID == nil || exerciseSession == nil
        }
        guard let session = exerciseSession else { return false }
        let expectedSessionEpoch = sessionEpoch
        do {
            let remote = try await remoteRepo.cancelExerciseSession(
                sessionId: session.id,
                reason: "USER_ABANDONED_LOCAL_EXERCISE"
            )
            guard expectedSessionEpoch == sessionEpoch,
                  isRemoteMode,
                  remote.id == session.id,
                  remote.status == "CANCELLED" else {
                return false
            }
            guard localStore.clearExerciseSession() else {
                errorMessage = BNBUL10n.text("服务器已取消本次运动，但设备无法清理本地会话。已保留本地材料，请释放存储空间后重试。")
                return false
            }
            clearExerciseMediaDrafts(sessionID: session.id)
            exerciseSession = nil
            errorMessage = nil
            return true
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .session)
            return false
        }
    }

    /// The credit bucket a completed session's record belongs to. Course-related
    /// sessions must still reference a course that exists in the workspace.
    func submissionContext(for session: ExerciseSession) -> (creditType: CreditType, courseId: String?)? {
        switch session.category {
        case .general:
            return (.general, nil)
        case .courseRelated:
            guard let courseID = session.courseID,
                  workspace.courses.contains(where: { $0.id == courseID && $0.allowsCheckIn })
            else { return nil }
            return (.courseRelated, courseID)
        }
    }

    /// Fail-closed validation of a check-in submission under the new model:
    /// timer-derived 1h/2h only, course-related must reference a live course.
    func validatedSubmission(creditType: CreditType, courseId: String?, hours: Double) -> CheckInSubmission? {
        guard creditType != .organizationOffset else { return nil }
        guard hours.isFinite, hours == 1 || hours == 2 else { return nil }
        if creditType == .courseRelated {
            guard let courseId,
                  workspace.courses.contains(where: { $0.id == courseId && $0.allowsCheckIn })
            else { return nil }
            return CheckInSubmission(creditType: .courseRelated, courseId: courseId, hours: hours)
        }
        return CheckInSubmission(creditType: .general, courseId: nil, hours: hours)
    }

    /// Rebuilds a submission from a persisted retry journal entry.
    private func submission(fromRequestFields fields: [String: String]) -> CheckInSubmission? {
        guard let creditValue = fields["creditType"],
              let creditType = CreditType(contractValue: creditValue) else { return nil }
        let courseId = fields["courseId"].flatMap { $0.isEmpty ? nil : $0 }
        let hours = Double(fields["hours"] ?? "") ?? 0
        return validatedSubmission(creditType: creditType, courseId: courseId, hours: hours)
    }

    func markExerciseSessionSubmitted() {
        let submittedSessionID = exerciseSession?.id
        exerciseSession = nil
        _ = localStore.clearExerciseSession()
        // Release only the evidence that was bound to this successful Record.
        // Orphans from an earlier under-one-hour Session are not silently
        // attached to, or deleted by, a different Session.
        if let submittedSessionID {
            clearExerciseMediaDrafts(sessionID: submittedSessionID)
        }
        exerciseRecordResubmission = nil
    }

#if DEBUG
    func installCompletedExerciseSessionForUITesting(at date: Date = Date()) {
        discardExerciseSession()
        let startTime = date.addingTimeInterval(-ExerciseSession.oneHour)
        guard startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: "",
            at: startTime
        ) else { return }
        _ = endExerciseSession(at: date)
        installExerciseProofForUITesting(saveSelection: true, at: date)
    }

    func installActiveExerciseSessionForUITesting(at date: Date = Date()) {
        discardExerciseSession()
        guard startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: "",
            at: date.addingTimeInterval(-10 * 60)
        ) else { return }
        installExerciseProofForUITesting(saveSelection: false, at: date)
    }

    private func installExerciseProofForUITesting(saveSelection: Bool, at date: Date) {
        guard let imageData = ProofThumbnailRenderer.demoThumbnailData(type: .image, index: 1),
              addExercisePhotoDraft(imageData: imageData, thumbnailData: imageData, at: date),
              let mediaDraft = exerciseMediaDrafts.last else { return }
        guard saveSelection,
              let session = exerciseSession,
              let context = submissionContext(for: session),
              let attachment = proofAttachment(from: mediaDraft) else { return }
        saveDraft(
            creditType: context.creditType,
            courseId: context.courseId,
            hours: session.creditedHours(),
            note: "",
            sportType: session.sportType.rawValue,
            customSportType: session.customSportName ?? "",
            proofAttachments: [attachment]
        )
    }
#endif

    func hasSubmittedCheckInToday(at date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let exerciseSubmissionDates = localStore.readExerciseSubmissionDates().value ?? [:]
        let fractionalISOFormatter = ISO8601DateFormatter()
        fractionalISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardISOFormatter = ISO8601DateFormatter()
        return workspace.records.contains { record in
            guard record.creditType != .organizationOffset else { return false }
            if let exerciseStartDate = exerciseSubmissionDates[record.id] {
                return calendar.isDate(exerciseStartDate, inSameDayAs: date)
            }
            let value = record.submittedAt.trimmingCharacters(in: .whitespacesAndNewlines)
            if RecentTimestamp.isJustNow(value) { return true }

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
            $0.creditType != .organizationOffset
        }
    }

    var invalidRecordCount: Int {
        workspace.records.filter { $0.validity == .invalid }.count
    }

    var actionableExemptionCount: Int {
        workspace.exemptions.filter { $0.status == .pending }.count
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
        isRemoteMode ? BNBUL10n.text("校园体育服务") : BNBUL10n.text("演示数据")
    }

    var dataIntegritySummary: String {
        let courseIds = Set(workspace.courses.map(\.id))
        var issues: [String] = []

        if containsDuplicates(workspace.courses.map(\.id)) {
            issues.append("课程 ID 重复")
        }
        if containsDuplicates(workspace.records.map(\.id)) {
            issues.append("记录 ID 重复")
        }
        if containsDuplicates(workspace.exemptions.map(\.id)) {
            issues.append("免测申请 ID 重复")
        }

        let invalidRecordCount = workspace.records.filter { record in
            guard let courseId = record.courseId else { return false }
            return !courseIds.contains(courseId)
        }.count
        if invalidRecordCount > 0 {
            issues.append("记录课程引用 \(invalidRecordCount)")
        }

        if let draft,
           draft.creditType == .courseRelated,
           let draftCourseId = draft.courseId,
           !courseIds.contains(draftCourseId) {
            issues.append("草稿课程引用失效")
        }

        return issues.isEmpty ? "正常" : issues.joined(separator: " / ")
    }

#if DEBUG
    func demoLogin() {
        guard LocalDemoAccess.permitsMockWorkspace else {
            errorMessage = BNBUL10n.text("本地免登录测试入口未启用。")
            return
        }
        sessionEpoch &+= 1
        // Clear any stale secure credential locally. Review mode must never
        // restore, refresh, revoke, or otherwise contact a Backend session.
        _ = remoteRepo.clearSession()
        mutationGate.removeAll()
        errorMessage = nil
        exerciseTestToolCapabilities = []
        let journalCleared = clearAllPendingRemoteMutations()
        // Never reuse a cached remote student's workspace in review mode.
        let localWorkspace = repository.loadWorkspace()
        workspace = localWorkspace
        restoreExerciseSession(for: workspace.student.id)
        restoreExerciseMediaDrafts(for: workspace.student.id)
        let localDraft = localStore.readDraft().value
        if let localDraft, localDraft.creditType != .organizationOffset {
            draft = localDraft
        } else {
            draft = nil
        }
        isRemoteMode = false
        isLocalReviewMode = true
        remoteCacheStudentID = nil
        clearPersistedRemoteAttemptFromDraft()
        if !journalCleared {
            presentUserFacingError(RemoteMutationJournalError.writeFailed, context: .record)
        }
        isAuthenticated = true
    }
#endif

    /// Test-only state setup for URLProtocol-backed contract tests. This does
    /// not install credentials, load fixtures, or report a business mutation as
    /// successful; tests still exercise RemoteStudentRepository over the real
    /// 2.0.13 request paths and must seed an AuthSession in secure storage.
    func installRemoteContractFixtureForTesting() {
        sessionEpoch &+= 1
        mutationGate.removeAll()
        errorMessage = nil
        exerciseTestToolCapabilities = []
        isRemoteMode = true
        isLocalReviewMode = false
        remoteCacheStudentID = workspace.student.id
        restoreExerciseSession(for: workspace.student.id)
        restoreExerciseMediaDrafts(for: workspace.student.id)
        sanitizePersistedRemoteMutations(for: workspace.student.id)
        isAuthenticated = true
    }

    func logout() async {
        sessionEpoch &+= 1
        let remoteStudentID = remoteCacheStudentID
        let wasRemoteMode = isRemoteMode
        let wasLocalReviewMode = isLocalReviewMode
        isAuthenticated = false
        isRemoteMode = false
        isLocalReviewMode = false
        exerciseTestToolCapabilities = []
        remoteCacheStudentID = nil
        isLoading = false
        isLoadingExemptions = false
        isLoadingFeedback = false
        isSubmittingFeedback = false
        feedbackTickets = []
        feedbackNotice = nil
        isRefreshingWorkspace = false
        studentSignInChallengeID = nil
        studentSignInChallengeAccount = nil
        studentSignInChallengeExpiresAt = nil
        firstEmailBindingChallengeID = nil
        firstEmailBindingExpectedVersion = nil
        mutationGate.removeAll()
        let journalCleared = clearAllPendingRemoteMutations()
        checkInSubmissionPhase = .idle
        canSafelyRetryCheckIn = false
        draft = nil
        exerciseSession = nil
        existingRemoteExerciseSession = nil
        exerciseRecordResubmission = nil
        _ = localStore.clearExerciseSession()
        _ = localStore.clearExerciseSubmissionDates()
        clearAllExerciseMediaDrafts()

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
        let securelyCleared: Bool
        if wasLocalReviewMode {
            securelyCleared = remoteRepo.clearSession()
        } else {
            securelyCleared = await remoteRepo.logout()
        }
        if !securelyCleared {
            errorMessage = BNBUL10n.text("设备已退出；服务端会话撤销或安全存储清理未完全确认，请联网后重新登录。")
        } else if !journalCleared {
            errorMessage = BNBUL10n.text("已退出，但设备未能清理待提交操作。请释放存储空间后重启 App。")
        } else {
            errorMessage = nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func activateRemoteStudent(
        _ authenticatedStudent: StudentProfile,
        expectedEpoch: UInt64
    ) async throws {
        guard expectedEpoch == sessionEpoch else { throw RepositoryError.sessionChanged }
        isRemoteMode = true
        isLocalReviewMode = false
        exerciseTestToolCapabilities = []
        remoteCacheStudentID = authenticatedStudent.id
        restoreExerciseSession(for: authenticatedStudent.id)
        restoreExerciseMediaDrafts(for: authenticatedStudent.id)
        sanitizePersistedRemoteMutations(for: authenticatedStudent.id)
        do {
            let remoteWorkspace = try await remoteRepo.loadWorkspace()
            guard expectedEpoch == sessionEpoch else { throw RepositoryError.sessionChanged }
            applyRemoteWorkspace(remoteWorkspace, event: "已从服务器同步工作台")
        } catch {
            guard expectedEpoch == sessionEpoch else { throw RepositoryError.sessionChanged }
            if let cachedWorkspace = localStore.readRemoteWorkspace(
                baseURL: StudentServerConfig.resolvedBaseURL(),
                studentID: authenticatedStudent.id
            ).value,
               !isUnauthorized(error) {
                applyRemoteWorkspace(cachedWorkspace, event: "服务器暂不可用，已读取最近同步数据")
                errorMessage = BNBUL10n.text("服务器暂时不可用，当前显示最近同步数据。下拉或重新进入后可再次刷新。")
            } else {
                throw error
            }
        }
        try await refreshExerciseTestToolCapabilities(expectedEpoch: expectedEpoch)
    }

    private func refreshExerciseTestToolCapabilities(expectedEpoch: UInt64) async throws {
        guard StudentTestToolsConfig.isEnabled else {
            if expectedEpoch == sessionEpoch { exerciseTestToolCapabilities = [] }
            return
        }
        do {
            let capabilities = try await remoteRepo.exerciseTestToolCapabilities()
            guard expectedEpoch == sessionEpoch, isRemoteMode else {
                throw RepositoryError.sessionChanged
            }
            exerciseTestToolCapabilities = capabilities
        } catch {
            guard expectedEpoch == sessionEpoch else { throw RepositoryError.sessionChanged }
            exerciseTestToolCapabilities = []
            if let repositoryError = error as? RepositoryError,
               repositoryError.isTerminalAuthenticationFailure {
                throw error
            }
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
            try await refreshExerciseTestToolCapabilities(expectedEpoch: refreshEpoch)
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: refreshEpoch)
        }
    }

    /// Refreshes only the exemption applications. A failed request deliberately
    /// leaves the cached list intact so the centre never turns a transport error
    /// into a misleading empty state.
    func refreshRemoteExemptions() async {
        guard isRemoteMode, !isLoadingExemptions else { return }
        let refreshEpoch = sessionEpoch
        isLoadingExemptions = true
        errorMessage = nil
        defer {
            if refreshEpoch == sessionEpoch {
                isLoadingExemptions = false
            }
        }
        do {
            let exemptions = try await remoteRepo.listExemptions(
                fallback: workspace.exemptions
            )
            guard refreshEpoch == sessionEpoch, isRemoteMode else { return }
            workspace.exemptions = exemptions
            saveWorkspace(event: "已从服务器刷新免测申请")
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: refreshEpoch)
        }
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
        creditType: CreditType,
        courseId: String?,
        hours: Double,
        note: String,
        sportType: String? = nil,
        proofAttachments: [ProofAttachment],
        exerciseSession: ExerciseSession? = nil,
        recoverySessionID: String? = nil,
        recoveryEnrollmentID: String? = nil,
        resubmissionRecordID: String? = nil
    ) async -> Bool {
        guard !isSubmittingCheckIn else { return false }
        guard allowWrite() else { return false }
        canSafelyRetryCheckIn = false
        checkInSubmissionPhase = .submitting
        defer { checkInSubmissionPhase = .idle }

        if let inputMessage = CheckInInputRule.validationMessage(note: note, for: creditType) {
            errorMessage = inputMessage
            return false
        }

        guard let submission = validatedSubmission(creditType: creditType, courseId: courseId, hours: hours) else {
            errorMessage = BNBUL10n.text("本次运动数据不完整，无法提交。请结束运动后重试。")
            return false
        }

        let retainedSessionID = recoverySessionID ?? exerciseSession?.id ?? self.exerciseSession?.id
        let retainedDrafts = retainedSessionID.map { sessionID in
            exerciseMediaDrafts.filter { $0.sessionID == sessionID }
        } ?? []
        let materializedRetainedProofs = retainedDrafts.compactMap { proofAttachment(from: $0) }
        guard retainedDrafts.isEmpty || materializedRetainedProofs.count == retainedDrafts.count else {
            presentUserFacingError(
                RepositoryError.serverError(
                    statusCode: 409,
                    code: "MEDIA_NOT_AVAILABLE",
                    message: "Retained evidence is not readable on this device."
                ),
                context: .media
            )
            return false
        }
        // The caller cannot submit a selected subset. Whenever this device has
        // retained Session evidence, that complete ordered collection is the
        // only source of truth for the Record. Persisted journal recovery may
        // supply its protected sourceProofs when no local draft pool remains.
        let effectiveProofAttachments = retainedDrafts.isEmpty
            ? proofAttachments
            : materializedRetainedProofs

        if isRemoteMode {
            let submissionEpoch = sessionEpoch
            return await submitCheckInRemote(
                submission: submission,
                note: note,
                sportType: sportType,
                proofAttachments: effectiveProofAttachments,
                exerciseSession: exerciseSession,
                recoverySessionID: recoverySessionID,
                recoveryEnrollmentID: recoveryEnrollmentID,
                resubmissionRecordID: resubmissionRecordID
                    ?? exerciseRecordResubmission?.previousRecordId,
                expectedSessionEpoch: submissionEpoch
            )
        }
        guard !hasSubmittedCheckInToday() else {
            errorMessage = BNBUL10n.text("今日已打卡，每天只能提交一次。")
            return false
        }
        guard !effectiveProofAttachments.isEmpty,
              ProofUploadRule.accepts(effectiveProofAttachments) else { return false }
        guard effectiveProofAttachments.allSatisfy(\.isValidForUpload) else { return false }
        let photoCount = effectiveProofAttachments.filter { $0.type == .image }.count
        let videoCount = effectiveProofAttachments.filter { $0.type == .video }.count
        let record = CheckInRecord(
            id: UUID().uuidString,
            courseId: submission.courseId,
            taskTitle: submission.title,
            creditType: submission.creditType,
            hours: submission.hours,
            submittedAt: RecentTimestamp.justNow,
            validity: .valid,
            proofSummary: proofSummary(proofAttachments: effectiveProofAttachments),
            proofPhotoCount: photoCount,
            proofVideoCount: videoCount,
            proofFiles: effectiveProofAttachments,
            note: note.isEmpty ? "学生未填写补充说明。" : note,
            sportType: sportType
        )
        workspace.records.insert(record, at: 0)
        if let exerciseSession {
            saveExerciseSubmissionDate(exerciseSession.startTime, recordID: record.id)
        }
        creditSubmittedExercise(hours: submission.hours, creditType: submission.creditType)
        workspace.notices.insert(
            StudentNotice(
                id: UUID().uuidString,
                title: BNBUL10n.text("打卡已提交"),
                message: BNBUL10n.text("\(submission.title) 已成功提交，可在打卡记录中查看。"),
                time: RecentTimestamp.justNow,
                category: .system,
                isUnread: true
            ),
            at: 0
        )
        enqueueSyncOperation(
            .submitRecord,
            title: "提交打卡记录",
            detail: "\(submission.title) · \(submission.hours.hourText) · \(effectiveProofAttachments.count) 个凭证"
        )
        clearDraft()
        saveWorkspace(event: "打卡提交已保存")
        return true
    }

    @discardableResult
    func submitExemption(
        item: ExemptionItem,
        reason: String,
        detail: String,
        organization: String = "",
        proofAttachments: [ProofAttachment]
    ) async -> Bool {
        guard !isSubmittingExemption else {
            errorMessage = BNBUL10n.text("免测申请正在提交，请勿重复操作。")
            return false
        }
        guard allowWrite() else { return false }
        isSubmittingExemption = true
        defer { isSubmittingExemption = false }

        let mutationKey = "submit-exemption"
        guard beginMutation(mutationKey) else {
            errorMessage = BNBUL10n.text("免测申请正在提交，请勿重复操作。")
            return false
        }
        defer { endMutation(mutationKey) }

        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inputMessage = ExemptionInputRule.validationMessage(reason: normalizedReason, detail: normalizedDetail) {
            errorMessage = inputMessage
            return false
        }
        let normalizedOrganization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        // A check-in exemption is granted through a named team or club, so the
        // teacher cannot review it without one.
        if item.isCheckInExemption, normalizedOrganization.isEmpty {
            errorMessage = BNBUL10n.text("请填写校队或社团名称")
            return false
        }
        guard isRemoteMode else {
            errorMessage = exemptionCopy(
                "演示账户仅供界面预览，不能提交免测申请。",
                "The demo account is for interface preview only and cannot submit exemption requests."
            )
            return false
        }
        guard ExemptionProofRule.accepts(proofAttachments) else {
            errorMessage = exemptionProofError
            return false
        }
        guard acceptsExemptionProofs(proofAttachments) ||
                acceptsPersistedExemptionProofs(proofAttachments) else {
            errorMessage = exemptionProofError
            return false
        }

        return await submitExemptionRemote(
            item: item,
            reason: normalizedReason,
            detail: normalizedDetail,
            organization: normalizedOrganization,
            proofAttachments: proofAttachments,
            expectedSessionEpoch: sessionEpoch
        )
    }

    @discardableResult
    func submitExemptionSupplement(
        for application: ExemptionApplication,
        reason: String,
        detail: String,
        proofAttachments: [ProofAttachment],
        allowPreparedRecovery: Bool = false
    ) async -> Bool {
        guard !isSubmittingExemption else {
            errorMessage = BNBUL10n.text("免测补充材料正在提交，请勿重复操作。")
            return false
        }
        guard allowWrite() else { return false }
        isSubmittingExemption = true
        defer { isSubmittingExemption = false }

        let mutationKey = "supplement-exemption:\(application.id)"
        guard beginMutation(mutationKey) else {
            errorMessage = BNBUL10n.text("免测补充材料正在提交，请勿重复操作。")
            return false
        }
        defer { endMutation(mutationKey) }

        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inputMessage = ExemptionInputRule.validationMessage(reason: normalizedReason, detail: normalizedDetail) {
            errorMessage = inputMessage
            return false
        }
        let scope = "exemption:supplement:\(application.id)"
        let hasPreparedRecovery = allowPreparedRecovery &&
            pendingRemoteMutations[scope]?.phase == .finalMutationPrepared &&
            pendingRemoteMutations[scope]?.preparedExpectedVersion != nil &&
            pendingRemoteMutations[scope]?.preparedMediaIDs != nil
        guard application.status.canSupplement || hasPreparedRecovery else {
            return false
        }
        guard isRemoteMode else {
            errorMessage = exemptionCopy(
                "演示账户仅供界面预览，不能补交免测材料。",
                "The demo account is for interface preview only and cannot submit exemption supplements."
            )
            return false
        }
        guard acceptsExemptionProofs(proofAttachments) ||
                acceptsPersistedExemptionProofs(proofAttachments) else {
            errorMessage = exemptionProofError
            return false
        }

        return await supplementExemptionRemote(
            application: application,
            reason: normalizedReason,
            detail: normalizedDetail,
            proofAttachments: proofAttachments,
            allowPreparedRecovery: hasPreparedRecovery,
            expectedSessionEpoch: sessionEpoch
        )
    }

    func saveDraft(
        creditType: CreditType,
        courseId: String?,
        hours: Double,
        note: String,
        sportType: String? = nil,
        customSportType: String? = nil,
        proofAttachments: [ProofAttachment]
    ) {
        guard let submission = validatedSubmission(creditType: creditType, courseId: courseId, hours: hours) else {
            clearDraft()
            return
        }
        let resolvedSportType = sportType == "other"
            ? customSportType?.trimmingCharacters(in: .whitespacesAndNewlines)
            : sportType
        let existingAttempt = draft?.pendingRemoteMutation
        let fingerprint = checkInFingerprint(
            submission: submission,
            note: note,
            sportType: resolvedSportType,
            authoritativeSessionID: existingAttempt?.authoritativeSessionID ?? (isRemoteMode ? exerciseSession?.id : nil),
            authoritativeEnrollmentID: existingAttempt?.authoritativeEnrollmentID,
            previousRecordID: existingAttempt?.requestFields["previousRecordId"]
                ?? exerciseRecordResubmission?.previousRecordId,
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
            creditType: submission.creditType,
            courseId: submission.courseId,
            hours: submission.hours,
            note: note,
            proofAttachments: proofAttachments,
            updatedAt: RecentTimestamp.justNow,
            sportType: sportType,
            customSportType: customSportType,
            pendingRemoteMutation: retainedAttempt
        )
        self.draft = draft
        saveDraft(draft, event: "打卡草稿已保存")
    }

    func canResumePendingCheckIn(
        creditType: CreditType,
        courseId: String?,
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
              attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }),
              let submission = validatedSubmission(creditType: creditType, courseId: courseId, hours: hours) else {
            return false
        }
        let fingerprint = checkInFingerprint(
            submission: submission,
            note: note,
            sportType: sportType,
            authoritativeSessionID: attempt.authoritativeSessionID,
            authoritativeEnrollmentID: attempt.authoritativeEnrollmentID,
            previousRecordID: attempt.requestFields["previousRecordId"].flatMap {
                $0.isEmpty ? nil : $0
            },
            proofAttachments: proofAttachments
        )
        return attempt.matches(
            scope: "sport-record:create",
            fingerprint: fingerprint,
            serverIdentity: remoteMutationServerIdentity,
            studentID: studentID
        )
    }

    func clearDraft() {
        removePendingRemoteMutation(scope: "sport-record:create")
        draft = nil
        localStore.clearDraft()
        storeHealth.draftReadStatus = .missing
        storeHealth.lastWriteStatus = .cleared
        storeHealth.lastEvent = "打卡草稿已清理"
    }

    func discardExemptionCreationAttempt() {
        let creationScopes = pendingRemoteMutations.keys.filter { $0.hasPrefix("exemption:create:") }
        creationScopes.forEach { discardPendingRemoteMutation(scope: $0) }
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
            guard let submission = submission(fromRequestFields: attempt.requestFields),
                  let authoritativeSessionID = attempt.authoritativeSessionID,
                  let authoritativeEnrollmentID = attempt.authoritativeEnrollmentID,
                  attempt.requestFields["authoritativeSessionId"] == authoritativeSessionID,
                  attempt.requestFields["authoritativeEnrollmentId"] == authoritativeEnrollmentID else {
                return false
            }
            // Backend organization timezone/businessDate and the persisted
            // idempotency key decide whether replay is legal. Device-local
            // calendar state must not pre-empt that decision.
            return attempt.requestFields["creditType"] == submission.creditType.apiValue
        }
        if scope.hasPrefix("exemption:create:") {
            guard acceptsPersistedExemptionProofs(attempt.sourceProofs) else { return false }
            guard let type = attempt.requestFields["type"] else { return false }
            return ExemptionItem.allCases.contains(where: { $0.apiValue == type })
        }
        if scope.hasPrefix("exemption:supplement:") {
            guard acceptsPersistedExemptionProofs(attempt.sourceProofs) else { return false }
            guard let applicationID = attempt.requestFields["exemptionId"] else { return false }
            guard let application = workspace.exemptions.first(where: { $0.id == applicationID }) else {
                return false
            }
            return application.status.canSupplement ||
                (attempt.phase == .finalMutationPrepared &&
                    attempt.preparedExpectedVersion != nil &&
                    attempt.preparedMediaIDs != nil)
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
            errorMessage = BNBUL10n.text("该待重试操作还缺少原始文件或目标已失效。请核对最新记录，或明确放弃后重新提交。")
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
            guard let submission = submission(fromRequestFields: fields),
                  let authoritativeSessionID = attempt.authoritativeSessionID,
                  let authoritativeEnrollmentID = attempt.authoritativeEnrollmentID else {
                return false
            }
            let sportType = fields["sportType"].flatMap { $0.isEmpty ? nil : $0 }
            return await submitCheckIn(
                creditType: submission.creditType,
                courseId: submission.courseId,
                hours: submission.hours,
                note: fields["description"] ?? "",
                sportType: sportType,
                proofAttachments: attempt.sourceProofs,
                recoverySessionID: authoritativeSessionID,
                recoveryEnrollmentID: authoritativeEnrollmentID,
                resubmissionRecordID: fields["previousRecordId"].flatMap {
                    $0.isEmpty ? nil : $0
                }
            )
        }
        if scope.hasPrefix("exemption:create:"),
           let type = fields["type"],
           let item = ExemptionItem.allCases.first(where: { $0.apiValue == type }) {
            return await submitExemption(
                item: item,
                reason: fields["reason"] ?? "",
                detail: fields["detail"] ?? "",
                organization: fields["organization"] ?? "",
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
                proofAttachments: attempt.sourceProofs,
                allowPreparedRecovery: true
            )
        }
        errorMessage = BNBUL10n.text("无法识别这项待重试操作；请明确放弃后重新提交。")
        return false
    }

    func pendingExemptionFormRecovery(applicationID: String?) -> PendingExemptionFormRecovery? {
        let scope: String
        if let applicationID {
            scope = "exemption:supplement:\(applicationID)"
        } else {
            let creationScopes = pendingRemoteMutations.keys.filter {
                $0.hasPrefix("exemption:create:")
            }
            guard creationScopes.count == 1, let onlyScope = creationScopes.first else {
                return nil
            }
            scope = onlyScope
        }
        let existingApplication = applicationID.flatMap { id in
            workspace.exemptions.first(where: { $0.id == id })
        }
        guard isRemoteMode,
              let studentID = remoteCacheStudentID,
              let attempt = pendingRemoteMutations[scope],
              acceptsPersistedExemptionProofs(attempt.sourceProofs),
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
            organization: attempt.requestFields["organization"]
                ?? existingApplication?.organization
                ?? "",
            sourceProofs: attempt.sourceProofs,
            uploadedProofCount: attempt.uploadedProofs.count
        )
    }

    func canResumePendingExemption(
        applicationID: String?,
        item: ExemptionItem,
        reason: String,
        detail: String,
        organization: String = "",
        proofAttachments: [ProofAttachment]
    ) -> Bool {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = applicationID.map { "exemption:supplement:\($0)" }
            ?? Self.exemptionCreationScope(for: item)
        var fields = [
            "reason": normalizedReason,
            "detail": normalizedDetail,
            "combinedReason": ExemptionInputRule.combinedReason(
                reason: normalizedReason,
                detail: normalizedDetail
            ),
            "organization": organization.trimmingCharacters(in: .whitespacesAndNewlines)
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
              acceptsPersistedExemptionProofs(proofAttachments),
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
            errorMessage = BNBUL10n.text("请连接校园体育服务器后使用成绩换算。")
            return nil
        }
        guard let gender = workspace.student.gender.apiValue else {
            errorMessage = BNBUL10n.text("学生性别尚未同步，暂时无法匹配耐力跑项目。")
            return nil
        }
        guard let gradeLevel = workspace.student.gradeLevel, !gradeLevel.isEmpty else {
            errorMessage = BNBUL10n.text("学生年级尚未同步，暂时无法匹配评分组别。")
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
        submission: CheckInSubmission,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment],
        exerciseSession: ExerciseSession?,
        recoverySessionID: String?,
        recoveryEnrollmentID: String?,
        resubmissionRecordID: String?,
        expectedSessionEpoch: UInt64
    ) async -> Bool {
        guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
        let scope = "sport-record:create"
        guard !proofAttachments.isEmpty, ProofUploadRule.accepts(proofAttachments) else { return false }
        // A journal recovery target wins over any newly restored/current local
        // session. This prevents an old record attempt from borrowing a newer
        // authoritative session after relaunch.
        guard let authoritativeSessionID = recoverySessionID ?? exerciseSession?.id else {
            errorMessage = BNBUL10n.text("缺少服务端运动会话，不能提交打卡。")
            return false
        }
        let submittedNote = note.isEmpty ? "学生未填写补充说明。" : note
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let authoritativeSession: ContractExerciseSession
        do {
            authoritativeSession = try await remoteRepo.getExerciseSession(sessionId: authoritativeSessionID)
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .record)
            return false
        }
        guard expectedSessionEpoch == sessionEpoch,
              isRemoteMode,
              authoritativeSession.id == authoritativeSessionID,
              authoritativeSession.status == "COMPLETED" else {
            errorMessage = BNBUL10n.text("服务端运动会话尚未完成或已失效，不能恢复本次提交。")
            return false
        }
        if let recoveryEnrollmentID,
           authoritativeSession.enrollmentId != recoveryEnrollmentID {
            errorMessage = BNBUL10n.text("服务端运动会话不属于原待提交 Enrollment，已停止重试。")
            return false
        }
        let matchingLocalSession = exerciseSession?.id == authoritativeSessionID ? exerciseSession : nil
        guard let authoritativeStart = Self.contractDate(authoritativeSession.startedAt),
              let recordSport = Self.recordSportSelection(
                persistedValue: sportType,
                localSession: matchingLocalSession
              ) else {
            errorMessage = BNBUL10n.text("待提交运动的服务端时间或运动类型无效。")
            return false
        }
        let fingerprint = checkInFingerprint(
            submission: submission,
            note: note,
            sportType: sportType,
            authoritativeSessionID: authoritativeSession.id,
            authoritativeEnrollmentID: authoritativeSession.enrollmentId,
            previousRecordID: resubmissionRecordID,
            proofAttachments: proofAttachments
        )
        var attempt = resolveCheckInAttempt(
            scope: scope,
            fingerprint: fingerprint,
            submission: submission,
            note: note,
            sportType: sportType,
            authoritativeSessionID: authoritativeSession.id,
            authoritativeEnrollmentID: authoritativeSession.enrollmentId,
            previousRecordID: resubmissionRecordID,
            proofAttachments: proofAttachments
        )
        guard !attempt.isServerConfirmed else {
            retainServerConfirmedAttemptInMemory(attempt)
            errorMessage = serverConfirmedCleanupWarning
            return false
        }
        do {
            try persistCheckInAttempt(
                attempt,
                submission: submission,
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
                    submission: submission,
                    note: note,
                    sportType: sportType,
                    authoritativeSessionID: authoritativeSession.id,
                    authoritativeEnrollmentID: authoritativeSession.enrollmentId,
                    previousRecordID: resubmissionRecordID,
                    proofAttachments: proofAttachments
                )
                try persistCheckInAttempt(
                    attempt,
                    submission: submission,
                    note: note,
                    sportType: sportType,
                    proofAttachments: proofAttachments
                )
            }
            guard sourceProofs.dropFirst(attempt.uploadedProofs.count).allSatisfy(\.isValidForUpload) else {
                errorMessage = BNBUL10n.text("尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。")
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
                let uploaded = try await remoteRepo.uploadExerciseEvidence(
                    attachment: attachment,
                    sessionId: authoritativeSession.id,
                    idempotencyKey: "\(attempt.idempotencyKey).proof-\(index)"
                )
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                attempt.uploadedProofs.append(uploaded)
                try persistCheckInAttempt(
                    attempt,
                    submission: submission,
                    note: note,
                    sportType: sportType,
                    proofAttachments: proofAttachments
                )
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
                submission: submission,
                note: note,
                sportType: sportType,
                proofAttachments: proofAttachments
            )
            checkInSubmissionPhase = .submitting
            var submittedRecord = try await remoteRepo.submitExerciseRecord(
                sessionId: authoritativeSession.id,
                previousRecordId: resubmissionRecordID,
                creditType: submission.creditType,
                sportType: recordSport.type,
                customSportName: recordSport.customName,
                description: submittedNote,
                mediaIds: attempt.uploadedProofs.compactMap(\.cosKey),
                clientRequestId: attempt.idempotencyKey,
                idempotencyKey: attempt.idempotencyKey
            )
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
            saveExerciseSubmissionDate(authoritativeStart, recordID: submittedRecord.id)

            attempt.markServerConfirmed(resultID: submittedRecord.id)
            var localJournalWarning: String?
            do {
                try persistCheckInAttempt(
                    attempt,
                    submission: submission,
                    note: note,
                    sportType: sportType,
                    proofAttachments: proofAttachments
                )
                try clearPersistedRemoteAttemptFromDraftStrict()
            } catch {
                retainServerConfirmedAttemptInMemory(attempt)
                localJournalWarning = BNBUL10n.text("打卡已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。")
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
                    await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .record)
                    return true
                }
                refreshWarning = combinedWarning(
                    refreshWarning,
                    BNBUL10n.text("记录已提交，但最新列表暂未同步。请稍后下拉刷新，不要重复提交。")
                )
            }

            if !refreshedSubmittedRecord {
                // Preserve the concrete record returned by Backend while
                // deriving progress from the same VALID record facts used by
                // every client. The record returned by this mutation belongs
                // to the current Enrollment and is VALID on submission.
                includeValidRemoteRecordInProgress(submittedRecord)
                upsertCheckInRecord(submittedRecord)
                enqueueSyncOperation(
                    .submitRecord,
                    title: BNBUL10n.text("打卡记录等待服务器列表同步"),
                    detail: BNBUL10n.text("服务器已返回有效记录，学时进度已按该记录更新。"),
                    status: .queued
                )
            }
            workspace.notices.insert(
                StudentNotice(
                    id: UUID().uuidString,
                    title: BNBUL10n.text("打卡已提交"),
                    message: BNBUL10n.text("\(submission.title) 已成功提交，可在打卡记录中查看。"),
                    time: RecentTimestamp.justNow,
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
            exerciseRecordResubmission = nil
            return true
        } catch {
            guard expectedSessionEpoch == sessionEpoch else { return false }
            if error is RemoteMutationJournalError {
                canSafelyRetryCheckIn = pendingRemoteMutations[scope] != nil
                presentUserFacingError(error, context: .record)
                return false
            }
            let shouldRetainAttempt = RemoteMutationJournalPolicy.shouldRetain(after: error)
            var journalError: Error?
            do {
                if shouldRetainAttempt {
                    try persistCheckInAttempt(
                        attempt,
                        submission: submission,
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
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .record)
            if let journalError, !isUnauthorized(error) {
                presentUserFacingError(journalError, context: .record)
            }
            return false
        }
    }

    private func submitExemptionRemote(
        item: ExemptionItem,
        reason: String,
        detail: String,
        organization: String = "",
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
        guard acceptsExemptionProofs(proofAttachments) ||
                acceptsPersistedExemptionProofs(proofAttachments) else {
            errorMessage = exemptionProofError
            return false
        }

        let normalizedOrganization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        // Team and club applications go to their own collection, so they get
        // their own idempotency scope; retrying one must not match the other.
        let scope = Self.exemptionCreationScope(for: item)
        let requestFields = [
            "type": item.apiValue,
            "reason": normalizedReason,
            "detail": normalizedDetail,
            "combinedReason": ExemptionInputRule.combinedReason(reason: normalizedReason, detail: normalizedDetail),
            "organization": normalizedOrganization
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
            let enrollmentId = try await remoteRepo.resolveActiveEnrollmentID(
                preferredClassSectionId: currentExerciseCourse?.id
            )
            let applicationId: String
            let draftExpectedVersion: Int
            if let targetResourceID = attempt.targetResourceID,
               let expectedVersion = attempt.preparedExpectedVersion {
                applicationId = targetResourceID
                draftExpectedVersion = expectedVersion
            } else {
                let draft = try await remoteRepo.createExemptionDraft(
                    enrollmentId: enrollmentId,
                    item: item,
                    reason: normalizedReason,
                    detail: normalizedDetail,
                    organization: normalizedOrganization,
                    idempotencyKey: attempt.idempotencyKey
                )
                guard draft.enrollmentId == enrollmentId else {
                    throw RepositoryError.apiError("服务器返回的免测草稿不属于当前 Enrollment。")
                }
                applicationId = draft.applicationId
                draftExpectedVersion = draft.expectedVersion
                attempt.bindTargetResource(
                    id: draft.applicationId,
                    expectedVersion: draft.expectedVersion
                )
                try storePendingRemoteMutation(attempt)
            }
            if attempt.uploadedProofs.count > proofAttachments.count ||
                !attempt.uploadedProofs.allSatisfy({ $0.cosKey?.isEmpty == false }) {
                if attempt.targetResourceID != nil {
                    throw RepositoryError.apiError("免测草稿已有服务端目标，但本地上传记录不完整；已停止创建第二份申请。")
                }
                attempt = replacePersistentAttempt(
                    scope: scope,
                    fingerprint: fingerprint,
                    requestFields: requestFields,
                    sourceProofs: proofAttachments
                )
                try storePendingRemoteMutation(attempt)
            }
            guard proofAttachments.dropFirst(attempt.uploadedProofs.count).allSatisfy(\.isValidForUpload) else {
                errorMessage = BNBUL10n.text("尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。")
                return false
            }
            for index in attempt.uploadedProofs.count..<proofAttachments.count {
                let attachment = proofAttachments[index]
                let uploaded = try await remoteRepo.uploadExemptionEvidence(
                    attachment: attachment,
                    applicationId: applicationId,
                    enrollmentId: enrollmentId,
                    idempotencyKey: "\(attempt.idempotencyKey).proof-\(index)"
                )
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                attempt.uploadedProofs.append(uploaded)
                try storePendingRemoteMutation(attempt)
            }

            let preparedMediaIDs = attempt.uploadedProofs.compactMap(\.cosKey)
            attempt.markFinalMutationPrepared(
                expectedVersion: draftExpectedVersion,
                mediaIDs: preparedMediaIDs
            )
            try storePendingRemoteMutation(attempt)
            let application = try await remoteRepo.updateAndSubmitCreatedExemption(
                applicationId: applicationId,
                item: item,
                reason: normalizedReason,
                detail: normalizedDetail,
                organization: normalizedOrganization,
                preparedExpectedVersion: draftExpectedVersion,
                mediaIds: preparedMediaIDs,
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
                localJournalWarning = BNBUL10n.text("免测申请已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。")
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
                    title: BNBUL10n.text("免测申请已提交"),
                    message: BNBUL10n.text("\(item.rawValue) 已进入审核流程。"),
                    time: RecentTimestamp.justNow,
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
                presentUserFacingError(error, context: .exemption)
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
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .exemption)
            if let journalError, !isUnauthorized(error) {
                presentUserFacingError(journalError, context: .exemption)
            }
            return false
        }
    }

    private func supplementExemptionRemote(
        application: ExemptionApplication,
        reason: String,
        detail: String,
        proofAttachments: [ProofAttachment],
        allowPreparedRecovery: Bool,
        expectedSessionEpoch: UInt64
    ) async -> Bool {
        guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
        let scope = "exemption:supplement:\(application.id)"
        guard let workspaceApplication = workspace.exemptions.first(where: { $0.id == application.id }),
              workspaceApplication.status.canSupplement || allowPreparedRecovery else {
            return false
        }
        guard acceptsExemptionProofs(proofAttachments) ||
                acceptsPersistedExemptionProofs(proofAttachments) else {
            errorMessage = exemptionProofError
            return false
        }
        let combinedReason = ExemptionInputRule.combinedReason(reason: reason, detail: detail)
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
            let enrollmentId = try await remoteRepo.exemptionEnrollmentID(
                applicationId: application.id
            )
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
                errorMessage = BNBUL10n.text("尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。")
                return false
            }
            for index in attempt.uploadedProofs.count..<proofAttachments.count {
                let attachment = proofAttachments[index]
                let uploaded = try await remoteRepo.uploadExemptionEvidence(
                    attachment: attachment,
                    applicationId: application.id,
                    enrollmentId: enrollmentId,
                    idempotencyKey: "\(attempt.idempotencyKey).proof-\(index)"
                )
                guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return false }
                attempt.uploadedProofs.append(uploaded)
                try storePendingRemoteMutation(attempt)
            }

            let preparedExpectedVersion: Int
            let preparedMediaIDs: [String]
            if attempt.phase == .finalMutationPrepared {
                guard let version = attempt.preparedExpectedVersion,
                      let mediaIDs = attempt.preparedMediaIDs else {
                    errorMessage = BNBUL10n.text("旧的免测补充重试记录缺少精确版本目标，已停止自动重试；请先核对服务器申请状态。")
                    return false
                }
                preparedExpectedVersion = version
                preparedMediaIDs = mediaIDs
            } else {
                let plan = try await remoteRepo.prepareExemptionSupplement(
                    applicationId: application.id,
                    newMediaIds: attempt.uploadedProofs.compactMap(\.cosKey)
                )
                guard plan.applicationId == application.id,
                      plan.enrollmentId == enrollmentId else {
                    throw RepositoryError.apiError("服务器返回的免测补充目标不属于原申请。")
                }
                preparedExpectedVersion = plan.expectedVersion
                preparedMediaIDs = plan.mediaIds
                attempt.markFinalMutationPrepared(
                    expectedVersion: preparedExpectedVersion,
                    mediaIDs: preparedMediaIDs
                )
                try storePendingRemoteMutation(attempt)
            }
            var supplemented = try await remoteRepo.updateAndSubmitExemption(
                application: application,
                reason: reason,
                detail: detail,
                preparedExpectedVersion: preparedExpectedVersion,
                preparedMediaIds: preparedMediaIDs,
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
                localJournalWarning = BNBUL10n.text("免测补充材料已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。")
            }
            supplemented.proofFiles = application.proofFiles + attempt.uploadedProofs
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
                    await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .exemption)
                    return true
                }
                refreshWarning = combinedWarning(
                    refreshWarning,
                    BNBUL10n.text("补充材料已提交，但最新申请列表暂未同步。请稍后下拉刷新，不要重复提交。")
                )
            }
            if !refreshedApplication {
                upsertExemption(supplemented)
            }
            workspace.notices.insert(
                StudentNotice(
                    id: UUID().uuidString,
                    title: BNBUL10n.text("免测补充材料已提交"),
                    message: BNBUL10n.text("\(application.item.rawValue) 的补充材料已进入复审队列。"),
                    time: RecentTimestamp.justNow,
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
                presentUserFacingError(error, context: .exemption)
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
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .exemption)
            if let journalError, !isUnauthorized(error) {
                presentUserFacingError(journalError, context: .exemption)
            }
            return false
        }
    }

    private func handleRemoteError(
        _ error: Error,
        expectedSessionEpoch: UInt64? = nil,
        context: ClientErrorContext = .generic
    ) async {
        if let expectedSessionEpoch, expectedSessionEpoch != sessionEpoch {
            return
        }
        if let repositoryError = error as? RepositoryError,
           case .sessionChanged = repositoryError {
            return
        }

        presentUserFacingError(error, context: context)

        if let repositoryError = error as? RepositoryError,
           repositoryError.isTerminalAuthenticationFailure {
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
            exerciseTestToolCapabilities = []
            remoteCacheStudentID = nil
            isLoading = false
            isLoadingExemptions = false
            isLoadingFeedback = false
            isSubmittingFeedback = false
            feedbackTickets = []
            feedbackNotice = nil
            isRefreshingWorkspace = false
            workspace = repository.loadWorkspace()
            draft = nil
            checkInSubmissionPhase = .idle
            canSafelyRetryCheckIn = false
            mutationGate.removeAll()
            let journalCleared = clearAllPendingRemoteMutations()
            if !securelyCleared {
                errorMessage = BNBUL10n.text("登录已过期，且设备未能清理安全存储。请重启 App 后再登录。")
            } else if !journalCleared {
                errorMessage = BNBUL10n.text("登录已过期，且设备未能清理待提交操作。请释放存储空间后重启 App。")
            }
        }
    }

    func requestAccountDeletionChallenge(
        locale: String
    ) async -> ContractAccountDeletionChallenge? {
        guard isRemoteMode else {
            errorMessage = BNBUL10n.text("演示账户不能发起正式注销。")
            return nil
        }
        guard !isProcessingAccountDeletion else { return nil }
        let expectedSessionEpoch = sessionEpoch
        isProcessingAccountDeletion = true
        defer { isProcessingAccountDeletion = false }
        do {
            let challenge = try await remoteRepo.requestAccountDeletionChallenge(locale: locale)
            guard expectedSessionEpoch == sessionEpoch, isRemoteMode else { return nil }
            errorMessage = nil
            return challenge
        } catch {
            await handleRemoteError(
                error,
                expectedSessionEpoch: expectedSessionEpoch,
                context: .accountDeletion
            )
            return nil
        }
    }

    @discardableResult
    func confirmAccountDeletion(
        challenge: ContractAccountDeletionChallenge,
        verificationCode: String
    ) async -> Bool {
        guard isRemoteMode, !isProcessingAccountDeletion else { return false }
        let normalizedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ContactBindingRule.isValidStudentSignInCode(normalizedCode) else {
            errorMessage = BNBUL10n.text("请输入 4 到 10 位数字验证码。")
            return false
        }
        let expectedSessionEpoch = sessionEpoch
        isProcessingAccountDeletion = true
        defer { isProcessingAccountDeletion = false }
        do {
            let outcome = try await remoteRepo.confirmAccountDeletion(
                challengeId: challenge.challengeId,
                expectedVersion: challenge.version,
                verificationCode: normalizedCode
            )
            guard expectedSessionEpoch == sessionEpoch,
                  outcome.result.status == "DELETED",
                  outcome.result.allSessionsRevoked,
                  outcome.result.newRegistrationRequired else {
                return false
            }
            // Backend has atomically disabled and de-identified the account and
            // revoked every session. Reuse the complete local logout cleanup so
            // caches, drafts, media and retry journals leave this device too.
            await logout()
            if !outcome.credentialsCleared, errorMessage == nil {
                errorMessage = BNBUL10n.text("账户已注销，但设备安全存储清理未完全确认。请重启 App 后再检查。")
            }
            return true
        } catch {
            await handleRemoteError(
                error,
                expectedSessionEpoch: expectedSessionEpoch,
                context: .accountDeletion
            )
            return false
        }
    }

    func prepareExerciseRecordResubmission(from record: CheckInRecord) -> Bool {
        guard isRemoteMode else {
            errorMessage = BNBUL10n.text("演示记录不能发起正式补交，请连接校园体育服务器。")
            return false
        }
        guard record.validity == .invalid else {
            errorMessage = BNBUL10n.text("只有最近一次被判定无效的记录可以补交。")
            return false
        }
        guard exerciseSession == nil else {
            errorMessage = BNBUL10n.text("请先完成当前运动，再开始新的补交尝试。")
            return false
        }
        exerciseRecordResubmission = ExerciseRecordResubmissionSelection(
            previousRecordId: record.id,
            nextAttemptNumber: (record.attemptContext?.attemptNumber ?? 1) + 1,
            creditType: record.creditType
        )
        clearDraft()
        errorMessage = nil
        return true
    }

    func cancelExerciseRecordResubmission() {
        guard exerciseSession == nil else { return }
        exerciseRecordResubmission = nil
    }

    func refreshExerciseRecordAttemptContext(recordId: String) async {
        guard isRemoteMode else { return }
        let expectedSessionEpoch = sessionEpoch
        do {
            let contract = try await remoteRepo.getExerciseRecordAttemptContext(recordId: recordId)
            guard expectedSessionEpoch == sessionEpoch,
                  isRemoteMode,
                  let index = workspace.records.firstIndex(where: { $0.id == recordId }) else {
                return
            }
            workspace.records[index].attemptContext = ExerciseRecordAttemptContext(
                recordId: contract.recordId,
                previousAttemptId: contract.previousAttemptId,
                rootAttemptId: contract.rootAttemptId,
                attemptNumber: contract.attemptNumber
            )
            saveWorkspace(event: "补交历史已同步")
        } catch {
            await handleRemoteError(error, expectedSessionEpoch: expectedSessionEpoch, context: .record)
        }
    }

    private func presentUserFacingError(
        _ error: Error,
        context: ClientErrorContext
    ) {
        let userError = ClientErrorMapper.map(error, context: context)
        SafeClientLogger.record(error, context: context, userError: userError)
        userFacingError = userError
        errorMessage = userError.displayText
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
                    createdAt: RecentTimestamp.justNow,
                    status: .synced
                )
            ]
        }
        if let currentDraft = draft,
           currentDraft.creditType == .courseRelated,
           let draftCourseId = currentDraft.courseId,
           !workspace.courses.contains(where: { $0.id == draftCourseId }) {
            clearDraft()
        }
        saveWorkspace(event: event)
    }

    private func restoreExerciseSession(for studentID: String) {
        guard let storedSession = localStore.readExerciseSession().value else {
            exerciseSession = nil
            return
        }
        guard storedSession.studentID == studentID else {
            exerciseSession = nil
            _ = localStore.clearExerciseSession()
            return
        }

        let reconciledSession = storedSession.reconciled()
        exerciseSession = reconciledSession
        if reconciledSession != storedSession {
            _ = localStore.saveExerciseSession(reconciledSession)
        }
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

    private func creditSubmittedExercise(hours: Double, creditType: CreditType) {
        guard !isRemoteMode, hours > 0 else { return }
        switch creditType {
        case .courseRelated:
            workspace.progress.course = min(workspace.progress.course + hours, hourRule.courseRequired)
        case .general:
            workspace.progress.rawGeneral += hours
            workspace.progress.general = min(workspace.progress.general + hours, hourRule.generalRequired)
        case .organizationOffset:
            break
        }
    }

    private func saveExerciseSubmissionDate(_ startDate: Date, recordID: String) {
        var datesByRecordID = localStore.readExerciseSubmissionDates().value ?? [:]
        datesByRecordID[recordID] = startDate
        if datesByRecordID.count > 120 {
            let retainedRecordIDs = datesByRecordID
                .sorted { $0.value > $1.value }
                .prefix(120)
                .map(\.key)
            datesByRecordID = datesByRecordID.filter { retainedRecordIDs.contains($0.key) }
        }
        _ = localStore.saveExerciseSubmissionDates(datesByRecordID)
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
            parts.append(BNBUL10n.text("\(photoCount) 张图片"))
        }
        if videoCount > 0 {
            parts.append(BNBUL10n.text("\(videoCount) 个短视频"))
        }
        return parts.isEmpty ? BNBUL10n.text("未添加凭证") : parts.joined(separator: BNBUL10n.text("，"))
    }

    private func acceptsExemptionProofs(_ attachments: [ProofAttachment]) -> Bool {
        ExemptionProofRule.accepts(attachments) &&
            attachments.allSatisfy { attachment in
                (attachment.source == "摄像头" || attachment.source == "相册") &&
                    attachment.isValidForUpload
            }
    }

    /// The protected retry journal drops original image bytes after upload.
    /// Recovery still requires camera provenance, image-only content, a stable
    /// digest and a valid count; the caller separately verifies every COS key.
    private func acceptsPersistedExemptionProofs(_ attachments: [ProofAttachment]) -> Bool {
        !attachments.isEmpty &&
            attachments.count <= ExemptionProofRule.maxAttachmentCount &&
            ExemptionProofRule.accepts(attachments) &&
            attachments.allSatisfy { attachment in
                (attachment.source == "摄像头" || attachment.source == "相册") &&
                    attachment.contentDigest?.isEmpty == false
            }
    }

    private func includeValidRemoteRecordInProgress(_ record: CheckInRecord) {
        guard isRemoteMode,
              record.validity == .valid,
              record.hours > 0,
              !workspace.records.contains(where: { $0.id == record.id }) else { return }
        let hours = record.hours
        switch record.creditType {
        case .courseRelated:
            workspace.progress.course += hours
            workspace.progress.rawCourse += hours
        case .general:
            workspace.progress.general += hours
            workspace.progress.rawGeneral += hours
        case .organizationOffset:
            return
        }
        workspace.progress.authoritativeTotalHours =
            max(workspace.progress.authoritativeTotalHours ?? 0, 0) + hours
        workspace.progress.status = BNBUL10n.text("已按有效打卡累计")
    }

    private var exemptionProofError: String {
        exemptionCopy(
            "免测材料必须至少包含 1 项有效的相机拍摄或文件选择凭证，并保留正确来源。",
            "Exemption proof must include at least one valid camera capture or file-picker item with its source preserved."
        )
    }

    private func exemptionCopy(_ chinese: String, _ english: String) -> String {
        BNBUL10n.locale.identifier.hasPrefix("zh") ? chinese : english
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
                createdAt: RecentTimestamp.justNow,
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
        submission: CheckInSubmission,
        note: String,
        sportType: String?,
        authoritativeSessionID: String?,
        authoritativeEnrollmentID: String?,
        previousRecordID: String? = nil,
        proofAttachments: [ProofAttachment]
    ) -> String {
        var fields = checkInRequestFields(
            submission: submission,
            note: note,
            sportType: sportType,
            authoritativeSessionID: authoritativeSessionID,
            authoritativeEnrollmentID: authoritativeEnrollmentID,
            previousRecordID: previousRecordID
        )
        fields.removeValue(forKey: "taskTitle")
        return RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: fields,
            attachments: proofAttachments
        )
    }

    private func checkInRequestFields(
        submission: CheckInSubmission,
        note: String,
        sportType: String?,
        authoritativeSessionID: String?,
        authoritativeEnrollmentID: String?,
        previousRecordID: String? = nil
    ) -> [String: String] {
        [
            "taskTitle": submission.title,
            "courseId": submission.courseId ?? "",
            "creditType": submission.creditType.apiValue,
            "hours": String(format: "%.1f", submission.hours),
            "description": note.isEmpty ? "学生未填写补充说明。" : note,
            "sportType": sportType ?? "",
            "authoritativeSessionId": authoritativeSessionID ?? "",
            "authoritativeEnrollmentId": authoritativeEnrollmentID ?? "",
            "previousRecordId": previousRecordID ?? ""
        ]
    }

    private func resolveCheckInAttempt(
        scope: String,
        fingerprint: String,
        submission: CheckInSubmission,
        note: String,
        sportType: String?,
        authoritativeSessionID: String,
        authoritativeEnrollmentID: String,
        previousRecordID: String?,
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
            submission: submission,
            note: note,
            sportType: sportType,
            authoritativeSessionID: authoritativeSessionID,
            authoritativeEnrollmentID: authoritativeEnrollmentID,
            previousRecordID: previousRecordID,
            proofAttachments: proofAttachments
        )
    }

    private func replaceCheckInAttempt(
        scope: String,
        fingerprint: String,
        submission: CheckInSubmission,
        note: String,
        sportType: String?,
        authoritativeSessionID: String,
        authoritativeEnrollmentID: String,
        previousRecordID: String?,
        proofAttachments: [ProofAttachment]
    ) -> PendingRemoteMutationAttempt {
        let attempt = PendingRemoteMutationAttempt.create(
            scope: scope,
            fingerprint: fingerprint,
            serverIdentity: remoteMutationServerIdentity,
            studentID: remoteCacheStudentID ?? workspace.student.id,
            authoritativeSessionID: authoritativeSessionID,
            authoritativeEnrollmentID: authoritativeEnrollmentID,
            requestFields: checkInRequestFields(
                submission: submission,
                note: note,
                sportType: sportType,
                authoritativeSessionID: authoritativeSessionID,
                authoritativeEnrollmentID: authoritativeEnrollmentID,
                previousRecordID: previousRecordID
            ),
            sourceProofs: proofAttachments
        )
        return attempt
    }

    private func persistCheckInAttempt(
        _ attempt: PendingRemoteMutationAttempt,
        submission: CheckInSubmission,
        note: String,
        sportType: String?,
        proofAttachments: [ProofAttachment]
    ) throws {
        let knownSportTypes: Set<String> = [
            "running", "basketball", "football", "badminton",
            "tableTennis", "swimming", "fitness", "cycling"
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
            creditType: submission.creditType,
            courseId: submission.courseId,
            hours: submission.hours,
            note: note,
            proofAttachments: proofAttachments,
            updatedAt: RecentTimestamp.justNow,
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
                    presentUserFacingError(RemoteMutationJournalError.writeFailed, context: .record)
                }
                return
            }
            guard IdempotencyKeyPolicy.isValid(attempt.idempotencyKey) else {
                clearPersistedRemoteAttemptFromDraft()
                if !persistPendingRemoteMutationJournal() {
                    presentUserFacingError(RemoteMutationJournalError.writeFailed, context: .record)
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
            if confirmedAttempts.isEmpty {
                presentUserFacingError(RemoteMutationJournalError.writeFailed, context: .record)
            } else {
                errorMessage = serverConfirmedCleanupWarning
            }
        }
    }

    private func clearPersistedRemoteAttemptFromDraft() {
        do {
            try clearPersistedRemoteAttemptFromDraftStrict()
        } catch {
            presentUserFacingError(error, context: .record)
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
        BNBUL10n.text("该操作已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。")
    }

    private func removePendingRemoteMutation(scope: String) {
        do {
            try removePendingRemoteMutationStrict(scope: scope)
        } catch {
            presentUserFacingError(error, context: .generic)
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
            presentUserFacingError(RemoteMutationJournalError.writeFailed, context: .generic)
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

    private func endMutation(_ key: String) {
        mutationGate.end(key)
    }

    private func containsDuplicates(_ ids: [String]) -> Bool {
        Set(ids).count != ids.count
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        guard let repositoryError = error as? RepositoryError else { return false }
        return repositoryError.isTerminalAuthenticationFailure
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

    private static func exemptionCreationScope(for item: ExemptionItem) -> String {
        item.isCheckInExemption
            ? "exemption:create:check-in"
            : "exemption:create:physical-test"
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

private extension Array {
    /// Splits the array into (matching, nonMatching) while preserving order.
    func partitioned(_ predicate: (Element) -> Bool) -> ([Element], [Element]) {
        var matching: [Element] = []
        var rest: [Element] = []
        for element in self {
            if predicate(element) {
                matching.append(element)
            } else {
                rest.append(element)
            }
        }
        return (matching, rest)
    }
}
