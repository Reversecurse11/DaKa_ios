import CryptoKit
import Foundation

struct MediaUploadOutcome: Equatable {
    let media: APIV1MediaEvidence
    let requestId: String
}

enum MediaUploadPipelineError: Error, Equatable {
    case invalidUploadCapability(requestId: String?)
    case uploadCapabilityRecoveryFailed(requestId: String?)
    case transportInvalidResponse(phase: String)
    case signedUploadRejected(statusCode: Int, providerCode: String?)
    case missingUploadEntityTag
    case confirmationProjectionMismatch(field: String, requestId: String)
    case bindingProjectionMismatch(field: String, requestId: String)
    case statusProjectionMismatch(field: String, requestId: String)
    case processingStopped(status: String, requestId: String)
    case processingTimedOut(status: String, requestId: String)

    var diagnosticCode: String {
        switch self {
        case .invalidUploadCapability:
            return "MEDIA_UPLOAD_CAPABILITY_INVALID"
        case .uploadCapabilityRecoveryFailed:
            return "MEDIA_UPLOAD_CAPABILITY_RECOVERY_FAILED"
        case .transportInvalidResponse(let phase):
            return "MEDIA_\(phase.uppercased())_RESPONSE_INVALID"
        case .signedUploadRejected(let statusCode, let providerCode):
            let providerSuffix = providerCode.flatMap(Self.safeDiagnosticComponent)
                .map { "_\($0)" } ?? ""
            return "MEDIA_SIGNED_PUT_HTTP_\(statusCode)\(providerSuffix)"
        case .missingUploadEntityTag:
            return "MEDIA_UPLOAD_ETAG_MISSING"
        case .confirmationProjectionMismatch(let field, _):
            return "MEDIA_CONFIRM_\(field.uppercased())_MISMATCH"
        case .bindingProjectionMismatch(let field, _):
            return "MEDIA_BIND_\(field.uppercased())_MISMATCH"
        case .statusProjectionMismatch(let field, _):
            return "MEDIA_STATUS_\(field.uppercased())_MISMATCH"
        case .processingStopped(let status, _):
            return "MEDIA_PROCESSING_STOPPED_\(status.uppercased())"
        case .processingTimedOut(let status, _):
            return "MEDIA_PROCESSING_TIMEOUT_\(status.uppercased())"
        }
    }

    private static func safeDiagnosticComponent(_ value: String) -> String? {
        let normalized = value.uppercased().map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let component = String(normalized.prefix(64))
        return component.isEmpty ? nil : component
    }

    var requestId: String? {
        switch self {
        case .invalidUploadCapability(let requestId):
            return requestId
        case .uploadCapabilityRecoveryFailed(let requestId):
            return requestId
        case .transportInvalidResponse, .signedUploadRejected:
            return nil
        case .missingUploadEntityTag:
            return nil
        case .confirmationProjectionMismatch(_, let requestId):
            return requestId
        case .bindingProjectionMismatch(_, let requestId):
            return requestId
        case .statusProjectionMismatch(_, let requestId),
             .processingStopped(_, let requestId),
             .processingTimedOut(_, let requestId):
            return requestId
        }
    }
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

/// Contract 2.0.2 capabilities used by the authenticated shell and its public
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

    func exemptionApplications() async throws -> APIResponse<[APIV1StructuredExemptionApplication]> {
        let response: APIResponse<[APIV1StructuredExemptionApplication]> = try await auth.sendAuthorized(APIRequest(
            operationID: "listStructuredExemptionApplications",
            method: .get,
            path: "exemption-application-details",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        ))
        guard response.pagination?.hasMore != true else {
            throw APITransportError.invalidResponse
        }
        return response
    }
}

/// Student-owned exemption mutations. Keeping create/update/submit in one
/// authenticated gateway preserves idempotency across the multi-step flow and
/// prevents the API-v1 app from falling back to the historical repository.
actor AuthoritativeExemptionApplicationGateway {
    private let auth: BackendAuthSessionController
    private let intents: IdempotencyIntentRegistry

    init(
        auth: BackendAuthSessionController,
        intents: IdempotencyIntentRegistry = IdempotencyIntentRegistry()
    ) {
        self.auth = auth
        self.intents = intents
    }

    func create(
        _ body: APIV1CreateExemptionApplicationRequest
    ) async throws -> APIResponse<APIV1ExemptionApplication> {
        let scope = "exemption:create"
        let fingerprint = try IntentFingerprint.make(body)
        let response: APIResponse<APIV1ExemptionApplication> = try await auth.sendAuthorized(APIRequest(
            operationID: "createExemptionApplication",
            method: .post,
            path: "exemption-applications",
            body: try APIRequest.jsonBody(body),
            idempotencyKey: await intents.key(scope: scope, fingerprint: fingerprint)
        ))
        await intents.clear(scope: scope)
        return response
    }

    func get(applicationID: String) async throws -> APIResponse<APIV1ExemptionApplication> {
        let applicationID = try APIPath.component(applicationID)
        return try await auth.sendAuthorized(APIRequest(
            operationID: "getExemptionApplication",
            method: .get,
            path: "exemption-applications/\(applicationID)"
        ))
    }

    func update(
        applicationID: String,
        body: APIV1UpdateExemptionApplicationRequest
    ) async throws -> APIResponse<APIV1ExemptionApplication> {
        let applicationID = try APIPath.component(applicationID)
        let scope = "exemption:update:\(applicationID)"
        let fingerprint = try IntentFingerprint.make(body)
        let response: APIResponse<APIV1ExemptionApplication> = try await auth.sendAuthorized(APIRequest(
            operationID: "updateExemptionApplication",
            method: .patch,
            path: "exemption-applications/\(applicationID)",
            body: try APIRequest.jsonBody(body),
            idempotencyKey: await intents.key(scope: scope, fingerprint: fingerprint)
        ))
        await intents.clear(scope: scope)
        return response
    }

    func submit(
        applicationID: String,
        expectedVersion: Int
    ) async throws -> APIResponse<APIV1ExemptionApplication> {
        let applicationID = try APIPath.component(applicationID)
        let body = APIV1VersionedRequest(expectedVersion: expectedVersion)
        let scope = "exemption:submit:\(applicationID)"
        let fingerprint = try IntentFingerprint.make(body)
        let response: APIResponse<APIV1ExemptionApplication> = try await auth.sendAuthorized(APIRequest(
            operationID: "submitExemptionApplication",
            method: .post,
            path: "exemption-applications/\(applicationID)/submit",
            body: try APIRequest.jsonBody(body),
            idempotencyKey: await intents.key(scope: scope, fingerprint: fingerprint)
        ))
        await intents.clear(scope: scope)
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
        guard enrollments.value.allSatisfy({ $0.studentId == studentID }) else {
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
        let effectiveIdempotencyKeySeed: String?
        let requiresBinding: Bool
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

        if !confirmedUpload.requiresBinding {
            await intents.clear(scope: confirmedUpload.initiateScope)
            await intents.clear(scope: confirmedUpload.confirmScope)
            return MediaUploadOutcome(media: confirmed.value, requestId: confirmed.requestId)
        }

        let mediaID = try APIPath.component(confirmed.value.id)
        let bind = APIV1BindMediaRequest(
            sessionId: sessionID,
            expectedVersion: confirmed.value.version
        )
        let bindScope = "media:bind:\(mediaID)"
        let bound: APIResponse<APIV1MediaEvidence> = try await pipelinePhase("BIND") {
            try await auth.sendAuthorized(APIRequest(
                operationID: "bindMediaEvidence",
                method: .post,
                path: "media/\(mediaID)/bind",
                body: try APIRequest.jsonBody(bind),
                idempotencyKey: try await idempotencyKey(
                    seed: confirmedUpload.effectiveIdempotencyKeySeed,
                    phase: "bind",
                    scope: bindScope,
                    fingerprint: IntentFingerprint.make(bind)
                )
            ))
        }
        guard bound.value.id == confirmed.value.id else {
            throw MediaUploadPipelineError.bindingProjectionMismatch(
                field: "media_id",
                requestId: bound.requestId
            )
        }
        guard bound.value.ownerStudentId == confirmed.value.ownerStudentId else {
            throw MediaUploadPipelineError.bindingProjectionMismatch(
                field: "owner_student_id",
                requestId: bound.requestId
            )
        }
        guard bound.value.sessionId == sessionID else {
            throw MediaUploadPipelineError.bindingProjectionMismatch(
                field: "session_id",
                requestId: bound.requestId
            )
        }
        guard bound.value.businessPurpose == request.businessPurpose else {
            throw MediaUploadPipelineError.bindingProjectionMismatch(
                field: "business_purpose",
                requestId: bound.requestId
            )
        }
        guard bound.value.mediaType == request.mediaType else {
            throw MediaUploadPipelineError.bindingProjectionMismatch(
                field: "media_type",
                requestId: bound.requestId
            )
        }
        guard bound.value.captureSource.rawValue == request.captureSource.rawValue else {
            throw MediaUploadPipelineError.bindingProjectionMismatch(
                field: "capture_source",
                requestId: bound.requestId
            )
        }
        guard bound.value.uploadStatus == .bound ||
                bound.value.uploadStatus == .processing ||
                bound.value.uploadStatus == .available else {
            throw MediaUploadPipelineError.bindingProjectionMismatch(
                field: "upload_status",
                requestId: bound.requestId
            )
        }
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

    func uploadForExemption(
        fileURL: URL,
        request: APIV1InitiateMediaUploadRequest,
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void = { _ in }
    ) async throws -> MediaUploadOutcome {
        guard MediaUploadContractPolicy.accepts(request),
              request.businessPurpose == .exemptionApplication else {
            throw APITransportError.invalidRequest
        }

        let confirmedUpload = try await uploadAndConfirm(
            payload: .file(fileURL),
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
        var effectiveSeed = idempotencyKeySeed
        var initiated = try await initiateUpload(
            request,
            seed: effectiveSeed,
            scope: initiateScope
        )
        var renewalCount = 0
        while Self.uploadCapabilityIsExpired(initiated.value.expiresAt) {
            if let recovered = try await recoverExpiredUpload(
                initiated,
                request: request,
                initiateScope: initiateScope,
                effectiveSeed: effectiveSeed
            ) {
                return recovered
            }
            guard renewalCount < 2 else {
                throw MediaUploadPipelineError.uploadCapabilityRecoveryFailed(
                    requestId: initiated.requestId
                )
            }
            effectiveSeed = Self.renewalSeed(
                previousSeed: effectiveSeed,
                expiredUploadSessionID: initiated.value.uploadSessionId
            )
            initiated = try await initiateUpload(
                request,
                seed: effectiveSeed,
                scope: initiateScope
            )
            renewalCount += 1
        }

        guard let uploadURL = URL(string: initiated.value.uploadUrl),
              let uploadMethod = HTTPMethod(rawValue: initiated.value.uploadMethod),
              uploadMethod == .put else {
            throw MediaUploadPipelineError.invalidUploadCapability(
                requestId: initiated.requestId
            )
        }
        let uploadResponse: HTTPURLResponse
        do {
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
        } catch let error as SignedUploadHTTPFailure {
            throw MediaUploadPipelineError.signedUploadRejected(
                statusCode: error.statusCode,
                providerCode: error.providerCode
            )
        } catch let error as APITransportError {
            switch error {
            case .invalidResponse:
                throw MediaUploadPipelineError.transportInvalidResponse(phase: "SIGNED_PUT")
            case .undecodableFailure(let statusCode, _):
                throw MediaUploadPipelineError.signedUploadRejected(
                    statusCode: statusCode,
                    providerCode: nil
                )
            case .invalidRequest, .malformedSuccessEnvelope, .requestIdMismatch, .failure, .network:
                throw error
            }
        }
        guard let etag = uploadResponse.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else {
            throw MediaUploadPipelineError.missingUploadEntityTag
        }

        let uploadSessionID = try APIPath.component(initiated.value.uploadSessionId)
        let confirm = APIV1ConfirmMediaUploadRequest(etag: etag)
        let confirmScope = "media:confirm:\(uploadSessionID)"
        let confirmed: APIResponse<APIV1MediaEvidence> = try await pipelinePhase("CONFIRM") {
            try await auth.sendAuthorized(APIRequest(
                operationID: "confirmMediaUpload",
                method: .post,
                path: "media-uploads/\(uploadSessionID)/confirm",
                body: try APIRequest.jsonBody(confirm),
                idempotencyKey: try await idempotencyKey(
                    seed: effectiveSeed,
                    phase: "confirm",
                    scope: confirmScope,
                    fingerprint: IntentFingerprint.make(confirm)
                )
            ))
        }
        guard confirmed.value.id == initiated.value.mediaId else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "media_id",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.businessPurpose == request.businessPurpose else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "business_purpose",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.sessionId == request.sessionId else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "session_id",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.enrollmentId == request.enrollmentId else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "enrollment_id",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.captureSource.rawValue == request.captureSource.rawValue else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "capture_source",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.mediaType == request.mediaType else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "media_type",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.declaredMimeType.lowercased() == request.mimeType.lowercased() else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "declared_mime_type",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.declaredFileSizeBytes == request.fileSizeBytes else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "declared_file_size",
                requestId: confirmed.requestId
            )
        }
        guard confirmed.value.uploadStatus == .uploaded else {
            throw MediaUploadPipelineError.confirmationProjectionMismatch(
                field: "upload_status",
                requestId: confirmed.requestId
            )
        }

        return ConfirmedUpload(
            response: confirmed,
            initiateScope: initiateScope,
            confirmScope: confirmScope,
            effectiveIdempotencyKeySeed: effectiveSeed,
            requiresBinding: true
        )
    }

    private func initiateUpload(
        _ request: APIV1InitiateMediaUploadRequest,
        seed: String?,
        scope: String
    ) async throws -> APIResponse<APIV1MediaUploadSession> {
        let key = try await idempotencyKey(
            seed: seed,
            phase: "initiate",
            scope: scope,
            fingerprint: IntentFingerprint.make(request)
        )
        return try await pipelinePhase("INITIATE") {
            try await auth.sendAuthorized(APIRequest(
                operationID: "initiateMediaUpload",
                method: .post,
                path: "media-uploads",
                body: try APIRequest.jsonBody(request),
                idempotencyKey: key
            ))
        }
    }

    private func recoverExpiredUpload(
        _ initiated: APIResponse<APIV1MediaUploadSession>,
        request: APIV1InitiateMediaUploadRequest,
        initiateScope: String,
        effectiveSeed: String?
    ) async throws -> ConfirmedUpload? {
        let media: APIResponse<APIV1MediaEvidence>
        do {
            media = try await status(mediaID: initiated.value.mediaId)
        } catch let error as APITransportError {
            if error.statusCode == 404 { return nil }
            throw error
        }
        try validateRecoveredMedia(media, initiated: initiated, request: request)
        let confirmScope = "media:confirm:\(initiated.value.uploadSessionId)"
        switch media.value.uploadStatus {
        case .uploaded:
            return ConfirmedUpload(
                response: media,
                initiateScope: initiateScope,
                confirmScope: confirmScope,
                effectiveIdempotencyKeySeed: effectiveSeed,
                requiresBinding: true
            )
        case .bound, .processing, .available:
            return ConfirmedUpload(
                response: media,
                initiateScope: initiateScope,
                confirmScope: confirmScope,
                effectiveIdempotencyKeySeed: effectiveSeed,
                requiresBinding: false
            )
        case .pendingUpload, .failed, .deleted:
            return nil
        }
    }

    private func validateRecoveredMedia(
        _ media: APIResponse<APIV1MediaEvidence>,
        initiated: APIResponse<APIV1MediaUploadSession>,
        request: APIV1InitiateMediaUploadRequest
    ) throws {
        let checks: [(Bool, String)] = [
            (media.value.id == initiated.value.mediaId, "media_id"),
            (media.value.sessionId == request.sessionId, "session_id"),
            (media.value.enrollmentId == request.enrollmentId, "enrollment_id"),
            (media.value.businessPurpose == request.businessPurpose, "business_purpose"),
            (media.value.mediaType == request.mediaType, "media_type"),
            (media.value.captureSource.rawValue == request.captureSource.rawValue, "capture_source")
        ]
        if let failed = checks.first(where: { !$0.0 }) {
            throw MediaUploadPipelineError.statusProjectionMismatch(
                field: failed.1,
                requestId: media.requestId
            )
        }
    }

    private func pipelinePhase<Value>(
        _ phase: String,
        operation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch let error as APITransportError {
            if case .invalidResponse = error {
                throw MediaUploadPipelineError.transportInvalidResponse(phase: phase)
            }
            throw error
        }
    }

    private static func uploadCapabilityIsExpired(_ value: String, now: Date = Date()) -> Bool {
        guard let expiry = StudentRecordTimeDisplay.instant(from: value) else { return true }
        return expiry <= now.addingTimeInterval(5)
    }

    private static func renewalSeed(
        previousSeed: String?,
        expiredUploadSessionID: String
    ) -> String {
        let material = "\(previousSeed ?? "unseeded"):\(expiredUploadSessionID)"
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "ios-media-renew-\(digest)"
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

    /// Lists the authenticated student's server-owned record projections. The
    /// backend applies student scope; the client still verifies ownership
    /// before publishing any item into the local workspace.
    func listOwned(limit: Int = 100) async throws -> APIResponse<[APIV1ExerciseRecord]> {
        guard (1...100).contains(limit) else {
            throw APITransportError.invalidRequest
        }
        return try await auth.sendAuthorized(APIRequest(
            operationID: "listExerciseRecords",
            method: .get,
            path: "exercise-records",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: "-businessDate")
            ]
        ))
    }

    func evidenceContext(
        recordID: String
    ) async throws -> APIResponse<APIV1ExerciseRecordEvidenceContext> {
        let recordID = try APIPath.component(recordID)
        return try await auth.sendAuthorized(APIRequest(
            operationID: "getExerciseRecordEvidenceContext",
            method: .get,
            path: "exercise-records/\(recordID)/evidence-context"
        ))
    }

    /// Recovers the one record (draft or submitted) owned by a completed
    /// session. Contract 2.0.2 has no direct sessionId filter, so the query is
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

    func discard(
        recordID: String,
        request: APIV1VersionedReasonRequest
    ) async throws -> APIResponse<APIV1ExerciseRecord> {
        guard !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.expectedVersion > 0 else {
            throw APITransportError.invalidRequest
        }
        let recordID = try APIPath.component(recordID)
        return try await mutate(
            operationID: "discardExerciseRecord",
            path: "exercise-records/\(recordID)/discard",
            scope: "exercise-record:discard:\(recordID)",
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
