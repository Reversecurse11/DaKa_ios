import XCTest
@testable import BNBUStudent

final class BackendFoundationTests: XCTestCase {
    override func tearDown() {
        FoundationURLProtocol.reset()
        super.tearDown()
    }

    func testContractMetadataAndLocalEnvironmentArePinned() throws {
        XCTAssertEqual(
            APIV1ContractMetadata.sourceSHA256,
            "fb040b671e3f25c48279ad6b173ced5f633de1b1a1a9db0cc0f23a11e3fde4d1"
        )
        XCTAssertEqual(APIV1ContractMetadata.contractVersion, "1.1.0-contract")
        XCTAssertEqual(APIV1ContractMetadata.apiPrefix, "/api/v1")
        XCTAssertEqual(APIV1ContractMetadata.pathCount, 104)
        XCTAssertEqual(APIV1ContractMetadata.operationCount, 122)
        XCTAssertEqual(APIV1ContractMetadata.schemaCount, 271)
        XCTAssertEqual(APIV1ContractMetadata.defaultDeniedClientCapabilityCount, 30)
        XCTAssertEqual(APIV1DefaultDeniedClientCapability.allCases.count, 30)

        let local = try BackendEnvironment.resolve(
            arguments: ["BNBUStudent"],
            processEnvironment: ["BNBU_ENVIRONMENT": "local"],
            bundle: .main
        )
        XCTAssertEqual(local.baseURL.absoluteString, "http://127.0.0.1:3000/api/v1")
        XCTAssertFalse(BackendEnvironment.isAllowed(
            URL(string: "http://123.207.5.70:82/api/v1")!,
            for: .local
        ))
        XCTAssertFalse(BackendEnvironment.isAllowed(
            URL(string: "https://configuration-required.invalid/api/v1")!,
            for: .production
        ))
        XCTAssertTrue(BackendEnvironment.isAllowed(
            URL(string: "https://sports.example.edu/api/v1")!,
            for: .production
        ))
        XCTAssertThrowsError(try BackendEnvironment.resolve(
            arguments: ["BNBUStudent"],
            processEnvironment: ["BNBU_ENVIRONMENT": "typo"],
            bundle: .main
        )) { error in
            XCTAssertEqual(error as? BackendEnvironmentError, .invalidEnvironment("typo"))
        }
    }

    func testTransportDecodesTypedEnvelopeAndUsesServerRequestID() async throws {
        let logger = CapturingAPIEventLogger()
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/system-mode")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return .json(
                status: 200,
                headers: ["X-Request-ID": "req-contract-001"],
                body: #"{"data":{"mode":"NORMAL","policyVersion":1,"updatedAt":"2026-08-06T00:00:00Z"},"meta":{"requestId":"req-contract-001"}}"#
            )
        }
        let client = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: session,
            logger: logger,
            maximumSafeRetries: 0
        )

        let response: APIResponse<APIV1SystemModeProjection> = try await client.send(APIRequest(
            operationID: "getSystemMode",
            method: .get,
            path: "system-mode"
        ))

        XCTAssertEqual(response.value.mode, .normal)
        XCTAssertEqual(response.requestId, "req-contract-001")
        XCTAssertEqual(logger.events.last?.requestId, "req-contract-001")
        XCTAssertEqual(logger.events.last?.outcome, .succeeded)
    }

    func testTransportPreservesFiveFieldErrorAndUnknownCode() async throws {
        let session = makeSession { _ in
            .json(
                status: 409,
                headers: ["X-Request-ID": "req-error-409"],
                body: #"{"code":"FUTURE_SAFE_FAILURE","message":"Not available","details":{},"requestId":"req-error-409","timestamp":"2026-08-06T00:00:00Z"}"#
            )
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)

        do {
            let _: APIResponse<APIV1SystemModeProjection> = try await client.send(APIRequest(
                operationID: "getSystemMode",
                method: .get,
                path: "system-mode"
            ))
            XCTFail("Expected a structured error")
        } catch let error as APITransportError {
            guard case .failure(409, let envelope) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(envelope.code, "FUTURE_SAFE_FAILURE")
            XCTAssertNil(envelope.knownCode)
            XCTAssertEqual(envelope.requestId, "req-error-409")
            XCTAssertEqual(envelope.timestamp, "2026-08-06T00:00:00Z")
        }
    }

    func testSafeReadRetriesOnceButMutationDoesNotRetry() async throws {
        let lock = NSLock()
        var getCount = 0
        var postCount = 0
        let session = makeSession { request in
            lock.lock()
            defer { lock.unlock() }
            if request.httpMethod == "GET" {
                getCount += 1
                if getCount == 1 {
                    return .json(
                        status: 503,
                        headers: ["X-Request-ID": "req-retry-1"],
                        body: Self.errorJSON(code: "SYSTEM_SERVICE_UNAVAILABLE", requestID: "req-retry-1")
                    )
                }
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-retry-2"],
                    body: #"{"data":{"mode":"NORMAL","policyVersion":1,"updatedAt":"2026-08-06T00:00:00Z"},"meta":{"requestId":"req-retry-2"}}"#
                )
            }
            postCount += 1
            return .json(
                status: 503,
                headers: ["X-Request-ID": "req-post"],
                body: Self.errorJSON(code: "SYSTEM_SERVICE_UNAVAILABLE", requestID: "req-post")
            )
        }
        let client = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: session,
            maximumSafeRetries: 1
        )

        let _: APIResponse<APIV1SystemModeProjection> = try await client.send(APIRequest(
            operationID: "getSystemMode",
            method: .get,
            path: "system-mode"
        ))
        do {
            let _: APIResponse<APIV1SystemModeProjection> = try await client.send(APIRequest(
                operationID: "mutation",
                method: .post,
                path: "mutations",
                idempotencyKey: "ios-test-intent"
            ))
            XCTFail("Expected mutation failure")
        } catch {}

        XCTAssertEqual(getCount, 2)
        XCTAssertEqual(postCount, 1)
    }

    func testIdempotencyVersionCursorFixtureAndLoggingPolicies() async throws {
        let registry = IdempotencyIntentRegistry()
        let first = await registry.key(scope: "record:create", fingerprint: "input-a")
        let replay = await registry.key(scope: "record:create", fingerprint: "input-a")
        let changed = await registry.key(scope: "record:create", fingerprint: "input-b")
        XCTAssertEqual(first, replay)
        XCTAssertNotEqual(first, changed)
        XCTAssertTrue(StudentAPIClient.isValidIdempotencyKey(first))

        let conflict = APITransportError.failure(
            statusCode: 409,
            envelope: APIErrorEnvelope(
                code: "CONFLICT_VERSION_MISMATCH",
                message: "Refresh required",
                details: .object(["expectedVersion": .number(2), "actualVersion": .number(3)]),
                requestId: "req-version",
                timestamp: "2026-08-06T00:00:00Z"
            )
        )
        XCTAssertEqual(
            VersionConflictPolicy.resolution(for: conflict),
            .refreshAndRequireConfirmation(requestId: "req-version")
        )

        let context = CursorQueryContext(accountID: "student-a", operationID: "list", filterFingerprint: "f1")
        let cursor = try OpaqueCursor(serverValue: "opaque+/=cursor", context: context)
        XCTAssertEqual(cursor.value(for: context), "opaque+/=cursor")
        XCTAssertNil(cursor.value(for: CursorQueryContext(
            accountID: "student-b",
            operationID: "list",
            filterFingerprint: "f1"
        )))

        XCTAssertFalse(FixturePolicy.isEnabled(arguments: ["BNBUStudent"]))
        XCTAssertTrue(FixturePolicy.isEnabled(arguments: ["BNBUStudent", "-ui-testing-reset"]))
        XCTAssertTrue(SensitiveLoggingPolicy.isAllowed(metadata: [
            "operationId": "getSystemMode",
            "requestId": "req-safe",
            "errorCode": "SYSTEM_MODE_UNSUPPORTED"
        ]))
        XCTAssertFalse(SensitiveLoggingPolicy.isAllowed(metadata: ["accessToken": "secret"]))
        XCTAssertFalse(SensitiveLoggingPolicy.isAllowed(metadata: ["url": "https://x.test/a?X-Amz-Signature=secret"]))
        XCTAssertFalse(SensitiveLoggingPolicy.isAllowed(metadata: ["sampleLatitude": "22.35"]))
        XCTAssertFalse(SensitiveLoggingPolicy.isAllowed(metadata: ["payload": #"{"longitude":114.20}"#]))
        XCTAssertTrue(SensitiveLoggingPolicy.isAllowed(metadata: [
            "operationId": "getExerciseRecordLocationSummary",
            "requestId": "req-coarse-summary"
        ]))
    }

    func testDefaultDeniedCapabilitiesKeep503AndIOSPlatformBoundaries() {
        let error = APITransportError.failure(
            statusCode: 503,
            envelope: APIErrorEnvelope(
                code: "SYSTEM_MODE_UNSUPPORTED",
                message: "Unsupported",
                details: .object([:]),
                requestId: "req-capability-503",
                timestamp: "2026-08-06T00:00:00Z"
            )
        )

        XCTAssertEqual(
            DefaultDeniedCapabilityPolicy.unavailableState(for: .listNotifications, from: error),
            DefaultDeniedCapabilityState(
                operationID: "listNotifications",
                message: "该功能尚未开放。",
                requestId: "req-capability-503"
            )
        )
        XCTAssertEqual(
            DefaultDeniedCapabilityPolicy.unavailableState(for: .startExerciseLocationTrack, from: error)?.requestId,
            "req-capability-503"
        )
        XCTAssertFalse(IOSPlatformContractPolicy.isRepresentable(.registerPushDevice))
        XCTAssertFalse(IOSPlatformContractPolicy.isRepresentable(.unregisterPushDevice))
        XCTAssertFalse(IOSPlatformContractPolicy.isRepresentable(.getAppReleasePolicy))
        XCTAssertTrue(IOSPlatformContractPolicy.isRepresentable(.requestStudentSignInCode))
        XCTAssertTrue(IOSPlatformContractPolicy.isRepresentable(.createFeedback))
    }

    func testLocationPrivacyGateFailsClosedUntilEveryGovernanceValueIsApproved() {
        let now = ISO8601DateFormatter().date(from: "2026-08-06T01:00:00Z")!
        let enabledPolicy = APIV1LocationPrivacyPolicy(
            organizationId: "organization-1",
            policyVersion: "gps-policy-1",
            collectionEnabled: true,
            purposeCode: "EXERCISE_EVIDENCE",
            sampleIntervalSeconds: 10,
            maximumAccuracyMeters: 100,
            rawRetentionDays: 0,
            coarseRetentionDays: 30,
            coarseProjectionMeters: 500,
            effectiveAt: "2026-08-06T00:00:00Z",
            version: 1
        )

        XCTAssertFalse(LocationPrivacyGate.allowsCollection(
            policy: nil,
            consentPolicyVersion: nil,
            at: now
        ))
        XCTAssertFalse(LocationPrivacyGate.allowsCollection(
            policy: enabledPolicy,
            consentPolicyVersion: "different-policy",
            at: now
        ))
        XCTAssertTrue(LocationPrivacyGate.allowsCollection(
            policy: enabledPolicy,
            consentPolicyVersion: "gps-policy-1",
            at: now
        ))

        let unapprovedPolicy = APIV1LocationPrivacyPolicy(
            organizationId: "organization-1",
            policyVersion: "gps-policy-1",
            collectionEnabled: true,
            purposeCode: "EXERCISE_EVIDENCE",
            sampleIntervalSeconds: nil,
            maximumAccuracyMeters: nil,
            rawRetentionDays: nil,
            coarseRetentionDays: nil,
            coarseProjectionMeters: nil,
            effectiveAt: nil,
            version: 1
        )
        XCTAssertFalse(LocationPrivacyGate.allowsCollection(
            policy: unapprovedPolicy,
            consentPolicyVersion: "gps-policy-1",
            at: now
        ))
    }

    func testConcurrent401UsesOneRefreshRotationAndLogoutRevokesFirst() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "old-access", refresh: "old-refresh"))
        let lock = NSLock()
        var refreshCount = 0
        var logoutAuthorization: String?
        var logoutBody = ""
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/v1/protected":
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" {
                    return .json(
                        status: 200,
                        headers: ["X-Request-ID": "req-protected"],
                        body: #"{"data":{"mode":"NORMAL","policyVersion":1,"updatedAt":"2026-08-06T00:00:00Z"},"meta":{"requestId":"req-protected"}}"#
                    )
                }
                return .json(
                    status: 401,
                    headers: ["X-Request-ID": "req-401"],
                    body: Self.errorJSON(code: "AUTH_TOKEN_EXPIRED", requestID: "req-401")
                )
            case "/api/v1/auth/refresh":
                lock.lock()
                refreshCount += 1
                lock.unlock()
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-refresh"],
                    body: Self.authEnvelopeJSON(access: "new-access", refresh: "new-refresh", requestID: "req-refresh")
                )
            case "/api/v1/auth/logout":
                logoutAuthorization = request.value(forHTTPHeaderField: "Authorization")
                logoutBody = String(data: Self.bodyData(from: request), encoding: .utf8) ?? ""
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-logout"],
                    body: #"{"data":null,"meta":{"requestId":"req-logout"}}"#
                )
            default:
                return .json(status: 404, headers: ["X-Request-ID": "req-404"], body: Self.errorJSON(code: "USER_NOT_FOUND", requestID: "req-404"))
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session, maximumSafeRetries: 0)
        let controller = BackendAuthSessionController(client: client, store: store)
        _ = try await controller.restore()

        async let first: APIResponse<APIV1SystemModeProjection> = controller.sendAuthorized(APIRequest(
            operationID: "protectedOne",
            method: .get,
            path: "protected"
        ))
        async let second: APIResponse<APIV1SystemModeProjection> = controller.sendAuthorized(APIRequest(
            operationID: "protectedTwo",
            method: .get,
            path: "protected"
        ))
        _ = try await (first, second)

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(store.session?.accessToken, "new-access")
        XCTAssertEqual(store.session?.refreshToken, "new-refresh")

        try await controller.logout()
        XCTAssertEqual(logoutAuthorization, "Bearer new-access")
        XCTAssertTrue(logoutBody.contains("new-refresh"))
        XCTAssertNil(store.session)
        let signedOutState = await controller.state()
        XCTAssertEqual(signedOutState, .signedOut)
    }

    func testQRJoinUsesCapabilityHeaderAndInstallsRotatingSession() async throws {
        let store = MemoryAuthSessionStore()
        let lock = NSLock()
        var paths: [String] = []
        var joinCapabilityHeader: String?
        var idempotencyKeys: [String] = []
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") { idempotencyKeys.append(key) }
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/course-invites/invite-token-1234/preview":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-preview"],
                    body: #"{"data":{"classSectionId":"cls-1","displayName":"Section 1","courseCode":"PE101","courseName":"PE","semesterDisplayName":"2026","teacherDisplayName":"Teacher","enrollmentOpen":true,"expiresAt":"2026-08-07T00:00:00Z"},"meta":{"requestId":"req-preview"}}"#
                )
            case "/api/v1/course-invites/invite-token-1234/join-capabilities":
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-capability"],
                    body: #"{"data":{"joinCapability":"capability-secret","classSectionId":"cls-1","expiresAt":"2026-08-06T01:00:00Z"},"meta":{"requestId":"req-capability"}}"#
                )
            case "/api/v1/course-invites/invite-token-1234/join":
                joinCapabilityHeader = request.value(forHTTPHeaderField: "X-Join-Capability")
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-join"],
                    body: Self.joinEnvelopeJSON(requestID: "req-join")
                )
            default:
                return .json(status: 404, headers: ["X-Request-ID": "req-404"], body: Self.errorJSON(code: "USER_NOT_FOUND", requestID: "req-404"))
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let controller = BackendAuthSessionController(client: client, store: store)

        _ = try await controller.previewCourseInvite(inviteToken: "invite-token-1234")
        let capability = try await controller.issueJoinCapability(
            inviteToken: "invite-token-1234",
            profile: APIV1IssueJoinCapabilityRequest(
                fullName: "Synthetic Student",
                studentNumber: "SYNTH-001",
                gender: .other,
                gradeYear: 2026
            )
        )
        _ = try await controller.joinClassSection(
            inviteToken: "invite-token-1234",
            capability: capability.value.joinCapability
        )

        XCTAssertEqual(paths, [
            "/api/v1/course-invites/invite-token-1234/preview",
            "/api/v1/course-invites/invite-token-1234/join-capabilities",
            "/api/v1/course-invites/invite-token-1234/join"
        ])
        XCTAssertEqual(joinCapabilityHeader, "capability-secret")
        XCTAssertEqual(idempotencyKeys.count, 2)
        XCTAssertEqual(store.session?.accessToken, "join-access")
        XCTAssertEqual(store.session?.refreshToken, "join-refresh")
    }

    func testKeychainSessionBlobRestartRestoreReuseRevocationAndFailedLogoutClear() async throws {
        let credentialStore = RecordingCredentialStore()
        let keychainStore = KeychainAuthSessionStore(
            environment: .local,
            credentialStore: credentialStore
        )
        let saved = Self.authSession(access: "restart-access", refresh: "restart-refresh")
        try keychainStore.save(saved)

        XCTAssertEqual(credentialStore.itemCount, 1)
        XCTAssertEqual(try keychainStore.load(), saved)

        let restoreClient = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: makeSession { _ in
                XCTFail("A valid restored session must not make a network request")
                return .json(status: 500, headers: [:], body: "{}")
            }
        )
        let restarted = BackendAuthSessionController(client: restoreClient, store: keychainStore)
        let restoredState = try await restarted.restore()
        XCTAssertEqual(restoredState, .authenticated(saved))

        let revokedStore = MemoryAuthSessionStore(session: saved)
        let revokedClient = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: makeSession { request in
                XCTAssertEqual(request.url?.path, "/api/v1/auth/refresh")
                return .json(
                    status: 401,
                    headers: ["X-Request-ID": "req-refresh-reused"],
                    body: Self.errorJSON(code: "AUTH_SESSION_REVOKED", requestID: "req-refresh-reused")
                )
            },
            maximumSafeRetries: 0
        )
        let revoked = BackendAuthSessionController(client: revokedClient, store: revokedStore)
        _ = try await revoked.restore()
        do {
            _ = try await revoked.refresh()
            XCTFail("A revoked token family must fail refresh")
        } catch {}
        XCTAssertNil(revokedStore.session)
        let revokedState = await revoked.state()
        XCTAssertEqual(revokedState, .signedOut)

        let logoutStore = MemoryAuthSessionStore(session: saved)
        let logoutClient = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: makeSession { request in
                XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
                return .json(
                    status: 503,
                    headers: ["X-Request-ID": "req-logout-failed"],
                    body: Self.errorJSON(code: "SYSTEM_SERVICE_UNAVAILABLE", requestID: "req-logout-failed")
                )
            },
            maximumSafeRetries: 0
        )
        let logout = BackendAuthSessionController(client: logoutClient, store: logoutStore)
        _ = try await logout.restore()
        do {
            try await logout.logout()
            XCTFail("Server revoke failure must remain visible")
        } catch {}
        XCTAssertNil(logoutStore.session)
        let logoutState = await logout.state()
        XCTAssertEqual(logoutState, .signedOut)

        try keychainStore.clear()
        XCTAssertEqual(credentialStore.itemCount, 0)
    }

    func testMediaPipelineUsesPrivatePutThenConfirmAndBind() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "media-access", refresh: "media-refresh"))
        let lock = NSLock()
        var operations: [String] = []
        var uploadedBytes = Data()
        let session = makeSession { request in
            lock.lock()
            operations.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/media-uploads":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer media-access")
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-media-init"],
                    body: #"{"data":{"uploadSessionId":"upload-session-1","mediaId":"media-1","uploadUrl":"https://private-upload.example.test/private/upload","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2026-08-06T01:00:00Z"},"meta":{"requestId":"req-media-init"}}"#
                )
            case "/private/upload":
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                uploadedBytes = Self.bodyData(from: request)
                return .json(status: 200, headers: ["ETag": "etag-private-1"], body: "{}")
            case "/api/v1/media-uploads/upload-session-1/confirm":
                XCTAssertTrue(String(data: Self.bodyData(from: request), encoding: .utf8)?.contains("etag-private-1") == true)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-confirm"],
                    body: Self.mediaEnvelopeJSON(status: "UPLOADED", requestID: "req-media-confirm")
                )
            case "/api/v1/media/media-1/bind":
                XCTAssertTrue(String(data: Self.bodyData(from: request), encoding: .utf8)?.contains("expectedVersion") == true)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-bind"],
                    body: Self.mediaEnvelopeJSON(status: "AVAILABLE", requestID: "req-media-bind")
                )
            default:
                return .json(status: 404, headers: ["X-Request-ID": "req-404"], body: Self.errorJSON(code: "MEDIA_NOT_FOUND", requestID: "req-404"))
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let coordinator = MediaUploadCoordinator(client: client, auth: auth)
        let bytes = Data([0xff, 0xd8, 0xff, 0xd9])
        let outcome = try await coordinator.uploadAndBind(
            bytes: bytes,
            request: APIV1InitiateMediaUploadRequest(
                sessionId: "exercise-session-1",
                businessPurpose: .exerciseRecord,
                mediaType: .image,
                mimeType: "image/jpeg",
                fileSizeBytes: bytes.count,
                captureSource: .inAppCamera,
                declaredContentSha256: nil,
                durationSeconds: nil
            ),
            expectedVersion: 3
        )

        XCTAssertEqual(outcome.media.uploadStatus, .available)
        XCTAssertEqual(outcome.requestId, "req-media-bind")
        XCTAssertEqual(uploadedBytes, bytes)
        XCTAssertEqual(operations, [
            "POST /api/v1/media-uploads",
            "PUT /private/upload",
            "POST /api/v1/media-uploads/upload-session-1/confirm",
            "POST /api/v1/media/media-1/bind"
        ])
    }

    func testGeneratedReviewVersionsDecimalScoreServerClockAndExport503() throws {
        let review = try JSONDecoder().decode(
            APIV1CreateReviewRequest.self,
            from: Data(#"{"result":"VALID","expectedReviewVersion":2,"expectedVersion":7}"#.utf8)
        )
        let encodedReview = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as? [String: Any])
        XCTAssertEqual(encodedReview["expectedReviewVersion"] as? Int, 2)
        XCTAssertEqual(encodedReview["expectedVersion"] as? Int, 7)

        let score = try JSONDecoder().decode(APIV1StudentScore.self, from: Data(Self.publishedScoreJSON.utf8))
        let published = try XCTUnwrap(PublishedScoreProjection(score))
        XCTAssertEqual(published.finalScore, Decimal(string: "87.35"))
        XCTAssertEqual(published.status, .published)

        let exercise = try JSONDecoder().decode(APIV1ExerciseSession.self, from: Data(Self.exerciseSessionJSON.utf8))
        let now = ISO8601DateFormatter().date(from: "2026-08-06T00:10:00Z")!
        XCTAssertEqual(ServerSessionDisplayClock.elapsedSeconds(for: exercise, now: now), 540)

        let exportError = APITransportError.failure(
            statusCode: 503,
            envelope: APIErrorEnvelope(
                code: "SYSTEM_MODE_UNSUPPORTED",
                message: "Unsupported",
                details: .object([:]),
                requestId: "req-export-503",
                timestamp: "2026-08-06T00:00:00Z"
            )
        )
        XCTAssertEqual(
            ExportAvailabilityPolicy.unavailableState(from: exportError),
            ExportUnavailableState(message: "该功能尚未开放。", requestId: "req-export-503")
        )
    }

    private func makeSession(handler: @escaping FoundationURLProtocol.Handler) -> URLSession {
        FoundationURLProtocol.install(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FoundationURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func errorJSON(code: String, requestID: String) -> String {
        """
        {"code":"\(code)","message":"failure","details":{},"requestId":"\(requestID)","timestamp":"2026-08-06T00:00:00Z"}
        """
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func authSession(access: String, refresh: String) -> APIV1AuthSession {
        try! JSONDecoder().decode(
            APIV1AuthSession.self,
            from: Data(authSessionJSON(access: access, refresh: refresh).utf8)
        )
    }

    private static func authSessionJSON(access: String, refresh: String) -> String {
        """
        {"sessionId":"session-1","accessToken":"\(access)","refreshToken":"\(refresh)","tokenType":"Bearer","accessTokenExpiresAt":"2099-08-06T00:00:00Z","refreshTokenExpiresAt":"2099-08-07T00:00:00Z","user":{"id":"user-1","organizationId":"org-1","role":"STUDENT","status":"ACTIVE","primaryEmailMasked":null,"primaryPhoneMasked":null,"emailVerified":false,"phoneVerified":false,"version":1}}
        """
    }

    private static func authEnvelopeJSON(access: String, refresh: String, requestID: String) -> String {
        "{\"data\":\(authSessionJSON(access: access, refresh: refresh)),\"meta\":{\"requestId\":\"\(requestID)\"}}"
    }

    private static func mediaEnvelopeJSON(status: String, requestID: String) -> String {
        """
        {"data":{"id":"media-1","organizationId":"org-1","ownerStudentId":"student-1","sessionId":"exercise-session-1","recordId":null,"businessPurpose":"EXERCISE_RECORD","mediaType":"IMAGE","declaredMimeType":"image/jpeg","verifiedMimeType":"image/jpeg","declaredFileSizeBytes":4,"verifiedFileSizeBytes":4,"captureSource":"IN_APP_CAMERA","uploadStatus":"\(status)","uploadedAt":"2026-08-06T00:00:00Z","boundAt":null,"declaredContentSha256":null,"verifiedContentSha256":null,"declaredDurationSeconds":null,"verifiedDurationSeconds":null,"version":1},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func joinEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"studentProfile":{"id":"student-1","organizationId":"org-1","userId":"user-1","studentNumber":"SYNTH-001","fullName":"Synthetic Student","gender":"OTHER","gradeYear":2026,"collegeName":null,"majorName":null,"administrativeClassName":null,"status":"ACTIVE","createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","deletedAt":null,"version":1},"enrollment":{"id":"enrollment-1","organizationId":"org-1","semesterId":"semester-1","classSectionId":"cls-1","studentId":"student-1","source":"QR_CODE","sourceReferenceId":null,"status":"ACTIVE","joinedAt":"2026-08-06T00:00:00Z","endedAt":null,"endReason":null,"createdBy":null,"createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","version":1},"course":{"id":"course-1","organizationId":"org-1","courseCode":"PE101","courseName":"PE","description":null,"status":"ACTIVE","createdBy":null,"createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","deletedAt":null,"version":1},"classSection":{"id":"cls-1","organizationId":"org-1","courseId":"course-1","semesterId":"semester-1","teacherId":"teacher-1","classCode":"001","displayName":"Section 1","status":"ACTIVE","isEnrollmentOpen":true,"checkInWindowMode":"AVAILABLE","checkInStartDate":null,"checkInEndDate":null,"dailyStartTime":null,"dailyEndTime":null,"submissionDeadlineAt":null,"excludedDates":[],"createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","version":1},"authSession":\(authSessionJSON(access: "join-access", refresh: "join-refresh"))},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static let publishedScoreJSON = """
    {"id":"score-1","organizationId":"org-1","enrollmentId":"enrollment-1","scoreRuleId":"rule-1","calculationRevision":1,"validCourseDurationSeconds":3600,"validGeneralDurationSeconds":3600,"totalValidDurationSeconds":7200,"scoringSeconds":7200,"excessSeconds":0,"qualificationStatus":"QUALIFIED","baseScore":80.10,"adjustmentTotal":7.25,"finalScore":87.35,"status":"PUBLISHED","calculatedAt":"2026-08-06T00:00:00Z","publishedAt":"2026-08-06T00:01:00Z","lockedAt":null,"sourceFingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":1}
    """

    private static let exerciseSessionJSON = """
    {"id":"session-1","organizationId":"org-1","semesterId":"semester-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"cls-1","status":"IN_PROGRESS","startedAt":"2026-08-06T00:00:00Z","endedAt":null,"actualDurationSeconds":120,"pausedDurationSeconds":60,"businessDate":"2026-08-06","lastHeartbeatAt":"2026-08-06T00:02:00Z","endReason":null,"version":1}
    """
}

private struct StubHTTPResponse {
    let status: Int
    let headers: [String: String]
    let data: Data

    static func json(status: Int, headers: [String: String], body: String) -> StubHTTPResponse {
        StubHTTPResponse(status: status, headers: headers.merging(["Content-Type": "application/json"]) { first, _ in first }, data: Data(body.utf8))
    }
}

private final class FoundationURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) -> StubHTTPResponse
    private static let lock = NSLock()
    private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stub = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CapturingAPIEventLogger: APIEventLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [APILogEvent] = []

    var events: [APILogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: APILogEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private final class MemoryAuthSessionStore: AuthSessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: APIV1AuthSession?

    init(session: APIV1AuthSession? = nil) {
        storage = session
    }

    var session: APIV1AuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func load() throws -> APIV1AuthSession? { session }

    func save(_ session: APIV1AuthSession) throws {
        lock.lock()
        storage = session
        lock.unlock()
    }

    func clear() throws {
        lock.lock()
        storage = nil
        lock.unlock()
    }
}

private final class RecordingCredentialStore: SecureCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    var itemCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    func data(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return items[key]
    }

    func set(_ data: Data, forKey key: String) throws {
        lock.lock()
        items[key] = data
        lock.unlock()
    }

    func removeData(forKey key: String) throws {
        lock.lock()
        items.removeValue(forKey: key)
        lock.unlock()
    }
}
