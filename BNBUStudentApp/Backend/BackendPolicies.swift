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

/// The 1.1 contract does not publish IOS as a legal platform value for these
/// routes. The client must wait for a contract revision instead of pretending
/// to be ANDROID or WEB.
enum IOSPlatformContractPolicy {
    static func isRepresentable(_ capability: APIV1DefaultDeniedClientCapability) -> Bool {
        switch capability {
        case .registerPushDevice, .unregisterPushDevice, .getAppReleasePolicy:
            return false
        default:
            return true
        }
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
