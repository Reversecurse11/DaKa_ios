import Foundation

struct VersionedMutationContext: Equatable {
    let expectedVersion: Int
    let expectedReviewVersion: Int?

    init(expectedVersion: Int, expectedReviewVersion: Int? = nil) {
        self.expectedVersion = expectedVersion
        self.expectedReviewVersion = expectedReviewVersion
    }
}
enum VersionConflictResolution: Equatable {
    case refreshAndRequireConfirmation(requestId: String)
    case notAVersionConflict
}

enum VersionConflictPolicy {
    static func resolution(for error: APITransportError) -> VersionConflictResolution {
        guard case .failure(409, let envelope) = error,
              envelope.code == "CONFLICT_VERSION_MISMATCH" || envelope.code == "SCORE_INPUT_VERSION_CONFLICT" else {
            return .notAVersionConflict
        }
        return .refreshAndRequireConfirmation(requestId: envelope.requestId)
    }
}

struct CursorQueryContext: Hashable {
    let accountID: String
    let operationID: String
    let filterFingerprint: String
}

struct OpaqueCursor: Equatable {
    private let rawValue: String
    private let context: CursorQueryContext

    init(serverValue: String, context: CursorQueryContext) throws {
        guard !serverValue.isEmpty, serverValue.utf8.count <= 2_048 else {
            throw APITransportError.invalidResponse
        }
        rawValue = serverValue
        self.context = context
    }

    func value(for requestedContext: CursorQueryContext) -> String? {
        requestedContext == context ? rawValue : nil
    }
}

struct PublishedScoreProjection: Equatable {
    let id: String
    let finalScore: Decimal
    let status: APIV1ScoreStatus
    let publishedAt: String

    init?(_ score: APIV1StudentScore) {
        guard score.status == .published,
              let finalScore = score.finalScore,
              let publishedAt = score.publishedAt else {
            return nil
        }
        id = score.id
        self.finalScore = finalScore
        status = score.status
        self.publishedAt = publishedAt
    }
}

struct ExportUnavailableState: Equatable {
    let message: String
    let requestId: String
}

struct DefaultDeniedCapabilityState: Equatable {
    let operationID: String
    let message: String
    let requestId: String
}

enum DefaultDeniedCapabilityPolicy {
    static func unavailableState(
        forSystemModeOperation operation: APIV1SystemModeUnsupportedOperation,
        from error: APITransportError
    ) -> DefaultDeniedCapabilityState? {
        unavailableState(operationID: operation.rawValue, from: error)
    }

    static func unavailableState(
        for capability: APIV1DefaultDeniedClientCapability,
        from error: APITransportError
    ) -> DefaultDeniedCapabilityState? {
        unavailableState(operationID: capability.rawValue, from: error)
    }

    static func unavailableState(
        operationID: String,
        from error: APITransportError
    ) -> DefaultDeniedCapabilityState? {
        guard case .failure(503, let envelope) = error,
              envelope.code == "SYSTEM_MODE_UNSUPPORTED" else {
            return nil
        }
        return DefaultDeniedCapabilityState(
            operationID: operationID,
            message: "该功能尚未开放。",
            requestId: envelope.requestId
        )
    }
}

enum ExportAvailabilityPolicy {
    static func unavailableState(from error: APITransportError) -> ExportUnavailableState? {
        guard let state = DefaultDeniedCapabilityPolicy.unavailableState(
            operationID: "export",
            from: error
        ) else {
            return nil
        }
        return ExportUnavailableState(
            message: state.message,
            requestId: state.requestId
        )
    }
}

/// OpenAPI 1.4 publishes IOS as the truthful wire value on every platform-
/// bearing client-capability route. This says nothing about remote readiness.
enum IOSPlatformContractPolicy {
    static let wireValue = "IOS"

    static func supportsIOS(_ capability: APIV1ClientCapability) -> Bool {
        switch capability {
        case .registerPushDevice, .unregisterPushDevice, .getAppReleasePolicy, .createFeedback:
            return true
        default:
            return false
        }
    }
}

/// A local-integration report is weaker than a deployable Staging capability.
/// Keep the two states distinct so client code cannot treat the 22 routes as
/// remotely available merely because their default-deny markers were removed.
enum ClientCapabilityReadinessPolicy {
    static let stagingExecutionReady = false

    static func hasLocalIntegrationEvidence(_ capability: APIV1ClientCapability) -> Bool {
        APIV1LocalIntegrationClientCapability.allCases.contains { $0.rawValue == capability.rawValue }
    }

    static func isExplicitlyDefaultDenied(_ capability: APIV1ClientCapability) -> Bool {
        APIV1DefaultDeniedClientCapability.allCases.contains { $0.rawValue == capability.rawValue }
    }
}

/// Contract 1.4 keeps three score sort strings only for 1.3 wire
/// compatibility. Their runtime order is fixed, so new clients always omit
/// those parameters instead of suggesting that the value has an effect.
enum RuntimeQueryContractPolicy {
    static func mustOmit(_ parameter: APIV1RuntimeUnsupportedQueryParameter) -> Bool {
        switch parameter {
        case .listScoreAdjustmentsSort, .listScoreRulesSort, .listStudentScoresSort:
            return true
        }
    }

    static func studentScoreQueryItems(status: APIV1ScoreStatus?) -> [URLQueryItem] {
        status.map { [URLQueryItem(name: "status", value: $0.rawValue)] } ?? []
    }
}

/// Stable, student-facing denials returned while creating an authoritative
/// exercise session. The server remains the final judge: qualification is
/// calculated from each record's latest VALID review, and window eligibility
/// is evaluated in Asia/Shanghai when the start request reaches the backend.
enum ExerciseSessionAdmissionError: Error, LocalizedError, Equatable {
    case qualificationReached(requestId: String)
    case outsideBeijingWindow(requestId: String)

    var errorDescription: String? {
        switch self {
        case .qualificationReached:
            return "已达到合格时长，无需继续打卡。"
        case .outsideBeijingWindow:
            return "当前不在每日打卡开放时段（北京时间 06:00–22:00），暂时不能开始运动。"
        }
    }
}

enum ExerciseSessionAdmissionPolicy {
    static func startError(from error: APITransportError) -> ExerciseSessionAdmissionError? {
        guard case .failure(409, let envelope) = error else { return nil }
        switch envelope.knownCode {
        case .sessionAlreadyCompleted:
            return .qualificationReached(requestId: envelope.requestId)
        case .sessionOutsideTimeWindow, .courseCheckinWindowClosed:
            return .outsideBeijingWindow(requestId: envelope.requestId)
        default:
            return nil
        }
    }
}

/// The generator intentionally emits a simple Swift struct for OpenAPI oneOf.
/// Enforce the media-purpose scope and capture-source branches before transport.
enum MediaUploadContractPolicy {
    static func accepts(_ request: APIV1InitiateMediaUploadRequest) -> Bool {
        guard request.fileSizeBytes > 0,
              !request.mimeType.isEmpty,
              acceptsDuration(mediaType: request.mediaType, durationSeconds: request.durationSeconds) else {
            return false
        }

        switch request.businessPurpose {
        case .exerciseRecord:
            return hasValue(request.sessionId) &&
                request.enrollmentId == nil &&
                request.captureSource == .inAppCamera
        case .exemptionApplication:
            return request.sessionId == nil &&
                hasValue(request.enrollmentId) &&
                (request.captureSource == .inAppCamera || request.captureSource == .filePicker)
        }
    }

    private static func acceptsDuration(mediaType: APIV1MediaType, durationSeconds: Int?) -> Bool {
        switch mediaType {
        case .image:
            return durationSeconds == nil
        case .video:
            return durationSeconds.map { $0 > 0 } == true
        }
    }

    private static func hasValue(_ value: String?) -> Bool {
        value.map { !$0.isEmpty } == true
    }
}

struct IOSAppReleasePolicyQuery: Equatable {
    let platform = IOSPlatformContractPolicy.wireValue
    let currentVersion: String?
    let currentBuildNumber: Int

    init?(infoDictionary: [String: Any]) {
        guard let rawBuildNumber = infoDictionary["CFBundleVersion"] as? String,
              let buildNumber = Int(rawBuildNumber),
              (1...Int(Int32.max)).contains(buildNumber) else {
            return nil
        }
        let version = infoDictionary["CFBundleShortVersionString"] as? String
        currentVersion = version.flatMap { $0.isEmpty ? nil : $0 }
        currentBuildNumber = buildNumber
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "currentBuildNumber", value: String(currentBuildNumber))
        ]
        if let currentVersion {
            items.append(URLQueryItem(name: "currentVersion", value: currentVersion))
        }
        return items
    }
}

enum IOSAppReleaseContractPolicy {
    static func accepts(_ policy: APIV1AppReleasePolicy) -> Bool {
        guard policy.platform == IOSPlatformContractPolicy.wireValue,
              let minimum = policy.minimumSupportedBuildNumber,
              let latest = policy.latestBuildNumber,
              (1...Int(Int32.max)).contains(minimum),
              (1...Int(Int32.max)).contains(latest),
              minimum <= latest,
              ["NONE", "RECOMMENDED", "REQUIRED"].contains(policy.enforcement) else {
            return false
        }
        return true
    }
}

/// Future-proof gate for the six location operations. The current backend
/// cannot return an enabled policy, and missing governance values always deny.
enum LocationPrivacyGate {
    static func allowsCollection(
        policy: APIV1LocationPrivacyPolicy?,
        consentPolicyVersion: String?,
        at date: Date = Date()
    ) -> Bool {
        guard let policy,
              policy.collectionEnabled,
              policy.purposeCode == "EXERCISE_EVIDENCE",
              !policy.policyVersion.isEmpty,
              consentPolicyVersion == policy.policyVersion,
              let sampleIntervalSeconds = policy.sampleIntervalSeconds,
              sampleIntervalSeconds > 0,
              let maximumAccuracyMeters = policy.maximumAccuracyMeters,
              maximumAccuracyMeters > 0,
              let rawRetentionDays = policy.rawRetentionDays,
              rawRetentionDays >= 0,
              let coarseRetentionDays = policy.coarseRetentionDays,
              coarseRetentionDays >= 0,
              let coarseProjectionMeters = policy.coarseProjectionMeters,
              coarseProjectionMeters > 0,
              let effectiveAt = policy.effectiveAt,
              let effectiveDate = ISO8601DateFormatter().date(from: effectiveAt),
              effectiveDate <= date,
              policy.version > 0 else {
            return false
        }
        return true
    }
}

enum SensitiveLoggingPolicy {
    private static let forbiddenNames: Set<String> = [
        "authorization", "cookie", "password", "accesstoken", "refreshtoken",
        "joincapability", "studentnumber", "email", "phone", "storagekey",
        "uploadurl", "accessurl", "downloadurl", "body", "media", "location"
    ]
    private static let forbiddenNameFragments = [
        "latitude", "longitude", "coordinate", "accuracymeters", "altitudemeters",
        "speedmillimeterspersecond", "locationsample", "rawlocation", "polyline", "gps"
    ]
    private static let forbiddenValueFragments = [
        "\"latitude\"", "\"longitude\"", "\"coordinates\"", "\"samples\""
    ]

    static func isAllowed(metadata: [String: String]) -> Bool {
        metadata.allSatisfy { key, value in
            let normalizedKey = key.lowercased().filter(\.isLetter)
            let normalizedValue = value.lowercased()
            return !forbiddenNames.contains(normalizedKey) &&
                !forbiddenNameFragments.contains(where: normalizedKey.contains) &&
                !value.lowercased().contains("bearer ") &&
                !value.lowercased().contains("x-amz-signature=") &&
                !value.lowercased().contains("x-cos-signature=") &&
                !forbiddenValueFragments.contains(where: normalizedValue.contains)
        }
    }
}

enum FixturePolicy {
    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if BNBU_FIXTURES && DEBUG
        return arguments.contains(where: { $0.hasPrefix("-ui-testing-") })
        #else
        return false
        #endif
    }
}
