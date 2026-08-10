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
        expectedVersion: Int,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void = { _ in }
    ) async throws -> MediaUploadOutcome {
        guard MediaUploadContractPolicy.accepts(request),
              request.businessPurpose == .exerciseRecord,
              let sessionID = request.sessionId,
              expectedVersion > 0 else {
            throw APITransportError.invalidRequest
        }

        let confirmedUpload = try await uploadAndConfirm(
            bytes: bytes,
            request: request,
            progressHandler: progressHandler
        )
        let confirmed = confirmedUpload.response

        let mediaID = try APIPath.component(confirmed.value.id)
        let bind = APIV1BindMediaRequest(
            sessionId: sessionID,
            expectedVersion: expectedVersion
        )
        let bindScope = "media:bind:\(mediaID)"
        let bound: APIResponse<APIV1MediaEvidence> = try await auth.sendAuthorized(APIRequest(
            operationID: "bindMediaEvidence",
            method: .post,
            path: "media/\(mediaID)/bind",
            body: try APIRequest.jsonBody(bind),
            idempotencyKey: await intents.key(
                scope: bindScope,
                fingerprint: try IntentFingerprint.make(bind)
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
            bytes: bytes,
            request: request,
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
        bytes: Data,
        request: APIV1InitiateMediaUploadRequest,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void
    ) async throws -> ConfirmedUpload {
        guard bytes.count == request.fileSizeBytes else { throw APITransportError.invalidRequest }

        let targetID = request.sessionId ?? request.enrollmentId ?? ""
        let initiateScope = "media:initiate:\(request.businessPurpose.rawValue):\(targetID)"
        let initiateKey = await intents.key(
            scope: initiateScope,
            fingerprint: try IntentFingerprint.make(request)
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
        let uploadResponse = try await client.upload(
            to: uploadURL,
            data: bytes,
            method: uploadMethod,
            requiredHeaders: initiated.value.requiredHeaders,
            progressHandler: progressHandler
        )
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
            idempotencyKey: await intents.key(
                scope: confirmScope,
                fingerprint: try IntentFingerprint.make(confirm)
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
