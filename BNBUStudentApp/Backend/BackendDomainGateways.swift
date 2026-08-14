import CryptoKit
import Foundation

struct MediaUploadOutcome: Equatable {
    let media: APIV1MediaEvidence
    let requestId: String
}

struct EphemeralMediaAccess: Equatable {
    let mediaID: String
    let url: URL
    let expiresAt: String
}

enum MediaUploadPayload: Sendable {
    case data(Data)
    case file(URL)

    var byteCount: Int? {
        switch self {
        case .data(let data):
            return data.count
        case .file(let url):
            return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }
    }
}

struct BackendStudentWorkspaceProjection: Equatable {
    let semester: APIV1Semester
    let enrollments: [APIV1Enrollment]
    let classSections: [APIV1ClassSection]
    let courses: [APIV1Course]
    let teachers: [APIV1TeacherProfile]
}

/// Contract 1.5 capabilities used by the authenticated shell and its public
/// support pages. Keeping these routes outside RemoteStudentRepository makes
/// it impossible for an API-v1 session to fall back to historical paths.
actor BackendClientCapabilityGateway {
    private let client: StudentAPIClient
    private let auth: BackendAuthSessionController
    private let intents: IdempotencyIntentRegistry

    init(
        client: StudentAPIClient,
        auth: BackendAuthSessionController,
        intents: IdempotencyIntentRegistry = IdempotencyIntentRegistry()
    ) {
        self.client = client
        self.auth = auth
        self.intents = intents
    }

    func systemMode() async throws -> APIResponse<APIV1SystemModeProjection> {
        try await client.send(APIRequest(
            operationID: "getSystemMode",
            method: .get,
            path: "system-mode"
        ))
    }

    func appReleasePolicy(
        query: IOSAppReleasePolicyQuery
    ) async throws -> APIResponse<APIV1AppReleasePolicy> {
        try await client.send(APIRequest(
            operationID: "getAppReleasePolicy",
            method: .get,
            path: "app-release-policy",
            queryItems: query.queryItems
        ))
    }

    func helpArticles(locale: String) async throws -> APIResponse<[APIV1HelpArticle]> {
        guard locale == "zh-CN" || locale == "en" else {
            throw APITransportError.invalidRequest
        }
        return try await client.send(APIRequest(
            operationID: "listHelpArticles",
            method: .get,
            path: "help-articles",
            queryItems: [URLQueryItem(name: "locale", value: locale)]
        ))
    }

    func notifications() async throws -> APIResponse<[APIV1Notification]> {
        let response: APIResponse<[APIV1Notification]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listNotifications",
            method: .get,
            path: "notifications",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        ))
        guard response.pagination?.hasMore != true else {
            throw APITransportError.invalidResponse
        }
        return response
    }

    func currentUserPreferences() async throws -> APIResponse<APIV1UserPreferences> {
        try await auth.sendAuthorized(APIRequest(
            operationID: "getCurrentUserPreferences",
            method: .get,
            path: "me/preferences"
        ))
    }

    func updateCurrentUserPreferences(
        _ body: APIV1UpdateUserPreferencesRequest
    ) async throws -> APIResponse<APIV1UserPreferences> {
        let scope = "preferences:update"
        let fingerprint = try IntentFingerprint.make(body)
        let response: APIResponse<APIV1UserPreferences> = try await auth.sendAuthorized(APIRequest(
            operationID: "updateCurrentUserPreferences",
            method: .patch,
            path: "me/preferences",
            body: try APIRequest.jsonBody(body),
            idempotencyKey: await intents.key(scope: scope, fingerprint: fingerprint)
        ))
        await intents.clear(scope: scope)
        return response
    }

    func markNotificationRead(id: String) async throws -> APIResponse<APIV1Notification> {
        let id = try APIPath.component(id)
        let scope = "notification:read:\(id)"
        let response: APIResponse<APIV1Notification> = try await auth.sendAuthorized(APIRequest(
            operationID: "markNotificationRead",
            method: .post,
            path: "notifications/\(id)/read",
            idempotencyKey: await intents.key(scope: scope, fingerprint: id)
        ))
        await intents.clear(scope: scope)
        return response
    }

    func feedback() async throws -> APIResponse<[APIV1Feedback]> {
        let response: APIResponse<[APIV1Feedback]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listFeedback",
            method: .get,
            path: "feedback",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        ))
        guard response.pagination?.hasMore != true else {
            throw APITransportError.invalidResponse
        }
        return response
    }

    func createFeedback(
        _ body: APIV1CreateFeedbackRequest
    ) async throws -> APIResponse<APIV1Feedback> {
        let scope = "feedback:create"
        let fingerprint = try IntentFingerprint.make(body)
        let response: APIResponse<APIV1Feedback> = try await auth.sendAuthorized(APIRequest(
            operationID: "createFeedback",
            method: .post,
            path: "feedback",
            body: try APIRequest.jsonBody(body),
            idempotencyKey: await intents.key(scope: scope, fingerprint: fingerprint)
        ))
        await intents.clear(scope: scope)
        return response
    }

    func exemptionApplications() async throws -> APIResponse<[APIV1ExemptionApplication]> {
        let response: APIResponse<[APIV1ExemptionApplication]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listExemptionApplications",
            method: .get,
            path: "exemption-applications",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        ))
        guard response.pagination?.hasMore != true else {
            throw APITransportError.invalidResponse
        }
        return response
    }
}

/// Reads the minimum authoritative course graph needed by the iOS student
/// shell. Every collection is role-scoped by Backend; pagination truncation
/// fails closed so the app never silently picks the wrong enrollment.
actor AuthoritativeStudentWorkspaceGateway {
    private let auth: BackendAuthSessionController

    init(auth: BackendAuthSessionController) {
        self.auth = auth
    }

    func load(studentID: String) async throws -> BackendStudentWorkspaceProjection {
        let studentID = try APIPath.component(studentID)
        let semester: APIResponse<APIV1Semester> = try await auth.sendAuthorized(APIRequest(
            operationID: "getCurrentSemester",
            method: .get,
            path: "semesters/current"
        ))
        let enrollments: APIResponse<[APIV1Enrollment]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listEnrollments",
            method: .get,
            path: "enrollments",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "studentId", value: studentID),
                URLQueryItem(name: "semesterId", value: semester.value.id),
                URLQueryItem(name: "status", value: APIV1EnrollmentStatus.active.rawValue),
                URLQueryItem(name: "sort", value: "-joinedAt")
            ]
        ))
        let sections: APIResponse<[APIV1ClassSection]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listClassSections",
            method: .get,
            path: "class-sections",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "semesterId", value: semester.value.id),
                URLQueryItem(name: "status", value: APIV1ClassSectionStatus.active.rawValue)
            ]
        ))
        let courses: APIResponse<[APIV1Course]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listCourses",
            method: .get,
            path: "courses",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "status", value: APIV1CourseStatus.active.rawValue)
            ]
        ))
        guard enrollments.pagination?.hasMore != true,
              sections.pagination?.hasMore != true,
              courses.pagination?.hasMore != true else {
            throw APITransportError.invalidResponse
        }

        let activeSectionIDs = Set(enrollments.value.map(\.classSectionId))
        let authorizedSections = sections.value.filter { activeSectionIDs.contains($0.id) }
        var teachers: [APIV1TeacherProfile] = []
        for teacherID in Set(authorizedSections.map(\.teacherId)).sorted() {
            let teacherID = try APIPath.component(teacherID)
            let teacher: APIResponse<APIV1TeacherProfile> = try await auth.sendAuthorized(APIRequest(
                operationID: "getTeacher",
                method: .get,
                path: "teachers/\(teacherID)"
            ))
            teachers.append(teacher.value)
        }
        return BackendStudentWorkspaceProjection(
            semester: semester.value,
            enrollments: enrollments.value,
            classSections: authorizedSections,
            courses: courses.value,
            teachers: teachers
        )
    }
}

actor MediaUploadCoordinator {
    private struct ConfirmedUpload {
        let response: APIResponse<APIV1MediaEvidence>
        let initiateScope: String
        let confirmScope: String
    }

    private let client: StudentAPIClient
    private let auth: BackendAuthSessionController
    private let intents: IdempotencyIntentRegistry

    init(
        client: StudentAPIClient,
        auth: BackendAuthSessionController,
        intents: IdempotencyIntentRegistry = IdempotencyIntentRegistry()
    ) {
        self.client = client
        self.auth = auth
        self.intents = intents
    }

    func uploadAndBind(
        bytes: Data,
        request: APIV1InitiateMediaUploadRequest,
        idempotencyKeySeed: String? = nil,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void = { _ in }
    ) async throws -> MediaUploadOutcome {
        try await uploadAndBind(
            payload: .data(bytes),
            request: request,
            idempotencyKeySeed: idempotencyKeySeed,
            progressHandler: progressHandler
        )
    }

    func uploadAndBind(
        fileURL: URL,
        request: APIV1InitiateMediaUploadRequest,
        idempotencyKeySeed: String? = nil,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void = { _ in }
    ) async throws -> MediaUploadOutcome {
        try await uploadAndBind(
            payload: .file(fileURL),
            request: request,
            idempotencyKeySeed: idempotencyKeySeed,
            progressHandler: progressHandler
        )
    }

    private func uploadAndBind(
        payload: MediaUploadPayload,
        request: APIV1InitiateMediaUploadRequest,
        idempotencyKeySeed: String?,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void
    ) async throws -> MediaUploadOutcome {
        guard MediaUploadContractPolicy.accepts(request),
              request.businessPurpose == .exerciseRecord,
              let sessionID = request.sessionId else {
            throw APITransportError.invalidRequest
        }

        let confirmedUpload = try await uploadAndConfirm(
            payload: payload,
            request: request,
            idempotencyKeySeed: idempotencyKeySeed,
            progressHandler: progressHandler
        )
        let confirmed = confirmedUpload.response

        let mediaID = try APIPath.component(confirmed.value.id)
        let bind = APIV1BindMediaRequest(
            sessionId: sessionID,
            expectedVersion: confirmed.value.version
        )
        let bindScope = "media:bind:\(mediaID)"
        let bound: APIResponse<APIV1MediaEvidence> = try await auth.sendAuthorized(APIRequest(
            operationID: "bindMediaEvidence",
            method: .post,
            path: "media/\(mediaID)/bind",
            body: try APIRequest.jsonBody(bind),
            idempotencyKey: try await idempotencyKey(
                seed: idempotencyKeySeed,
                phase: "bind",
                scope: bindScope,
                fingerprint: IntentFingerprint.make(bind)
            )
        ))
        await intents.clear(scope: confirmedUpload.initiateScope)
        await intents.clear(scope: confirmedUpload.confirmScope)
        await intents.clear(scope: bindScope)
        return MediaUploadOutcome(media: bound.value, requestId: bound.requestId)
    }

    /// Exemption media is scoped to an Enrollment and is associated atomically
    /// by createExemptionApplication; it must never use the exercise bind route.
    func uploadForExemption(
        bytes: Data,
        request: APIV1InitiateMediaUploadRequest,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void = { _ in }
    ) async throws -> MediaUploadOutcome {
        guard MediaUploadContractPolicy.accepts(request),
              request.businessPurpose == .exemptionApplication else {
            throw APITransportError.invalidRequest
        }

        let confirmedUpload = try await uploadAndConfirm(
            payload: .data(bytes),
            request: request,
            idempotencyKeySeed: nil,
            progressHandler: progressHandler
        )
        await intents.clear(scope: confirmedUpload.initiateScope)
        await intents.clear(scope: confirmedUpload.confirmScope)
        return MediaUploadOutcome(
            media: confirmedUpload.response.value,
            requestId: confirmedUpload.response.requestId
        )
    }

    private func uploadAndConfirm(
        payload: MediaUploadPayload,
        request: APIV1InitiateMediaUploadRequest,
        idempotencyKeySeed: String?,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void
    ) async throws -> ConfirmedUpload {
        guard payload.byteCount == request.fileSizeBytes else {
            throw APITransportError.invalidRequest
        }

        let targetID = request.sessionId ?? request.enrollmentId ?? ""
        let initiateScope = "media:initiate:\(request.businessPurpose.rawValue):\(targetID)"
        let initiateKey = try await idempotencyKey(
            seed: idempotencyKeySeed,
            phase: "initiate",
            scope: initiateScope,
            fingerprint: IntentFingerprint.make(request)
        )
        let initiated: APIResponse<APIV1MediaUploadSession> = try await auth.sendAuthorized(APIRequest(
            operationID: "initiateMediaUpload",
            method: .post,
            path: "media-uploads",
            body: try APIRequest.jsonBody(request),
            idempotencyKey: initiateKey
        ))

        guard let uploadURL = URL(string: initiated.value.uploadUrl),
              let uploadMethod = HTTPMethod(rawValue: initiated.value.uploadMethod),
              uploadMethod == .put else {
            throw APITransportError.invalidResponse
        }
        let uploadResponse: HTTPURLResponse
        switch payload {
        case .data(let bytes):
            uploadResponse = try await client.upload(
                to: uploadURL,
                data: bytes,
                method: uploadMethod,
                requiredHeaders: initiated.value.requiredHeaders,
                progressHandler: progressHandler
            )
        case .file(let fileURL):
            uploadResponse = try await client.upload(
                to: uploadURL,
                fileURL: fileURL,
                method: uploadMethod,
                requiredHeaders: initiated.value.requiredHeaders,
                progressHandler: progressHandler
            )
        }
        guard let etag = uploadResponse.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else {
            throw APITransportError.invalidResponse
        }

        let uploadSessionID = try APIPath.component(initiated.value.uploadSessionId)
        let confirm = APIV1ConfirmMediaUploadRequest(etag: etag)
        let confirmScope = "media:confirm:\(uploadSessionID)"
        let confirmed: APIResponse<APIV1MediaEvidence> = try await auth.sendAuthorized(APIRequest(
            operationID: "confirmMediaUpload",
            method: .post,
            path: "media-uploads/\(uploadSessionID)/confirm",
            body: try APIRequest.jsonBody(confirm),
            idempotencyKey: try await idempotencyKey(
                seed: idempotencyKeySeed,
                phase: "confirm",
                scope: confirmScope,
                fingerprint: IntentFingerprint.make(confirm)
            )
        ))
        guard confirmed.value.businessPurpose == request.businessPurpose,
              confirmed.value.sessionId == request.sessionId,
              confirmed.value.enrollmentId == request.enrollmentId,
              confirmed.value.captureSource.rawValue == request.captureSource.rawValue else {
            throw APITransportError.invalidResponse
        }

        return ConfirmedUpload(
            response: confirmed,
            initiateScope: initiateScope,
            confirmScope: confirmScope
        )
    }

    private func idempotencyKey(
        seed: String?,
        phase: String,
        scope: String,
        fingerprint: String
    ) async throws -> String {
        guard let seed else {
            return await intents.key(scope: scope, fingerprint: fingerprint)
        }
        guard IdempotencyKeyPolicy.isValid(seed) else {
            throw APITransportError.invalidRequest
        }
        let digest = SHA256.hash(data: Data("\(seed):\(phase)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "ios-\(digest)"
    }

    func status(mediaID: String) async throws -> APIResponse<APIV1MediaEvidence> {
        let mediaID = try APIPath.component(mediaID)
        return try await auth.sendAuthorized(APIRequest(
            operationID: "getMediaEvidence",
            method: .get,
            path: "media/\(mediaID)"
        ))
    }

    func ephemeralAccess(
        mediaID: String,
        purpose: APIV1MediaAccessPurpose = .viewOriginal
    ) async throws -> EphemeralMediaAccess {
        let mediaID = try APIPath.component(mediaID)
        let request = APIV1MediaAccessRequest(purpose: purpose)
        let scope = "media:access:\(mediaID)"
        let response: APIResponse<APIV1MediaAccess> = try await auth.sendAuthorized(APIRequest(
            operationID: "createMediaAccessUrl",
            method: .post,
            path: "media/\(mediaID)/access-url",
            body: try APIRequest.jsonBody(request),
            idempotencyKey: await intents.key(
                scope: scope,
                fingerprint: try IntentFingerprint.make(request)
            )
        ))
        await intents.clear(scope: scope)
        guard let url = URL(string: response.value.accessUrl) else {
            throw APITransportError.invalidResponse
        }
        return EphemeralMediaAccess(
            mediaID: response.value.mediaId,
            url: url,
            expiresAt: response.value.expiresAt
        )
    }

}

actor AuthoritativeExerciseSessionGateway {
    private let auth: BackendAuthSessionController
    private let intents: IdempotencyIntentRegistry

    init(
        auth: BackendAuthSessionController,
        intents: IdempotencyIntentRegistry = IdempotencyIntentRegistry()
    ) {
        self.auth = auth
        self.intents = intents
    }

    func restoreActive(enrollmentID: String? = nil) async throws -> APIResponse<APIV1ExerciseSession?> {
        let query = enrollmentID.map { [URLQueryItem(name: "enrollmentId", value: $0)] } ?? []
        return try await auth.sendAuthorized(APIRequest(
            operationID: "getActiveExerciseSession",
            method: .get,
            path: "exercise-sessions/active",
            queryItems: query
        ))
    }

    func get(sessionID: String) async throws -> APIResponse<APIV1ExerciseSession> {
        let sessionID = try APIPath.component(sessionID)
        return try await auth.sendAuthorized(APIRequest(
            operationID: "getExerciseSession",
            method: .get,
            path: "exercise-sessions/\(sessionID)"
        ))
    }

    func start(_ request: APIV1StartSessionRequest) async throws -> APIResponse<APIV1ExerciseSession> {
        let scope = "session:start:\(request.enrollmentId)"
        do {
            return try await mutate(
                operationID: "startExerciseSession",
                path: "exercise-sessions",
                scope: scope,
                body: request
            )
        } catch let error as APITransportError {
            guard let admissionError = ExerciseSessionAdmissionPolicy.startError(from: error) else {
                throw error
            }
            // These denials are deterministic for this attempt. A later retry
            // must re-read server state and use a fresh idempotency key.
            await intents.clear(scope: scope)
            throw admissionError
        }
    }

    func pause(sessionID: String, request: APIV1SessionControlRequest) async throws -> APIResponse<APIV1ExerciseSession> {
        try await control(operation: "pauseExerciseSession", action: "pause", sessionID: sessionID, body: request)
    }

    func resume(sessionID: String, request: APIV1SessionControlRequest) async throws -> APIResponse<APIV1ExerciseSession> {
        try await control(operation: "resumeExerciseSession", action: "resume", sessionID: sessionID, body: request)
    }

    func finish(sessionID: String, request: APIV1SessionControlRequest) async throws -> APIResponse<APIV1ExerciseSession> {
        try await control(operation: "finishExerciseSession", action: "finish", sessionID: sessionID, body: request)
    }

    func cancel(sessionID: String, request: APIV1VersionedReasonRequest) async throws -> APIResponse<APIV1ExerciseSession> {
        try await control(operation: "cancelExerciseSession", action: "cancel", sessionID: sessionID, body: request)
    }

    func reconcile(sessionID: String, request: APIV1ReconcileSessionRequest) async throws -> APIResponse<APIV1ExerciseSession> {
        try await control(operation: "reconcileExerciseSession", action: "reconcile", sessionID: sessionID, body: request)
    }

    private func control<Body: Encodable>(
        operation: String,
        action: String,
        sessionID: String,
        body: Body
    ) async throws -> APIResponse<APIV1ExerciseSession> {
        let sessionID = try APIPath.component(sessionID)
        return try await mutate(
            operationID: operation,
            path: "exercise-sessions/\(sessionID)/\(action)",
            scope: "session:\(action):\(sessionID)",
            body: body
        )
    }

    private func mutate<Body: Encodable>(
        operationID: String,
        path: String,
        scope: String,
        body: Body
    ) async throws -> APIResponse<APIV1ExerciseSession> {
        let fingerprint = try IntentFingerprint.make(body)
        let response: APIResponse<APIV1ExerciseSession> = try await auth.sendAuthorized(APIRequest(
            operationID: operationID,
            method: .post,
            path: path,
            body: try APIRequest.jsonBody(body),
            idempotencyKey: await intents.key(scope: scope, fingerprint: fingerprint)
        ))
        await intents.clear(scope: scope)
        return response
    }
}

actor AuthoritativeExerciseRecordGateway {
    private let auth: BackendAuthSessionController
    private let intents: IdempotencyIntentRegistry

    init(
        auth: BackendAuthSessionController,
        intents: IdempotencyIntentRegistry = IdempotencyIntentRegistry()
    ) {
        self.auth = auth
        self.intents = intents
    }

    func createDraft(
        _ request: APIV1CreateExerciseRecordRequest
    ) async throws -> APIResponse<APIV1ExerciseRecord> {
        guard ExerciseRecordContractPolicy.accepts(request) else {
            throw APITransportError.invalidRequest
        }
        let scope = "exercise-record:create:\(request.sessionId)"
        return try await mutate(
            operationID: "createExerciseRecordDraft",
            path: "exercise-records",
            scope: scope,
            body: request
        )
    }

    func get(recordID: String) async throws -> APIResponse<APIV1ExerciseRecord> {
        let recordID = try APIPath.component(recordID)
        return try await auth.sendAuthorized(APIRequest(
            operationID: "getExerciseRecord",
            method: .get,
            path: "exercise-records/\(recordID)"
        ))
    }

    /// Recovers the one record (draft or submitted) owned by a completed
    /// session. Contract 1.5 has no direct sessionId filter, so the query is
    /// narrowed by enrollment and frozen business date, then matched locally.
    func findForSession(
        sessionID: String,
        enrollmentID: String,
        businessDate: String
    ) async throws -> APIResponse<APIV1ExerciseRecord?> {
        let response: APIResponse<[APIV1ExerciseRecord]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listExerciseRecords",
            method: .get,
            path: "exercise-records",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "enrollmentId", value: enrollmentID),
                URLQueryItem(name: "businessDateFrom", value: businessDate),
                URLQueryItem(name: "businessDateTo", value: businessDate),
                URLQueryItem(name: "sort", value: "-businessDate")
            ]
        ))
        guard response.pagination?.hasMore != true else {
            throw APITransportError.invalidResponse
        }
        let matches = response.value.filter { $0.sessionId == sessionID }
        guard matches.count <= 1 else { throw APITransportError.invalidResponse }
        return APIResponse(
            value: matches.first,
            requestId: response.requestId,
            pagination: response.pagination,
            statusCode: response.statusCode
        )
    }

    func submit(
        recordID: String,
        request: APIV1SubmitExerciseRecordRequest
    ) async throws -> APIResponse<APIV1ExerciseRecord> {
        guard !request.mediaIds.isEmpty, request.expectedVersion > 0 else {
            throw APITransportError.invalidRequest
        }
        let recordID = try APIPath.component(recordID)
        return try await mutate(
            operationID: "submitExerciseRecord",
            path: "exercise-records/\(recordID)/submit",
            scope: "exercise-record:submit:\(recordID)",
            body: request
        )
    }

    private func mutate<Body: Encodable>(
        operationID: String,
        path: String,
        scope: String,
        body: Body
    ) async throws -> APIResponse<APIV1ExerciseRecord> {
        let response: APIResponse<APIV1ExerciseRecord> = try await auth.sendAuthorized(APIRequest(
            operationID: operationID,
            method: .post,
            path: path,
            body: try APIRequest.jsonBody(body),
            idempotencyKey: await intents.key(
                scope: scope,
                fingerprint: try IntentFingerprint.make(body)
            )
        ))
        await intents.clear(scope: scope)
        return response
    }
}

enum ServerSessionDisplayClock {
    /// This value is display-only. Every persisted and submitted duration must
    /// come from the server projection.
    static func elapsedSeconds(for session: APIV1ExerciseSession, now: Date = Date()) -> Int {
        guard session.status == .inProgress,
              let startedAt = ISO8601DateFormatter().date(from: session.startedAt) else {
            return session.actualDurationSeconds
        }
        let localEstimate = max(0, Int(now.timeIntervalSince(startedAt))) - session.pausedDurationSeconds
        return min(7_200, max(session.actualDurationSeconds, localEstimate))
    }
}
