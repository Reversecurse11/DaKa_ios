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

enum ExportAvailabilityPolicy {
    static func unavailableState(from error: APITransportError) -> ExportUnavailableState? {
        guard case .failure(503, let envelope) = error,
              envelope.code == "SYSTEM_MODE_UNSUPPORTED" else {
            return nil
        }
        return ExportUnavailableState(
            message: "该功能尚未开放。",
            requestId: envelope.requestId
        )
    }
}

enum SensitiveLoggingPolicy {
    private static let forbiddenNames: Set<String> = [
        "authorization", "cookie", "password", "accesstoken", "refreshtoken",
        "joincapability", "studentnumber", "email", "phone", "storagekey",
        "uploadurl", "accessurl", "downloadurl", "body", "media"
    ]

    static func isAllowed(metadata: [String: String]) -> Bool {
        metadata.allSatisfy { key, value in
            !forbiddenNames.contains(key.lowercased()) &&
                !value.lowercased().contains("bearer ") &&
                !value.lowercased().contains("x-amz-signature=") &&
                !value.lowercased().contains("x-cos-signature=")
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
