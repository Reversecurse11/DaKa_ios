import CryptoKit
import Foundation

protocol AuthSessionPersisting: Sendable {
    func load() throws -> APIV1AuthSession?
    func save(_ session: APIV1AuthSession) throws
    func clear() throws
}

struct KeychainAuthSessionStore: AuthSessionPersisting, @unchecked Sendable {
    private let credentialStore: any SecureCredentialStoring
    private let storageKey: String

    init(
        environment: BackendEnvironment,
        credentialStore: any SecureCredentialStoring = KeychainCredentialStore()
    ) {
        self.credentialStore = credentialStore
        let digest = SHA256.hash(data: Data(environment.baseURL.absoluteString.utf8))
        storageKey = "bnbu.auth.session.v1." + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func load() throws -> APIV1AuthSession? {
        guard let data = try credentialStore.data(forKey: storageKey) else { return nil }
        return try JSONDecoder().decode(APIV1AuthSession.self, from: data)
    }

    func save(_ session: APIV1AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        try credentialStore.set(data, forKey: storageKey)
    }

    func clear() throws {
        try credentialStore.removeData(forKey: storageKey)
    }
}

actor IdempotencyIntentRegistry {
    private struct Entry {
        let fingerprint: String
        let key: String
    }

    private var entries: [String: Entry] = [:]

    func key(scope: String, fingerprint: String) -> String {
        if let existing = entries[scope], existing.fingerprint == fingerprint {
            return existing.key
        }
        let key = IdempotencyKeyPolicy.make()
        entries[scope] = Entry(fingerprint: fingerprint, key: key)
        return key
    }

    func clear(scope: String) {
        entries.removeValue(forKey: scope)
    }

    func clearAll() {
        entries.removeAll()
    }
}

enum IntentFingerprint {
    static func make<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(value))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum AuthSessionState: Equatable {
    case signedOut
    case authenticated(APIV1AuthSession)
}

actor BackendAuthSessionController {
    private let client: StudentAPIClient
    private let store: any AuthSessionPersisting
    private let intents: IdempotencyIntentRegistry
    private var session: APIV1AuthSession?
    private var refreshTask: Task<APIV1AuthSession, Error>?
    private var refreshIntent: (fingerprint: String, key: String)?

    init(
        client: StudentAPIClient,
        store: any AuthSessionPersisting,
        intents: IdempotencyIntentRegistry = IdempotencyIntentRegistry()
    ) {
        self.client = client
        self.store = store
        self.intents = intents
    }

    func state() -> AuthSessionState {
        session.map(AuthSessionState.authenticated) ?? .signedOut
    }

    func requestStudentSignInCode(
        _ request: APIV1StudentSignInCodeRequest
    ) async throws -> APIResponse<APIV1StudentSignInCodeAccepted> {
        let scope = "auth:student-sign-in-code:request"
        let response: APIResponse<APIV1StudentSignInCodeAccepted> = try await client.send(APIRequest(
            operationID: "requestStudentSignInCode",
            method: .post,
            path: "auth/student-sign-in-codes",
            body: try APIRequest.jsonBody(request),
            idempotencyKey: await intents.key(
                scope: scope,
                fingerprint: try IntentFingerprint.make(request)
            )
        ))
        await intents.clear(scope: scope)
        return response
    }

    func verifyStudentSignInCode(
        _ request: APIV1StudentSignInCodeVerificationRequest
    ) async throws -> APIResponse<APIV1AuthSession> {
        let challengeID = try APIPath.component(request.challengeId)
        let scope = "auth:student-sign-in-code:verify:\(challengeID)"
        let response: APIResponse<APIV1AuthSession> = try await client.send(APIRequest(
            operationID: "verifyStudentSignInCode",
            method: .post,
            path: "auth/student-sign-in-codes/verify",
            body: try APIRequest.jsonBody(request),
            idempotencyKey: await intents.key(
                scope: scope,
                fingerprint: try IntentFingerprint.make(request)
            )
        ))
        try install(response.value)
        await intents.clear(scope: scope)
        return response
    }

    func requestCurrentUserEmailChallenge(
        _ request: APIV1EmailVerificationChallengeRequest
    ) async throws -> APIResponse<APIV1EmailVerificationChallengeAccepted> {
        let scope = "me:email-verification:request"
        let response: APIResponse<APIV1EmailVerificationChallengeAccepted> = try await sendAuthorized(APIRequest(
            operationID: "requestCurrentUserEmailChallenge",
            method: .post,
            path: "me/email-verification-challenges",
            body: try APIRequest.jsonBody(request),
            idempotencyKey: await intents.key(
                scope: scope,
                fingerprint: try IntentFingerprint.make(request)
            )
        ))
        await intents.clear(scope: scope)
        return response
    }

    func verifyCurrentUserEmailChallenge(
        challengeID: String,
        request: APIV1VerifyEmailChallengeRequest
    ) async throws -> APIResponse<APIV1CurrentUserData> {
        let challengeID = try APIPath.component(challengeID)
        let scope = "me:email-verification:verify:\(challengeID)"
        let response: APIResponse<APIV1CurrentUserData> = try await sendAuthorized(APIRequest(
            operationID: "verifyCurrentUserEmailChallenge",
            method: .post,
            path: "me/email-verification-challenges/\(challengeID)/verify",
            body: try APIRequest.jsonBody(request),
            idempotencyKey: await intents.key(
                scope: scope,
                fingerprint: try IntentFingerprint.make(request)
            )
        ))
        await intents.clear(scope: scope)
        return response
    }

    @discardableResult
    func restore(now: Date = Date()) async throws -> AuthSessionState {
        guard let restored = try store.load() else {
            session = nil
            return .signedOut
        }
        session = restored
        if Self.isExpired(restored.refreshTokenExpiresAt, now: now) {
            try clearLocalSession()
            return .signedOut
        }
        if Self.isExpired(restored.accessTokenExpiresAt, now: now) {
            _ = try await refresh()
        }
        return session.map(AuthSessionState.authenticated) ?? .signedOut
    }

    func previewCourseInvite(inviteToken: String) async throws -> APIResponse<APIV1CourseInvitePreview> {
        let token = try APIPath.component(inviteToken)
        return try await client.send(APIRequest(
            operationID: "previewCourseInvite",
            method: .get,
            path: "course-invites/\(token)/preview"
        ))
    }

    func issueJoinCapability(
        inviteToken: String,
        profile: APIV1IssueJoinCapabilityRequest
    ) async throws -> APIResponse<APIV1JoinCapabilityTransport> {
        let token = try APIPath.component(inviteToken)
        let scope = "join-capability:\(token)"
        let key = await intents.key(scope: scope, fingerprint: try IntentFingerprint.make(profile))
        return try await client.send(APIRequest(
            operationID: "issueJoinCapability",
            method: .post,
            path: "course-invites/\(token)/join-capabilities",
            body: try APIRequest.jsonBody(profile),
            idempotencyKey: key
        ))
    }

    func joinClassSection(
        inviteToken: String,
        capability: String
    ) async throws -> APIResponse<APIV1JoinResult> {
        let token = try APIPath.component(inviteToken)
        let scope = "join:\(token)"
        let fingerprint = SHA256.hash(data: Data(capability.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = await intents.key(scope: scope, fingerprint: fingerprint)
        let response: APIResponse<APIV1JoinResult> = try await client.send(APIRequest(
            operationID: "joinClassSectionWithInvite",
            method: .post,
            path: "course-invites/\(token)/join",
            authorization: .joinCapability(capability),
            idempotencyKey: key
        ))
        try install(response.value.authSession)
        await intents.clear(scope: scope)
        return response
    }

    func sendAuthorized<Value: Decodable & Equatable>(
        _ request: APIRequest,
        as type: Value.Type = Value.self
    ) async throws -> APIResponse<Value> {
        guard let current = try (session ?? store.load()) else {
            throw APITransportError.failure(
                statusCode: 401,
                envelope: APIErrorEnvelope(
                    code: "AUTH_REQUIRED",
                    message: "Authentication is required.",
                    details: .object([:]),
                    requestId: "local-auth-required",
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
            )
        }
        session = current
        var authorized = request
        authorized.authorization = .bearer(current.accessToken)
        do {
            return try await client.send(authorized, as: type)
        } catch let error as APITransportError where Self.isUnauthorized(error) {
            // Another request may have completed the shared refresh while this request
            // was in flight. Reuse that rotation instead of issuing a second refresh.
            if let active = session, active.accessToken != current.accessToken {
                authorized.authorization = .bearer(active.accessToken)
            } else {
                let rotated = try await refresh()
                authorized.authorization = .bearer(rotated.accessToken)
            }
            return try await client.send(authorized, as: type)
        }
    }

    @discardableResult
    func refresh() async throws -> APIV1AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let current = try (session ?? store.load()) else {
            throw APITransportError.invalidRequest
        }
        session = current
        let requestBody = APIV1RefreshRequest(refreshToken: current.refreshToken)
        let scope = "auth:refresh:\(current.sessionId ?? current.user.id)"
        let fingerprint = try IntentFingerprint.make(requestBody)
        let key: String
        if let refreshIntent, refreshIntent.fingerprint == fingerprint {
            key = refreshIntent.key
        } else {
            key = IdempotencyKeyPolicy.make()
            refreshIntent = (fingerprint, key)
        }
        let client = self.client
        let task = Task<APIV1AuthSession, Error> {
            let response: APIResponse<APIV1AuthSession> = try await client.send(APIRequest(
                operationID: "refreshSession",
                method: .post,
                path: "auth/refresh",
                body: try APIRequest.jsonBody(requestBody),
                idempotencyKey: key
            ))
            return response.value
        }
        refreshTask = task
        do {
            let rotated = try await task.value
            refreshTask = nil
            try install(rotated)
            refreshIntent = nil
            await intents.clear(scope: scope)
            return rotated
        } catch {
            refreshTask = nil
            if let transportError = error as? APITransportError,
               Self.invalidatesTokenFamily(transportError) {
                try? clearLocalSession()
                await intents.clearAll()
            }
            throw error
        }
    }

    func logout() async throws {
        guard let current = try (session ?? store.load()) else {
            try clearLocalSession()
            return
        }
        let body = APIV1LogoutRequest(refreshToken: current.refreshToken)
        let scope = "auth:logout:\(current.sessionId ?? current.user.id)"
        let key = await intents.key(scope: scope, fingerprint: try IntentFingerprint.make(body))
        do {
            let _: APIResponse<APIV1JSONValue> = try await client.send(APIRequest(
                operationID: "logoutSession",
                method: .post,
                path: "auth/logout",
                body: try APIRequest.jsonBody(body),
                authorization: .bearer(current.accessToken),
                idempotencyKey: key
            ))
            try clearLocalSession()
        } catch {
            // A failed revoke must not leave a locally refreshable pseudo-session.
            try? clearLocalSession()
            await intents.clearAll()
            throw error
        }
        await intents.clearAll()
    }

    private func install(_ newSession: APIV1AuthSession) throws {
        guard !newSession.accessToken.isEmpty, !newSession.refreshToken.isEmpty else {
            throw APITransportError.invalidResponse
        }
        try store.save(newSession)
        session = newSession
    }

    private func clearLocalSession() throws {
        session = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshIntent = nil
        try store.clear()
    }

    private static func isExpired(_ value: String, now: Date) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date.map { $0 <= now } ?? true
    }

    private static func isUnauthorized(_ error: APITransportError) -> Bool {
        error.statusCode == 401
    }

    private static func invalidatesTokenFamily(_ error: APITransportError) -> Bool {
        guard case .failure(let statusCode, let envelope) = error else { return statusCodeIsUnauthorized(error) }
        return statusCode == 401 || [
            "AUTH_TOKEN_INVALID",
            "AUTH_TOKEN_EXPIRED",
            "AUTH_SESSION_REVOKED"
        ].contains(envelope.code)
    }

    private static func statusCodeIsUnauthorized(_ error: APITransportError) -> Bool {
        error.statusCode == 401
    }
}
