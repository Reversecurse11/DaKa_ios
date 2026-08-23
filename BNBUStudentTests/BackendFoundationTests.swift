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
            "56f7f13cdd8122dae630fec93bf198f7ed6d92a5fc4f67ae4f866a3b41c38ad7"
        )
        XCTAssertEqual(APIV1ContractMetadata.contractVersion, "2.0.10-contract")
        XCTAssertEqual(APIV1ContractMetadata.apiPrefix, "/api/v1")
        XCTAssertEqual(APIV1ContractMetadata.pathCount, 109)
        XCTAssertEqual(APIV1ContractMetadata.operationCount, 126)
        XCTAssertEqual(APIV1ContractMetadata.schemaCount, 288)
        XCTAssertEqual(APIV1ContractMetadata.implementedOperationCount, 109)
        XCTAssertEqual(APIV1ContractMetadata.intentionallyDisabledOperationCount, 17)
        XCTAssertEqual(APIV1ContractMetadata.systemModeUnsupportedOperationCount, 13)
        XCTAssertEqual(APIV1IntentionallyDisabledOperation.allCases.count, 17)
        XCTAssertEqual(APIV1SystemModeUnsupportedOperation.allCases.count, 13)
        XCTAssertEqual(APIV1ContractMetadata.clientCapabilityCount, 31)
        XCTAssertEqual(APIV1ContractMetadata.localIntegrationClientCapabilityCount, 23)
        XCTAssertEqual(APIV1ContractMetadata.defaultDeniedClientCapabilityCount, 8)
        XCTAssertEqual(APIV1ClientCapability.allCases.count, 31)
        XCTAssertEqual(APIV1LocalIntegrationClientCapability.allCases.count, 23)
        XCTAssertEqual(APIV1DefaultDeniedClientCapability.allCases.count, 8)

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
        XCTAssertTrue(BackendEnvironment.isAllowed(
            URL(string: "https://api.verityai.cn/api/v1")!,
            for: .staging
        ))
        XCTAssertFalse(BackendEnvironment.isAllowed(
            URL(string: "https://sports.example.edu/api/v1")!,
            for: .staging
        ))
        let stagingConfiguration = [
            "BNBU_ENVIRONMENT": "staging",
            "BNBU_API_BASE_URL": "https://api.verityai.cn/api/v1",
            "BNBU_ORGANIZATION_CODE": "BNBU",
            "BNBU_CONTRACT_VERSION": "2.0.10-contract",
            "BNBU_CONTRACT_SHA256": "56f7f13cdd8122dae630fec93bf198f7ed6d92a5fc4f67ae4f866a3b41c38ad7"
        ]
        let staging = try BackendEnvironment.resolve(
            arguments: ["BNBUStudent"],
            processEnvironment: stagingConfiguration,
            bundle: .main
        )
        XCTAssertEqual(staging.baseURL.absoluteString, "https://api.verityai.cn/api/v1")
        var mismatchedContract = stagingConfiguration
        mismatchedContract["BNBU_CONTRACT_SHA256"] = "wrong"
        XCTAssertThrowsError(try BackendEnvironment.resolve(
            arguments: ["BNBUStudent"],
            processEnvironment: mismatchedContract,
            bundle: .main
        )) { error in
            XCTAssertEqual(error as? BackendEnvironmentError, .contractSHA256Mismatch("wrong"))
        }
        XCTAssertThrowsError(try BackendEnvironment.resolve(
            arguments: ["BNBUStudent"],
            processEnvironment: ["BNBU_ENVIRONMENT": "typo"],
            bundle: .main
        )) { error in
            XCTAssertEqual(error as? BackendEnvironmentError, .invalidEnvironment("typo"))
        }
    }

    func testExerciseRecordSubmissionProjectionPreservesAuthoritativeReviewState() {
        func record(
            status: APIV1ExerciseRecordStatus,
            review: APIV1ReviewResult?
        ) -> APIV1ExerciseRecord {
            APIV1ExerciseRecord(
                id: "record-1",
                organizationId: "org-1",
                semesterId: "semester-1",
                studentId: "student-1",
                enrollmentId: "enrollment-1",
                classSectionId: "section-1",
                courseId: "course-1",
                teacherId: "teacher-1",
                sessionId: "session-1",
                businessDate: "2026-08-22",
                creditType: .courseRelated,
                sportType: "RUNNING",
                sportName: nil,
                description: nil,
                actualDurationSeconds: 3_600,
                pausedDurationSeconds: 0,
                creditedDurationSeconds: 3_600,
                status: status,
                submittedAt: "2026-08-22T10:00:00Z",
                cancelledAt: nil,
                clientRequestId: "ios-record-1",
                currentReview: review.map {
                    APIV1StudentCurrentReview(result: $0, reasonCode: nil, publicComment: nil)
                },
                version: 2
            )
        }

        XCTAssertTrue(ExerciseRecordSubmissionProjectionPolicy.accepts(
            record(status: .submitted, review: .pending)
        ))
        XCTAssertTrue(ExerciseRecordSubmissionProjectionPolicy.accepts(
            record(status: .reviewed, review: .valid)
        ))
        XCTAssertTrue(ExerciseRecordSubmissionProjectionPolicy.accepts(
            record(status: .reviewed, review: .invalid)
        ))
        XCTAssertFalse(ExerciseRecordSubmissionProjectionPolicy.accepts(
            record(status: .draft, review: nil)
        ))
        XCTAssertFalse(ExerciseRecordSubmissionProjectionPolicy.accepts(
            record(status: .submitted, review: .valid)
        ))
        XCTAssertFalse(ExerciseRecordSubmissionProjectionPolicy.accepts(
            record(status: .reviewed, review: .pending)
        ))
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
        XCTAssertTrue(FixturePolicy.isEnabled(arguments: ["BNBUStudent", "-mock-test-account"]))
        XCTAssertTrue(FixturePolicy.isEnabled(arguments: ["BNBUStudent", "-ui-testing-reset"]))
        XCTAssertFalse(FixturePolicy.isEnabled(arguments: [
            "BNBUStudent",
            "-ui-testing-reset",
            "-ui-testing-real-backend"
        ]))
        XCTAssertFalse(UITestingPolicy.isEnabled(arguments: ["BNBUStudent"]))
        XCTAssertTrue(UITestingPolicy.isEnabled(arguments: ["BNBUStudent", "-ui-testing-reset"]))
        XCTAssertTrue(UITestingPolicy.shouldResetState(arguments: ["BNBUStudent", "-ui-testing-reset"]))
        XCTAssertTrue(UITestingPolicy.isEnabled(arguments: ["BNBUStudent", "-ui-testing-preserve-state"]))
        XCTAssertFalse(UITestingPolicy.shouldResetState(arguments: ["BNBUStudent", "-ui-testing-preserve-state"]))
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

    func testClientCapabilityReadinessKeepsLocalIntegrationSeparateFromStaging() {
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
            DefaultDeniedCapabilityPolicy.unavailableState(for: .getSportCatalog, from: error),
            DefaultDeniedCapabilityState(
                operationID: "getSportCatalog",
                message: "该功能尚未开放。",
                requestId: "req-capability-503"
            )
        )
        XCTAssertEqual(
            DefaultDeniedCapabilityPolicy.unavailableState(for: .startExerciseLocationTrack, from: error)?.requestId,
            "req-capability-503"
        )
        XCTAssertEqual(
            DefaultDeniedCapabilityPolicy.unavailableState(
                forSystemModeOperation: .listExports,
                from: error
            )?.operationID,
            "listExports"
        )
        XCTAssertTrue(ClientCapabilityReadinessPolicy.hasLocalIntegrationEvidence(.listNotifications))
        XCTAssertTrue(ClientCapabilityReadinessPolicy.hasLocalIntegrationEvidence(.requestStudentSignInCode))
        XCTAssertFalse(ClientCapabilityReadinessPolicy.isExplicitlyDefaultDenied(.listNotifications))
        XCTAssertTrue(ClientCapabilityReadinessPolicy.isExplicitlyDefaultDenied(.getSportCatalog))
        XCTAssertTrue(ClientCapabilityReadinessPolicy.isExplicitlyDefaultDenied(.startExerciseLocationTrack))
        XCTAssertFalse(ClientCapabilityReadinessPolicy.stagingExecutionReady)

        XCTAssertEqual(IOSPlatformContractPolicy.wireValue, "IOS")
        XCTAssertTrue(IOSPlatformContractPolicy.supportsIOS(.registerPushDevice))
        XCTAssertTrue(IOSPlatformContractPolicy.supportsIOS(.unregisterPushDevice))
        XCTAssertTrue(IOSPlatformContractPolicy.supportsIOS(.getAppReleasePolicy))
        XCTAssertTrue(IOSPlatformContractPolicy.supportsIOS(.createFeedback))
        XCTAssertFalse(IOSPlatformContractPolicy.supportsIOS(.requestStudentSignInCode))
    }

    func testContract15MediaValidationErrorsProduceActionableMessages() {
        for code in [
            "MEDIA_VIDEO_DURATION_EXCEEDED",
            "MEDIA_AUDIO_TRACK_REQUIRED",
            "MEDIA_LOCATION_METADATA_NOT_ALLOWED",
            "MEDIA_TYPE_NOT_ALLOWED",
            "MEDIA_INTEGRITY_MISMATCH",
            "MEDIA_UPLOAD_SESSION_EXPIRED"
        ] {
            let error = APITransportError.failure(
                statusCode: 422,
                envelope: APIErrorEnvelope(
                    code: code,
                    message: "Backend fallback",
                    details: .object([:]),
                    requestId: "req-media-15",
                    timestamp: "2026-08-13T00:00:00Z"
                )
            )
            XCTAssertNotNil(MediaValidationErrorPolicy.message(for: error), code)
            XCTAssertTrue(error.localizedDescription.contains("req-media-15"), code)
            XCTAssertFalse(error.localizedDescription.contains("Backend fallback"), code)
        }
    }

    func testContract15RuntimeQueryErrataAndWallTimeCompatibility() throws {
        XCTAssertEqual(
            APIV1ListExerciseRecordsSortRuntimeValue.allCases.map(\.rawValue),
            ["businessDate", "-businessDate"]
        )
        XCTAssertEqual(
            APIV1ListClassSectionsStatusRuntimeValue.allCases.map(\.rawValue),
            ["UPCOMING", "ACTIVE", "CLOSED", "ARCHIVED"]
        )
        XCTAssertEqual(APIV1ListStudentsSortRuntimeValue.allCases.count, 6)
        XCTAssertEqual(APIV1ListAuditLogsSortRuntimeValue.allCases.count, 2)

        XCTAssertEqual(APIV1RuntimeUnsupportedQueryParameter.allCases.count, 3)
        for parameter in APIV1RuntimeUnsupportedQueryParameter.allCases {
            XCTAssertTrue(RuntimeQueryContractPolicy.mustOmit(parameter))
        }
        let scoreQuery = RuntimeQueryContractPolicy.studentScoreQueryItems(status: .published)
        XCTAssertEqual(scoreQuery, [URLQueryItem(name: "status", value: "PUBLISHED")])
        XCTAssertFalse(scoreQuery.contains { $0.name == "sort" })

        XCTAssertEqual(
            APIV1InitiateMediaUploadCaptureSource.allCases.map(\.rawValue),
            ["IN_APP_CAMERA", "FILE_PICKER"]
        )
        XCTAssertEqual(APIV1MediaAccessPurpose.allCases.map(\.rawValue), ["VIEW_ORIGINAL"])

        for (start, end) in [
            ("08:30", "10:30"),
            ("08:30:00", "10:30:00"),
            ("08:30:00+08:00", "10:30:00+08:00")
        ] {
            let section = try JSONDecoder().decode(
                APIV1ClassSection.self,
                from: Data(Self.classSectionJSON(dailyStartTime: start, dailyEndTime: end).utf8)
            )
            XCTAssertEqual(section.dailyStartTime, start)
            XCTAssertEqual(section.dailyEndTime, end)
        }

        let update = try JSONDecoder().decode(
            APIV1UpdateClassSectionRequest.self,
            from: Data(#"{"dailyStartTime":"08:30","dailyEndTime":null,"expectedVersion":2}"#.utf8)
        )
        XCTAssertEqual(update.dailyStartTime, "08:30")
        XCTAssertNil(update.dailyEndTime)
    }

    func testIOSAuthPlatformAndNumericReleasePolicyContracts() throws {
        let codeRequest = APIV1StudentSignInCodeRequest(
            organizationCode: "BNBU",
            account: "student@example.edu",
            channel: "EMAIL",
            locale: "zh-CN"
        )
        let codeJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(codeRequest)) as? [String: Any]
        )
        XCTAssertEqual(codeJSON["organizationCode"] as? String, "BNBU")
        XCTAssertEqual(codeJSON["account"] as? String, "student@example.edu")

        let accepted = try JSONDecoder().decode(
            APIV1StudentSignInCodeAcceptedEnvelope.self,
            from: Data(#"{"data":{"challengeId":"challenge-1","expiresAt":"2026-08-07T09:00:00Z"},"meta":{"requestId":"req-code"}}"#.utf8)
        )
        XCTAssertEqual(accepted.data.challengeId, "challenge-1")
        let acceptedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(accepted)) as? [String: Any]
        )
        let acceptedData = try XCTUnwrap(acceptedJSON["data"] as? [String: Any])
        XCTAssertNil(acceptedData["account"])
        XCTAssertNil(acceptedData["accountExists"])

        let recovery = APIV1AccountRecoveryRequest(
            organizationCode: "BNBU",
            account: "teacher@example.edu",
            requestedRole: "TEACHER",
            channel: "EMAIL",
            locale: "zh-CN"
        )
        let recoveryJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(recovery)) as? [String: Any]
        )
        XCTAssertEqual(recoveryJSON["organizationCode"] as? String, "BNBU")
        XCTAssertEqual(recoveryJSON["requestedRole"] as? String, "TEACHER")

        let push = APIV1PushDeviceRegistrationRequest(
            platform: IOSPlatformContractPolicy.wireValue,
            registrationToken: String(repeating: "a", count: 64),
            appVersion: "1.0.0",
            locale: "zh-CN"
        )
        let pushJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(push)) as? [String: Any]
        )
        XCTAssertEqual(pushJSON["platform"] as? String, "IOS")

        let feedback = APIV1CreateFeedbackRequest(
            category: "BUG",
            content: "Something went wrong",
            clientContext: ["platform": .string(IOSPlatformContractPolicy.wireValue)]
        )
        let feedbackJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(feedback)) as? [String: Any]
        )
        XCTAssertEqual((feedbackJSON["clientContext"] as? [String: Any])?["platform"] as? String, "IOS")

        let query = try XCTUnwrap(IOSAppReleasePolicyQuery(infoDictionary: [
            "CFBundleVersion": "104",
            "CFBundleShortVersionString": "1.0.4"
        ]))
        XCTAssertEqual(query.platform, "IOS")
        XCTAssertEqual(query.currentBuildNumber, 104)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: query.queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            }),
            ["platform": "IOS", "currentBuildNumber": "104", "currentVersion": "1.0.4"]
        )
        XCTAssertNil(IOSAppReleasePolicyQuery(infoDictionary: ["CFBundleVersion": "1.0.4"]))

        let policy = try JSONDecoder().decode(
            APIV1AppReleasePolicy.self,
            from: Data(#"{"platform":"IOS","minimumSupportedVersion":"1.0.0","latestVersion":"1.2.0","minimumSupportedBuildNumber":100,"latestBuildNumber":120,"enforcement":"NONE","message":null,"downloadUrl":null,"effectiveAt":"2026-08-07T00:00:00Z","expiresAt":null,"policyVersion":"ios-policy-1"}"#.utf8)
        )
        XCTAssertTrue(IOSAppReleaseContractPolicy.accepts(policy))

        let invalidPolicy = try JSONDecoder().decode(
            APIV1AppReleasePolicy.self,
            from: Data(#"{"platform":"IOS","minimumSupportedVersion":"1.0.0","latestVersion":"1.2.0","minimumSupportedBuildNumber":120,"latestBuildNumber":100,"enforcement":"NONE","message":null,"downloadUrl":null,"effectiveAt":"2026-08-07T00:00:00Z","expiresAt":null,"policyVersion":"ios-policy-1"}"#.utf8)
        )
        XCTAssertFalse(IOSAppReleaseContractPolicy.accepts(invalidPolicy))

        XCTAssertEqual(APIV1ErrorCode.exemptionApplicationNotFound.rawValue, "EXEMPTION_APPLICATION_NOT_FOUND")
        XCTAssertEqual(APIV1ErrorCode.exemptionApplicationMediaInvalid.rawValue, "EXEMPTION_APPLICATION_MEDIA_INVALID")
    }

    func testMediaUploadPurposeScopeRejectsInvalidOneOfCombinations() {
        let exercise = APIV1InitiateMediaUploadRequest(
            sessionId: "session-1",
            enrollmentId: nil,
            businessPurpose: .exerciseRecord,
            mediaType: .image,
            mimeType: "image/jpeg",
            fileSizeBytes: 4,
            captureSource: .inAppCamera,
            declaredContentSha256: nil,
            durationSeconds: nil
        )
        XCTAssertTrue(MediaUploadContractPolicy.accepts(exercise))

        let exemption = APIV1InitiateMediaUploadRequest(
            sessionId: nil,
            enrollmentId: "enrollment-1",
            businessPurpose: .exemptionApplication,
            mediaType: .image,
            mimeType: "image/jpeg",
            fileSizeBytes: 4,
            captureSource: .filePicker,
            declaredContentSha256: nil,
            durationSeconds: nil
        )
        XCTAssertTrue(MediaUploadContractPolicy.accepts(exemption))

        let crossScoped = APIV1InitiateMediaUploadRequest(
            sessionId: "session-1",
            enrollmentId: "enrollment-1",
            businessPurpose: .exemptionApplication,
            mediaType: .image,
            mimeType: "image/jpeg",
            fileSizeBytes: 4,
            captureSource: .filePicker,
            declaredContentSha256: nil,
            durationSeconds: nil
        )
        XCTAssertFalse(MediaUploadContractPolicy.accepts(crossScoped))

        let exerciseFromPicker = APIV1InitiateMediaUploadRequest(
            sessionId: "session-1",
            enrollmentId: nil,
            businessPurpose: .exerciseRecord,
            mediaType: .image,
            mimeType: "image/jpeg",
            fileSizeBytes: 4,
            captureSource: .filePicker,
            declaredContentSha256: nil,
            durationSeconds: nil
        )
        XCTAssertFalse(MediaUploadContractPolicy.accepts(exerciseFromPicker))
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
                gender: .female,
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

    @MainActor
    func testAppStateFirstUseJoinAcceptsMissingOptionalSessionEnrollmentAndInstallsOnlyPendingSession() async throws {
        let authStore = MemoryAuthSessionStore()
        let lock = NSLock()
        var paths: [String] = []
        var profileBody: [String: Any] = [:]
        var joinCapabilityHeader: String?
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            if request.url?.path.hasSuffix("/join-capabilities") == true {
                profileBody = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any] ?? [:]
            }
            if request.url?.path.hasSuffix("/join") == true {
                joinCapabilityHeader = request.value(forHTTPHeaderField: "X-Join-Capability")
            }
            lock.unlock()

            switch request.url?.path {
            case "/api/v1/course-invites/Opaque-Invite-Token-1234/preview":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-initial-preview"],
                    body: #"{"data":{"classSectionId":"cls-1","displayName":"Section 1","courseCode":"PE101","courseName":"PE","semesterDisplayName":"2026","teacherDisplayName":"Teacher","enrollmentOpen":true,"expiresAt":"2026-09-07T00:00:00Z"},"meta":{"requestId":"req-initial-preview"}}"#
                )
            case "/api/v1/course-invites/Opaque-Invite-Token-1234/join-capabilities":
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-initial-capability"],
                    body: #"{"data":{"joinCapability":"one-time-capability","classSectionId":"cls-1","expiresAt":"2026-09-06T01:00:00Z"},"meta":{"requestId":"req-initial-capability"}}"#
                )
            case "/api/v1/course-invites/Opaque-Invite-Token-1234/join":
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-initial-join"],
                    body: Self.pendingContactJoinEnvelopeJSON(requestID: "req-initial-join")
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let client = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: session,
            maximumSafeRetries: 0
        )
        let services = BackendAppServices(
            environment: .local,
            client: client,
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-initial-join")
        )
        let suiteName = "BackendFoundationTests.initial-join.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        let token = "Opaque-Invite-Token-1234"
        let loadedPreview = await state.previewInitialCourseJoin(inviteToken: token)
        let preview = try XCTUnwrap(loadedPreview)
        let joined = await state.joinCourseBeforeLogin(
            inviteToken: token,
            preview: preview,
            fullName: "Synthetic Student",
            studentNumber: "SYNTH-001",
            gender: .female,
            gradeYear: 2026
        )

        XCTAssertTrue(joined)
        XCTAssertEqual(paths, [
            "/api/v1/course-invites/Opaque-Invite-Token-1234/preview",
            "/api/v1/course-invites/Opaque-Invite-Token-1234/join-capabilities",
            "/api/v1/course-invites/Opaque-Invite-Token-1234/join"
        ])
        XCTAssertEqual(profileBody["fullName"] as? String, "Synthetic Student")
        XCTAssertEqual(profileBody["studentNumber"] as? String, "SYNTH-001")
        XCTAssertEqual(profileBody["gender"] as? String, "FEMALE")
        XCTAssertEqual(profileBody["gradeYear"] as? Int, 2026)
        XCTAssertEqual(joinCapabilityHeader, "one-time-capability")
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.isAPIV1Session)
        XCTAssertFalse(state.isEmailVerified)
        XCTAssertEqual(state.workspace.student.id, "student-1")
        XCTAssertEqual(state.workspace.student.email, "")
        XCTAssertEqual(authStore.session?.user.status, .pendingContactBinding)
        XCTAssertFalse(authStore.session?.user.emailVerified ?? true)
    }

    @MainActor
    func testAppStateRestoresPendingContactSessionWithoutOpeningVerifiedWorkspace() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.pendingAuthSession(access: "pending-access", refresh: "pending-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/me":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pending-access")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-pending-restore"],
                    body: Self.pendingStudentCurrentUserEnvelopeJSON(requestID: "req-pending-restore")
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-pending-restore")
        )
        let suiteName = "BackendFoundationTests.pending-restore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()

        XCTAssertEqual(paths, ["/api/v1/me"])
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.isAPIV1Session)
        XCTAssertFalse(state.isEmailVerified)
        XCTAssertEqual(state.workspace.student.id, "student-1")
        XCTAssertEqual(state.workspace.student.email, "")
        XCTAssertEqual(authStore.session?.accessToken, "pending-access")
        XCTAssertEqual(authStore.session?.refreshToken, "pending-refresh")
    }

    @MainActor
    func testAppStateFirstEmailBindingKeepsJoinSessionAndTrustsServerActivation() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.pendingAuthSession(access: "pending-access", refresh: "pending-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        var challengeBody: [String: Any] = [:]
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            if request.url?.path == "/api/v1/me/email-verification-challenges" {
                challengeBody = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any] ?? [:]
            }
            lock.unlock()

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pending-access")
            switch request.url?.path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-pending-me"],
                    body: Self.pendingStudentCurrentUserEnvelopeJSON(requestID: "req-pending-me")
                )
            case "/api/v1/me/email-verification-challenges":
                return .json(
                    status: 202,
                    headers: ["X-Request-ID": "req-first-bind"],
                    body: #"{"data":{"challengeId":"challenge-first-bind","mode":"FIRST_BIND","expiresAt":"2026-08-22T15:00:00Z"},"meta":{"requestId":"req-first-bind"}}"#
                )
            case "/api/v1/me/email-verification-challenges/challenge-first-bind/verify":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-first-bind-verify"],
                    body: Self.studentCurrentUserEnvelopeJSON(
                        requestID: "req-first-bind-verify",
                        emailMasked: "i***@example.edu",
                        userVersion: 2
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-first-bind")
        )
        let suiteName = "BackendFoundationTests.first-bind.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        XCTAssertFalse(state.isEmailVerified)
        let requested = await state.requestContactEmailVerification(
            email: "IOS.Test@Example.edu ",
            locale: "en-US"
        )
        let verified = await state.completeContactEmailVerification(
            newEmailCode: "654321",
            currentEmailCode: nil,
            email: "IOS.Test@Example.edu "
        )

        XCTAssertTrue(requested)
        XCTAssertTrue(verified)
        XCTAssertEqual(paths, [
            "/api/v1/me",
            "/api/v1/me/email-verification-challenges",
            "/api/v1/me/email-verification-challenges/challenge-first-bind/verify"
        ])
        XCTAssertEqual(challengeBody["email"] as? String, "ios.test@example.edu")
        XCTAssertEqual(challengeBody["locale"] as? String, "en")
        XCTAssertEqual(challengeBody["expectedVersion"] as? Int, 1)
        XCTAssertTrue(state.isEmailVerified)
        XCTAssertEqual(state.workspace.student.email, "ios.test@example.edu")
        XCTAssertFalse(state.contactVerificationRequiresCurrentEmailCode)
        XCTAssertEqual(authStore.session?.accessToken, "pending-access")
        XCTAssertEqual(authStore.session?.refreshToken, "pending-refresh")
    }

    @MainActor
    func testInitialJoinMapsStableInviteErrorsWithoutRetryOrSession() async throws {
        let authStore = MemoryAuthSessionStore()
        let lock = NSLock()
        var paths: [String] = []
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            lock.lock()
            paths.append(path)
            lock.unlock()

            if path.contains("Invalid-Invite-Token-1234") {
                return .json(
                    status: 400,
                    headers: ["X-Request-ID": "req-invite-invalid"],
                    body: Self.errorJSON(code: "COURSE_INVITE_INVALID", requestID: "req-invite-invalid")
                )
            }
            if path.contains("Expired-Invite-Token-1234") {
                return .json(
                    status: 410,
                    headers: ["X-Request-ID": "req-invite-expired"],
                    body: Self.errorJSON(code: "COURSE_INVITE_EXPIRED", requestID: "req-invite-expired")
                )
            }
            if path.contains("Revoked-Invite-Token-1234") {
                return .json(
                    status: 410,
                    headers: ["X-Request-ID": "req-invite-revoked"],
                    body: Self.errorJSON(code: "COURSE_INVITE_REVOKED", requestID: "req-invite-revoked")
                )
            }
            return .json(
                status: 429,
                headers: ["X-Request-ID": "req-invite-rate-limited"],
                body: Self.errorJSON(code: "AUTH_RATE_LIMITED", requestID: "req-invite-rate-limited")
            )
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-invite-errors")
        )
        let suiteName = "BackendFoundationTests.invite-errors.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        for token in [
            "Invalid-Invite-Token-1234",
            "Expired-Invite-Token-1234",
            "Revoked-Invite-Token-1234"
        ] {
            let preview = await state.previewInitialCourseJoin(inviteToken: token)
            XCTAssertNil(preview)
            XCTAssertEqual(state.errorMessage, BNBUL10n.text("邀请已失效，请向老师获取新的邀请。"))
        }
        let rateLimitedPreview = await state.previewInitialCourseJoin(
            inviteToken: "Rate-Limited-Invite-Token-1234"
        )
        XCTAssertNil(rateLimitedPreview)
        XCTAssertEqual(state.errorMessage, BNBUL10n.text("操作过于频繁，请稍后再试。"))

        XCTAssertEqual(paths, [
            "/api/v1/course-invites/Invalid-Invite-Token-1234/preview",
            "/api/v1/course-invites/Expired-Invite-Token-1234/preview",
            "/api/v1/course-invites/Revoked-Invite-Token-1234/preview",
            "/api/v1/course-invites/Rate-Limited-Invite-Token-1234/preview"
        ])
        XCTAssertNil(authStore.session)
        XCTAssertFalse(state.isAuthenticated)
    }

    func testContract15EmailSignInAndBindingInstallOneRotatingSession() async throws {
        let store = MemoryAuthSessionStore()
        let lock = NSLock()
        var paths: [String] = []
        var authorizedEmailRequests = 0
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            if request.url?.path.contains("/me/email-verification-challenges") == true,
               request.value(forHTTPHeaderField: "Authorization") == "Bearer otp-access" {
                authorizedEmailRequests += 1
            }
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/auth/student-sign-in-codes":
                return .json(
                    status: 202,
                    headers: ["X-Request-ID": "req-otp-request"],
                    body: #"{"data":{"challengeId":"challenge-otp","expiresAt":"2026-08-13T05:00:00Z"},"meta":{"requestId":"req-otp-request"}}"#
                )
            case "/api/v1/auth/student-sign-in-codes/verify":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-otp-verify"],
                    body: Self.authEnvelopeJSON(access: "otp-access", refresh: "otp-refresh", requestID: "req-otp-verify")
                )
            case "/api/v1/me/email-verification-challenges":
                return .json(
                    status: 202,
                    headers: ["X-Request-ID": "req-email-request"],
                    body: #"{"data":{"challengeId":"challenge-email","mode":"FIRST_BIND","expiresAt":"2026-08-13T05:00:00Z"},"meta":{"requestId":"req-email-request"}}"#
                )
            case "/api/v1/me/email-verification-challenges/challenge-email/verify":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-email-verify"],
                    body: Self.currentUserEnvelopeJSON(requestID: "req-email-verify")
                )
            default:
                return .json(status: 404, headers: ["X-Request-ID": "req-404"], body: Self.errorJSON(code: "USER_NOT_FOUND", requestID: "req-404"))
            }
        }
        let controller = BackendAuthSessionController(
            client: StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session),
            store: store
        )

        let challenge = try await controller.requestStudentSignInCode(APIV1StudentSignInCodeRequest(
            organizationCode: "BNBU",
            account: "student@example.edu",
            channel: "EMAIL",
            locale: "zh-CN"
        ))
        _ = try await controller.verifyStudentSignInCode(APIV1StudentSignInCodeVerificationRequest(
            challengeId: challenge.value.challengeId,
            code: "123456",
            deviceId: "ios-test-device"
        ))
        let emailChallenge = try await controller.requestCurrentUserEmailChallenge(
            APIV1EmailVerificationChallengeRequest(
                email: "student@example.edu",
                locale: "zh-CN",
                expectedVersion: 1
            )
        )
        let currentUser = try await controller.verifyCurrentUserEmailChallenge(
            challengeID: emailChallenge.value.challengeId,
            request: APIV1VerifyEmailChallengeRequest(currentEmailCode: nil, newEmailCode: "654321")
        )

        XCTAssertEqual(paths, [
            "/api/v1/auth/student-sign-in-codes",
            "/api/v1/auth/student-sign-in-codes/verify",
            "/api/v1/me/email-verification-challenges",
            "/api/v1/me/email-verification-challenges/challenge-email/verify"
        ])
        XCTAssertEqual(authorizedEmailRequests, 2)
        XCTAssertEqual(store.session?.accessToken, "otp-access")
        XCTAssertEqual(currentUser.value.user.id, "user-1")
    }

    @MainActor
    func testAppStateUsesContract15EmailSignInWithoutLegacyFallback() async throws {
        let authStore = MemoryAuthSessionStore()
        let lock = NSLock()
        var paths: [String] = []
        var requestedBody: [String: Any] = [:]
        var verifiedBody: [String: Any] = [:]
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            let body = Self.bodyData(from: request)
            if request.url?.path == "/api/v1/auth/student-sign-in-codes" {
                requestedBody = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            } else if request.url?.path == "/api/v1/auth/student-sign-in-codes/verify" {
                verifiedBody = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            }
            lock.unlock()

            switch request.url?.path {
            case "/api/v1/auth/student-sign-in-codes":
                return .json(
                    status: 202,
                    headers: ["X-Request-ID": "req-app-code"],
                    body: #"{"data":{"challengeId":"challenge-app","expiresAt":"2026-08-14T01:00:00Z"},"meta":{"requestId":"req-app-code"}}"#
                )
            case "/api/v1/auth/student-sign-in-codes/verify":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-app-verify"],
                    body: Self.authEnvelopeJSON(
                        access: "app-access",
                        refresh: "app-refresh",
                        requestID: "req-app-verify"
                    )
                )
            case "/api/v1/me":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer app-access")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-app-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-app-me")
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let client = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: session,
            maximumSafeRetries: 0
        )
        let services = BackendAppServices(
            environment: .local,
            client: client,
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-test-installation")
        )
        let suiteName = "BackendFoundationTests.app-state-auth.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        let didRequestCode = await state.sendLoginCode(
            to: "Student@Example.edu ",
            channel: .email,
            locale: "en-US"
        )
        XCTAssertTrue(didRequestCode)
        let didSignIn = await state.signInWithCode(
            "123456",
            contact: "student@example.edu",
            channel: .email
        )
        XCTAssertTrue(didSignIn)

        XCTAssertEqual(paths, [
            "/api/v1/auth/student-sign-in-codes",
            "/api/v1/auth/student-sign-in-codes/verify",
            "/api/v1/me"
        ])
        XCTAssertEqual(requestedBody["organizationCode"] as? String, "BNBU")
        XCTAssertEqual(requestedBody["account"] as? String, "student@example.edu")
        XCTAssertEqual(requestedBody["channel"] as? String, "EMAIL")
        XCTAssertEqual(requestedBody["locale"] as? String, "en")
        XCTAssertEqual(verifiedBody["challengeId"] as? String, "challenge-app")
        XCTAssertEqual(verifiedBody["deviceId"] as? String, "ios-test-installation")
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.isRemoteMode)
        XCTAssertTrue(state.isAPIV1Session)
        XCTAssertTrue(state.isEmailVerified)
        XCTAssertEqual(state.workspace.student.id, "student-1")
        XCTAssertEqual(state.workspace.student.name, "测试学生")
        XCTAssertEqual(state.workspace.student.email, "student@example.edu")
        XCTAssertEqual(authStore.session?.accessToken, "app-access")
    }

    @MainActor
    func testAppStateRestoresAndRevokesContract15Session() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "restored-access", refresh: "restored-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/me":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer restored-access")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-restore-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-restore-me")
                )
            case "/api/v1/auth/logout":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer restored-access")
                let body = (try? JSONSerialization.jsonObject(with: Self.bodyData(from: request))) as? [String: Any]
                XCTAssertEqual(body?["refreshToken"] as? String, "restored-refresh")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-restore-logout"],
                    body: #"{"data":{},"meta":{"requestId":"req-restore-logout"}}"#
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let client = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: session,
            maximumSafeRetries: 0
        )
        let services = BackendAppServices(
            environment: .local,
            client: client,
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-restore-installation")
        )
        let suiteName = "BackendFoundationTests.app-state-restore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.isAPIV1Session)
        XCTAssertTrue(state.isEmailVerified)
        XCTAssertEqual(state.workspace.student.id, "student-1")
        XCTAssertEqual(state.workspace.student.email, "s***@example.edu")

        await state.logout()
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertFalse(state.isAPIV1Session)
        XCTAssertNil(authStore.session)
        XCTAssertEqual(paths, ["/api/v1/me", "/api/v1/auth/logout"])
    }

    @MainActor
    func testAPIV1PreferenceSyncPreservesLocalLanguageAndServerCommunicationFlags() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "preference-access", refresh: "preference-refresh")
        )
        let lock = NSLock()
        var operations: [String] = []
        var updateBody: [String: Any] = [:]
        let session = makeSession { request in
            let operation = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            lock.lock()
            operations.append(operation)
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-preference-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-preference-me")
                )
            case "/api/v1/me/preferences":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer preference-access")
                if request.httpMethod == "GET" {
                    return .json(
                        status: 200,
                        headers: ["X-Request-ID": "req-preference-load"],
                        body: """
                        {"data":{"locale":"zh-CN","pushEnabled":false,"emailEnabled":true,"version":4},"meta":{"requestId":"req-preference-load"}}
                        """
                    )
                }
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
                updateBody = ((try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]) ?? [:]
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-preference-update"],
                    body: """
                    {"data":{"locale":"en","pushEnabled":false,"emailEnabled":true,"version":5},"meta":{"requestId":"req-preference-update"}}
                    """
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-preference-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-preference-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-preference-installation")
        )
        let suiteName = "BackendFoundationTests.preferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(BNBULanguage.english.rawValue, forKey: BNBULanguage.defaultsKey)
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        await state.refreshAPIV1Preferences()
        XCTAssertEqual(defaults.string(forKey: BNBULanguage.defaultsKey), BNBULanguage.english.rawValue)
        await state.synchronizeAPIV1Locale("en")

        XCTAssertEqual(updateBody["locale"] as? String, "en")
        XCTAssertEqual(updateBody["pushEnabled"] as? Bool, false)
        XCTAssertEqual(updateBody["emailEnabled"] as? Bool, true)
        XCTAssertEqual(updateBody["expectedVersion"] as? Int, 4)
        XCTAssertNil(state.preferenceSyncNotice)
        XCTAssertEqual(operations, [
            "GET /api/v1/me",
            "GET /api/v1/me/preferences",
            "PATCH /api/v1/me/preferences"
        ])
    }

    @MainActor
    func testAPIV1Preference503KeepsTheOnDeviceLanguageSelection() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "preference-503-access", refresh: "preference-503-refresh")
        )
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-preference-503-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-preference-503-me")
                )
            case "/api/v1/me/preferences":
                return .json(
                    status: 503,
                    headers: ["X-Request-ID": "req-preference-503"],
                    body: Self.errorJSON(
                        code: "SYSTEM_MODE_UNSUPPORTED",
                        requestID: "req-preference-503"
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-preference-503-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-preference-503-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-preference-503")
        )
        let suiteName = "BackendFoundationTests.preferences-503.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(BNBULanguage.english.rawValue, forKey: BNBULanguage.defaultsKey)
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        await state.refreshAPIV1Preferences()
        await state.synchronizeAPIV1Locale("zh-CN")

        XCTAssertTrue(state.isAuthenticated)
        XCTAssertEqual(defaults.string(forKey: BNBULanguage.defaultsKey), BNBULanguage.english.rawValue)
        XCTAssertEqual(
            state.preferenceSyncNotice,
            BNBUL10n.text("云端偏好同步暂未开放，本机语言设置仍然有效。")
        )
    }

    @MainActor
    func testAPIV1ExemptionListUsesStructuredContractTypesAndServerLifecycle() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "exemption-access", refresh: "exemption-refresh")
        )
        let lock = NSLock()
        var operations: [String] = []
        let session = makeSession { request in
            lock.lock()
            operations.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exemption-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-exemption-me")
                )
            case "/api/v1/exemption-application-details":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer exemption-access")
                XCTAssertEqual(request.url?.query, "limit=100")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exemption-list"],
                    body: """
                    {"data":[
                      {"id":"draft-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","applicationType":"PHYSICAL_TEST","applicationSubtype":"RUN_800M","organizationName":null,"reason":"Medical documentation","mediaIds":["media-1"],"status":"DRAFT","publicComment":null,"submittedAt":null,"decidedAt":null,"version":1},
                      {"id":"submitted-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","applicationType":"EXERCISE_CHECK_IN","applicationSubtype":"SCHOOL_TEAM","organizationName":"BNBU Badminton Team","reason":"Approved team activity","mediaIds":[],"status":"SUBMITTED","publicComment":null,"submittedAt":"2026-08-14T01:00:00Z","decidedAt":null,"version":2},
                      {"id":"supplement-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","applicationType":"SPECIAL_CIRCUMSTANCE","applicationSubtype":"SPECIAL_CIRCUMSTANCE","organizationName":null,"reason":"Special circumstance","mediaIds":[],"status":"SUPPLEMENT_REQUIRED","publicComment":"Please add one document","submittedAt":"2026-08-14T02:00:00Z","decidedAt":null,"version":3}
                    ],"meta":{"requestId":"req-exemption-list","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
                    """
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-exemption-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-exemption-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-exemption-installation")
        )
        let suiteName = "BackendFoundationTests.exemptions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        await state.refreshRemoteExemptions()

        XCTAssertFalse(state.canSubmitExemptions)
        XCTAssertEqual(state.workspace.exemptions.map(\.item), [.run800m, .team, .specialCircumstance])
        XCTAssertEqual(state.workspace.exemptions.map(\.status), [.draft, .pending, .supplementRequired])
        XCTAssertEqual(state.workspace.exemptions.first?.proofFiles.first?.id, "media-1")
        XCTAssertEqual(state.workspace.exemptions[1].organization, "BNBU Badminton Team")
        XCTAssertEqual(state.workspace.exemptions.last?.teacherFeedback, "Please add one document")
        XCTAssertEqual(operations, [
            "GET /api/v1/me",
            "GET /api/v1/exemption-application-details"
        ])
    }

    @MainActor
    func testAPIV1Exemption503PreservesTheLastSuccessfulProjection() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "exemption-503-access", refresh: "exemption-503-refresh")
        )
        let lock = NSLock()
        var listCallCount = 0
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exemption-503-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-exemption-503-me")
                )
            case "/api/v1/exemption-application-details":
                lock.lock()
                listCallCount += 1
                let call = listCallCount
                lock.unlock()
                if call == 1 {
                    return .json(
                        status: 200,
                        headers: ["X-Request-ID": "req-exemption-first"],
                        body: """
                        {"data":[{"id":"kept-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","applicationType":"PHYSICAL_TEST","applicationSubtype":"RUN_1000M","organizationName":null,"reason":"Keep this projection","mediaIds":[],"status":"SUBMITTED","publicComment":null,"submittedAt":"2026-08-14T01:00:00Z","decidedAt":null,"version":1}],"meta":{"requestId":"req-exemption-first","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
                        """
                    )
                }
                return .json(
                    status: 503,
                    headers: ["X-Request-ID": "req-exemption-503"],
                    body: Self.errorJSON(
                        code: "SYSTEM_MODE_UNSUPPORTED",
                        requestID: "req-exemption-503"
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-exemption-503-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-exemption-503-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-exemption-503")
        )
        let suiteName = "BackendFoundationTests.exemptions-503.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        await state.refreshRemoteExemptions()
        XCTAssertEqual(state.workspace.exemptions.map(\.id), ["kept-1"])

        await state.refreshRemoteExemptions()

        XCTAssertEqual(state.workspace.exemptions.map(\.id), ["kept-1"])
        XCTAssertEqual(
            state.errorMessage,
            BNBUL10n.text("免测申请服务暂未开放，当前保留最近一次同步结果。")
        )
        XCTAssertEqual(listCallCount, 2)
    }

    @MainActor
    func testAPIV1LogoutFailureStillClearsDeviceSessionAndReportsRemoteRevocation() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "restored-access", refresh: "restored-refresh")
        )
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-restore-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-restore-me")
                )
            case "/api/v1/auth/logout":
                return .json(
                    status: 503,
                    headers: ["X-Request-ID": "req-logout-failed"],
                    body: Self.errorJSON(
                        code: "SYSTEM_MODE_UNSUPPORTED",
                        requestID: "req-logout-failed"
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-logout-installation")
        )
        let suiteName = "BackendFoundationTests.app-state-failed-logout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        await state.logout()

        XCTAssertFalse(state.isAuthenticated)
        XCTAssertNil(authStore.session)
        XCTAssertEqual(
            state.errorMessage,
            BNBUL10n.text("本机已退出，但服务器会话撤销失败。如账号存在风险，请联系管理员。")
        )
    }

    @MainActor
    func testAPIV1EmailRebindRequiresCurrentAndNewCodes() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "rebind-access", refresh: "rebind-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        var requestBody: [String: Any] = [:]
        var verifyBody: [String: Any] = [:]
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-rebind-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-rebind-me")
                )
            case "/api/v1/me/email-verification-challenges":
                requestBody = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any] ?? [:]
                return .json(
                    status: 202,
                    headers: ["X-Request-ID": "req-rebind-start"],
                    body: #"{"data":{"challengeId":"challenge-rebind","mode":"REBIND","expiresAt":"2099-08-14T01:00:00Z"},"meta":{"requestId":"req-rebind-start"}}"#
                )
            case "/api/v1/me/email-verification-challenges/challenge-rebind/verify":
                verifyBody = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any] ?? [:]
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-rebind-finish"],
                    body: Self.studentCurrentUserEnvelopeJSON(
                        requestID: "req-rebind-finish",
                        emailMasked: "n***@example.edu",
                        userVersion: 3
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-rebind-installation")
        )
        let suiteName = "BackendFoundationTests.app-state-email-rebind.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )

        await state.restoreBackendSession()
        let didRequestRebind = await state.requestContactEmailVerification(
            email: " New@Example.edu ",
            locale: "en-US"
        )
        XCTAssertTrue(didRequestRebind)
        XCTAssertTrue(state.contactVerificationRequiresCurrentEmailCode)
        XCTAssertEqual(requestBody["email"] as? String, "new@example.edu")
        XCTAssertEqual(requestBody["locale"] as? String, "en")
        XCTAssertEqual(requestBody["expectedVersion"] as? Int, 2)

        let didAcceptMissingCurrentCode = await state.completeContactEmailVerification(
            newEmailCode: "222222",
            currentEmailCode: nil,
            email: "new@example.edu"
        )
        XCTAssertFalse(didAcceptMissingCurrentCode)
        XCTAssertEqual(paths.count, 2, "Missing current proof must fail before HTTP")

        let didCompleteRebind = await state.completeContactEmailVerification(
            newEmailCode: "222222",
            currentEmailCode: "111111",
            email: "new@example.edu"
        )
        XCTAssertTrue(didCompleteRebind)
        XCTAssertEqual(verifyBody["currentEmailCode"] as? String, "111111")
        XCTAssertEqual(verifyBody["newEmailCode"] as? String, "222222")
        XCTAssertEqual(state.workspace.student.email, "new@example.edu")
        XCTAssertTrue(state.isEmailVerified)
        XCTAssertFalse(state.contactVerificationRequiresCurrentEmailCode)
        XCTAssertEqual(paths, [
            "/api/v1/me",
            "/api/v1/me/email-verification-challenges",
            "/api/v1/me/email-verification-challenges/challenge-rebind/verify"
        ])
    }

    func testContract15RecordDraftSubmitAndDiscardAllowEmptyCourseDescription() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "record-access", refresh: "record-refresh"))
        let lock = NSLock()
        var paths: [String] = []
        var idempotencyKeys: [String] = []
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") { idempotencyKeys.append(key) }
            lock.unlock()
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer record-access")
            switch request.url?.path {
            case "/api/v1/exercise-records":
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-record-create"],
                    body: Self.exerciseRecordEnvelopeJSON(status: "DRAFT", description: nil, version: 1, requestID: "req-record-create")
                )
            case "/api/v1/exercise-records/record-1/submit":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-record-submit"],
                    body: Self.exerciseRecordEnvelopeJSON(status: "SUBMITTED", description: nil, version: 2, requestID: "req-record-submit")
                )
            case "/api/v1/exercise-records/record-1/discard":
                let body = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(body?["reason"] as? String, "STUDENT_ABANDONED_DRAFT")
                XCTAssertEqual(body?["expectedVersion"] as? Int, 1)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-record-discard"],
                    body: Self.exerciseRecordEnvelopeJSON(status: "CANCELLED", description: nil, version: 2, requestID: "req-record-discard")
                )
            default:
                return .json(status: 404, headers: ["X-Request-ID": "req-404"], body: Self.errorJSON(code: "USER_NOT_FOUND", requestID: "req-404"))
            }
        }
        let auth = BackendAuthSessionController(
            client: StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session),
            store: store
        )
        let gateway = AuthoritativeExerciseRecordGateway(auth: auth)
        let draft = try await gateway.createDraft(APIV1CreateExerciseRecordRequest(
            sessionId: "exercise-session-1",
            creditType: .courseRelated,
            sportType: "RUNNING",
            sportName: nil,
            description: nil,
            clientRequestId: "ios-record-1"
        ))
        let submitted = try await gateway.submit(
            recordID: draft.value.id,
            request: APIV1SubmitExerciseRecordRequest(mediaIds: ["media-1"], expectedVersion: draft.value.version)
        )
        let discardableDraft = try await gateway.createDraft(APIV1CreateExerciseRecordRequest(
            sessionId: "exercise-session-3",
            creditType: .courseRelated,
            sportType: "RUNNING",
            sportName: nil,
            description: nil,
            clientRequestId: "ios-record-3"
        ))
        let discarded = try await gateway.discard(
            recordID: discardableDraft.value.id,
            request: APIV1VersionedReasonRequest(
                reason: "STUDENT_ABANDONED_DRAFT",
                expectedVersion: discardableDraft.value.version
            )
        )

        XCTAssertEqual(paths, [
            "/api/v1/exercise-records",
            "/api/v1/exercise-records/record-1/submit",
            "/api/v1/exercise-records",
            "/api/v1/exercise-records/record-1/discard"
        ])
        XCTAssertEqual(idempotencyKeys.count, 4)
        XCTAssertNil(draft.value.description)
        XCTAssertEqual(submitted.value.status, .submitted)
        XCTAssertEqual(discarded.value.status, .cancelled)

        do {
            _ = try await gateway.createDraft(APIV1CreateExerciseRecordRequest(
                sessionId: "exercise-session-2",
                creditType: .general,
                sportType: "RUNNING",
                sportName: nil,
                description: nil,
                clientRequestId: "ios-record-2"
            ))
            XCTFail("GENERAL must fail before transport without a nonblank description")
        } catch let error as APITransportError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertEqual(paths.count, 4)
    }

    @MainActor
    func testAPIV1LocalOnlyDraftCanBeDiscardedWithoutNetwork() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "local-discard-access", refresh: "local-discard-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            lock.lock()
            paths.append(path)
            lock.unlock()
            guard path == "/api/v1/me" else {
                XCTFail("A local-only draft discard must not call \(path)")
                return .json(
                    status: 500,
                    headers: ["X-Request-ID": "req-local-discard-unexpected"],
                    body: Self.errorJSON(code: "UNEXPECTED_REQUEST", requestID: "req-local-discard-unexpected")
                )
            }
            return .json(
                status: 200,
                headers: ["X-Request-ID": "req-local-discard-me"],
                body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-local-discard-me")
            )
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-local-discard-installation")
        )
        let suiteName = "BackendFoundationTests.local-only-discard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let localStore = AppLocalStore(defaults: defaults, legacyDefaults: defaults)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T00:00:00Z"))
        let completedSession = ExerciseSession(
            id: "local-only-session",
            studentID: "student-1",
            category: .general,
            sportType: .running,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: start.addingTimeInterval(ExerciseSession.oneHour),
            status: .completed,
            locationStatus: .unavailable
        )
        let draft = CheckInDraft(
            id: "local-only-draft",
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "Synthetic local draft",
            proofAttachments: [],
            updatedAt: "2026-08-14 09:00"
        )
        XCTAssertTrue(localStore.saveExerciseSession(completedSession))
        XCTAssertTrue(localStore.saveDraft(draft))
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: localStore,
            backendServices: services
        )
        await state.restoreBackendSession()

        let discarded = await state.discardCompletedCheckInDraft()
        XCTAssertTrue(discarded)
        XCTAssertEqual(paths, ["/api/v1/me"])
        XCTAssertNil(state.exerciseSession)
        XCTAssertNil(state.draft)
    }

    @MainActor
    func testAPIV1DraftDiscardRefreshesAStaleVersionAfterConflict() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "discard-access", refresh: "discard-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        var discardVersions: [Int] = []
        var discardCount = 0
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            lock.lock()
            paths.append(path)
            lock.unlock()
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer discard-access")

            switch path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-discard-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-discard-me")
                )
            case "/api/v1/exercise-sessions/exercise-session-1":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-discard-session"],
                    body: Self.exerciseSessionEnvelopeJSON(
                        status: "COMPLETED",
                        version: 4,
                        actualDurationSeconds: 3_600,
                        pausedDurationSeconds: 0,
                        endedAt: "2026-08-14T01:00:00Z",
                        endReason: "USER_COMPLETED",
                        requestID: "req-discard-session"
                    )
                )
            case "/api/v1/exercise-records" where request.httpMethod == "GET":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-discard-list"],
                    body: Self.exerciseRecordListEnvelopeJSON(
                        status: "DRAFT",
                        version: 1,
                        requestID: "req-discard-list"
                    )
                )
            case "/api/v1/exercise-records/record-1" where request.httpMethod == "GET":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-discard-refresh"],
                    body: Self.exerciseRecordEnvelopeJSON(
                        status: "DRAFT",
                        description: nil,
                        version: 2,
                        requestID: "req-discard-refresh",
                        classSectionID: "section-1",
                        businessDate: "2026-08-14"
                    )
                )
            case "/api/v1/exercise-records/record-1/discard":
                let body = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                let expectedVersion = body?["expectedVersion"] as? Int ?? -1
                lock.lock()
                discardVersions.append(expectedVersion)
                discardCount += 1
                let currentDiscardCount = discardCount
                lock.unlock()
                if currentDiscardCount == 1 {
                    return .json(
                        status: 409,
                        headers: ["X-Request-ID": "req-discard-conflict"],
                        body: Self.errorJSON(code: "VERSION_CONFLICT", requestID: "req-discard-conflict")
                    )
                }
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-discard-success"],
                    body: Self.exerciseRecordEnvelopeJSON(
                        status: "CANCELLED",
                        description: nil,
                        version: 3,
                        requestID: "req-discard-success",
                        classSectionID: "section-1",
                        businessDate: "2026-08-14"
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-discard-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-discard-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-discard-installation")
        )
        let suiteName = "BackendFoundationTests.app-state-discard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let localStore = AppLocalStore(defaults: defaults, legacyDefaults: defaults)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T00:00:00Z"))
        let completedSession = ExerciseSession(
            id: "exercise-session-1",
            studentID: "student-1",
            category: .general,
            sportType: .running,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: start.addingTimeInterval(ExerciseSession.oneHour),
            status: .completed,
            locationStatus: .unavailable
        )
        let draft = CheckInDraft(
            id: "discard-draft",
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "Synthetic running session",
            proofAttachments: [],
            updatedAt: "2026-08-14 09:00"
        )
        let scope = "apiv1-exercise-record:submit:exercise-session-1"
        let attempt = PendingRemoteMutationAttempt.create(
            scope: scope,
            fingerprint: "discard-fingerprint",
            serverIdentity: BackendEnvironment.local.baseURL.absoluteString,
            studentID: "student-1"
        )
        XCTAssertTrue(localStore.saveExerciseSession(completedSession))
        XCTAssertTrue(localStore.saveDraft(draft))
        XCTAssertTrue(localStore.savePendingRemoteMutations([scope: attempt]))

        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: localStore,
            backendServices: services
        )
        await state.restoreBackendSession()

        XCTAssertTrue(state.isAPIV1Session)
        XCTAssertEqual(state.exerciseSession, completedSession)
        let discarded = await state.discardCompletedCheckInDraft()
        XCTAssertTrue(discarded)
        XCTAssertEqual(discardVersions, [1, 2])
        XCTAssertEqual(Array(paths.suffix(5)), [
            "/api/v1/exercise-sessions/exercise-session-1",
            "/api/v1/exercise-records",
            "/api/v1/exercise-records/record-1/discard",
            "/api/v1/exercise-records/record-1",
            "/api/v1/exercise-records/record-1/discard"
        ])
        XCTAssertNil(state.exerciseSession)
        XCTAssertNil(state.draft)
        XCTAssertNil(localStore.readPendingRemoteMutations().value?[scope])
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
        let uploadProgress = UploadProgressRecorder()
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
                    body: #"{"data":{"uploadSessionId":"upload-session-1","mediaId":"media-1","uploadUrl":"https://private-upload.example.test/private/upload","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2099-08-06T01:00:00Z"},"meta":{"requestId":"req-media-init"}}"#
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
                    body: Self.mediaEnvelopeJSON(status: "BOUND", requestID: "req-media-bind")
                )
            case "/api/v1/media/media-1":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-available"],
                    body: Self.mediaEnvelopeJSON(status: "AVAILABLE", requestID: "req-media-available")
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
                enrollmentId: nil,
                businessPurpose: .exerciseRecord,
                mediaType: .image,
                mimeType: "image/jpeg",
                fileSizeBytes: bytes.count,
                captureSource: .inAppCamera,
                declaredContentSha256: nil,
                durationSeconds: nil
            ),
            progressHandler: { uploadProgress.record($0) }
        )

        XCTAssertEqual(outcome.media.uploadStatus, .bound)
        XCTAssertEqual(outcome.requestId, "req-media-bind")
        XCTAssertEqual(uploadedBytes, bytes)
        XCTAssertEqual(uploadProgress.values.first, APIUploadProgress(bytesSent: 0, totalBytes: 4))
        XCTAssertEqual(uploadProgress.values.last, APIUploadProgress(bytesSent: 4, totalBytes: 4))
        XCTAssertEqual(uploadProgress.values.last?.percentage, 100)
        XCTAssertEqual(operations, [
            "POST /api/v1/media-uploads",
            "PUT /private/upload",
            "POST /api/v1/media-uploads/upload-session-1/confirm",
            "POST /api/v1/media/media-1/bind"
        ])
    }

    func testMediaPipelineRenewsAnExpiredReplayedUploadCapability() async throws {
        let store = MemoryAuthSessionStore(
            session: Self.authSession(access: "media-access", refresh: "media-refresh")
        )
        let lock = NSLock()
        var initiationCount = 0
        var initiationKeys: [String] = []
        var paths: [String] = []
        let session = makeSession { request in
            lock.lock()
            paths.append(request.url?.path ?? "")
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/media-uploads":
                lock.lock()
                initiationCount += 1
                let currentCount = initiationCount
                if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                    initiationKeys.append(key)
                }
                lock.unlock()
                if currentCount == 1 {
                    return .json(
                        status: 201,
                        headers: ["X-Request-ID": "req-media-init-expired"],
                        body: #"{"data":{"uploadSessionId":"upload-session-expired","mediaId":"media-expired","uploadUrl":"https://private-upload.example.test/private/expired","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2020-08-06T01:00:00Z"},"meta":{"requestId":"req-media-init-expired"}}"#
                    )
                }
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-media-init-renewed"],
                    body: #"{"data":{"uploadSessionId":"upload-session-renewed","mediaId":"media-renewed","uploadUrl":"https://private-upload.example.test/private/renewed","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2099-08-06T01:00:00Z"},"meta":{"requestId":"req-media-init-renewed"}}"#
                )
            case "/api/v1/media/media-expired":
                let pending = Self.mediaEnvelopeJSON(
                    status: "PENDING_UPLOAD",
                    requestID: "req-media-expired-status"
                ).replacingOccurrences(of: #""id":"media-1""#, with: #""id":"media-expired""#)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-expired-status"],
                    body: pending
                )
            case "/private/renewed":
                return .json(status: 200, headers: ["ETag": "etag-renewed"], body: "{}")
            case "/api/v1/media-uploads/upload-session-renewed/confirm":
                let uploaded = Self.mediaEnvelopeJSON(
                    status: "UPLOADED",
                    requestID: "req-media-confirm-renewed"
                ).replacingOccurrences(of: #""id":"media-1""#, with: #""id":"media-renewed""#)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-confirm-renewed"],
                    body: uploaded
                )
            case "/api/v1/media/media-renewed/bind":
                let bound = Self.mediaEnvelopeJSON(
                    status: "BOUND",
                    requestID: "req-media-bind-renewed"
                ).replacingOccurrences(of: #""id":"media-1""#, with: #""id":"media-renewed""#)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-bind-renewed"],
                    body: bound
                )
            default:
                XCTFail("Unexpected expired-capability recovery route: \(request.url?.path ?? "")")
                return .json(status: 404, headers: [:], body: "{}")
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let coordinator = MediaUploadCoordinator(client: client, auth: auth)

        let outcome = try await coordinator.uploadAndBind(
            bytes: Data([0xff, 0xd8, 0xff, 0xd9]),
            request: Self.exerciseImageUploadRequest,
            idempotencyKeySeed: "ios-expired-capability-test"
        )

        XCTAssertEqual(outcome.media.id, "media-renewed")
        XCTAssertEqual(outcome.media.uploadStatus, .bound)
        XCTAssertEqual(initiationKeys.count, 2)
        XCTAssertEqual(Set(initiationKeys).count, 2)
        XCTAssertEqual(paths, [
            "/api/v1/media-uploads",
            "/api/v1/media/media-expired",
            "/api/v1/media-uploads",
            "/private/renewed",
            "/api/v1/media-uploads/upload-session-renewed/confirm",
            "/api/v1/media/media-renewed/bind"
        ])
    }

    func testMediaPipelineClassifiesMissingUploadEntityTag() async throws {
        let store = MemoryAuthSessionStore(
            session: Self.authSession(access: "media-access", refresh: "media-refresh")
        )
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/v1/media-uploads":
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-media-init"],
                    body: #"{"data":{"uploadSessionId":"upload-session-1","mediaId":"media-1","uploadUrl":"https://private-upload.example.test/private/upload","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2099-08-06T01:00:00Z"},"meta":{"requestId":"req-media-init"}}"#
                )
            case "/private/upload":
                return .json(status: 200, headers: [:], body: "{}")
            default:
                XCTFail("Missing ETag must stop before confirmation")
                return .json(status: 404, headers: [:], body: "{}")
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let coordinator = MediaUploadCoordinator(client: client, auth: auth)

        do {
            _ = try await coordinator.uploadAndBind(
                bytes: Data([0xff, 0xd8, 0xff, 0xd9]),
                request: Self.exerciseImageUploadRequest
            )
            XCTFail("A signed PUT response without ETag must be rejected")
        } catch let error as MediaUploadPipelineError {
            XCTAssertEqual(error, .missingUploadEntityTag)
            XCTAssertEqual(error.diagnosticCode, "MEDIA_UPLOAD_ETAG_MISSING")
            XCTAssertNil(error.requestId)
        }
    }

    func testMediaPipelineExtractsSafeObjectStorageRejectionCode() async throws {
        let store = MemoryAuthSessionStore(
            session: Self.authSession(access: "media-access", refresh: "media-refresh")
        )
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/v1/media-uploads":
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-media-init"],
                    body: #"{"data":{"uploadSessionId":"upload-session-1","mediaId":"media-1","uploadUrl":"https://private-upload.example.test/private/upload","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2099-08-06T01:00:00Z"},"meta":{"requestId":"req-media-init"}}"#
                )
            case "/private/upload":
                return StubHTTPResponse(
                    status: 403,
                    headers: ["Content-Type": "application/xml"],
                    data: Data(
                        "<Error><Code>SignatureDoesNotMatch</Code><Message>sensitive</Message></Error>".utf8
                    )
                )
            default:
                XCTFail("A rejected signed PUT must stop before confirmation")
                return .json(status: 404, headers: [:], body: "{}")
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let coordinator = MediaUploadCoordinator(client: client, auth: auth)

        do {
            _ = try await coordinator.uploadAndBind(
                bytes: Data([0xff, 0xd8, 0xff, 0xd9]),
                request: Self.exerciseImageUploadRequest
            )
            XCTFail("A signed PUT HTTP 403 must be rejected")
        } catch let error as MediaUploadPipelineError {
            XCTAssertEqual(
                error,
                .signedUploadRejected(
                    statusCode: 403,
                    providerCode: "SignatureDoesNotMatch"
                )
            )
            XCTAssertEqual(
                error.diagnosticCode,
                "MEDIA_SIGNED_PUT_HTTP_403_SIGNATUREDOESNOTMATCH"
            )
            XCTAssertNil(error.requestId)
        }
    }

    func testMediaPipelineClassifiesConfirmationProjectionMismatch() async throws {
        let store = MemoryAuthSessionStore(
            session: Self.authSession(access: "media-access", refresh: "media-refresh")
        )
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/v1/media-uploads":
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-media-init"],
                    body: #"{"data":{"uploadSessionId":"upload-session-1","mediaId":"media-1","uploadUrl":"https://private-upload.example.test/private/upload","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2099-08-06T01:00:00Z"},"meta":{"requestId":"req-media-init"}}"#
                )
            case "/private/upload":
                return .json(status: 200, headers: ["ETag": "etag-private-1"], body: "{}")
            case "/api/v1/media-uploads/upload-session-1/confirm":
                let mismatched = Self.mediaEnvelopeJSON(
                    status: "UPLOADED",
                    requestID: "req-media-confirm"
                ).replacingOccurrences(
                    of: #""sessionId":"exercise-session-1""#,
                    with: #""sessionId":"another-session""#
                )
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-confirm"],
                    body: mismatched
                )
            default:
                XCTFail("Projection mismatch must stop before binding")
                return .json(status: 404, headers: [:], body: "{}")
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let coordinator = MediaUploadCoordinator(client: client, auth: auth)

        do {
            _ = try await coordinator.uploadAndBind(
                bytes: Data([0xff, 0xd8, 0xff, 0xd9]),
                request: Self.exerciseImageUploadRequest
            )
            XCTFail("A mismatched media confirmation target must be rejected")
        } catch let error as MediaUploadPipelineError {
            XCTAssertEqual(
                error,
                .confirmationProjectionMismatch(
                    field: "session_id",
                    requestId: "req-media-confirm"
                )
            )
            XCTAssertEqual(error.diagnosticCode, "MEDIA_CONFIRM_SESSION_ID_MISMATCH")
            XCTAssertEqual(error.requestId, "req-media-confirm")
        }
    }

    func testMediaPipelineDiagnosticCodesIncludeStatusAndProcessingStage() {
        XCTAssertEqual(
            MediaUploadPipelineError.statusProjectionMismatch(
                field: "session_id",
                requestId: "req-media-status"
            ).diagnosticCode,
            "MEDIA_STATUS_SESSION_ID_MISMATCH"
        )
        XCTAssertEqual(
            MediaUploadPipelineError.bindingProjectionMismatch(
                field: "upload_status",
                requestId: "req-media-bind"
            ).diagnosticCode,
            "MEDIA_BIND_UPLOAD_STATUS_MISMATCH"
        )
        XCTAssertEqual(
            MediaUploadPipelineError.processingStopped(
                status: "FAILED",
                requestId: "req-media-failed"
            ).diagnosticCode,
            "MEDIA_PROCESSING_STOPPED_FAILED"
        )
        XCTAssertEqual(
            MediaUploadPipelineError.processingTimedOut(
                status: "PROCESSING",
                requestId: "req-media-timeout"
            ).diagnosticCode,
            "MEDIA_PROCESSING_TIMEOUT_PROCESSING"
        )
        XCTAssertEqual(
            MediaUploadPipelineError.signedUploadRejected(
                statusCode: 403,
                providerCode: nil
            ).diagnosticCode,
            "MEDIA_SIGNED_PUT_HTTP_403"
        )
        XCTAssertEqual(
            MediaUploadPipelineError.signedUploadRejected(
                statusCode: 403,
                providerCode: "SignatureDoesNotMatch"
            ).diagnosticCode,
            "MEDIA_SIGNED_PUT_HTTP_403_SIGNATUREDOESNOTMATCH"
        )
    }

    func testSessionStartMapsQualificationAndBeijingWindowDenials() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "session-access", refresh: "session-refresh"))
        let lock = NSLock()
        var idempotencyKeys: [String] = []
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/exercise-sessions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-access")
            lock.lock()
            idempotencyKeys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
            lock.unlock()
            return .json(
                status: 409,
                headers: ["X-Request-ID": "req-qualified"],
                body: Self.errorJSON(code: "SESSION_ALREADY_COMPLETED", requestID: "req-qualified")
            )
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let gateway = AuthoritativeExerciseSessionGateway(auth: auth)
        let request = APIV1StartSessionRequest(
            enrollmentId: "enrollment-1",
            clientObservedAt: "2026-08-10T10:00:00Z"
        )

        for _ in 0..<2 {
            do {
                _ = try await gateway.start(request)
                XCTFail("Qualified students must not receive a new session")
            } catch let error as ExerciseSessionAdmissionError {
                XCTAssertEqual(error, .qualificationReached(requestId: "req-qualified"))
                XCTAssertEqual(error.localizedDescription, "已达到合格时长，无需继续打卡。")
            }
        }

        XCTAssertEqual(idempotencyKeys.count, 2)
        XCTAssertFalse(idempotencyKeys.contains(where: \.isEmpty))
        XCTAssertNotEqual(idempotencyKeys[0], idempotencyKeys[1])

        let windowError = APITransportError.failure(
            statusCode: 409,
            envelope: APIErrorEnvelope(
                code: "SESSION_OUTSIDE_TIME_WINDOW",
                message: "closed",
                details: .object([:]),
                requestId: "req-window",
                timestamp: "2026-08-10T14:00:01Z"
            )
        )
        XCTAssertEqual(
            ExerciseSessionAdmissionPolicy.startError(from: windowError),
            .outsideBeijingWindow(requestId: "req-window")
        )
    }

    func testStudentWorkspaceGatewayLoadsOnlyActiveAuthorizedCourseGraph() async throws {
        let store = MemoryAuthSessionStore(
            session: Self.authSession(access: "workspace-access", refresh: "workspace-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        var queries: [String: [String: String]] = [:]
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            lock.lock()
            paths.append(path)
            queries[path] = Dictionary(uniqueKeysWithValues: URLComponents(
                url: request.url!,
                resolvingAgainstBaseURL: false
            )?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
            lock.unlock()
            switch path {
            case "/api/v1/semesters/current":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-semester"],
                    body: #"{"data":{"id":"semester-1","organizationId":"org-1","academicYear":"2026-2027","termCode":"FIRST","displayName":"2026 秋季","startDate":"2026-09-01","endDate":"2027-01-15","status":"CURRENT","isCurrent":true,"createdBy":null,"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","version":1},"meta":{"requestId":"req-semester"}}"#
                )
            case "/api/v1/enrollments":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-enrollments"],
                    body: #"{"data":[{"id":"enrollment-1","organizationId":"org-1","semesterId":"semester-1","classSectionId":"section-1","studentId":"student-1","source":"QR_CODE","sourceReferenceId":null,"status":"ACTIVE","joinedAt":"2026-09-01T00:00:00Z","endedAt":null,"endReason":null,"createdBy":"user-1","createdAt":"2026-09-01T00:00:00Z","updatedAt":"2026-09-01T00:00:00Z","version":1}],"meta":{"requestId":"req-enrollments","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}"#
                )
            case "/api/v1/class-sections":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-sections"],
                    body: #"{"data":[{"id":"section-1","organizationId":"org-1","courseId":"course-1","semesterId":"semester-1","teacherId":"teacher-1","classCode":"001","displayName":"羽毛球 001","status":"ACTIVE","isEnrollmentOpen":true,"checkInWindowMode":"AVAILABLE","checkInStartDate":null,"checkInEndDate":null,"dailyStartTime":"06:00:00","dailyEndTime":"22:00:00","submissionDeadlineAt":null,"excludedDates":[],"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","version":1}],"meta":{"requestId":"req-sections","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}"#
                )
            case "/api/v1/courses":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-courses"],
                    body: #"{"data":[{"id":"course-1","organizationId":"org-1","courseCode":"GEPE101","courseName":"大学体育（羽毛球）","description":null,"status":"ACTIVE","createdBy":null,"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","deletedAt":null,"version":1}],"meta":{"requestId":"req-courses","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}"#
                )
            case "/api/v1/teachers/teacher-1":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-teacher"],
                    body: #"{"data":{"id":"teacher-1","organizationId":"org-1","userId":"teacher-user-1","employeeNumber":"T001","fullName":"合成教师","collegeName":null,"departmentName":"体育部","title":null,"status":"ACTIVE","createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","deletedAt":null,"version":1},"meta":{"requestId":"req-teacher"}}"#
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let client = StudentAPIClient(
            baseURL: BackendEnvironment.local.baseURL,
            urlSession: session,
            maximumSafeRetries: 0
        )
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let projection = try await AuthoritativeStudentWorkspaceGateway(auth: auth)
            .load(studentID: "student-1")

        XCTAssertEqual(projection.semester.id, "semester-1")
        XCTAssertEqual(projection.enrollments.map(\.id), ["enrollment-1"])
        XCTAssertEqual(projection.classSections.map(\.id), ["section-1"])
        XCTAssertEqual(projection.courses.map(\.id), ["course-1"])
        XCTAssertEqual(projection.teachers.map(\.fullName), ["合成教师"])
        XCTAssertNil(queries["/api/v1/enrollments"]?["studentId"])
        XCTAssertEqual(queries["/api/v1/enrollments"]?["status"], "ACTIVE")
        XCTAssertEqual(queries["/api/v1/class-sections"]?["semesterId"], "semester-1")
        XCTAssertEqual(paths, [
            "/api/v1/semesters/current",
            "/api/v1/enrollments",
            "/api/v1/class-sections",
            "/api/v1/courses",
            "/api/v1/teachers/teacher-1"
        ])
    }

    @MainActor
    func testContract202SystemModeHelpNotificationsAndStructuredExemptionsNeverUseLegacyRoutes() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "capability-access", refresh: "capability-refresh")
        )
        let lock = NSLock()
        var operations: [String] = []
        let session = makeSession { request in
            let operation = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            lock.lock()
            operations.append(operation)
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/system-mode":
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-system-mode"],
                    body: #"{"data":{"mode":"READ_ONLY","policyVersion":3,"updatedAt":"2026-08-14T00:00:00Z"},"meta":{"requestId":"req-system-mode"}}"#
                )
            case "/api/v1/app-release-policy":
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let components = request.url.flatMap {
                    URLComponents(url: $0, resolvingAgainstBaseURL: false)
                }
                let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name, $0) }
                })
                XCTAssertEqual(query["platform"], "IOS")
                XCTAssertEqual(query["currentVersion"], "1.0.4")
                XCTAssertEqual(query["currentBuildNumber"], "104")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-release-policy"],
                    body: """
                    {"data":{"platform":"IOS","minimumSupportedVersion":"1.0.0","latestVersion":"1.2.0","minimumSupportedBuildNumber":100,"latestBuildNumber":120,"enforcement":"RECOMMENDED","message":"Update available","downloadUrl":"https://apps.apple.com/app/id123","effectiveAt":"2026-08-07T00:00:00Z","expiresAt":null,"policyVersion":"ios-policy-1"},"meta":{"requestId":"req-release-policy"}}
                    """
                )
            case "/api/v1/help-articles":
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertEqual(request.url?.query, "locale=en")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-help"],
                    body: #"{"data":[{"id":"help-1","category":"CHECK_IN","locale":"en","title":"Upload proof","bodyMarkdown":"Use the in-app camera.","publishedAt":"2026-08-14T00:00:00Z","version":1}],"meta":{"requestId":"req-help"}}"#
                )
            case "/api/v1/notifications":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer capability-access")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-notifications"],
                    body: #"{"data":[{"id":"notice-1","recipientUserId":"user-1","notificationType":"REVIEW_RESULT","title":"Review complete","body":"Your record was reviewed.","targetType":"EXERCISE_RECORD","targetId":"record-1","createdAt":"2026-08-14T00:00:00Z","readAt":null}],"meta":{"requestId":"req-notifications","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}"#
                )
            case "/api/v1/notifications/notice-1/read":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer capability-access")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-notification-read"],
                    body: #"{"data":{"id":"notice-1","recipientUserId":"user-1","notificationType":"REVIEW_RESULT","title":"Review complete","body":"Your record was reviewed.","targetType":"EXERCISE_RECORD","targetId":"record-1","createdAt":"2026-08-14T00:00:00Z","readAt":"2026-08-14T00:01:00Z"},"meta":{"requestId":"req-notification-read"}}"#
                )
            case "/api/v1/me/preferences":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer capability-access")
                if request.httpMethod == "GET" {
                    return .json(
                        status: 200,
                        headers: ["X-Request-ID": "req-preferences-get"],
                        body: """
                        {"data":{"locale":"en","pushEnabled":false,"emailEnabled":true,"version":2},"meta":{"requestId":"req-preferences-get"}}
                        """
                    )
                }
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
                let object = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(object?["locale"] as? String, "zh-CN")
                XCTAssertEqual(object?["pushEnabled"] as? Bool, false)
                XCTAssertEqual(object?["emailEnabled"] as? Bool, true)
                XCTAssertEqual(object?["expectedVersion"] as? Int, 2)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-preferences-update"],
                    body: """
                    {"data":{"locale":"zh-CN","pushEnabled":false,"emailEnabled":true,"version":3},"meta":{"requestId":"req-preferences-update"}}
                    """
                )
            case "/api/v1/feedback":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer capability-access")
                if request.httpMethod == "GET" {
                    XCTAssertEqual(request.url?.query, "limit=100")
                    return .json(
                        status: 200,
                        headers: ["X-Request-ID": "req-feedback-list"],
                        body: """
                        {"data":[{"id":"feedback-1","category":"BUG","content":"The timer stopped.","status":"OPEN","publicReply":null,"createdAt":"2026-08-14T00:00:00Z","updatedAt":"2026-08-14T00:00:00Z","version":1}],"meta":{"requestId":"req-feedback-list","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
                        """
                    )
                }
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
                let object = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(object?["category"] as? String, "BUG")
                XCTAssertEqual(object?["content"] as? String, "The timer stopped again.")
                let context = object?["clientContext"] as? [String: Any]
                XCTAssertEqual(context?["platform"] as? String, "IOS")
                XCTAssertNil(object?["email"])
                XCTAssertNil(object?["phone"])
                XCTAssertNil(object?["screenshots"])
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-feedback-create"],
                    body: """
                    {"data":{"id":"feedback-2","category":"BUG","content":"The timer stopped again.","status":"OPEN","publicReply":null,"createdAt":"2026-08-14T00:02:00Z","updatedAt":"2026-08-14T00:02:00Z","version":1},"meta":{"requestId":"req-feedback-create"}}
                    """
                )
            case "/api/v1/exemption-application-details":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer capability-access")
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.query, "limit=100")
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exemptions"],
                    body: """
                    {"data":[{"id":"exemption-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","applicationType":"EXERCISE_CHECK_IN","applicationSubtype":"SCHOOL_TEAM","organizationName":"BNBU Athletics","reason":"Medical certificate","mediaIds":["media-1"],"status":"SUBMITTED","publicComment":null,"submittedAt":"2026-08-14T00:03:00Z","decidedAt":null,"version":1}],"meta":{"requestId":"req-exemptions","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
                    """
                )
            default:
                XCTFail("Contract 2.0.10 capability gateway reached an unexpected route: \(operation)")
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-capability-installation")
        )
        _ = try await services.auth.restore()

        let mode = try await services.clientCapabilities.systemMode()
        let releasePolicy = try await services.clientCapabilities.appReleasePolicy(
            query: try XCTUnwrap(IOSAppReleasePolicyQuery(infoDictionary: [
                "CFBundleVersion": "104",
                "CFBundleShortVersionString": "1.0.4"
            ]))
        )
        let help = try await services.clientCapabilities.helpArticles(locale: "en")
        let notices = try await services.clientCapabilities.notifications()
        let read = try await services.clientCapabilities.markNotificationRead(id: "notice-1")
        let preferences = try await services.clientCapabilities.currentUserPreferences()
        let updatedPreferences = try await services.clientCapabilities.updateCurrentUserPreferences(
            APIV1UpdateUserPreferencesRequest(
                locale: "zh-CN",
                pushEnabled: preferences.value.pushEnabled,
                emailEnabled: preferences.value.emailEnabled,
                expectedVersion: preferences.value.version
            )
        )
        let feedback = try await services.clientCapabilities.feedback()
        let createdFeedback = try await services.clientCapabilities.createFeedback(
            APIV1CreateFeedbackRequest(
                category: "BUG",
                content: "The timer stopped again.",
                clientContext: [
                    "platform": .string(IOSPlatformContractPolicy.wireValue),
                    "appVersion": .string("1.0.4"),
                    "osVersion": .string("iOS 26.5")
                ]
            )
        )
        let exemptions = try await services.clientCapabilities.exemptionApplications()

        XCTAssertEqual(mode.value.mode, .readOnly)
        XCTAssertEqual(releasePolicy.value.platform, "IOS")
        XCTAssertEqual(releasePolicy.value.enforcement, "RECOMMENDED")
        XCTAssertEqual(help.value.first?.title, "Upload proof")
        XCTAssertNil(notices.value.first?.readAt)
        XCTAssertNotNil(read.value.readAt)
        XCTAssertEqual(preferences.value.locale, "en")
        XCTAssertEqual(updatedPreferences.value.locale, "zh-CN")
        XCTAssertEqual(updatedPreferences.value.version, 3)
        XCTAssertEqual(feedback.value.first?.id, "feedback-1")
        XCTAssertEqual(createdFeedback.value.id, "feedback-2")
        XCTAssertEqual(exemptions.value.first?.applicationType, "EXERCISE_CHECK_IN")
        XCTAssertEqual(exemptions.value.first?.applicationSubtype, "SCHOOL_TEAM")
        XCTAssertEqual(exemptions.value.first?.organizationName, "BNBU Athletics")
        XCTAssertEqual(exemptions.value.first?.status, "SUBMITTED")
        XCTAssertEqual(operations, [
            "GET /api/v1/system-mode",
            "GET /api/v1/app-release-policy",
            "GET /api/v1/help-articles",
            "GET /api/v1/notifications",
            "POST /api/v1/notifications/notice-1/read",
            "GET /api/v1/me/preferences",
            "PATCH /api/v1/me/preferences",
            "GET /api/v1/feedback",
            "POST /api/v1/feedback",
            "GET /api/v1/exemption-application-details"
        ])
    }

    func testIOSReleasePolicyUsesNumericBuildAndOnlyBlocksRequiredUpdates() throws {
        let required = try JSONDecoder().decode(
            APIV1AppReleasePolicy.self,
            from: Data("""
            {"platform":"IOS","minimumSupportedVersion":"2.0","latestVersion":"2.1","minimumSupportedBuildNumber":200,"latestBuildNumber":210,"enforcement":"REQUIRED","message":"Please update","downloadUrl":"https://apps.apple.com/app/id123","effectiveAt":"2026-08-14T00:00:00Z","expiresAt":null,"policyVersion":"ios-2"}
            """.utf8)
        )
        XCTAssertEqual(
            IOSAppReleaseContractPolicy.expectedEnforcement(
                for: required,
                currentBuildNumber: 199
            ),
            "REQUIRED"
        )
        let requirement = try XCTUnwrap(
            IOSAppReleaseContractPolicy.requiredUpdate(
                for: required,
                currentBuildNumber: 199
            )
        )
        XCTAssertEqual(requirement.minimumVersion, "2.0")
        XCTAssertEqual(requirement.downloadURL, "https://apps.apple.com/app/id123")
        XCTAssertNil(
            IOSAppReleaseContractPolicy.requiredUpdate(
                for: required,
                currentBuildNumber: 200
            )
        )
    }

    @MainActor
    func testUnauthenticatedProductionShellUsesPublicContract15StatusRoutes() async {
        let lock = NSLock()
        var paths: [String] = []
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            lock.lock()
            paths.append(path)
            lock.unlock()
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            switch path {
            case "/api/v1/system-mode":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-public-system"],
                    body: """
                    {"data":{"mode":"NORMAL","policyVersion":4,"updatedAt":"2026-08-14T00:00:00Z"},"meta":{"requestId":"req-public-system"}}
                    """
                )
            case "/api/v1/app-release-policy":
                XCTAssertTrue(request.url?.query?.contains("platform=IOS") == true)
                XCTAssertTrue(request.url?.query?.contains("currentBuildNumber=") == true)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-public-release"],
                    body: """
                    {"data":{"platform":"IOS","minimumSupportedVersion":"1.0","latestVersion":"1.0","minimumSupportedBuildNumber":1,"latestBuildNumber":1,"enforcement":"NONE","message":null,"downloadUrl":null,"effectiveAt":"2026-08-14T00:00:00Z","expiresAt":null,"policyVersion":"ios-public-1"},"meta":{"requestId":"req-public-release"}}
                    """
                )
            default:
                XCTFail("Pre-login shell reached an unexpected route: \(path)")
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-public-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-public-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: MemoryAuthSessionStore(),
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-public-capabilities")
        )
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: UserDefaults(
                suiteName: "BackendFoundationTests.public-capabilities.\(UUID().uuidString)"
            )!),
            backendServices: services
        )

        await state.refreshSystemStatus()

        XCTAssertEqual(state.systemMode, .normal)
        XCTAssertNil(state.updateRequirement)
        XCTAssertEqual(paths, [
            "/api/v1/system-mode",
            "/api/v1/app-release-policy"
        ])
    }

    @MainActor
    func testAPIV1AppStateExerciseLifecycleUsesServerIDsAndVersions() async throws {
        let authStore = MemoryAuthSessionStore(
            session: Self.authSession(access: "exercise-access", refresh: "exercise-refresh")
        )
        let lock = NSLock()
        var paths: [String] = []
        var expectedVersions: [Int] = []
        var mediaIdempotencyKeys: [String] = []
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            lock.lock()
            paths.append(path)
            lock.unlock()
            if path == "/private/exercise-upload" {
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer exercise-access")
            }
            switch path {
            case "/api/v1/me":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-me"],
                    body: Self.studentCurrentUserEnvelopeJSON(requestID: "req-exercise-me")
                )
            case "/api/v1/semesters/current":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-semester"],
                    body: Self.currentSemesterEnvelopeJSON(requestID: "req-exercise-semester")
                )
            case "/api/v1/enrollments":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-enrollments"],
                    body: Self.activeEnrollmentListEnvelopeJSON(requestID: "req-exercise-enrollments")
                )
            case "/api/v1/class-sections":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-sections"],
                    body: Self.activeClassSectionListEnvelopeJSON(requestID: "req-exercise-sections")
                )
            case "/api/v1/courses":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-courses"],
                    body: Self.activeCourseListEnvelopeJSON(requestID: "req-exercise-courses")
                )
            case "/api/v1/teachers/teacher-1":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-teacher"],
                    body: Self.teacherEnvelopeJSON(requestID: "req-exercise-teacher")
                )
            case "/api/v1/notifications":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-notifications"],
                    body: #"{"data":[],"meta":{"requestId":"req-exercise-notifications","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}"#
                )
            case "/api/v1/exercise-sessions":
                let body = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(body?["enrollmentId"] as? String, "enrollment-1")
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-exercise-start"],
                    body: Self.exerciseSessionEnvelopeJSON(
                        status: "IN_PROGRESS",
                        version: 1,
                        actualDurationSeconds: 0,
                        pausedDurationSeconds: 0,
                        endedAt: nil,
                        endReason: nil,
                        requestID: "req-exercise-start"
                    )
                )
            case "/api/v1/exercise-sessions/exercise-session-1/pause":
                Self.captureExpectedVersion(from: request, into: &expectedVersions, lock: lock)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-pause"],
                    body: Self.exerciseSessionEnvelopeJSON(
                        status: "PAUSED",
                        version: 2,
                        actualDurationSeconds: 600,
                        pausedDurationSeconds: 0,
                        endedAt: nil,
                        endReason: nil,
                        requestID: "req-exercise-pause"
                    )
                )
            case "/api/v1/exercise-sessions/exercise-session-1/resume":
                Self.captureExpectedVersion(from: request, into: &expectedVersions, lock: lock)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-resume"],
                    body: Self.exerciseSessionEnvelopeJSON(
                        status: "IN_PROGRESS",
                        version: 3,
                        actualDurationSeconds: 600,
                        pausedDurationSeconds: 600,
                        endedAt: nil,
                        endReason: nil,
                        requestID: "req-exercise-resume"
                    )
                )
            case "/api/v1/exercise-sessions/exercise-session-1/finish":
                Self.captureExpectedVersion(from: request, into: &expectedVersions, lock: lock)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exercise-finish"],
                    body: Self.exerciseSessionEnvelopeJSON(
                        status: "COMPLETED",
                        version: 4,
                        actualDurationSeconds: 3_600,
                        pausedDurationSeconds: 600,
                        endedAt: "2026-08-14T01:10:00Z",
                        endReason: "USER_COMPLETED",
                        requestID: "req-exercise-finish"
                    )
                )
            case "/api/v1/exercise-records" where request.httpMethod == "GET":
                XCTAssertTrue(request.url?.query?.contains("enrollmentId=enrollment-1") == true)
                XCTAssertTrue(request.url?.query?.contains("businessDateFrom=2026-08-14") == true)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-record-list"],
                    body: #"{"data":[],"meta":{"requestId":"req-record-list","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}"#
                )
            case "/api/v1/exercise-records" where request.httpMethod == "POST":
                let body = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(body?["sessionId"] as? String, "exercise-session-1")
                XCTAssertEqual(body?["creditType"] as? String, "COURSE_RELATED")
                XCTAssertEqual(body?["sportType"] as? String, "BADMINTON")
                XCTAssertNil(body?["description"])
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-record-create"],
                    body: Self.exerciseRecordEnvelopeJSON(
                        status: "DRAFT",
                        description: nil,
                        version: 1,
                        requestID: "req-record-create",
                        classSectionID: "section-1",
                        businessDate: "2026-08-14",
                        sportType: "BADMINTON"
                    )
                )
            case "/api/v1/media-uploads":
                if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                    lock.lock()
                    mediaIdempotencyKeys.append(key)
                    lock.unlock()
                }
                let body = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(body?["sessionId"] as? String, "exercise-session-1")
                XCTAssertEqual(body?["businessPurpose"] as? String, "EXERCISE_RECORD")
                XCTAssertEqual(body?["captureSource"] as? String, "IN_APP_CAMERA")
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-media-init"],
                    body: #"{"data":{"uploadSessionId":"upload-session-1","mediaId":"media-1","uploadUrl":"https://private-upload.example.test/private/exercise-upload","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2099-08-14T02:00:00Z"},"meta":{"requestId":"req-media-init"}}"#
                )
            case "/private/exercise-upload":
                XCTAssertEqual(Self.bodyData(from: request), Data([0xff, 0xd8, 0xff, 0xd9]))
                return .json(status: 200, headers: ["ETag": "etag-exercise-1"], body: "{}")
            case "/api/v1/media-uploads/upload-session-1/confirm":
                if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                    lock.lock()
                    mediaIdempotencyKeys.append(key)
                    lock.unlock()
                }
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-confirm"],
                    body: Self.mediaEnvelopeJSON(status: "UPLOADED", requestID: "req-media-confirm")
                )
            case "/api/v1/media/media-1/bind":
                if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                    lock.lock()
                    mediaIdempotencyKeys.append(key)
                    lock.unlock()
                }
                let body = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(body?["sessionId"] as? String, "exercise-session-1")
                XCTAssertEqual(body?["expectedVersion"] as? Int, 1)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-bind"],
                    body: Self.mediaEnvelopeJSON(status: "BOUND", requestID: "req-media-bind")
                )
            case "/api/v1/media/media-1":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-media-available"],
                    body: Self.mediaEnvelopeJSON(status: "AVAILABLE", requestID: "req-media-available")
                )
            case "/api/v1/exercise-records/record-1/submit":
                let body = (try? JSONSerialization.jsonObject(
                    with: Self.bodyData(from: request)
                )) as? [String: Any]
                XCTAssertEqual(body?["mediaIds"] as? [String], ["media-1"])
                XCTAssertEqual(body?["expectedVersion"] as? Int, 1)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-record-submit"],
                    body: Self.exerciseRecordEnvelopeJSON(
                        status: "REVIEWED",
                        description: nil,
                        version: 2,
                        requestID: "req-record-submit",
                        classSectionID: "section-1",
                        businessDate: "2026-08-14",
                        sportType: "BADMINTON",
                        currentReviewResult: "VALID"
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let services = BackendAppServices(
            environment: .local,
            client: StudentAPIClient(
                baseURL: BackendEnvironment.local.baseURL,
                urlSession: session,
                maximumSafeRetries: 0
            ),
            authStore: authStore,
            deviceIdentifier: FixedAuthDeviceIdentifier(value: "ios-exercise-installation")
        )
        let suiteName = "BackendFoundationTests.app-state-exercise.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(
            repository: UnauthenticatedStudentRepository(),
            localStore: AppLocalStore(defaults: defaults, legacyDefaults: defaults),
            backendServices: services
        )
        state.enforcesCheckInTimeWindow = false

        await state.restoreBackendSession()
        await state.refreshRemoteWorkspace()
        XCTAssertTrue(state.canSubmitExemptions)
        XCTAssertEqual(state.exemptionEligibleCourses.map(\.id), ["section-1"])
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T00:00:00Z"))
        let pause = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T00:10:00Z"))
        let resume = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T00:20:00Z"))
        let finish = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T01:10:00Z"))

        let didStart = await state.beginExerciseSession(
            category: .courseRelated,
            sportType: .badminton,
            customSportName: "",
            at: start
        )
        XCTAssertTrue(didStart)
        XCTAssertEqual(state.exerciseSession?.id, "exercise-session-1")
        let didPause = await state.pauseCurrentExerciseSession(at: pause)
        XCTAssertTrue(didPause)
        XCTAssertTrue(state.exerciseSession?.isPaused == true)
        let didResume = await state.resumeCurrentExerciseSession(at: resume)
        XCTAssertTrue(didResume)
        XCTAssertFalse(state.exerciseSession?.isPaused == true)
        let didFinish = await state.finishCurrentExerciseSession(at: finish)
        XCTAssertTrue(didFinish)
        XCTAssertEqual(state.exerciseSession?.status, .completed)
        XCTAssertEqual(state.exerciseSession?.creditedHours(), 1)
        XCTAssertEqual(expectedVersions, [1, 2, 3])
        XCTAssertEqual(Array(paths.suffix(4)), [
            "/api/v1/exercise-sessions",
            "/api/v1/exercise-sessions/exercise-session-1/pause",
            "/api/v1/exercise-sessions/exercise-session-1/resume",
            "/api/v1/exercise-sessions/exercise-session-1/finish"
        ])

        let bytes = Data([0xff, 0xd8, 0xff, 0xd9])
        XCTAssertTrue(state.addExercisePhotoDraft(imageData: bytes, thumbnailData: nil, at: finish))
        let mediaDraft = try XCTUnwrap(state.exerciseMediaDrafts.first)
        let proof = try XCTUnwrap(state.proofAttachment(from: mediaDraft))
        let didSubmit = await state.submitCheckIn(
            creditType: .courseRelated,
            courseId: "section-1",
            hours: 1,
            note: "",
            proofAttachments: [proof],
            exerciseSession: state.exerciseSession
        )
        XCTAssertTrue(didSubmit)
        XCTAssertEqual(state.workspace.records.first?.id, "record-1")
        XCTAssertEqual(state.workspace.records.first?.hours, 1)
        XCTAssertEqual(state.workspace.records.first?.validity, .valid)
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(state.pendingRemoteMutationSummaries.isEmpty)
        XCTAssertEqual(mediaIdempotencyKeys.count, 3)
        XCTAssertEqual(Set(mediaIdempotencyKeys).count, 3)
        XCTAssertEqual(Array(paths.suffix(8)), [
            "/api/v1/exercise-records",
            "/api/v1/exercise-records",
            "/api/v1/media-uploads",
            "/private/exercise-upload",
            "/api/v1/media-uploads/upload-session-1/confirm",
            "/api/v1/media/media-1/bind",
            "/api/v1/media/media-1",
            "/api/v1/exercise-records/record-1/submit"
        ])
    }

    func testExemptionMediaPipelineStopsAfterConfirmWithoutExerciseBind() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "media-access", refresh: "media-refresh"))
        let lock = NSLock()
        var operations: [String] = []
        let session = makeSession { request in
            lock.lock()
            operations.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
            lock.unlock()
            switch request.url?.path {
            case "/api/v1/media-uploads":
                let body = String(data: Self.bodyData(from: request), encoding: .utf8) ?? ""
                XCTAssertTrue(body.contains(#""businessPurpose":"EXEMPTION_APPLICATION""#))
                XCTAssertTrue(body.contains(#""enrollmentId":"enrollment-1""#))
                XCTAssertFalse(body.contains("sessionId"))
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-exemption-media-init"],
                    body: #"{"data":{"uploadSessionId":"exemption-upload-1","mediaId":"exemption-media-1","uploadUrl":"https://private-upload.example.test/private/exemption","uploadMethod":"PUT","requiredHeaders":{"Content-Type":"image/jpeg"},"expiresAt":"2099-08-07T10:00:00Z"},"meta":{"requestId":"req-exemption-media-init"}}"#
                )
            case "/private/exemption":
                return .json(status: 200, headers: ["ETag": "etag-exemption-1"], body: "{}")
            case "/api/v1/media-uploads/exemption-upload-1/confirm":
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exemption-media-confirm"],
                    body: Self.exemptionMediaEnvelopeJSON(requestID: "req-exemption-media-confirm")
                )
            default:
                XCTFail("Exemption upload must not call the exercise bind route: \(request.url?.path ?? "")")
                return .json(status: 404, headers: ["X-Request-ID": "req-404"], body: Self.errorJSON(code: "MEDIA_NOT_FOUND", requestID: "req-404"))
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let coordinator = MediaUploadCoordinator(client: client, auth: auth)
        let bytes = Data([0xff, 0xd8, 0xff, 0xd9])
        let outcome = try await coordinator.uploadForExemption(
            bytes: bytes,
            request: APIV1InitiateMediaUploadRequest(
                sessionId: nil,
                enrollmentId: "enrollment-1",
                businessPurpose: .exemptionApplication,
                mediaType: .image,
                mimeType: "image/jpeg",
                fileSizeBytes: bytes.count,
                captureSource: .filePicker,
                declaredContentSha256: nil,
                durationSeconds: nil
            )
        )

        XCTAssertEqual(outcome.media.businessPurpose, .exemptionApplication)
        XCTAssertEqual(outcome.media.enrollmentId, "enrollment-1")
        XCTAssertNil(outcome.media.sessionId)
        XCTAssertEqual(outcome.requestId, "req-exemption-media-confirm")
        XCTAssertEqual(operations, [
            "POST /api/v1/media-uploads",
            "PUT /private/exemption",
            "POST /api/v1/media-uploads/exemption-upload-1/confirm"
        ])
    }

    func testExemptionGatewayCreatesDraftThenSubmitsWithAuthoritativeVersion() async throws {
        let store = MemoryAuthSessionStore(
            session: Self.authSession(access: "exemption-write-access", refresh: "exemption-write-refresh")
        )
        let lock = NSLock()
        var operations: [String] = []
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            lock.lock()
            operations.append("\(request.httpMethod ?? "") \(path)")
            lock.unlock()
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer exemption-write-access")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
            let body = (try? JSONSerialization.jsonObject(
                with: Self.bodyData(from: request)
            )) as? [String: Any]
            switch path {
            case "/api/v1/exemption-applications":
                XCTAssertEqual(body?["enrollmentId"] as? String, "enrollment-1")
                XCTAssertEqual(body?["applicationType"] as? String, "PHYSICAL_TEST")
                XCTAssertEqual(body?["applicationSubtype"] as? String, "RUN_800M")
                XCTAssertEqual(body?["mediaIds"] as? [String], ["media-1"])
                return .json(
                    status: 201,
                    headers: ["X-Request-ID": "req-exemption-create"],
                    body: Self.exemptionApplicationEnvelopeJSON(
                        status: "DRAFT",
                        version: 1,
                        requestID: "req-exemption-create"
                    )
                )
            case "/api/v1/exemption-applications/exemption-1/submit":
                XCTAssertEqual(body?["expectedVersion"] as? Int, 1)
                return .json(
                    status: 200,
                    headers: ["X-Request-ID": "req-exemption-submit"],
                    body: Self.exemptionApplicationEnvelopeJSON(
                        status: "SUBMITTED",
                        version: 2,
                        requestID: "req-exemption-submit"
                    )
                )
            default:
                return .json(
                    status: 404,
                    headers: ["X-Request-ID": "req-unexpected"],
                    body: Self.errorJSON(code: "NOT_FOUND", requestID: "req-unexpected")
                )
            }
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let gateway = AuthoritativeExemptionApplicationGateway(auth: auth)

        let created = try await gateway.create(APIV1CreateExemptionApplicationRequest(
            enrollmentId: "enrollment-1",
            applicationType: "PHYSICAL_TEST",
            applicationSubtype: "RUN_800M",
            organizationName: nil,
            reason: "Medical documentation",
            mediaIds: ["media-1"]
        )).value
        let submitted = try await gateway.submit(
            applicationID: created.id,
            expectedVersion: created.version
        ).value

        XCTAssertEqual(created.status, "DRAFT")
        XCTAssertEqual(submitted.status, "SUBMITTED")
        XCTAssertEqual(operations, [
            "POST /api/v1/exemption-applications",
            "POST /api/v1/exemption-applications/exemption-1/submit"
        ])
    }

    func testMediaAccessUsesOnlyContract15ViewOriginalPurpose() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "media-access", refresh: "media-refresh"))
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/media/media-1/access-url")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer media-access")
            let body = String(data: Self.bodyData(from: request), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains(#""purpose":"VIEW_ORIGINAL""#))
            return .json(
                status: 200,
                headers: ["X-Request-ID": "req-media-access"],
                body: #"{"data":{"mediaId":"media-1","accessUrl":"https://private-media.example.test/object","expiresAt":"2026-08-08T10:00:00Z"},"meta":{"requestId":"req-media-access"}}"#
            )
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()
        let coordinator = MediaUploadCoordinator(client: client, auth: auth)

        let access = try await coordinator.ephemeralAccess(mediaID: "media-1")

        XCTAssertEqual(access.mediaID, "media-1")
        XCTAssertEqual(access.url.absoluteString, "https://private-media.example.test/object")
        XCTAssertEqual(access.expiresAt, "2026-08-08T10:00:00Z")
    }

    func testContract202ExerciseEvidenceContextUsesTheAdditiveReadRoute() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "record-access", refresh: "record-refresh"))
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/exercise-records/record-1/evidence-context")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer record-access")
            return .json(
                status: 200,
                headers: ["X-Request-ID": "req-evidence-context"],
                body: #"{"data":{"recordId":"record-1","sessionId":"session-1","startedAt":"2026-08-14T00:00:00Z","endedAt":"2026-08-14T01:00:00Z","mediaIds":["media-1"]},"meta":{"requestId":"req-evidence-context"}}"#
            )
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()

        let response = try await AuthoritativeExerciseRecordGateway(auth: auth)
            .evidenceContext(recordID: "record-1")

        XCTAssertEqual(response.value.recordId, "record-1")
        XCTAssertEqual(response.value.mediaIds, ["media-1"])
        XCTAssertEqual(response.requestId, "req-evidence-context")
    }

    func testContract202StudentRecordListUsesTheRoleScopedCanonicalRoute() async throws {
        let store = MemoryAuthSessionStore(session: Self.authSession(access: "record-access", refresh: "record-refresh"))
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/exercise-records")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer record-access")
            guard let requestURL = request.url else {
                XCTFail("Record-list request must contain a URL")
                return .json(status: 400, headers: [:], body: "{}")
            }
            let query = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(query.first(where: { $0.name == "limit" })?.value, "100")
            XCTAssertEqual(query.first(where: { $0.name == "sort" })?.value, "-businessDate")
            return .json(
                status: 200,
                headers: ["X-Request-ID": "req-record-list"],
                body: Self.exerciseRecordListEnvelopeJSON(
                    status: "REVIEWED",
                    version: 2,
                    requestID: "req-record-list"
                )
            )
        }
        let client = StudentAPIClient(baseURL: BackendEnvironment.local.baseURL, urlSession: session)
        let auth = BackendAuthSessionController(client: client, store: store)
        _ = try await auth.restore()

        let response = try await AuthoritativeExerciseRecordGateway(auth: auth).listOwned()

        XCTAssertEqual(response.value.map { $0.id }, ["record-1"])
        XCTAssertEqual(response.value.first?.status, .reviewed)
        XCTAssertEqual(response.requestId, "req-record-list")
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

    private static func captureExpectedVersion(
        from request: URLRequest,
        into versions: inout [Int],
        lock: NSLock
    ) {
        let body = (try? JSONSerialization.jsonObject(
            with: bodyData(from: request)
        )) as? [String: Any]
        lock.lock()
        versions.append(body?["expectedVersion"] as? Int ?? -1)
        lock.unlock()
    }

    private static func authSession(access: String, refresh: String) -> APIV1AuthSession {
        try! JSONDecoder().decode(
            APIV1AuthSession.self,
            from: Data(authSessionJSON(access: access, refresh: refresh).utf8)
        )
    }

    private static func pendingAuthSession(access: String, refresh: String) -> APIV1AuthSession {
        try! JSONDecoder().decode(
            APIV1AuthSession.self,
            from: Data(pendingAuthSessionJSON(access: access, refresh: refresh).utf8)
        )
    }

    private static func authSessionJSON(access: String, refresh: String) -> String {
        """
        {"sessionId":"session-1","accessToken":"\(access)","refreshToken":"\(refresh)","tokenType":"Bearer","accessTokenExpiresAt":"2099-08-06T00:00:00Z","refreshTokenExpiresAt":"2099-08-07T00:00:00Z","user":{"id":"user-1","organizationId":"org-1","role":"STUDENT","status":"ACTIVE","primaryEmailMasked":null,"primaryPhoneMasked":null,"emailVerified":false,"phoneVerified":false,"version":1}}
        """
    }

    private static func pendingAuthSessionJSON(access: String, refresh: String) -> String {
        """
        {"sessionId":"session-pending-1","accessToken":"\(access)","refreshToken":"\(refresh)","tokenType":"Bearer","accessTokenExpiresAt":"2099-08-06T00:00:00Z","refreshTokenExpiresAt":"2099-08-07T00:00:00Z","user":{"id":"user-1","organizationId":"org-1","role":"STUDENT","status":"PENDING_CONTACT_BINDING","primaryEmailMasked":null,"emailVerified":false,"version":1}}
        """
    }

    private static func authEnvelopeJSON(access: String, refresh: String, requestID: String) -> String {
        "{\"data\":\(authSessionJSON(access: access, refresh: refresh)),\"meta\":{\"requestId\":\"\(requestID)\"}}"
    }

    private static func currentUserEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"user":{"id":"user-1","organizationId":"org-1","role":"STUDENT","status":"ACTIVE","primaryEmailMasked":"s***@example.edu","emailVerified":true,"version":2},"studentProfile":null,"teacherProfile":null,"adminProfile":null},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func studentCurrentUserEnvelopeJSON(
        requestID: String,
        emailMasked: String = "s***@example.edu",
        userVersion: Int = 2
    ) -> String {
        """
        {"data":{"user":{"id":"user-1","organizationId":"org-1","role":"STUDENT","status":"ACTIVE","primaryEmailMasked":"\(emailMasked)","emailVerified":true,"version":\(userVersion)},"studentProfile":{"id":"student-1","organizationId":"org-1","userId":"user-1","studentNumber":"2400123456","fullName":"测试学生","gender":"FEMALE","gradeYear":2024,"collegeName":"商学院","majorName":"工商管理","administrativeClassName":"2024A","status":"ACTIVE","createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-14T00:00:00Z","deletedAt":null,"version":1},"teacherProfile":null,"adminProfile":null},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func pendingStudentCurrentUserEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"user":{"id":"user-1","organizationId":"org-1","role":"STUDENT","status":"PENDING_CONTACT_BINDING","primaryEmailMasked":null,"emailVerified":false,"version":1},"studentProfile":{"id":"student-1","organizationId":"org-1","userId":"user-1","studentNumber":"SYNTH-001","fullName":"Synthetic Student","gender":"FEMALE","gradeYear":2026,"collegeName":null,"majorName":null,"administrativeClassName":null,"status":"ACTIVE","createdAt":"2026-08-22T00:00:00Z","updatedAt":"2026-08-22T00:00:00Z","deletedAt":null,"version":1},"teacherProfile":null,"adminProfile":null},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func currentSemesterEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"id":"semester-1","organizationId":"org-1","academicYear":"2026-2027","termCode":"FIRST","displayName":"2026 秋季","startDate":"2026-08-01","endDate":"2027-01-15","status":"CURRENT","isCurrent":true,"createdBy":null,"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","version":1},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func activeEnrollmentListEnvelopeJSON(requestID: String) -> String {
        """
        {"data":[{"id":"enrollment-1","organizationId":"org-1","semesterId":"semester-1","classSectionId":"section-1","studentId":"student-1","source":"QR_CODE","sourceReferenceId":null,"status":"ACTIVE","joinedAt":"2026-08-01T00:00:00Z","endedAt":null,"endReason":null,"createdBy":"user-1","createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","version":1}],"meta":{"requestId":"\(requestID)","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
        """
    }

    private static func activeClassSectionListEnvelopeJSON(requestID: String) -> String {
        """
        {"data":[{"id":"section-1","organizationId":"org-1","courseId":"course-1","semesterId":"semester-1","teacherId":"teacher-1","classCode":"001","displayName":"羽毛球 001","status":"ACTIVE","isEnrollmentOpen":true,"checkInWindowMode":"AVAILABLE","checkInStartDate":null,"checkInEndDate":null,"dailyStartTime":"06:00:00","dailyEndTime":"22:00:00","submissionDeadlineAt":null,"excludedDates":[],"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","version":1}],"meta":{"requestId":"\(requestID)","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
        """
    }

    private static func activeCourseListEnvelopeJSON(requestID: String) -> String {
        """
        {"data":[{"id":"course-1","organizationId":"org-1","courseCode":"GEPE101","courseName":"大学体育（羽毛球）","description":null,"status":"ACTIVE","createdBy":null,"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","deletedAt":null,"version":1}],"meta":{"requestId":"\(requestID)","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
        """
    }

    private static func teacherEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"id":"teacher-1","organizationId":"org-1","userId":"teacher-user-1","employeeNumber":"T001","fullName":"合成教师","collegeName":null,"departmentName":"体育部","title":null,"status":"ACTIVE","createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","deletedAt":null,"version":1},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func exerciseSessionEnvelopeJSON(
        status: String,
        version: Int,
        actualDurationSeconds: Int,
        pausedDurationSeconds: Int,
        endedAt: String?,
        endReason: String?,
        requestID: String
    ) -> String {
        let endedAtJSON = endedAt.map { "\"\($0)\"" } ?? "null"
        let endReasonJSON = endReason.map { "\"\($0)\"" } ?? "null"
        return """
        {"data":{"id":"exercise-session-1","organizationId":"org-1","semesterId":"semester-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","status":"\(status)","startedAt":"2026-08-14T00:00:00Z","endedAt":\(endedAtJSON),"actualDurationSeconds":\(actualDurationSeconds),"pausedDurationSeconds":\(pausedDurationSeconds),"businessDate":"2026-08-14","lastHeartbeatAt":"2026-08-14T00:00:00Z","endReason":\(endReasonJSON),"version":\(version)},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func exerciseRecordEnvelopeJSON(
        status: String,
        description: String?,
        version: Int,
        requestID: String,
        classSectionID: String = "class-section-1",
        businessDate: String = "2026-08-13",
        sportType: String = "RUNNING",
        currentReviewResult: String? = nil
    ) -> String {
        let descriptionJSON = description.map { "\"\($0)\"" } ?? "null"
        let currentReviewJSON = currentReviewResult.map {
            #"{"id":"review-1","organizationId":"org-1","recordId":"record-1","teacherId":null,"reviewVersion":1,"previousReviewId":null,"result":"\#($0)","creditedDurationOverrideSeconds":null,"reasonCode":null,"reason":null,"publicComment":null,"internalNote":null,"reviewedAt":"2026-08-14T01:11:00Z"}"#
        } ?? "null"
        return """
        {"data":{"id":"record-1","organizationId":"org-1","semesterId":"semester-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"\(classSectionID)","courseId":"course-1","teacherId":"teacher-1","sessionId":"exercise-session-1","businessDate":"\(businessDate)","creditType":"COURSE_RELATED","sportType":"\(sportType)","sportName":null,"description":\(descriptionJSON),"actualDurationSeconds":3600,"pausedDurationSeconds":0,"creditedDurationSeconds":3600,"status":"\(status)","submittedAt":null,"cancelledAt":null,"clientRequestId":"ios-record-1","currentReview":\(currentReviewJSON),"version":\(version)},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func exerciseRecordListEnvelopeJSON(
        status: String,
        version: Int,
        requestID: String
    ) -> String {
        """
        {"data":[{"id":"record-1","organizationId":"org-1","semesterId":"semester-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","courseId":"course-1","teacherId":"teacher-1","sessionId":"exercise-session-1","businessDate":"2026-08-14","creditType":"COURSE_RELATED","sportType":"RUNNING","sportName":null,"description":null,"actualDurationSeconds":3600,"pausedDurationSeconds":0,"creditedDurationSeconds":3600,"status":"\(status)","submittedAt":null,"cancelledAt":null,"clientRequestId":"ios-record-1","currentReview":null,"version":\(version)}],"meta":{"requestId":"\(requestID)","pagination":{"nextCursor":null,"hasMore":false,"limit":100}}}
        """
    }

    private static func mediaEnvelopeJSON(status: String, requestID: String) -> String {
        """
        {"data":{"id":"media-1","organizationId":"org-1","ownerStudentId":"student-1","sessionId":"exercise-session-1","enrollmentId":null,"recordId":null,"businessPurpose":"EXERCISE_RECORD","mediaType":"IMAGE","declaredMimeType":"image/jpeg","verifiedMimeType":"image/jpeg","declaredFileSizeBytes":4,"verifiedFileSizeBytes":4,"captureSource":"IN_APP_CAMERA","uploadStatus":"\(status)","uploadedAt":"2026-08-06T00:00:00Z","boundAt":null,"declaredContentSha256":null,"verifiedContentSha256":null,"declaredDurationSeconds":null,"verifiedDurationSeconds":null,"version":1},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static let exerciseImageUploadRequest = APIV1InitiateMediaUploadRequest(
        sessionId: "exercise-session-1",
        enrollmentId: nil,
        businessPurpose: .exerciseRecord,
        mediaType: .image,
        mimeType: "image/jpeg",
        fileSizeBytes: 4,
        captureSource: .inAppCamera,
        declaredContentSha256: nil,
        durationSeconds: nil
    )

    private static func exemptionMediaEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"id":"exemption-media-1","organizationId":"org-1","ownerStudentId":"student-1","sessionId":null,"enrollmentId":"enrollment-1","recordId":null,"businessPurpose":"EXEMPTION_APPLICATION","mediaType":"IMAGE","declaredMimeType":"image/jpeg","verifiedMimeType":"image/jpeg","declaredFileSizeBytes":4,"verifiedFileSizeBytes":4,"captureSource":"FILE_PICKER","uploadStatus":"UPLOADED","uploadedAt":"2026-08-07T00:00:00Z","boundAt":null,"declaredContentSha256":null,"verifiedContentSha256":null,"declaredDurationSeconds":null,"verifiedDurationSeconds":null,"version":1},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func exemptionApplicationEnvelopeJSON(
        status: String,
        version: Int,
        requestID: String
    ) -> String {
        let submittedAtJSON = status == "SUBMITTED"
            ? "\"2026-08-22T10:00:00Z\""
            : "null"
        return """
        {"data":{"id":"exemption-1","studentId":"student-1","enrollmentId":"enrollment-1","classSectionId":"section-1","applicationType":"PHYSICAL_TEST","reason":"Medical documentation","mediaIds":["media-1"],"status":"\(status)","publicComment":null,"submittedAt":\(submittedAtJSON),"decidedAt":null,"version":\(version)},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func classSectionJSON(dailyStartTime: String, dailyEndTime: String) -> String {
        """
        {"id":"class-section-1","organizationId":"org-1","courseId":"course-1","semesterId":"semester-1","teacherId":"teacher-1","classCode":"001","displayName":"Section 1","status":"ACTIVE","isEnrollmentOpen":true,"checkInWindowMode":"AVAILABLE","checkInStartDate":null,"checkInEndDate":null,"dailyStartTime":"\(dailyStartTime)","dailyEndTime":"\(dailyEndTime)","submissionDeadlineAt":null,"excludedDates":[],"createdAt":"2026-08-08T00:00:00Z","updatedAt":"2026-08-08T00:00:00Z","version":1}
        """
    }

    private static func joinEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"studentProfile":{"id":"student-1","organizationId":"org-1","userId":"user-1","studentNumber":"SYNTH-001","fullName":"Synthetic Student","gender":"OTHER","gradeYear":2026,"collegeName":null,"majorName":null,"administrativeClassName":null,"status":"ACTIVE","createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","deletedAt":null,"version":1},"enrollment":{"id":"enrollment-1","organizationId":"org-1","semesterId":"semester-1","classSectionId":"cls-1","studentId":"student-1","source":"QR_CODE","sourceReferenceId":null,"status":"ACTIVE","joinedAt":"2026-08-06T00:00:00Z","endedAt":null,"endReason":null,"createdBy":null,"createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","version":1},"course":{"id":"course-1","organizationId":"org-1","courseCode":"PE101","courseName":"PE","description":null,"status":"ACTIVE","createdBy":null,"createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","deletedAt":null,"version":1},"classSection":{"id":"cls-1","organizationId":"org-1","courseId":"course-1","semesterId":"semester-1","teacherId":"teacher-1","classCode":"001","displayName":"Section 1","status":"ACTIVE","isEnrollmentOpen":true,"checkInWindowMode":"AVAILABLE","checkInStartDate":null,"checkInEndDate":null,"dailyStartTime":null,"dailyEndTime":null,"submissionDeadlineAt":null,"excludedDates":[],"createdAt":"2026-08-06T00:00:00Z","updatedAt":"2026-08-06T00:00:00Z","version":1},"authSession":\(authSessionJSON(access: "join-access", refresh: "join-refresh"))},"meta":{"requestId":"\(requestID)"}}
        """
    }

    private static func pendingContactJoinEnvelopeJSON(requestID: String) -> String {
        """
        {"data":{"studentProfile":{"id":"student-1","organizationId":"org-1","userId":"user-1","studentNumber":"SYNTH-001","fullName":"Synthetic Student","gender":"FEMALE","gradeYear":2026,"collegeName":null,"majorName":null,"administrativeClassName":null,"status":"ACTIVE","createdAt":"2026-08-22T00:00:00Z","updatedAt":"2026-08-22T00:00:00Z","deletedAt":null,"version":1},"enrollment":{"id":"enrollment-1","organizationId":"org-1","semesterId":"semester-1","classSectionId":"cls-1","studentId":"student-1","source":"QR_CODE","sourceReferenceId":null,"status":"ACTIVE","joinedAt":"2026-08-22T00:00:00Z","endedAt":null,"endReason":null,"createdBy":null,"createdAt":"2026-08-22T00:00:00Z","updatedAt":"2026-08-22T00:00:00Z","version":1},"course":{"id":"course-1","organizationId":"org-1","courseCode":"PE101","courseName":"PE","description":null,"status":"ACTIVE","createdBy":null,"createdAt":"2026-08-22T00:00:00Z","updatedAt":"2026-08-22T00:00:00Z","deletedAt":null,"version":1},"classSection":{"id":"cls-1","organizationId":"org-1","courseId":"course-1","semesterId":"semester-1","teacherId":"teacher-1","classCode":"001","displayName":"Section 1","status":"ACTIVE","isEnrollmentOpen":true,"checkInWindowMode":"AVAILABLE","checkInStartDate":null,"checkInEndDate":null,"dailyStartTime":null,"dailyEndTime":null,"submissionDeadlineAt":null,"excludedDates":[],"createdAt":"2026-08-22T00:00:00Z","updatedAt":"2026-08-22T00:00:00Z","version":1},"authSession":{"sessionId":"session-join-1","accessToken":"join-pending-access","refreshToken":"join-pending-refresh","tokenType":"Bearer","accessTokenExpiresAt":"2026-08-22T01:00:00Z","refreshTokenExpiresAt":"2026-08-29T00:00:00Z","user":{"id":"user-1","organizationId":"org-1","role":"STUDENT","status":"PENDING_CONTACT_BINDING","primaryEmailMasked":null,"emailVerified":false,"version":1}}},"meta":{"requestId":"\(requestID)"}}
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

private final class UploadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [APIUploadProgress] = []

    var values: [APIUploadProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ progress: APIUploadProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
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

private struct FixedAuthDeviceIdentifier: AuthDeviceIdentifying {
    let value: String

    func identifier() throws -> String { value }
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
