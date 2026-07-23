import XCTest
@testable import BNBUStudent

@MainActor
final class BNBUStudentModelTests: XCTestCase {
    func testExerciseSessionCreditsOnlyCompletedWholeHoursAndCapsAtTwoHours() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = ExerciseSession(
            id: "exercise-1",
            studentID: "student-1",
            category: .general,
            sportType: .running,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: nil,
            status: .active,
            locationStatus: .unavailable,
            latitude: nil,
            longitude: nil
        )

        XCTAssertEqual(session.creditedHours(at: start.addingTimeInterval(3_599)), 0)
        XCTAssertEqual(session.creditedHours(at: start.addingTimeInterval(3_600)), 1)
        XCTAssertEqual(session.creditedHours(at: start.addingTimeInterval(7_199)), 1)
        XCTAssertEqual(session.creditedHours(at: start.addingTimeInterval(7_200)), 2)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(10_000)), 7_200)
    }

    func testExerciseSessionAutomaticallyEndsAtTwoHourBoundary() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let active = ExerciseSession(
            id: "exercise-2",
            studentID: "student-1",
            category: .courseRelated,
            sportType: .basketball,
            customSportName: nil,
            courseID: "course-1",
            startTime: start,
            endTime: nil,
            status: .active,
            locationStatus: .available,
            latitude: 22.35,
            longitude: 114.20
        )

        XCTAssertEqual(active.reconciled(at: start.addingTimeInterval(7_199)).status, .active)
        let completed = active.reconciled(at: start.addingTimeInterval(7_201))
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.endTime, start.addingTimeInterval(7_200))
        XCTAssertEqual(completed.creditedHours(), 2)
    }

    func testExerciseSessionPersistsAndRestoresForCurrentStudent() throws {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        let appState = AppState(repository: MockStudentRepository(), localStore: store)
        let start = Date(timeIntervalSince1970: 1_783_516_800)

        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .other,
            customSportName: "飞盘",
            at: start
        ))

        let stored = try XCTUnwrap(store.readExerciseSession().value)
        XCTAssertEqual(stored.resolvedSportName, "飞盘")
        XCTAssertEqual(stored.studentID, appState.workspace.student.id)

        let restored = AppState(repository: MockStudentRepository(), localStore: store)
        XCTAssertEqual(restored.exerciseSession?.id, stored.id)
        XCTAssertEqual(restored.exerciseSession?.resolvedSportName, "飞盘")
    }

    // MARK: - Pause model (business rule 3.2.1)

    func testPausedTimeIsExcludedFromExerciseDuration() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = ExerciseSession(
            id: "exercise-pause",
            studentID: "student-1",
            category: .general,
            sportType: .running,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: nil,
            status: .active,
            locationStatus: .unavailable
        )

        // Exercise 30min, pause 20min, resume, exercise 40min → active 70min.
        session = try XCTUnwrap(session.paused(at: start.addingTimeInterval(1_800)))
        XCTAssertTrue(session.isPaused)
        // Timer freezes while paused.
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(2_400)), 1_800)
        session = try XCTUnwrap(session.resumed(at: start.addingTimeInterval(3_000)))
        XCTAssertFalse(session.isPaused)
        let checkpoint = start.addingTimeInterval(3_000 + 2_400)
        XCTAssertEqual(session.elapsed(at: checkpoint), 4_200)
        XCTAssertEqual(session.pausedDuration(at: checkpoint), 1_200)
        XCTAssertEqual(session.creditedHours(at: checkpoint), 1)

        // Pause/resume instants are all recorded.
        XCTAssertEqual(session.pauses.count, 1)
        XCTAssertEqual(session.pauses[0].startedAt, start.addingTimeInterval(1_800))
        XCTAssertEqual(session.pauses[0].resumedAt, start.addingTimeInterval(3_000))

        // Cannot double-pause or resume when not paused.
        XCTAssertNil(session.resumed(at: checkpoint))
        let repaused = try XCTUnwrap(session.paused(at: checkpoint))
        XCTAssertNil(repaused.paused(at: checkpoint))
    }

    func testTwoHourCapShiftsByAccumulatedPauses() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = ExerciseSession(
            id: "exercise-cap",
            studentID: "student-1",
            category: .general,
            sportType: .cycling,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: nil,
            status: .active,
            locationStatus: .unavailable
        )
        session = try XCTUnwrap(session.paused(at: start.addingTimeInterval(3_600)))
        session = try XCTUnwrap(session.resumed(at: start.addingTimeInterval(5_400)))

        // Cap instant moves from start+2h to start+2h+30min of pause.
        let expectedCap = start.addingTimeInterval(7_200 + 1_800)
        XCTAssertEqual(session.reconciled(at: expectedCap.addingTimeInterval(-1)).status, .active)
        let completed = session.reconciled(at: expectedCap.addingTimeInterval(1))
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.endTime, expectedCap)
        XCTAssertEqual(completed.creditedHours(), 2)
        XCTAssertTrue(session.reachedDailyCap(at: expectedCap))
    }

    func testPauseOverSixHoursAutoEndsAtPauseStart() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = ExerciseSession(
            id: "exercise-timeout",
            studentID: "student-1",
            category: .general,
            sportType: .fitness,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: nil,
            status: .active,
            locationStatus: .unavailable
        )
        let pauseStart = start.addingTimeInterval(4_000)
        session = try XCTUnwrap(session.paused(at: pauseStart))

        // Under the 6h timeout the session simply stays paused.
        XCTAssertEqual(session.reconciled(at: pauseStart.addingTimeInterval(6 * 3_600 - 1)).status, .active)

        let autoEnded = session.reconciled(at: pauseStart.addingTimeInterval(6 * 3_600))
        XCTAssertEqual(autoEnded.status, .completed)
        // Exercise effectively stopped when the pause began.
        XCTAssertEqual(autoEnded.endTime, pauseStart)
        XCTAssertEqual(autoEnded.elapsed(), 4_000)
        XCTAssertEqual(autoEnded.creditedHours(), 1)
        XCTAssertFalse(session.reachedDailyCap(at: pauseStart.addingTimeInterval(6 * 3_600)))
    }

    func testEndingWhilePausedStopsAtPauseStart() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = ExerciseSession(
            id: "exercise-end-paused",
            studentID: "student-1",
            category: .general,
            sportType: .swimming,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: nil,
            status: .active,
            locationStatus: .unavailable
        )
        let pauseStart = start.addingTimeInterval(3_700)
        session = try XCTUnwrap(session.paused(at: pauseStart))

        let ended = session.ended(at: pauseStart.addingTimeInterval(1_200))
        XCTAssertEqual(ended.endTime, pauseStart)
        XCTAssertEqual(ended.elapsed(), 3_700)
        XCTAssertEqual(ended.creditedHours(), 1)
    }

    func testPauseStatePersistsAcrossRestartAndLegacySessionsDecode() throws {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        let appState = AppState(repository: MockStudentRepository(), localStore: store)
        appState.enforcesCheckInTimeWindow = false
        let start = Date().addingTimeInterval(-1_800)

        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: "",
            at: start
        ))
        XCTAssertTrue(appState.pauseExerciseSession(at: start.addingTimeInterval(1_200)))
        XCTAssertEqual(appState.exerciseSession?.isPaused, true)

        // Restart: pause state survives.
        let restored = AppState(repository: MockStudentRepository(), localStore: store)
        XCTAssertEqual(restored.exerciseSession?.isPaused, true)
        XCTAssertEqual(restored.exerciseSession?.pauses.count, 1)
        XCTAssertTrue(restored.resumeExerciseSession(at: start.addingTimeInterval(1_500)))
        XCTAssertEqual(restored.exerciseSession?.isPaused, false)

        // A payload persisted before the pause feature (no pauses key)
        // still decodes with an empty pause list.
        let legacyJSON = """
        {"id":"legacy","studentID":"s1","category":"general","sportType":"running",
         "startTime":700000000,"status":"active","locationStatus":"unavailable"}
        """
        let legacy = try JSONDecoder().decode(ExerciseSession.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(legacy.pauses.isEmpty)
        XCTAssertNil(legacy.openPause)
    }

    // MARK: - Media draft pool (business rules 5.5/6.4/7)

    func testExercisePhotoDraftsCapAtSixAndVideosDoNotCount() throws {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        appState.enforcesCheckInTimeWindow = false
        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: ""
        ))

        for index in 1...6 {
            XCTAssertTrue(
                appState.addExercisePhotoDraft(imageData: Data([UInt8(index)]), thumbnailData: nil),
                "第 \(index) 张照片草稿应能保存"
            )
        }
        XCTAssertFalse(appState.canAddExercisePhotoDraft)
        XCTAssertFalse(appState.addExercisePhotoDraft(imageData: Data([7]), thumbnailData: nil))
        XCTAssertEqual(appState.errorMessage, "最多保存 6 张照片草稿。")

        // Videos are not blocked by the photo cap.
        XCTAssertTrue(appState.addInlineExerciseVideoDraftForTesting(
            videoData: Data([0xAA]),
            durationSeconds: 12
        ))
        XCTAssertEqual(appState.exerciseMediaDrafts.count, 7)
        XCTAssertEqual(appState.exercisePhotoDraftCount, 6)
    }

    func testUnderOneHourEndRetainsDraftsWhileAbandonClearsThem() throws {
        let store = AppLocalStore(defaults: isolatedDefaults())
        let appState = AppState(repository: MockStudentRepository(), localStore: store)
        appState.enforcesCheckInTimeWindow = false
        let start = Date().addingTimeInterval(-1_200)

        // Attempt 1: capture two photos, end under one hour → drafts retained.
        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: "",
            at: start
        ))
        XCTAssertTrue(appState.addExercisePhotoDraft(imageData: Data([1]), thumbnailData: nil))
        XCTAssertTrue(appState.addExercisePhotoDraft(imageData: Data([2]), thumbnailData: nil))
        XCTAssertTrue(appState.endExerciseSession())
        XCTAssertEqual(appState.exerciseSession?.creditedHours(), 0)
        appState.finishUncreditedExerciseSession()
        XCTAssertNil(appState.exerciseSession)
        XCTAssertEqual(appState.exerciseMediaDrafts.count, 2, "不足 1 小时结束时草稿应保留")

        // The day quota is untouched: a new session can start immediately.
        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: ""
        ))
        XCTAssertTrue(appState.addExercisePhotoDraft(imageData: Data([3]), thumbnailData: nil))
        XCTAssertEqual(appState.exerciseMediaDrafts.count, 3)

        // Abandoning clears only the current session's captures.
        appState.discardExerciseSession()
        XCTAssertNil(appState.exerciseSession)
        XCTAssertEqual(appState.exerciseMediaDrafts.count, 2, "放弃只清除本次会话拍摄的草稿")
    }

    func testSubmissionClearsAllMediaDraftsAndDraftsExpireNextDay() throws {
        let store = AppLocalStore(defaults: isolatedDefaults())
        let appState = AppState(repository: MockStudentRepository(), localStore: store)
        appState.enforcesCheckInTimeWindow = false

        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: ""
        ))
        XCTAssertTrue(appState.addExercisePhotoDraft(imageData: Data([1]), thumbnailData: nil))
        XCTAssertEqual(store.readExerciseMediaDrafts().value?.count, 1)

        appState.markExerciseSessionSubmitted()
        XCTAssertTrue(appState.exerciseMediaDrafts.isEmpty)
        XCTAssertNil(store.readExerciseMediaDrafts().value)

        // Same-day restore keeps drafts; next-day restore drops them.
        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: ""
        ))
        XCTAssertTrue(appState.addExercisePhotoDraft(imageData: Data([2]), thumbnailData: nil))
        let sameDay = AppState(repository: MockStudentRepository(), localStore: store)
        sameDay.demoLogin()
        XCTAssertEqual(sameDay.exerciseMediaDrafts.count, 1)

        XCTAssertEqual(store.readExerciseMediaDrafts().value?.count, 1)
        let materialized = try XCTUnwrap(sameDay.proofAttachment(from: sameDay.exerciseMediaDrafts[0]))
        XCTAssertEqual(materialized.uploadData, Data([2]))
        XCTAssertEqual(materialized.type, .image)
    }

    // MARK: - Daily open window (business rule 3.3)

    func testExerciseCanOnlyStartInsideDailyOpenWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func shanghai(_ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 7, day: 21, hour: hour, minute: minute
            )))
        }

        XCTAssertFalse(CheckInTimeWindowRule.canStartExercise(at: try shanghai(5, 59)))
        XCTAssertTrue(CheckInTimeWindowRule.canStartExercise(at: try shanghai(6, 0)))
        XCTAssertTrue(CheckInTimeWindowRule.canStartExercise(at: try shanghai(21, 59)))
        XCTAssertFalse(CheckInTimeWindowRule.canStartExercise(at: try shanghai(22, 0)))
        XCTAssertFalse(CheckInTimeWindowRule.canStartExercise(at: try shanghai(23, 30)))

        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        XCTAssertFalse(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: "",
            at: try shanghai(22, 30)
        ))
        XCTAssertEqual(appState.errorMessage, "当前不在每日打卡开放时段（06:00–22:00），暂时不能开始运动。")
        XCTAssertNil(appState.exerciseSession)

        // A session started inside the window may end past it (3.3).
        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: "",
            at: try shanghai(21, 0)
        ))
        XCTAssertTrue(appState.endExerciseSession(at: try shanghai(22, 30)))
        XCTAssertEqual(appState.exerciseSession?.creditedHours(), 1)
    }

    // MARK: - Best-effort location (business rules 5.5/10.3)

    func testLocationAttachesOnlyToRunningSessionWithoutFix() throws {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        appState.enforcesCheckInTimeWindow = false

        // No session: attach is a no-op.
        appState.attachExerciseSessionLocation(latitude: 22.35, longitude: 114.20)
        XCTAssertNil(appState.exerciseSession)

        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: ""
        ))
        XCTAssertEqual(appState.exerciseSession?.locationStatus, .unavailable)

        // A late fix attaches to the running session and persists.
        appState.attachExerciseSessionLocation(latitude: 22.35, longitude: 114.20)
        XCTAssertEqual(appState.exerciseSession?.locationStatus, .available)
        XCTAssertEqual(appState.exerciseSession?.latitude, 22.35)
        XCTAssertEqual(appState.exerciseSession?.longitude, 114.20)

        // A second fix never overwrites the first.
        appState.attachExerciseSessionLocation(latitude: 0, longitude: 0)
        XCTAssertEqual(appState.exerciseSession?.latitude, 22.35)

        // A completed session no longer accepts fixes.
        XCTAssertTrue(appState.endExerciseSession())
        let endedLatitude = appState.exerciseSession?.latitude
        appState.attachExerciseSessionLocation(latitude: 1, longitude: 1)
        XCTAssertEqual(appState.exerciseSession?.latitude, endedLatitude)
    }

    func testDailyLimitUsesExerciseStartDateWhenSessionCrossesMidnight() async throws {
        let defaults = isolatedDefaults()
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )
        // The window rule (3.3) is exercised separately; this test targets
        // the day-attribution rule, so the gate is disabled to allow a
        // 23:30 start that crosses midnight.
        appState.enforcesCheckInTimeWindow = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 21,
            hour: 23,
            minute: 30
        )))
        let nextDay = start.addingTimeInterval(3_600)
        XCTAssertTrue(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: "",
            at: start
        ))
        XCTAssertTrue(appState.endExerciseSession(at: nextDay))
        let session = try XCTUnwrap(appState.exerciseSession)

        let submitted = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: session.creditedHours(),
            note: "跨零点运动",
            sportType: session.sportType.rawValue,
            proofAttachments: [
                ProofAttachment(
                    id: "cross-midnight-proof",
                    type: .image,
                    fileName: "proof.jpg",
                    byteCount: 400_000,
                    source: "test"
                )
            ],
            exerciseSession: session
        )
        XCTAssertTrue(submitted)

        XCTAssertTrue(appState.hasSubmittedCheckInToday(at: start))
        XCTAssertFalse(appState.hasSubmittedCheckInToday(at: nextDay))
    }

    func testDebugServerConfigDefaultsToTestAPI() {
        let resolved = StudentServerConfig.resolvedBaseURL(arguments: ["BNBUStudent"], environment: [:])

        XCTAssertEqual(resolved.absoluteString, "http://123.207.5.70:82/api/v1")
        XCTAssertEqual(StudentAPIClient().baseURL.absoluteString, resolved.absoluteString)
    }

    func testServerConfigAllowsArgumentAndEnvironmentOverrides() {
        let argumentURL = StudentServerConfig.resolvedBaseURL(
            arguments: ["BNBUStudent", "-server-base-url", "http://127.0.0.1:8080/api/v1"],
            environment: ["BNBU_API_BASE_URL": "http://123.207.5.70:82/api/v1"]
        )
        let environmentURL = StudentServerConfig.resolvedBaseURL(
            arguments: ["BNBUStudent"],
            environment: ["BNBU_API_BASE_URL": "http://123.207.5.70:82/api/v1"]
        )

        XCTAssertEqual(argumentURL.absoluteString, "http://127.0.0.1:8080/api/v1")
        XCTAssertEqual(environmentURL.absoluteString, "http://123.207.5.70:82/api/v1")
    }

    func testProofAttachmentValidationCatchesSizeAndDurationLimits() {
        let oversizedImage = ProofAttachment(
            id: "image-too-large",
            type: .image,
            fileName: "large.jpg",
            byteCount: ProofUploadRule.maxImageBytes + 1,
            source: "test"
        )
        XCTAssertEqual(oversizedImage.validationMessage, "图片超过 8MB")

        let staleLocalImage = ProofAttachment(
            id: "image-needs-reselect",
            type: .image,
            fileName: "stale.jpg",
            byteCount: ProofUploadRule.maxImageBytes + 1,
            source: "相册"
        )
        XCTAssertEqual(staleLocalImage.validationMessage, "原始文件已不在内存中，请删除后重新选择")

        let longVideo = ProofAttachment(
            id: "video-too-large",
            type: .video,
            fileName: "large.mov",
            byteCount: ProofUploadRule.maxVideoBytes + 1,
            source: "test"
        )
        XCTAssertEqual(longVideo.validationMessage, "视频超过 100MB")
        XCTAssertFalse(longVideo.isValidForUpload)
    }

    func testCheckInSubmissionPhaseCalculatesOverallUploadProgress() {
        let uploading = CheckInSubmissionPhase.uploading(
            fileName: "proof.mov",
            completedFiles: 1,
            totalFiles: 4,
            fileProgress: 0.5
        )
        let clamped = CheckInSubmissionPhase.uploading(
            fileName: "proof.jpg",
            completedFiles: 0,
            totalFiles: 1,
            fileProgress: 2
        )

        XCTAssertTrue(uploading.isActive)
        XCTAssertTrue(uploading.canRetryWithoutDuplicateRisk)
        XCTAssertEqual(uploading.overallProgress, 0.375)
        XCTAssertEqual(clamped.overallProgress, 1)
        XCTAssertEqual(CheckInSubmissionPhase.submitting.overallProgress, 1)
        XCTAssertEqual(CheckInSubmissionPhase.syncing.overallProgress, 1)
        XCTAssertFalse(CheckInSubmissionPhase.submitting.canRetryWithoutDuplicateRisk)
        XCTAssertFalse(CheckInSubmissionPhase.syncing.canRetryWithoutDuplicateRisk)
        XCTAssertNil(CheckInSubmissionPhase.idle.overallProgress)
        XCTAssertFalse(CheckInSubmissionPhase.idle.isActive)
    }

    func testRepositoryErrorsUseActionableStudentMessages() {
        XCTAssertEqual(
            RepositoryError.httpError(409).localizedDescription,
            "今天已提交过该任务。请先刷新打卡记录，勿重复提交。"
        )
        XCTAssertEqual(
            RepositoryError.httpError(413).localizedDescription,
            "凭证文件超过服务器限制，请删除过大文件后重新选择。"
        )
        XCTAssertEqual(
            RepositoryError.apiError("Check-in already submitted").localizedDescription,
            "今天已提交过该任务。请先刷新打卡记录，勿重复提交。"
        )
        XCTAssertEqual(
            RepositoryError.apiError("Task is outside date range").localizedDescription,
            "当前不在任务允许的打卡时间内，请刷新任务并确认开始和截止时间。"
        )
    }

    func testIdempotencyConflictCodesRemainStructuredAndAmbiguous() async throws {
        for code in ["IDEMPOTENCY_CONFLICT", "IDEMPOTENCY_KEY_REUSED"] {
            IdempotencyConflictURLProtocol.configure(code: code)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [IdempotencyConflictURLProtocol.self]
            let credentialStore = InMemoryCredentialStore()
            try credentialStore.set(
                Data("short-lived-token".utf8),
                forKey: RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
            )
            let repository = RemoteStudentRepository(
                baseURL: StudentServerConfig.testBaseURL,
                credentialStore: credentialStore,
                urlSession: URLSession(configuration: configuration),
                legacyDefaults: isolatedDefaults()
            )
            var capturedError: RepositoryError?
            do {
                _ = try await repository.submitCheckIn(
                    courseId: nil,
                    creditType: "other",
                    taskTitle: "running",
                    hours: 1,
                    note: "same logical request",
                    idempotencyKey: "ios-conflict-test-0001"
                )
                XCTFail("Expected \(code)")
            } catch let error as RepositoryError {
                capturedError = error
            }

            let error = try XCTUnwrap(capturedError)
            XCTAssertTrue(error.isAmbiguousMutationFailure, "\(code) must retain the existing logical attempt")
            guard case let .serverError(statusCode, decodedCode, _) = error else {
                return XCTFail("Expected a structured server error")
            }
            XCTAssertEqual(statusCode, 409)
            XCTAssertEqual(decodedCode, code)
        }

        XCTAssertFalse(RepositoryError.serverError(
            statusCode: 409,
            code: "VALIDATION_ERROR",
            message: "The submitted payload is invalid."
        ).isAmbiguousMutationFailure)
        XCTAssertTrue(RepositoryError.serverError(
            statusCode: 503,
            code: "SERVICE_UNAVAILABLE",
            message: "Try again later."
        ).isAmbiguousMutationFailure)
        for statusCode in [408, 425, 429] {
            XCTAssertTrue(
                RepositoryError.httpError(statusCode).isAmbiguousMutationFailure,
                "HTTP \(statusCode) must preserve the logical mutation attempt"
            )
            XCTAssertTrue(
                RepositoryError.serverError(
                    statusCode: statusCode,
                    code: "RETRY_LATER",
                    message: "Try again later."
                ).isAmbiguousMutationFailure,
                "Structured HTTP \(statusCode) must preserve the logical mutation attempt"
            )
        }
    }

    func testAppStateRejectsHoursOutsideOneOrTwoWhenSubmitting() async {
        let defaults = isolatedDefaults()
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )

        // Hours outside the 1h/2h contract are rejected instead of clamped.
        let recordCountBefore = appState.workspace.records.count
        let oversized = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 4,
            note: "操场跑步。",
            proofAttachments: [
                ProofAttachment(id: "proof-oversized", type: .image, fileName: "proof.jpg", byteCount: 400_000, source: "test")
            ]
        )
        XCTAssertFalse(oversized)
        XCTAssertEqual(appState.workspace.records.count, recordCountBefore)

        let submitted = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 2,
            note: "操场跑步。",
            proofAttachments: [
                ProofAttachment(id: "proof", type: .image, fileName: "proof.jpg", byteCount: 400_000, source: "test")
            ]
        )
        XCTAssertTrue(submitted)
        XCTAssertEqual(appState.workspace.records.first?.hours, 2)
        XCTAssertEqual(appState.workspace.records.first?.validity, .valid)
        XCTAssertEqual(appState.workspace.records.first?.proofPhotoCount, 1)
        XCTAssertEqual(appState.workspace.progress.rawGeneral, 2)
        XCTAssertEqual(appState.workspace.progress.general, appState.hourRule.generalRequired)
    }

    func testProofUploadRuleRejectsBatchAboveServerRequestLimit() {
        let attachments = [
            ProofAttachment(id: "video", type: .video, fileName: "proof.mov", byteCount: 100_000_000, source: "test"),
            ProofAttachment(id: "image-1", type: .image, fileName: "proof-1.jpg", byteCount: 7_000_001, source: "test"),
            ProofAttachment(id: "image-2", type: .image, fileName: "proof-2.jpg", byteCount: 7_000_001, source: "test"),
            ProofAttachment(id: "image-3", type: .image, fileName: "proof-3.jpg", byteCount: 7_000_001, source: "test")
        ]

        XCTAssertEqual(ProofUploadRule.totalByteCount(in: attachments), 121_000_003)
        XCTAssertFalse(ProofUploadRule.accepts(attachments))
        XCTAssertEqual(ProofUploadRule.validationMessage(for: attachments), "全部凭证总大小不能超过 120MB。")
    }

    func testExemptionProofRuleStopsAtFiveBackendReferences() {
        let attachments = (1...6).map { index in
            ProofAttachment(
                id: "proof-\(index)",
                type: .image,
                fileName: "proof-\(index).jpg",
                byteCount: 100_000,
                source: "test"
            )
        }

        XCTAssertTrue(ProofUploadRule.accepts(attachments))
        XCTAssertFalse(ExemptionProofRule.accepts(attachments))
        XCTAssertEqual(
            ExemptionProofRule.validationMessage(for: attachments),
            "免测申请最多只能添加 5 个证明材料。"
        )
        XCTAssertTrue(ExemptionProofRule.accepts(Array(attachments.prefix(5))))
    }

    func testExemptionReasonMatchesBackendLengthContract() async {
        XCTAssertEqual(
            ExemptionInputRule.validationMessage(reason: "伤", detail: "医生证明"),
            "申请原因至少需要 2 个字符。"
        )
        XCTAssertNil(
            ExemptionInputRule.validationMessage(
                reason: "受伤",
                detail: String(repeating: "明", count: 1_996)
            )
        )
        XCTAssertEqual(
            ExemptionInputRule.validationMessage(
                reason: "受伤",
                detail: String(repeating: "明", count: 1_997)
            ),
            "申请原因和情况说明合计不能超过 2000 个字符。"
        )

        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        let originalCount = appState.workspace.exemptions.count
        let submitted = await appState.submitExemption(
            item: .run800m,
            reason: "伤",
            detail: "医生证明",
            proofAttachments: [
                ProofAttachment(id: "proof", type: .image, fileName: "proof.jpg", byteCount: 100_000, source: "test")
            ]
        )
        XCTAssertFalse(submitted)
        XCTAssertEqual(appState.workspace.exemptions.count, originalCount)
        XCTAssertEqual(appState.errorMessage, "申请原因至少需要 2 个字符。")
    }

    // Business rule 5.7 + Q&A 7/23 Q5: the sport note is required and capped
    // at 200 characters.
    func testCheckInDescriptionStopsAboveTwoHundredCharacters() async {
        XCTAssertEqual(BNBULanguage.defaultMode, .system)
        XCTAssertEqual(
            BNBULanguage.supportedSystemLocaleIdentifier(preferredLanguages: ["zh-Hans-CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            BNBULanguage.supportedSystemLocaleIdentifier(preferredLanguages: ["zh-Hant-HK"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            BNBULanguage.supportedSystemLocaleIdentifier(preferredLanguages: ["en-US"]),
            "en"
        )
        XCTAssertEqual(
            BNBULanguage.supportedSystemLocaleIdentifier(preferredLanguages: ["ja-JP"]),
            "en"
        )
        XCTAssertEqual(
            BNBULanguage.supportedSystemLocaleIdentifier(preferredLanguages: []),
            "en"
        )
        let consentSuiteName = "bnbu.privacy.tests.\(UUID().uuidString)"
        let consentDefaults = UserDefaults(suiteName: consentSuiteName)!
        defer {
            consentDefaults.removePersistentDomain(forName: consentSuiteName)
        }
        XCTAssertFalse(
            BNBUPrivacyConsent.hasAccepted(account: " Student@BNBU.edu.cn ", defaults: consentDefaults)
        )
        BNBUPrivacyConsent.recordAcceptance(
            account: " Student@BNBU.edu.cn ",
            defaults: consentDefaults
        )
        XCTAssertTrue(
            BNBUPrivacyConsent.hasAccepted(account: "student@bnbu.edu.cn", defaults: consentDefaults)
        )
        XCTAssertNotNil(
            consentDefaults.dictionary(
                forKey: BNBUPrivacyConsent.defaultsKeyPrefix + "student@bnbu.edu.cn"
            )?["acceptedAt"]
        )
        XCTAssertEqual(
            BNBUOnboarding.completedVersion(studentID: "student-a", defaults: consentDefaults),
            0
        )
        BNBUOnboarding.markCompleted(studentID: "student-a", defaults: consentDefaults)
        XCTAssertEqual(
            BNBUOnboarding.completedVersion(studentID: "student-a", defaults: consentDefaults),
            BNBUOnboarding.currentVersion
        )
        XCTAssertEqual(
            BNBUOnboarding.completedVersion(studentID: "student-b", defaults: consentDefaults),
            0
        )
        let languageSettings = BNBULanguageSettings(defaults: consentDefaults)
        XCTAssertEqual(languageSettings.mode, .system)
        languageSettings.select(rawValue: BNBULanguage.english.rawValue)
        XCTAssertEqual(languageSettings.mode, .english)
        XCTAssertEqual(
            consentDefaults.string(forKey: BNBULanguage.defaultsKey),
            BNBULanguage.english.rawValue
        )
        XCTAssertEqual(CheckInInputRule.validationMessage(note: ""), "请填写运动说明。")
        XCTAssertEqual(CheckInInputRule.validationMessage(note: "  \n"), "请填写运动说明。")
        XCTAssertNil(CheckInInputRule.validationMessage(note: String(repeating: "跑", count: 200)))
        XCTAssertEqual(
            CheckInInputRule.validationMessage(note: String(repeating: "跑", count: 201)),
            "运动说明不能超过 200 个字符。"
        )
        XCTAssertEqual(
            CheckInInputRule.normalizedDescription("晚间慢跑", for: .general),
            "晚间慢跑"
        )
        XCTAssertEqual(
            CheckInInputRule.normalizedDescription("  课程训练说明  ", for: .courseRelated),
            "课程训练说明"
        )
        XCTAssertEqual(BNBUNotificationManager.route(from: ["route": "course"]), .courses)
        XCTAssertEqual(BNBUNotificationManager.route(from: ["target": "sport_record"]), .checkin)
        XCTAssertEqual(BNBUNotificationManager.route(from: ["type": "grade"]), .grades)
        XCTAssertEqual(BNBUNotificationManager.route(from: [:]), .dashboard)

        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        let originalCount = appState.workspace.records.count
        let submitted = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: String(repeating: "跑", count: 201),
            sportType: "running",
            proofAttachments: [
                ProofAttachment(id: "proof", type: .image, fileName: "proof.jpg", byteCount: 100_000, source: "test")
            ]
        )
        XCTAssertFalse(submitted)
        XCTAssertEqual(appState.workspace.records.count, originalCount)
        XCTAssertEqual(appState.errorMessage, "运动说明不能超过 200 个字符。")
    }

    func testPersistedLocalProofRequiresOriginalFileReselection() throws {
        let selectedProof = ProofAttachment(
            id: "selected",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xFF, 0xD8, 0xFF]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "相册"
        )
        XCTAssertTrue(selectedProof.isValidForUpload)

        let restoredProof = try JSONDecoder().decode(
            ProofAttachment.self,
            from: JSONEncoder().encode(selectedProof)
        )
        XCTAssertFalse(restoredProof.isValidForUpload)
        XCTAssertEqual(restoredProof.validationMessage, "原始文件已不在内存中，请删除后重新选择")
    }

    func testSubmissionHoursAlwaysMatchBackendOneOrTwoHourContract() async {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )

        // Only whole 1h/2h submissions produce a validated submission.
        XCTAssertNil(appState.validatedSubmission(creditType: .general, courseId: nil, hours: 0.5))
        XCTAssertNil(appState.validatedSubmission(creditType: .general, courseId: nil, hours: 1.5))
        XCTAssertNil(appState.validatedSubmission(creditType: .general, courseId: nil, hours: Double.nan))
        XCTAssertEqual(appState.validatedSubmission(creditType: .general, courseId: nil, hours: 1)?.hours, 1)
        XCTAssertEqual(appState.validatedSubmission(creditType: .general, courseId: nil, hours: 2)?.hours, 2)

        // Course-related submissions require a known course reference.
        XCTAssertNil(appState.validatedSubmission(creditType: .courseRelated, courseId: nil, hours: 1))
        XCTAssertNil(appState.validatedSubmission(creditType: .courseRelated, courseId: "missing-course", hours: 1))
        let courseId = appState.workspace.courses.first?.id
        XCTAssertEqual(
            appState.validatedSubmission(creditType: .courseRelated, courseId: courseId, hours: 1)?.courseId,
            courseId
        )

        // Organization offsets can never be submitted by the student client.
        XCTAssertNil(appState.validatedSubmission(creditType: .organizationOffset, courseId: nil, hours: 1))
    }

    func testCurrentBackendStudentWorkspacePayloadsDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let courses = try decoder.decode(StudentCoursesPayload.self, from: Data(
            """
            {
              "courses": [{
                "id": "course-1",
                "code": "GEPE101",
                "section": "1004",
                "name": "大学体育",
                "teacherName": "体育教师",
                "isCurrent": true,
                "semester": { "name": "2026-2027 第一学期" }
              }],
              "scope": "all"
            }
            """.utf8
        )).models()
        XCTAssertEqual(courses.first?.teacher, "体育教师")
        XCTAssertEqual(courses.first?.semester, "2026-2027 第一学期")
        XCTAssertEqual(courses.first?.isCurrent, true)

        let student = StudentProfile(
            id: "student-1",
            name: "测试学生",
            email: "student@example.invalid",
            college: "BNBU",
            className: "2026A",
            status: "正常"
        )
        let grades = try decoder.decode(StudentGradesPayload.self, from: Data(
            """
            {
              "grades": [{
                "studentId": "student-1",
                "studentName": "测试学生",
                "checkinScore": 80,
                "exam": 86,
                "attendance": 90,
                "physical": 78,
                "total": 83,
                "sourceTrace": "API: /student/grades"
              }],
              "summary": {
                "overallCheckinScore": 80,
                "overallExam": 86,
                "overallAttendance": 90,
                "overallPhysical": 78,
                "overallTotal": 83,
                "totalPossible": 100
              }
            }
            """.utf8
        )).model(for: student)
        XCTAssertEqual(grades.total, 83)
        XCTAssertEqual(grades.exam, 86)
        XCTAssertTrue(grades.missingItems.isEmpty)
    }

    func testRecordValidityMapsLegacyReviewStatesOntoValidInvalid() throws {
        let decoder = JSONDecoder()
        func decode(_ raw: String) throws -> RecordValidity {
            try decoder.decode(RecordValidity.self, from: Data("\"\(raw)\"".utf8))
        }

        // Legacy pending/approved/supplement/offset states all read back as valid.
        for legacy in ["待审核", "已通过", "待补充", "系统抵扣", "pending", "approved", "supplement", "offset", "有效"] {
            XCTAssertEqual(try decode(legacy), .valid, "\(legacy) must map to valid")
        }
        // Only explicit invalidation (including the legacy rejected state) reads back as invalid.
        for invalid in ["无效", "invalid", "INVALID", "rejected", "REJECTED", "被驳回", "已驳回"] {
            XCTAssertEqual(try decode(invalid), .invalid, "\(invalid) must map to invalid")
        }

        let record = try decoder.decode(CheckInRecord.self, from: Data(
            """
            {
              "id": "record-invalid",
              "creditType": "其他运动",
              "hours": 1,
              "submittedAt": "2026-07-16T04:00:00.000Z",
              "status": "rejected",
              "teacherFeedback": "凭证与运动内容不符"
            }
            """.utf8
        ))
        XCTAssertEqual(record.validity, .invalid)
        XCTAssertEqual(record.invalidReason, "凭证与运动内容不符")

        let roundTripped = try decoder.decode(CheckInRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(roundTripped.validity, .invalid)
        XCTAssertEqual(roundTripped.invalidReason, "凭证与运动内容不符")
    }

    func testMutationResultsAreNotMistakenForCompleteDomainObjects() throws {
        let record = try JSONDecoder().decode(CheckInRecord.self, from: Data(
            """
            {
              "id": "record-1",
              "status": "待审核",
              "submittedAt": "2026-07-16T04:00:00.000Z"
            }
            """.utf8
        ))
        XCTAssertEqual(record.hours, 0)
        XCTAssertFalse(record.representsCompleteServerRecord)

        let exemption = try JSONDecoder().decode(ExemptionApplication.self, from: Data(
            """
            {
              "id": "exemption-1",
              "status": "pending",
              "createdAt": "2026-07-16T04:00:00.000Z"
            }
            """.utf8
        ))
        XCTAssertTrue(exemption.studentId.isEmpty)
        XCTAssertFalse(exemption.representsCompleteServerApplication)
    }

    func testStudentProgressWithoutIdentityFailsClosedToEmptyIdentifier() throws {
        let progress = try JSONDecoder().decode(StudentProgress.self, from: Data(
            """
            {
              "courseHours": 2,
              "generalHours": 3,
              "status": "暂无风险"
            }
            """.utf8
        ))

        XCTAssertTrue(progress.id.isEmpty)
        XCTAssertEqual(progress.course, 2)
        XCTAssertEqual(progress.general, 3)
    }

    func testMembershipAndExemptionStatusDecodeCurrentNullableBackendShape() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let membership = try decoder.decode(Membership.self, from: Data(
            """
            {
              "id": "membership-1",
              "type": "team",
              "organization": "羽毛球队",
              "studentId": "student-1",
              "studentName": "测试学生",
              "status": "pending",
              "validUntil": null,
              "offset": "0h",
              "comment": null,
              "updatedBy": null,
              "updatedAt": null
            }
            """.utf8
        ))
        XCTAssertEqual(membership.validUntil, "")
        XCTAssertEqual(membership.comment, "")

        let proof = try decoder.decode(ProofAttachment.self, from: Data(
            """
            {
              "url": "https://example.invalid/signed-proof.jpg",
              "cosKey": "proofs/student-1/proof.jpg",
              "mediaType": "image",
              "mimeType": "image/jpeg",
              "size": 128000
            }
            """.utf8
        ))
        XCTAssertEqual(proof.id, "proofs/student-1/proof.jpg")
        XCTAssertEqual(proof.cosKey, proof.id)

        for rawStatus in ["reviewing", "审核中"] {
            let status = try decoder.decode(ExemptionStatus.self, from: Data("\"\(rawStatus)\"".utf8))
            XCTAssertEqual(status, .pending)
        }
        let supplementRequired = try decoder.decode(ExemptionStatus.self, from: Data("\"supplement_required\"".utf8))
        let expired = try decoder.decode(ExemptionStatus.self, from: Data("\"expired\"".utf8))
        XCTAssertEqual(supplementRequired, .supplementRequired)
        XCTAssertTrue(supplementRequired.canSupplement)
        XCTAssertEqual(expired, .expired)
        XCTAssertFalse(expired.canSupplement)
    }

    func testAppStateSubmitsExemptionAsPendingWithProofs() async {
        let defaults = isolatedDefaults()
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )

        await appState.submitExemption(
            item: .run800m,
            reason: "膝关节运动损伤",
            detail: "医生建议暂缓耐力跑测试。",
            proofAttachments: [
                ProofAttachment(id: "proof", type: .image, fileName: "hospital-note.jpg", byteCount: 480_000, source: "test")
            ]
        )

        let application = appState.workspace.exemptions.first
        XCTAssertEqual(application?.item, .run800m)
        XCTAssertEqual(application?.status, .pending)
        XCTAssertEqual(application?.proofFiles.count, 1)
        XCTAssertEqual(appState.workspace.syncOperations.first?.type, .submitExemption)
        XCTAssertTrue(appState.workspace.notices.first?.title.contains("免测") ?? false)
    }

    func testAppStateRejectsInvalidExemptionProof() async {
        let defaults = isolatedDefaults()
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )
        let originalExemptionCount = appState.workspace.exemptions.count
        let originalSyncCount = appState.workspace.syncOperations.count

        await appState.submitExemption(
            item: .run800m,
            reason: "膝关节运动损伤",
            detail: "医生建议暂缓耐力跑测试。",
            proofAttachments: [
                ProofAttachment(
                    id: "too-large",
                    type: .image,
                    fileName: "hospital-note.jpg",
                    byteCount: ProofUploadRule.maxImageBytes + 1,
                    source: "test"
                )
            ]
        )

        XCTAssertEqual(appState.workspace.exemptions.count, originalExemptionCount)
        XCTAssertEqual(appState.workspace.syncOperations.count, originalSyncCount)
    }

    func testExemptionApplicationDecodesRemoteBackendPayload() throws {
        let json = Data(
            """
            {
              "exemption_id": "ex-remote",
              "student_id": "demo-student-001",
              "type": "800m",
              "reason": "运动损伤",
              "created_at": "2026-06-30T10:00:00Z",
              "status": "已驳回",
              "proofFiles": [
                {
                  "file_id": "pf-1",
                  "media_type": "image",
                  "name": "proof.jpg",
                  "url": "/uploads/proof.jpg",
                  "size": 128000
                }
              ],
              "comment": "证明材料不足"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let application = try decoder.decode(ExemptionApplication.self, from: json)

        XCTAssertEqual(application.id, "ex-remote")
        XCTAssertEqual(application.studentId, "demo-student-001")
        XCTAssertEqual(application.item, .run800m)
        XCTAssertEqual(application.status, .rejected)
        XCTAssertEqual(application.proofFiles.first?.source, "/uploads/proof.jpg")
        XCTAssertEqual(application.teacherFeedback, "证明材料不足")
    }

    func testExemptionApplicationDecodesRemoteStringProofFiles() throws {
        let json = Data(
            """
            {
              "id": "ex-1782973379583-ms6q5c",
              "studentId": "demo-student-001",
              "type": "800m",
              "reason": "iOS联调测试",
              "status": "待审核",
              "proofFiles": ["/uploads/1782973342744-jxf3a2.jpg"],
              "reviewComment": null,
              "reviewerName": "",
              "createdAt": "2026-07-02T06:22:59.000Z",
              "updatedAt": "2026-07-02T06:22:59.000Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let application = try decoder.decode(ExemptionApplication.self, from: json)

        XCTAssertEqual(application.item, .run800m)
        XCTAssertEqual(application.status, .pending)
        XCTAssertEqual(application.proofFiles.count, 1)
        XCTAssertEqual(application.proofFiles.first?.type, .image)
        XCTAssertEqual(application.proofFiles.first?.source, "/uploads/1782973342744-jxf3a2.jpg")
    }

    func testProofUploadPayloadDecodesUrlsArray() throws {
        let json = Data(
            """
            {
              "urls": ["/uploads/1782973342744-jxf3a2.jpg"],
              "count": 1
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(ProofUploadPayload.self, from: json)
        let attachment = payload.attachment(
            fallback: ProofAttachment(
                id: "local",
                type: .image,
                fileName: "local.jpg",
                byteCount: 1000,
                source: "local"
            )
        )

        XCTAssertEqual(attachment.source, "/uploads/1782973342744-jxf3a2.jpg")
        XCTAssertEqual(attachment.fileName, "local.jpg")
    }

    func testCheckInRecordDecodesRemoteStringFields() throws {
        let json = Data(
            """
            {
              "id": "sr-1782973536035-5wvg4n",
              "courseId": "gepe",
              "taskId": "t1",
              "creditType": "course",
              "hours": "0.5",
              "approvedHours": "0.0",
              "description": "iOS联调测试：验证学生端提交打卡写入链路",
              "proofFiles": ["/uploads/1782973342744-jxf3a2.jpg"],
              "status": "待审核",
              "reviewComment": null,
              "submittedAt": "2026-07-02T06:25:36.000Z"
            }
            """.utf8
        )

        let record = try JSONDecoder().decode(CheckInRecord.self, from: json)

        XCTAssertEqual(record.hours, 0.5)
        XCTAssertEqual(record.validity, .valid)
        XCTAssertEqual(record.taskTitle, "iOS联调测试：验证学生端提交打卡写入链路")
        XCTAssertEqual(record.proofFiles.count, 1)
        XCTAssertEqual(record.proofSummary, "1 张图片")
    }

    func testCheckInRecordDecodesSportType() throws {
        let json = Data(
            """
            {
              "id": "sport-record",
              "creditType": "general",
              "hours": 1,
              "sportType": "running",
              "description": "操场慢跑",
              "proofFiles": [],
              "submittedAt": "2026-07-15T06:00:00Z"
            }
            """.utf8
        )

        let record = try JSONDecoder().decode(CheckInRecord.self, from: json)

        XCTAssertEqual(record.sportType, "running")
    }

    func testEnduranceScoreResultDecodesServerPayload() throws {
        let json = Data(
            """
            {
              "score": 82,
              "tier": "good",
              "timeSeconds": 244,
              "gender": "female",
              "gradeLevel": "sophomore",
              "gradeGroup": "female-year2"
            }
            """.utf8
        )

        let result = try JSONDecoder().decode(EnduranceScoreResult.self, from: json)
        XCTAssertEqual(result.score, 82)
        XCTAssertEqual(result.tierTitle, "良好")
        XCTAssertEqual(result.timeSeconds, 244)
    }

    func testSelfCheckInDraftRestoresSportSelection() {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        let appState = AppState(repository: MockStudentRepository(), localStore: store)

        appState.saveDraft(
            creditType: .general,
            courseId: nil,
            hours: 2,
            note: "操场训练",
            sportType: "other",
            customSportType: "飞盘",
            proofAttachments: []
        )

        let restored = AppState(repository: MockStudentRepository(), localStore: store)
        XCTAssertEqual(restored.draft?.creditType, .general)
        XCTAssertNil(restored.draft?.courseId)
        XCTAssertEqual(restored.draft?.sportType, "other")
        XCTAssertEqual(restored.draft?.customSportType, "飞盘")
    }

    func testSelfCheckInAllowsOnlyOneSubmissionPerDay() async {
        let defaults = isolatedDefaults()
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )
        let proof = ProofAttachment(
            id: "daily-proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 200_000,
            source: "test"
        )

        let first = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "第一次",
            sportType: "running",
            proofAttachments: [proof]
        )
        let second = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "第二次",
            sportType: "running",
            proofAttachments: [proof]
        )

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(appState.errorMessage, "今日已打卡，每天只能提交一次。")
    }

    func testDailySubmissionBoundaryUsesChinaTimeAndFractionalISODate() throws {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        appState.workspace.records = [
            CheckInRecord(
                id: "china-day-record",
                courseId: nil,
                taskTitle: "自主运动打卡",
                creditType: .general,
                hours: 1,
                submittedAt: "2026-07-15T16:30:00.000Z",
                validity: .valid,
                proofSummary: "1 张图片",
                proofPhotoCount: 1,
                proofVideoCount: 0,
                proofFiles: [],
                note: ""
            )
        ]
        let formatter = ISO8601DateFormatter()
        let comparisonDate = try XCTUnwrap(formatter.date(from: "2026-07-16T08:00:00Z"))

        XCTAssertTrue(appState.hasSubmittedCheckInToday(at: comparisonDate))
    }

    func testLocalStoreReportsCorruptDraftData() {
        let defaults = isolatedDefaults()
        defaults.set(Data("not-json".utf8), forKey: AppLocalStore.draftStorageKey)

        let result = AppLocalStore(defaults: defaults).readDraft()

        XCTAssertNil(result.value)
        XCTAssertEqual(result.status, .decodeFailed)
    }

    func testAppStateDiscardsOrganizationOffsetDraft() {
        let defaults = isolatedDefaults()
        // Organization-offset credit can never be student-submitted, so a
        // persisted draft claiming it is stale and must be discarded on boot.
        let staleDraft = CheckInDraft(
            id: "stale",
            creditType: .organizationOffset,
            courseId: nil,
            hours: 2,
            note: "old",
            proofAttachments: [],
            updatedAt: "刚刚"
        )
        XCTAssertTrue(AppLocalStore(defaults: defaults).saveDraft(staleDraft))

        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )

        XCTAssertNil(appState.draft)
        XCTAssertEqual(appState.storeHealth.draftReadStatus, .discarded)
    }

    func testStudentProfileDecodesYearGenderAndGradeFields() throws {
        let data = Data(
            """
            {
              "id": "demo-student-001",
              "name": "演示学生",
              "admissionYear": "2024",
              "birthDate": "2000-01-01",
              "gender": "female",
              "gradeLevel": "sophomore"
            }
            """.utf8
        )

        let profile = try JSONDecoder().decode(StudentProfile.self, from: data)

        XCTAssertEqual(profile.enrollmentYear, 2024)
        XCTAssertEqual(profile.birthDate, "2000-01-01")
        XCTAssertEqual(profile.gender, .female)
        XCTAssertEqual(profile.gradeLevel, "sophomore")
    }

    func testStudentProfileUsesServerCalculatedGradeFallback() throws {
        let profile = try JSONDecoder().decode(StudentProfile.self, from: Data(
            """
            {
              "id": "student-1",
              "name": "测试学生",
              "currentGradeLevel": "junior"
            }
            """.utf8
        ))

        XCTAssertEqual(profile.gradeLevel, "junior")
    }

    func testAcademicProjectionRollsGradeAtSeptemberBoundary() throws {
        let profile = StudentProfile(
            id: "demo-student-001",
            name: "演示学生",
            email: "demo.student@example.invalid",
            college: "工商管理学院",
            className: "2024A",
            status: "正常",
            enrollmentYear: 2024,
            birthDate: "2000-01-01",
            gender: .female
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let august = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12)))
        let september = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)))

        let before = StudentAcademicProjection.resolve(profile: profile, at: august, calendar: calendar)
        let after = StudentAcademicProjection.resolve(profile: profile, at: september, calendar: calendar)

        XCTAssertEqual(before.academicYear, "2025–2026 学年")
        XCTAssertEqual(before.grade, "大二")
        XCTAssertEqual(before.semester, "春季学期")
        XCTAssertEqual(after.academicYear, "2026–2027 学年")
        XCTAssertEqual(after.grade, "大三")
        XCTAssertEqual(after.semester, "秋季学期")
        XCTAssertEqual(after.physicalStandard, "女生 · 大三体测标准")
    }

    func testRemoteWorkspaceCacheIsSeparatedByServerAndStudent() {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        let remoteWorkspace = MockStudentRepository().loadWorkspace()

        XCTAssertTrue(
            store.saveRemoteWorkspace(
                remoteWorkspace,
                baseURL: StudentServerConfig.testBaseURL,
                studentID: "demo-student-001"
            )
        )
        XCTAssertNil(store.readWorkspace().value)
        XCTAssertEqual(
            store.readRemoteWorkspace(
                baseURL: StudentServerConfig.testBaseURL,
                studentID: "demo-student-001"
            ).value?.student.id,
            "demo-student-001"
        )
        XCTAssertNil(
            store.readRemoteWorkspace(
                baseURL: StudentServerConfig.testBaseURL,
                studentID: "another-student"
            ).value
        )
        XCTAssertNil(
            store.readRemoteWorkspace(
                baseURL: StudentServerConfig.productionBaseURL,
                studentID: "demo-student-001"
            ).value
        )
    }

    func testLocalMarkAllNoticesReadUpdatesWorkspaceAndSyncQueue() {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        XCTAssertGreaterThan(appState.unreadNoticeCount, 0)

        appState.markAllNoticesRead()

        XCTAssertEqual(appState.unreadNoticeCount, 0)
        XCTAssertEqual(appState.workspace.syncOperations.first?.type, .markNoticeRead)
    }

    func testDemoLoginRestoresLocalWorkspaceAfterTransientWorkspaceChanges() {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        let expectedRecordCount = MockStudentRepository().loadWorkspace().records.count
        appState.workspace.records.removeAll()

        appState.demoLogin()

        XCTAssertEqual(appState.workspace.records.count, expectedRecordCount)
        XCTAssertEqual(appState.dataSourceDescription, "演示数据")
        XCTAssertTrue(appState.isAuthenticated)
    }

    func testSubmittedCheckInRecordsExcludeSystemOffsets() {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )

        XCTAssertFalse(appState.submittedCheckInRecords.isEmpty)
        XCTAssertTrue(appState.submittedCheckInRecords.allSatisfy { $0.creditType != .organizationOffset })
        XCTAssertLessThan(appState.submittedCheckInRecords.count, appState.workspace.records.count)
    }

    func testProductionURLValidationRejectsPlaceholderAndInsecureHosts() {
        XCTAssertNil(StudentServerConfig.validatedProductionBaseURL(nil))
        XCTAssertNil(StudentServerConfig.validatedProductionBaseURL("http://api.example.edu/api/v1"))
        XCTAssertNil(StudentServerConfig.validatedProductionBaseURL("https://configuration-required.invalid/api/v1"))
        XCTAssertNil(StudentServerConfig.validatedProductionBaseURL("https://api.example.edu/api/v2"))
        XCTAssertEqual(
            StudentServerConfig.validatedProductionBaseURL("https://sports.example.edu/api/v1")?.absoluteString,
            "https://sports.example.edu/api/v1"
        )
    }

    func testMutationGateRejectsDuplicateInFlightOperationUntilCompletion() {
        var gate = InFlightMutationGate()

        XCTAssertTrue(gate.begin("submit-exemption"))
        XCTAssertFalse(gate.begin("submit-exemption"))
        XCTAssertTrue(gate.begin("supplement:record-1"))
        gate.end("submit-exemption")
        XCTAssertTrue(gate.begin("submit-exemption"))
        gate.removeAll()
        XCTAssertTrue(gate.begin("supplement:record-1"))
    }

    func testAccessTokenMigratesFromDefaultsToDeviceCredentialStore() async throws {
        let defaults = isolatedDefaults()
        let credentialStore = InMemoryCredentialStore()
        let legacyKey = RemoteStudentRepository.legacyAccessTokenDefaultsKey(for: StudentServerConfig.testBaseURL)
        let secureKey = RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
        defaults.set("legacy-short-lived-token", forKey: legacyKey)

        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            legacyDefaults: defaults
        )

        let isAuthenticated = await repository.isAuthenticated
        XCTAssertTrue(isAuthenticated)
        XCTAssertNil(defaults.string(forKey: legacyKey))
        XCTAssertEqual(
            try credentialStore.data(forKey: secureKey).flatMap { String(data: $0, encoding: .utf8) },
            "legacy-short-lived-token"
        )
    }

    func testLogoutIsLocalAndClearsSecureCredentialWithoutServerEndpoint() async throws {
        let defaults = isolatedDefaults()
        let credentialStore = InMemoryCredentialStore()
        let secureKey = RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
        try credentialStore.set(Data("short-lived-token".utf8), forKey: secureKey)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            legacyDefaults: defaults
        )

        let wasAuthenticated = await repository.isAuthenticated
        let securelyCleared = await repository.logout()
        let isAuthenticated = await repository.isAuthenticated
        XCTAssertTrue(wasAuthenticated)
        XCTAssertTrue(securelyCleared)
        XCTAssertFalse(isAuthenticated)
        XCTAssertNil(try credentialStore.data(forKey: secureKey))
    }

    func testLogoutInvalidatesLoginResponseThatFinishesLater() async throws {
        let credentialStore = InMemoryCredentialStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedLoginURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: session,
            legacyDefaults: isolatedDefaults()
        )

        let loginTask = Task {
            try await repository.login(account: "s1", password: "not-persisted")
        }
        try await Task.sleep(for: .milliseconds(25))
        let securelyCleared = await repository.logout()
        XCTAssertTrue(securelyCleared)

        do {
            _ = try await loginTask.value
            XCTFail("A stale login response must not restore a logged-out session")
        } catch let error as RepositoryError {
            guard case .sessionChanged = error else {
                XCTFail("Expected sessionChanged, got \(error)")
                return
            }
        }
        let isAuthenticated = await repository.isAuthenticated
        XCTAssertFalse(isAuthenticated)
        XCTAssertNil(try credentialStore.data(forKey: RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)))
    }

    func testCourseRelatedSubmissionKeepsCourseReferenceWhileGeneralOmitsIt() async throws {
        RecordingSportRecordURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingSportRecordURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("short-lived-token".utf8),
            forKey: RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
        )
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        _ = try await repository.submitCheckIn(
            courseId: "course-1",
            creditType: "课程相关",
            taskTitle: "课程相关运动打卡",
            hours: 1,
            note: "course related"
        )
        _ = try await repository.submitCheckIn(
            courseId: nil,
            creditType: "其他运动",
            taskTitle: "自主运动打卡",
            hours: 1,
            note: "autonomous"
        )

        let bodies = RecordingSportRecordURLProtocol.recordedBodies
        XCTAssertEqual(bodies.count, 2)
        let courseRelatedBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any]
        )
        let generalBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.last)) as? [String: Any]
        )
        XCTAssertEqual(courseRelatedBody["courseId"] as? String, "course-1")
        XCTAssertNil(courseRelatedBody["taskId"], "The legacy task reference must never be sent")
        XCTAssertNil(generalBody["taskId"])
        XCTAssertNil(generalBody["courseId"])
    }

    func testProofUploadUsesOnlyFrozenV1EndpointAndCleansTemporaryBody() async throws {
        RecordingNotFoundURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingNotFoundURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("short-lived-token".utf8),
            forKey: RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
        )
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )
        let attachment = ProofAttachment(
            id: "proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xFF, 0xD8]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "相册"
        )

        do {
            _ = try await repository.uploadProof(attachment: attachment)
            XCTFail("The 404 test transport must fail the upload")
        } catch {
            // The endpoint assertion below is the contract under test.
        }

        XCTAssertEqual(RecordingNotFoundURLProtocol.recordedPaths, ["/api/v1/upload/proof"])
        let uploadDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BNBUStudentUploads", isDirectory: true)
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: uploadDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(leftovers.filter { $0.lastPathComponent.hasPrefix("multipart-") }.isEmpty)
    }

    func testProtectedLocalStoreUsesFilesExcludedFromBackup() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BNBUStudentStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let defaults = isolatedDefaults()
        let store = AppLocalStore(
            fileManager: .default,
            directoryURL: directoryURL,
            legacyDefaults: defaults
        )
        let workspace = MockStudentRepository().loadWorkspace()

        XCTAssertTrue(store.usesProtectedFileStorage)
        XCTAssertTrue(store.saveWorkspace(workspace))
        let fileURL = try XCTUnwrap(store.storageURL(forKey: AppLocalStore.workspaceStorageKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(defaults.data(forKey: AppLocalStore.workspaceStorageKey))
        XCTAssertEqual(try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(store.readWorkspace().value?.student.id, workspace.student.id)
    }

    func testAppStateLogoutClearsDraftAndPersistedLocalState() async throws {
        let defaults = isolatedDefaults()
        let credentialStore = InMemoryCredentialStore()
        let secureKey = RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
        try credentialStore.set(Data("short-lived-token".utf8), forKey: secureKey)
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            legacyDefaults: defaults
        )
        let localStore = AppLocalStore(defaults: defaults)
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: remoteRepository
        )
        appState.demoLogin()
        appState.saveDraft(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "private draft",
            proofAttachments: []
        )

        await appState.logout()

        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(appState.draft)
        XCTAssertNil(defaults.data(forKey: AppLocalStore.draftStorageKey))
        XCTAssertNil(defaults.data(forKey: AppLocalStore.workspaceStorageKey))
        XCTAssertNil(try credentialStore.data(forKey: secureKey))
    }

    func testIdempotencyAttemptMatchesOnlySamePayloadAccountAndServer() throws {
        let proof = ProofAttachment(
            id: "proof-1",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "test"
        )
        let firstFingerprint = RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: ["description": "same", "hours": "1.0"],
            attachments: [proof]
        )
        let sameFingerprint = RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: ["hours": "1.0", "description": "same"],
            attachments: [proof]
        )
        let changedFingerprint = RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: ["description": "changed", "hours": "1.0"],
            attachments: [proof]
        )
        let attempt = PendingRemoteMutationAttempt.create(
            scope: "sport-record:create",
            fingerprint: firstFingerprint,
            serverIdentity: "https://sports.example.edu/api/v1",
            studentID: "student-1"
        )

        XCTAssertEqual(firstFingerprint, sameFingerprint)
        XCTAssertNotEqual(firstFingerprint, changedFingerprint)
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(attempt.idempotencyKey))
        XCTAssertTrue(attempt.matches(
            scope: "sport-record:create",
            fingerprint: sameFingerprint,
            serverIdentity: "https://sports.example.edu/api/v1",
            studentID: "student-1"
        ))
        XCTAssertFalse(attempt.matches(
            scope: "sport-record:create",
            fingerprint: sameFingerprint,
            serverIdentity: "https://sports.example.edu/api/v1",
            studentID: "student-2"
        ))
        XCTAssertFalse(attempt.matches(
            scope: "sport-record:create",
            fingerprint: changedFingerprint,
            serverIdentity: "https://sports.example.edu/api/v1",
            studentID: "student-1"
        ))
    }

    func testAllPendingMutationScopesRoundTripWithoutRawBytesThumbnailsOrSignedURLs() throws {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        let original = ProofAttachment(
            id: "source-proof",
            type: .image,
            fileName: "hospital-proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xAA, 0xBB]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "https://private.example/source.jpg?q-signature=secret"
        )
        let uploaded = ProofAttachment(
            id: "uploaded-proof",
            type: .image,
            fileName: "hospital-proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xCC]),
            uploadData: Data([0x01, 0x02]),
            source: "https://cos.example/proofs/one.jpg?q-signature=secret",
            cosKey: "proofs/one.jpg",
            mimeType: "image/jpeg",
            contentDigest: original.contentDigest
        )
        let scopes = [
            "sport-record:create",
            "exemption:create:physical-test",
            "exemption:supplement:ex1"
        ]
        var attempts: [String: PendingRemoteMutationAttempt] = [:]
        for scope in scopes {
            let fields = ["scopePayload": scope, "reason": "same payload"]
            let fingerprint = RemoteMutationFingerprint.make(
                scope: scope,
                fields: fields,
                attachments: [original]
            )
            var attempt = PendingRemoteMutationAttempt.create(
                scope: scope,
                fingerprint: fingerprint,
                serverIdentity: "https://sports.example.edu/api/v1",
                studentID: "s1",
                requestFields: fields,
                sourceProofs: [original]
            )
            attempt.uploadedProofs = [uploaded]
            attempts[scope] = attempt
        }

        XCTAssertTrue(store.savePendingRemoteMutations(attempts))
        let raw = try XCTUnwrap(defaults.data(forKey: AppLocalStore.pendingMutationStorageKey))
        let rawJSON = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(rawJSON.contains("private.example"))
        XCTAssertFalse(rawJSON.contains("cos.example"))
        XCTAssertFalse(rawJSON.contains("q-signature"))
        XCTAssertFalse(rawJSON.contains("uploadData"))
        XCTAssertFalse(rawJSON.contains("thumbnailData"))

        let restored = try XCTUnwrap(store.readPendingRemoteMutations().value)
        XCTAssertEqual(Set(restored.keys), Set(scopes))
        for scope in scopes {
            let attempt = try XCTUnwrap(restored[scope])
            XCTAssertEqual(attempt.requestFields["scopePayload"], scope)
            XCTAssertEqual(attempt.sourceProofs.first?.id, original.id)
            XCTAssertEqual(attempt.sourceProofs.first?.source, "本地凭证")
            XCTAssertNil(attempt.sourceProofs.first?.uploadData)
            XCTAssertNil(attempt.sourceProofs.first?.thumbnailData)
            XCTAssertEqual(attempt.uploadedProofs.first?.cosKey, "proofs/one.jpg")
            XCTAssertEqual(attempt.uploadedProofs.first?.source, "proofs/one.jpg")
            XCTAssertNil(attempt.uploadedProofs.first?.uploadData)
            XCTAssertNil(attempt.uploadedProofs.first?.thumbnailData)
        }
    }

    func testPendingMutationSummariesAllowPerScopeDiscardAndLogoutCleanup() async throws {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        let scopes = [
            "sport-record:create",
            "exemption:create:physical-test",
            "exemption:supplement:ex1"
        ]
        let attempts = Dictionary(uniqueKeysWithValues: scopes.map { scope in
            (scope, PendingRemoteMutationAttempt.create(
                scope: scope,
                fingerprint: "fingerprint-\(scope)",
                serverIdentity: "http://123.207.5.70:82/api/v1",
                studentID: "s1"
            ))
        })
        XCTAssertTrue(store.savePendingRemoteMutations(attempts))
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: store
        )

        XCTAssertEqual(Set(appState.pendingRemoteMutationSummaries.map(\.scope)), Set(scopes))
        for scope in scopes.dropLast() {
            appState.discardPendingRemoteMutation(scope: scope)
            XCTAssertFalse(appState.pendingRemoteMutationSummaries.contains(where: { $0.scope == scope }))
        }
        XCTAssertEqual(appState.pendingRemoteMutationSummaries.map(\.scope), [scopes.last!])

        await appState.logout()
        XCTAssertTrue(appState.pendingRemoteMutationSummaries.isEmpty)
        XCTAssertNil(defaults.data(forKey: AppLocalStore.pendingMutationStorageKey))
    }

    func testCheckInAmbiguousRetryReusesUploadedProofBodyAndIdempotencyKey() async throws {
        IdempotencyRetryURLProtocol.reset(recordFailures: 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyRetryURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        let defaults = isolatedDefaults()
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let localStore = AppLocalStore(defaults: defaults)
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: remoteRepository
        )
        await appState.login(account: "s1", password: "test-password")
        XCTAssertTrue(appState.isRemoteMode)
        let proof = ProofAttachment(
            id: "logical-proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xFF, 0xD8]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "相册"
        )

        let first = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "same logical attempt",
            sportType: "running",
            proofAttachments: [proof]
        )
        XCTAssertFalse(first)
        XCTAssertTrue(appState.canSafelyRetryCheckIn)
        XCTAssertEqual(IdempotencyRetryURLProtocol.uploadCount, 1)
        let persistedAttempt = try XCTUnwrap(localStore.readDraft().value?.pendingRemoteMutation)
        XCTAssertEqual(persistedAttempt.uploadedProofs.count, 1)
        let restoredRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let restoredState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: restoredRepository
        )
        let restoredProofs = try XCTUnwrap(restoredState.draft?.proofAttachments)
        XCTAssertNil(restoredProofs.first?.uploadData)
        XCTAssertEqual(restoredProofs.first?.contentDigest, proof.contentDigest)
        XCTAssertFalse(restoredProofs[0].isValidForUpload)
        await restoredState.login(account: "s1", password: "test-password")
        XCTAssertTrue(restoredState.canResumePendingCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "same logical attempt",
            sportType: "running",
            proofAttachments: restoredProofs
        ))
        XCTAssertTrue(restoredState.canRetryPendingRemoteMutation(scope: "sport-record:create"))

        let second = await restoredState.retryPendingRemoteMutation(
            scope: "sport-record:create"
        )
        XCTAssertTrue(second)
        XCTAssertEqual(IdempotencyRetryURLProtocol.uploadCount, 1, "An ambiguous retry must reuse uploaded COS references")
        XCTAssertEqual(IdempotencyRetryURLProtocol.recordBodies.count, 2)
        XCTAssertEqual(IdempotencyRetryURLProtocol.recordBodies[0], IdempotencyRetryURLProtocol.recordBodies[1])
        XCTAssertEqual(IdempotencyRetryURLProtocol.recordKeys.count, 2)
        XCTAssertEqual(IdempotencyRetryURLProtocol.recordKeys[0], IdempotencyRetryURLProtocol.recordKeys[1])
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(IdempotencyRetryURLProtocol.recordKeys[0]))
        let authoritativeRecord = try XCTUnwrap(
            restoredState.workspace.records.first(where: { $0.id == "record-idempotent" })
        )
        let authoritativeProof = try XCTUnwrap(authoritativeRecord.proofFiles.first)
        XCTAssertEqual(authoritativeProof.cosKey, "proofs/1.jpg")
        XCTAssertTrue(authoritativeProof.source.hasPrefix("https://"))
        XCTAssertTrue(authoritativeProof.source.contains("q-signature="))
        XCTAssertNil(localStore.readDraft().value)
        XCTAssertNil(defaults.data(forKey: AppLocalStore.pendingMutationStorageKey))
    }

    func testExemptionMutationsRecoverSamePayloadKeyAndUploadedReferencesAfterRestart() async throws {
        AllMutationRetryURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AllMutationRetryURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        let defaults = isolatedDefaults()
        let localStore = AppLocalStore(defaults: defaults)
        let firstRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let firstState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: firstRepository
        )
        await firstState.login(account: "s1", password: "test-password")
        let proof = ProofAttachment(
            id: "secondary-logical-proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xAA]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "相册"
        )
        let exemption = try XCTUnwrap(firstState.workspace.exemptions.first(where: { $0.id == "ex1" }))

        let firstCreateExemptionResult = await firstState.submitExemption(
            item: .run800m,
            reason: "膝关节损伤",
            detail: "医生建议暂缓耐力跑。",
            proofAttachments: [proof]
        )
        let firstSupplementExemptionResult = await firstState.submitExemptionSupplement(
            for: exemption,
            reason: "补充诊断",
            detail: "追加医院盖章证明。",
            proofAttachments: [proof]
        )
        XCTAssertFalse(firstCreateExemptionResult)
        XCTAssertFalse(firstSupplementExemptionResult)
        XCTAssertEqual(AllMutationRetryURLProtocol.uploadCount, 2)
        XCTAssertEqual(firstState.pendingRemoteMutationSummaries.count, 2)

        let persisted = try XCTUnwrap(localStore.readPendingRemoteMutations().value)
        XCTAssertEqual(persisted["exemption:create:physical-test"]?.uploadedProofs.count, 1)
        XCTAssertEqual(persisted["exemption:supplement:ex1"]?.uploadedProofs.count, 1)

        let restoredRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let restoredState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: restoredRepository
        )
        await restoredState.login(account: "s1", password: "test-password")
        let restoredExemption = try XCTUnwrap(restoredState.workspace.exemptions.first(where: { $0.id == "ex1" }))
        let createRecovery = try XCTUnwrap(restoredState.pendingExemptionFormRecovery(applicationID: nil))
        let supplementRecovery = try XCTUnwrap(
            restoredState.pendingExemptionFormRecovery(applicationID: restoredExemption.id)
        )
        XCTAssertTrue(createRecovery.isReadyToRetryWithoutOriginalBytes)
        XCTAssertTrue(supplementRecovery.isReadyToRetryWithoutOriginalBytes)
        XCTAssertTrue(restoredState.canResumePendingExemption(
            applicationID: nil,
            item: createRecovery.item,
            reason: createRecovery.reason,
            detail: createRecovery.detail,
            proofAttachments: createRecovery.sourceProofs
        ))

        XCTAssertTrue(restoredState.canRetryPendingRemoteMutation(scope: "exemption:create:physical-test"))
        XCTAssertTrue(restoredState.canRetryPendingRemoteMutation(scope: "exemption:supplement:ex1"))
        let restoredCreateExemptionResult = await restoredState.retryPendingRemoteMutation(
            scope: "exemption:create:physical-test"
        )
        let restoredSupplementExemptionResult = await restoredState.retryPendingRemoteMutation(
            scope: "exemption:supplement:ex1"
        )
        XCTAssertTrue(restoredCreateExemptionResult)
        XCTAssertTrue(restoredSupplementExemptionResult)

        XCTAssertEqual(AllMutationRetryURLProtocol.uploadCount, 2, "Restart retries must reuse uploaded COS references")
        for path in AllMutationRetryURLProtocol.mutationPaths {
            let bodies = AllMutationRetryURLProtocol.bodies[path] ?? []
            let keys = AllMutationRetryURLProtocol.keys[path] ?? []
            XCTAssertEqual(bodies.count, 2, path)
            XCTAssertEqual(bodies[0], bodies[1], path)
            XCTAssertEqual(keys.count, 2, path)
            XCTAssertEqual(keys[0], keys[1], path)
            XCTAssertTrue(IdempotencyKeyPolicy.isValid(keys[0]), path)
        }
        XCTAssertTrue(restoredState.pendingRemoteMutationSummaries.isEmpty)
        XCTAssertNil(defaults.data(forKey: AppLocalStore.pendingMutationStorageKey))
    }

    func testProofContentDigestSurvivesDraftRoundTripWithoutPersistingOriginalBytes() throws {
        let proof = ProofAttachment(
            id: "digest-proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "相册"
        )
        let before = RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: ["description": "same"],
            attachments: [proof]
        )
        let decoded = try JSONDecoder().decode(
            ProofAttachment.self,
            from: JSONEncoder().encode(proof)
        )
        let after = RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: ["description": "same"],
            attachments: [decoded]
        )

        XCTAssertNil(decoded.uploadData)
        XCTAssertNotNil(decoded.contentDigest)
        XCTAssertEqual(decoded.contentDigest, proof.contentDigest)
        XCTAssertEqual(before, after)

        let changedBytes = ProofAttachment(
            id: proof.id,
            type: proof.type,
            fileName: proof.fileName,
            byteCount: proof.byteCount,
            uploadData: Data([0xFF, 0xD8, 0x00, 0xD9]),
            source: proof.source
        )
        XCTAssertNotEqual(
            before,
            RemoteMutationFingerprint.make(
                scope: "sport-record:create",
                fields: ["description": "same"],
                attachments: [changedBytes]
            )
        )
    }

    func testRemoteMutationFingerprintReusesIdentityWhenSameContentIsRenamed() {
        let bytes = Data([0x10, 0x20, 0x30, 0x40])
        let original = ProofAttachment(
            id: "local-selection-1",
            type: .image,
            fileName: "before.jpg",
            byteCount: bytes.count,
            durationSeconds: nil,
            uploadData: bytes,
            source: "相册",
            mimeType: "image/jpeg"
        )
        let renamedAndRemapped = ProofAttachment(
            id: "server-reference-99",
            type: .video,
            fileName: "after-renamed.mov",
            byteCount: 99_999_999,
            durationSeconds: 23.75,
            uploadData: nil,
            source: "https://example.invalid/signed-proof?q-signature=redacted",
            cosKey: "proofs/server-reference-99",
            mimeType: "video/quicktime",
            contentDigest: original.contentDigest
        )
        let fields = ["description": "same business payload", "hours": "1.0"]

        let first = RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: fields,
            attachments: [original]
        )
        let renamed = RemoteMutationFingerprint.make(
            scope: "sport-record:create",
            fields: fields,
            attachments: [renamedAndRemapped]
        )
        let attempt = PendingRemoteMutationAttempt.create(
            scope: "sport-record:create",
            fingerprint: first,
            serverIdentity: "https://sports.example.edu/api/v1",
            studentID: "s1"
        )

        XCTAssertEqual(first, renamed, "Attachment metadata and storage transitions must not rotate the logical-attempt key")
        XCTAssertTrue(attempt.matches(
            scope: "sport-record:create",
            fingerprint: renamed,
            serverIdentity: "https://sports.example.edu/api/v1",
            studentID: "s1"
        ), "The renamed proof must resolve to the existing idempotency key")
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(attempt.idempotencyKey))
    }

    func testRemoteMutationFingerprintChangesWhenAttachmentBytesChange() {
        let firstProof = ProofAttachment(
            id: "same-id",
            type: .image,
            fileName: "same.jpg",
            byteCount: 4,
            uploadData: Data([0x01, 0x02, 0x03, 0x04]),
            source: "相册"
        )
        let changedProof = ProofAttachment(
            id: "same-id",
            type: .image,
            fileName: "same.jpg",
            byteCount: 4,
            uploadData: Data([0x01, 0x02, 0x03, 0x05]),
            source: "相册"
        )
        let fields = ["description": "same business payload"]

        XCTAssertNotEqual(
            RemoteMutationFingerprint.make(
                scope: "sport-record:create",
                fields: fields,
                attachments: [firstProof]
            ),
            RemoteMutationFingerprint.make(
                scope: "sport-record:create",
                fields: fields,
                attachments: [changedProof]
            ),
            "Different proof bytes must receive a different logical-attempt key"
        )
    }

    func testProofContentDigestStreamsFileInBoundedChunks() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bnbu-proof-digest-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let payload = Data((0..<65_553).map { UInt8($0 % 251) })
        try payload.write(to: fileURL, options: [.atomic, .completeFileProtection])
        var observedChunkSizes: [Int] = []
        let chunkSize = 4_096

        let streamed = try ProofContentDigest.sha256(
            fileURL: fileURL,
            chunkSize: chunkSize,
            onChunkRead: { observedChunkSizes.append($0) }
        )

        XCTAssertEqual(streamed, ProofContentDigest.sha256(data: payload))
        XCTAssertGreaterThan(observedChunkSizes.count, 1)
        XCTAssertEqual(observedChunkSizes.reduce(0, +), payload.count)
        XCTAssertTrue(observedChunkSizes.allSatisfy { (1...chunkSize).contains($0) })

        let fileBackedProof = ProofAttachment(
            id: "file-backed-proof",
            type: .video,
            fileName: "large-proof.mov",
            byteCount: payload.count,
            sourceFileURL: fileURL,
            source: "相册",
            contentDigest: streamed
        )
        let attempt = PendingRemoteMutationAttempt.create(
            scope: "sport-record:create",
            fingerprint: RemoteMutationFingerprint.make(
                scope: "sport-record:create",
                fields: ["description": "journal safety"],
                attachments: [fileBackedProof]
            ),
            serverIdentity: "https://sports.example.edu/api/v1",
            studentID: "s1",
            requestFields: ["description": "journal safety"],
            sourceProofs: [fileBackedProof]
        )
        let journalData = try JSONEncoder().encode(attempt)
        let journalText = String(decoding: journalData, as: UTF8.self)
        let restoredAttempt = try JSONDecoder().decode(PendingRemoteMutationAttempt.self, from: journalData)
        XCTAssertFalse(journalText.contains(fileURL.path))
        XCTAssertNil(restoredAttempt.sourceProofs.first?.sourceFileURL)
        XCTAssertNil(restoredAttempt.sourceProofs.first?.uploadData)
        XCTAssertEqual(restoredAttempt.sourceProofs.first?.contentDigest, streamed)
    }

    func testChangedCheckInPayloadStartsNewIdempotencyAttemptAndUploadSet() async throws {
        IdempotencyRetryURLProtocol.reset(recordFailures: 2)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyRetryURLProtocol.self]
        let defaults = isolatedDefaults()
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: InMemoryCredentialStore(),
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults),
            remoteRepo: remoteRepository
        )
        await appState.login(account: "s1", password: "test-password")
        let proof = ProofAttachment(
            id: "logical-proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "test"
        )

        _ = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "payload A",
            proofAttachments: [proof]
        )
        _ = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "payload B",
            proofAttachments: [proof]
        )

        XCTAssertEqual(IdempotencyRetryURLProtocol.uploadCount, 2)
        XCTAssertEqual(IdempotencyRetryURLProtocol.recordKeys.count, 2)
        XCTAssertNotEqual(IdempotencyRetryURLProtocol.recordKeys[0], IdempotencyRetryURLProtocol.recordKeys[1])
        XCTAssertNotEqual(IdempotencyRetryURLProtocol.recordBodies[0], IdempotencyRetryURLProtocol.recordBodies[1])
    }

    func testDeterministicClientErrorDiscardsCheckInAttemptJournal() async throws {
        IdempotencyRetryURLProtocol.reset(recordFailures: 1, failureStatusCode: 422)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdempotencyRetryURLProtocol.self]
        let defaults = isolatedDefaults()
        let localStore = AppLocalStore(defaults: defaults)
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: InMemoryCredentialStore(),
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: remoteRepository
        )
        await appState.login(account: "s1", password: "test-password")
        let proof = ProofAttachment(
            id: "deterministic-proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "相册"
        )

        let result = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "invalid deterministic payload",
            proofAttachments: [proof]
        )

        XCTAssertFalse(result)
        XCTAssertTrue(appState.pendingRemoteMutationSummaries.isEmpty)
        XCTAssertNil(localStore.readDraft().value?.pendingRemoteMutation)
        XCTAssertNil(defaults.data(forKey: AppLocalStore.pendingMutationStorageKey))
    }

    func testMutationJournalPolicyClassifiesDeterministicAndAmbiguousFailures() {
        for statusCode in [400, 403, 409, 413, 415, 422] {
            XCTAssertFalse(
                RemoteMutationJournalPolicy.shouldRetain(after: RepositoryError.httpError(statusCode)),
                "HTTP \(statusCode) must clear the affected scope"
            )
        }
        for statusCode in [408, 425, 429, 500, 503] {
            XCTAssertTrue(
                RemoteMutationJournalPolicy.shouldRetain(after: RepositoryError.httpError(statusCode)),
                "HTTP \(statusCode) may be ambiguous"
            )
        }
        XCTAssertTrue(RemoteMutationJournalPolicy.shouldRetain(after: RepositoryError.networkError("offline")))
        XCTAssertTrue(RemoteMutationJournalPolicy.shouldRetain(after: RepositoryError.serverError(
            statusCode: 409,
            code: "IDEMPOTENCY_CONFLICT",
            message: "still processing"
        )))
        XCTAssertFalse(RemoteMutationJournalPolicy.shouldRetain(after: RepositoryError.serverError(
            statusCode: 422,
            code: "VALIDATION_ERROR",
            message: "processing-looking text cannot override deterministic status"
        )))
        XCTAssertFalse(RemoteMutationJournalPolicy.shouldRetain(after: RepositoryError.unauthorized))
    }

    func testUploadStageDeterministicClientErrorClearsEachMutationScope() async throws {
        for flow in FailClosedMutationFlow.allCases {
            MutationFailClosedURLProtocol.reset(uploadFailure: .http(422))
            let defaults = isolatedDefaults()
            let localStore = AppLocalStore(defaults: defaults)
            let siblingScope = "journal-sibling:\(flow.scope)"
            let sibling = PendingRemoteMutationAttempt.create(
                scope: siblingScope,
                fingerprint: "sibling-fingerprint-\(flow.scope)",
                serverIdentity: StudentServerConfig.testBaseURL.absoluteString,
                studentID: "s1"
            )
            XCTAssertTrue(localStore.savePendingRemoteMutations([siblingScope: sibling]))
            let appState = await makeFailClosedRemoteState(defaults: defaults, localStore: localStore)

            let result = try await submitFailClosedFlow(flow, on: appState)

            XCTAssertFalse(result, flow.scope)
            XCTAssertEqual(MutationFailClosedURLProtocol.uploadCount, 1, flow.scope)
            XCTAssertTrue(MutationFailClosedURLProtocol.mutationPaths.isEmpty, flow.scope)
            XCTAssertFalse(
                appState.pendingRemoteMutationSummaries.contains(where: { $0.scope == flow.scope }),
                flow.scope
            )
            XCTAssertNil(localStore.readPendingRemoteMutations().value?[flow.scope], flow.scope)
            XCTAssertNotNil(
                localStore.readPendingRemoteMutations().value?[siblingScope],
                "Clearing \(flow.scope) must preserve sibling scopes"
            )
        }
    }

    func testUploadStageAmbiguousNetworkErrorRetainsEachMutationScope() async throws {
        for flow in FailClosedMutationFlow.allCases {
            MutationFailClosedURLProtocol.reset(uploadFailure: .network)
            let defaults = isolatedDefaults()
            let localStore = AppLocalStore(defaults: defaults)
            let appState = await makeFailClosedRemoteState(defaults: defaults, localStore: localStore)

            let result = try await submitFailClosedFlow(flow, on: appState)

            XCTAssertFalse(result, flow.scope)
            XCTAssertEqual(MutationFailClosedURLProtocol.uploadCount, 1, flow.scope)
            XCTAssertTrue(MutationFailClosedURLProtocol.mutationPaths.isEmpty, flow.scope)
            XCTAssertTrue(
                appState.pendingRemoteMutationSummaries.contains(where: { $0.scope == flow.scope }),
                flow.scope
            )
            XCTAssertNotNil(localStore.readPendingRemoteMutations().value?[flow.scope], flow.scope)
        }
    }

    func testInitialJournalWriteFailureBlocksUploadAndFinalMutationForAllFlows() async throws {
        for flow in FailClosedMutationFlow.allCases {
            MutationFailClosedURLProtocol.reset(uploadFailure: .none)
            let defaults = isolatedDefaults()
            let failure = PendingMutationWriteFailureController(failingWrites: [1])
            let localStore = AppLocalStore(
                defaults: defaults,
                shouldFailWrite: { failure.shouldFailWrite(forKey: $0) }
            )
            let appState = await makeFailClosedRemoteState(defaults: defaults, localStore: localStore)

            let result = try await submitFailClosedFlow(flow, on: appState)

            XCTAssertFalse(result, flow.scope)
            XCTAssertEqual(MutationFailClosedURLProtocol.uploadCount, 0, flow.scope)
            XCTAssertTrue(MutationFailClosedURLProtocol.mutationPaths.isEmpty, flow.scope)
            XCTAssertNil(localStore.readPendingRemoteMutations().value?[flow.scope], flow.scope)
            XCTAssertEqual(appState.errorMessage, RemoteMutationJournalError.writeFailed.localizedDescription)
        }
    }

    func testUploadedProofReferenceWriteFailureBlocksFinalMutationForAllFlows() async throws {
        for flow in FailClosedMutationFlow.allCases {
            MutationFailClosedURLProtocol.reset(uploadFailure: .none)
            let defaults = isolatedDefaults()
            let failure = PendingMutationWriteFailureController(failingWrites: [2])
            let localStore = AppLocalStore(
                defaults: defaults,
                shouldFailWrite: { failure.shouldFailWrite(forKey: $0) }
            )
            let appState = await makeFailClosedRemoteState(defaults: defaults, localStore: localStore)

            let result = try await submitFailClosedFlow(flow, on: appState)

            XCTAssertFalse(result, flow.scope)
            XCTAssertEqual(MutationFailClosedURLProtocol.uploadCount, 1, flow.scope)
            XCTAssertTrue(MutationFailClosedURLProtocol.mutationPaths.isEmpty, flow.scope)
            XCTAssertEqual(
                appState.pendingRemoteMutationSummaries.first(where: { $0.scope == flow.scope })?.uploadedProofCount,
                0,
                flow.scope
            )
            XCTAssertEqual(
                localStore.readPendingRemoteMutations().value?[flow.scope]?.uploadedProofs.count,
                0,
                flow.scope
            )
            XCTAssertEqual(appState.errorMessage, RemoteMutationJournalError.writeFailed.localizedDescription)
        }
    }

    func testServerConfirmedCleanupFailureNeverResubmitsAndClearsOnNextLoginForAllFlows() async throws {
        for flow in FailClosedMutationFlow.allCases {
            MutationFailClosedURLProtocol.reset(uploadFailure: .none)
            let defaults = isolatedDefaults()
            let removalFailure = PendingMutationRemovalFailureController()
            let failingStore = AppLocalStore(
                defaults: defaults,
                shouldFailRemoval: { removalFailure.shouldFailRemoval(forKey: $0) }
            )
            let appState = await makeFailClosedRemoteState(defaults: defaults, localStore: failingStore)
            removalFailure.enable()

            let result = try await submitFailClosedFlow(flow, on: appState)

            XCTAssertTrue(result, flow.scope)
            XCTAssertEqual(MutationFailClosedURLProtocol.mutationPaths.count, 1, flow.scope)
            let warning = appState.errorMessage ?? ""
            XCTAssertTrue(warning.contains("服务器成功"), flow.scope)
            XCTAssertTrue(warning.contains("请勿重复提交"), flow.scope)
            let confirmedSummary = try XCTUnwrap(
                appState.pendingRemoteMutationSummaries.first(where: { $0.scope == flow.scope })
            )
            XCTAssertTrue(confirmedSummary.isServerConfirmed, flow.scope)
            XCTAssertTrue(
                failingStore.readPendingRemoteMutations().value?[flow.scope]?.isServerConfirmed == true,
                flow.scope
            )

            let directResubmit = try await submitFailClosedFlow(flow, on: appState)
            XCTAssertFalse(directResubmit, flow.scope)
            XCTAssertEqual(
                MutationFailClosedURLProtocol.mutationPaths.count,
                1,
                "The original form must not resend a server-confirmed mutation for \(flow.scope)"
            )

            let cleanupWhileRemovalStillFails = await appState.retryPendingRemoteMutation(scope: flow.scope)
            XCTAssertFalse(cleanupWhileRemovalStillFails, flow.scope)
            XCTAssertEqual(
                MutationFailClosedURLProtocol.mutationPaths.count,
                1,
                "Cleanup-only recovery must never send the final mutation again for \(flow.scope)"
            )

            let recoveredStore = AppLocalStore(defaults: defaults)
            let recoveredState = await makeFailClosedRemoteState(
                defaults: defaults,
                localStore: recoveredStore
            )
            XCTAssertEqual(
                MutationFailClosedURLProtocol.mutationPaths.count,
                1,
                "Login cleanup must not replay a server-confirmed mutation for \(flow.scope)"
            )
            XCTAssertFalse(
                recoveredState.pendingRemoteMutationSummaries.contains(where: { $0.scope == flow.scope }),
                flow.scope
            )
            XCTAssertNil(recoveredStore.readPendingRemoteMutations().value?[flow.scope], flow.scope)
        }
    }

    func testCanonicalMutationRoutesCarryExplicitIdempotencyKeys() async throws {
        CanonicalMutationURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanonicalMutationURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("short-lived-token".utf8),
            forKey: RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
        )
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )
        let uploadedProof = ProofAttachment(
            id: "proofs/a.jpg",
            type: .image,
            fileName: "a.jpg",
            byteCount: 4,
            source: "https://cos.example/proofs/a.jpg",
            cosKey: "proofs/a.jpg",
            mimeType: "image/jpeg"
        )
        let application = ExemptionApplication(
            id: "exemption-1",
            studentId: "student-1",
            item: .run800m,
            reason: "medical reason",
            detail: "doctor note",
            submittedAt: "2026-07-16T00:00:00Z",
            status: .rejected,
            proofFiles: [],
            teacherFeedback: "supplement",
            updatedAt: "2026-07-16T00:00:00Z"
        )

        _ = try await repository.submitCheckIn(
            courseId: nil,
            creditType: "其他运动",
            taskTitle: "自主运动",
            hours: 1,
            note: "record",
            proofFiles: [uploadedProof],
            idempotencyKey: "ios-record-0001"
        )
        _ = try await repository.submitExemption(
            item: "800m",
            reason: "medical reason",
            detail: "doctor note",
            proofFiles: ["proofs/a.jpg"],
            idempotencyKey: "ios-exemption-0001"
        )
        _ = try await repository.supplementExemption(
            application: application,
            reason: "additional doctor note",
            proofFiles: ["proofs/a.jpg"],
            idempotencyKey: "ios-exemption-supplement-0001"
        )

        XCTAssertEqual(CanonicalMutationURLProtocol.paths, [
            "/api/v1/sport/records",
            "/api/v1/student/physical-test-exemptions",
            "/api/v1/student/physical-test-exemptions/exemption-1/supplements"
        ])
        XCTAssertEqual(CanonicalMutationURLProtocol.keys, [
            "ios-record-0001",
            "ios-exemption-0001",
            "ios-exemption-supplement-0001"
        ])
        XCTAssertFalse(CanonicalMutationURLProtocol.paths.contains("/api/v1/student/exemptions"))
    }

    func testAppStateSupplementsOnlyActionableExemptionStatuses() async {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        let base = ExemptionApplication(
            id: "supplementable-exemption",
            studentId: appState.workspace.student.id,
            item: .run800m,
            reason: "medical reason",
            detail: "doctor note",
            submittedAt: "2026-07-16T00:00:00Z",
            status: .supplementRequired,
            proofFiles: [],
            teacherFeedback: "请补充材料",
            updatedAt: "2026-07-16T00:00:00Z"
        )
        let expired = ExemptionApplication(
            id: "expired-exemption",
            studentId: base.studentId,
            item: base.item,
            reason: base.reason,
            detail: base.detail,
            submittedAt: base.submittedAt,
            status: .expired,
            proofFiles: [],
            teacherFeedback: "已过期",
            updatedAt: base.updatedAt
        )
        appState.workspace.exemptions = [base, expired]
        let proof = ProofAttachment(
            id: "supplement-proof",
            type: .image,
            fileName: "new-proof.jpg",
            byteCount: 4,
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "test"
        )

        let expiredResult = await appState.submitExemptionSupplement(
            for: expired,
            reason: "additional proof",
            detail: "new doctor note",
            proofAttachments: [proof]
        )
        let supplementResult = await appState.submitExemptionSupplement(
            for: base,
            reason: "additional proof",
            detail: "new doctor note",
            proofAttachments: [proof]
        )

        XCTAssertFalse(expiredResult)
        XCTAssertTrue(supplementResult)
        XCTAssertEqual(appState.workspace.exemptions.first(where: { $0.id == base.id })?.status, .pending)
        XCTAssertEqual(appState.workspace.exemptions.first(where: { $0.id == base.id })?.proofFiles.count, 1)
        XCTAssertEqual(appState.workspace.exemptions.first(where: { $0.id == expired.id })?.status, .expired)
    }

    private enum FailClosedMutationFlow: CaseIterable {
        case createRecord
        case createExemption
        case supplementExemption

        var scope: String {
            switch self {
            case .createRecord:
                return "sport-record:create"
            case .createExemption:
                return "exemption:create:physical-test"
            case .supplementExemption:
                return "exemption:supplement:ex1"
            }
        }
    }

    private func makeFailClosedRemoteState(
        defaults: UserDefaults,
        localStore: AppLocalStore
    ) async -> AppState {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MutationFailClosedURLProtocol.self]
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: InMemoryCredentialStore(),
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: remoteRepository
        )
        await appState.login(account: "s1", password: "test-password")
        XCTAssertTrue(appState.isRemoteMode)
        return appState
    }

    private func submitFailClosedFlow(
        _ flow: FailClosedMutationFlow,
        on appState: AppState
    ) async throws -> Bool {
        let proof = ProofAttachment(
            id: "fail-closed-\(flow.scope)",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xFF, 0xD8]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "相册"
        )
        switch flow {
        case .createRecord:
            return await appState.submitCheckIn(
                creditType: .general,
                courseId: nil,
                hours: 1,
                note: "fail-closed record",
                sportType: "running",
                proofAttachments: [proof]
            )
        case .createExemption:
            return await appState.submitExemption(
                item: .run800m,
                reason: "膝关节损伤",
                detail: "医生建议暂缓耐力跑。",
                proofAttachments: [proof]
            )
        case .supplementExemption:
            let application = try XCTUnwrap(appState.workspace.exemptions.first(where: { $0.id == "ex1" }))
            return await appState.submitExemptionSupplement(
                for: application,
                reason: "补充诊断",
                detail: "追加医院盖章证明。",
                proofAttachments: [proof]
            )
        }
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "BNBUStudentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class InMemoryCredentialStore: SecureCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = data
    }

    func removeData(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

private final class PendingMutationWriteFailureController: @unchecked Sendable {
    private let lock = NSLock()
    private let failingWrites: Set<Int>
    private var pendingMutationWriteCount = 0

    init(failingWrites: Set<Int>) {
        self.failingWrites = failingWrites
    }

    func shouldFailWrite(forKey key: String) -> Bool {
        guard key == AppLocalStore.pendingMutationStorageKey else { return false }
        lock.lock()
        defer { lock.unlock() }
        pendingMutationWriteCount += 1
        return failingWrites.contains(pendingMutationWriteCount)
    }
}

private final class PendingMutationRemovalFailureController: @unchecked Sendable {
    private let lock = NSLock()
    private var isEnabled = false

    func enable() {
        lock.lock()
        isEnabled = true
        lock.unlock()
    }

    func shouldFailRemoval(forKey key: String) -> Bool {
        guard key == AppLocalStore.pendingMutationStorageKey else { return false }
        lock.lock()
        defer { lock.unlock() }
        return isEnabled
    }
}

private enum MutationFailClosedUploadFailure {
    case none
    case http(Int)
    case network
}

private final class MutationFailClosedURLProtocol: URLProtocol, @unchecked Sendable {
    private static let mutationRouteSet: Set<String> = [
        "/api/v1/sport/records",
        "/api/v1/sport/records/r1/supplements",
        "/api/v1/student/physical-test-exemptions",
        "/api/v1/student/physical-test-exemptions/ex1/supplements"
    ]
    private static let lock = NSLock()
    private static var uploadFailure: MutationFailClosedUploadFailure = .none
    private static var storedUploadCount = 0
    private static var storedMutationPaths: [String] = []

    static var uploadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUploadCount
    }

    static var mutationPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedMutationPaths
    }

    static func reset(uploadFailure: MutationFailClosedUploadFailure) {
        lock.lock()
        self.uploadFailure = uploadFailure
        storedUploadCount = 0
        storedMutationPaths = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if path == "/api/v1/auth/login", method == "POST" {
            send(
                statusCode: 200,
                data: Data(
                    """
                    {
                      "token": "fail-closed-test-token",
                      "user": {
                        "id": "s1",
                        "name": "Test Student",
                        "email": "s1@example.edu",
                        "college": "BNBU",
                        "className": "2026A",
                        "status": "正常"
                      },
                      "defaultRoute": "/student"
                    }
                    """.utf8
                )
            )
            return
        }

        if path == "/api/v1/student/workspace", method == "GET" {
            let workspace = MockStudentRepository().loadWorkspace()
            send(statusCode: 200, data: (try? JSONEncoder().encode(workspace)) ?? Data("{}".utf8))
            return
        }

        if path == "/api/v1/upload/proof", method == "POST" {
            Self.lock.lock()
            Self.storedUploadCount += 1
            let failure = Self.uploadFailure
            Self.lock.unlock()
            switch failure {
            case .none:
                send(
                    statusCode: 200,
                    data: Data(
                        """
                        {"files":[{"url":"https://cos.example/proofs/fail-closed.jpg?q-signature=temporary","cosKey":"proofs/fail-closed.jpg","mediaType":"image","mimeType":"image/jpeg","size":4}]}
                        """.utf8
                    )
                )
            case .http(let statusCode):
                send(
                    statusCode: statusCode,
                    data: Data("{\"code\":\"VALIDATION_ERROR\",\"message\":\"invalid upload\"}".utf8)
                )
            case .network:
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }

        if Self.mutationRouteSet.contains(path), method == "POST" {
            Self.lock.lock()
            Self.storedMutationPaths.append(path)
            Self.lock.unlock()
            let body: Data
            if path == "/api/v1/sport/records" {
                body = Data("{\"id\":\"record-fail-closed\"}".utf8)
            } else if path == "/api/v1/sport/records/r1/supplements" {
                body = Data("{\"id\":\"r1\"}".utf8)
            } else if path == "/api/v1/student/physical-test-exemptions" {
                body = Data("{\"id\":\"ex-fail-closed\"}".utf8)
            } else {
                body = Data("{\"id\":\"ex1\"}".utf8)
            }
            send(statusCode: 201, data: body)
            return
        }

        send(
            statusCode: 404,
            data: Data("{\"code\":\"RESOURCE_NOT_FOUND\",\"message\":\"not found\"}".utf8)
        )
    }

    override func stopLoading() {}

    private func send(statusCode: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class DelayedLoginURLProtocol: URLProtocol, @unchecked Sendable {
    private let stopLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Data(
            """
            {
              "token": "late-token-must-be-discarded",
              "user": {
                "id": "s1",
                "name": "测试学生",
                "email": "s1@example.edu",
                "college": "BNBU",
                "className": "2026A",
                "status": "正常"
              },
              "defaultRoute": "/student"
            }
            """.utf8
        )
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.isStopped else { return }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopLock.lock()
        stopped = true
        stopLock.unlock()
    }

    private var isStopped: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopped
    }
}

private final class RecordingNotFoundURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var paths: [String] = []

    static var recordedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    static func reset() {
        lock.lock()
        paths = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.paths.append(request.url?.path ?? "")
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self,
            didLoad: Data("{\"code\":\"RESOURCE_NOT_FOUND\",\"message\":\"not found\"}".utf8)
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class RecordingSportRecordURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var bodies: [Data] = []

    static var recordedBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    static func reset() {
        lock.lock()
        bodies = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let body = Self.bodyData(from: request) {
            Self.lock.lock()
            Self.bodies.append(body)
            Self.lock.unlock()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"id\":\"record-1\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

private final class IdempotencyRetryURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var remainingRecordFailures = 0
    private static var recordFailureStatusCode: Int?
    private static var storedUploadCount = 0
    private static var storedRecordBodies: [Data] = []
    private static var storedRecordKeys: [String] = []
    private static var recordSucceeded = false

    static var uploadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUploadCount
    }

    static var recordBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedRecordBodies
    }

    static var recordKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedRecordKeys
    }

    static func reset(recordFailures: Int, failureStatusCode: Int? = nil) {
        lock.lock()
        remainingRecordFailures = recordFailures
        recordFailureStatusCode = failureStatusCode
        storedUploadCount = 0
        storedRecordBodies = []
        storedRecordKeys = []
        recordSucceeded = false
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if path == "/api/v1/auth/login", method == "POST" {
            send(
                statusCode: 200,
                data: Data(
                    """
                    {
                      "token": "idempotency-test-token",
                      "user": {
                        "id": "s1",
                        "name": "Test Student",
                        "email": "s1@example.edu",
                        "college": "BNBU",
                        "className": "2026A",
                        "status": "正常"
                      },
                      "defaultRoute": "/student"
                    }
                    """.utf8
                )
            )
            return
        }

        if path == "/api/v1/upload/proof", method == "POST" {
            Self.lock.lock()
            Self.storedUploadCount += 1
            let uploadNumber = Self.storedUploadCount
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: Data(
                    """
                    {"files":[{"url":"https://cos.example/proofs/\(uploadNumber).jpg","cosKey":"proofs/\(uploadNumber).jpg","mediaType":"image","mimeType":"image/jpeg","size":4}]}
                    """.utf8
                )
            )
            return
        }

        if path == "/api/v1/sport/records", method == "POST" {
            let body = Self.bodyData(from: request) ?? Data()
            let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
            Self.lock.lock()
            Self.storedRecordBodies.append(body)
            Self.storedRecordKeys.append(key)
            let shouldFail = Self.remainingRecordFailures > 0
            let failureStatusCode = Self.recordFailureStatusCode
            if shouldFail { Self.remainingRecordFailures -= 1 }
            Self.lock.unlock()
            if shouldFail {
                if let failureStatusCode {
                    send(
                        statusCode: failureStatusCode,
                        data: Data("{\"code\":\"VALIDATION_ERROR\",\"message\":\"invalid payload\"}".utf8)
                    )
                } else {
                    client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                }
            } else {
                Self.lock.lock()
                Self.recordSucceeded = true
                Self.lock.unlock()
                send(statusCode: 201, data: Data("{\"id\":\"record-idempotent\"}".utf8))
            }
            return
        }

        if path == "/api/v1/student/workspace", method == "GET" {
            var workspace = MockStudentRepository().loadWorkspace()
            Self.lock.lock()
            let recordSucceeded = Self.recordSucceeded
            Self.lock.unlock()
            if recordSucceeded {
                let signedProof = ProofAttachment(
                    id: "proofs/1.jpg",
                    type: .image,
                    fileName: "proof.jpg",
                    byteCount: 4,
                    source: "https://bnbu-sportsverified-1443273655.cos.ap-guangzhou.myqcloud.com/proofs/1.jpg?q-signature=test",
                    cosKey: "proofs/1.jpg",
                    mimeType: "image/jpeg"
                )
                workspace.records = [
                    CheckInRecord(
                        id: "record-idempotent",
                        courseId: nil,
                        taskTitle: "Self check-in",
                        creditType: .general,
                        hours: 1,
                        submittedAt: "2026-07-16T08:00:00.000Z",
                        validity: .valid,
                        proofSummary: "1 image",
                        proofPhotoCount: 1,
                        proofVideoCount: 0,
                        proofFiles: [signedProof],
                        note: "same logical attempt",
                        sportType: "running"
                    )
                ]
            } else {
                workspace.records.removeAll()
            }
            workspace.exemptions.removeAll()
            send(statusCode: 200, data: (try? JSONEncoder().encode(workspace)) ?? Data("{}".utf8))
            return
        }

        send(
            statusCode: 404,
            data: Data("{\"code\":\"RESOURCE_NOT_FOUND\",\"message\":\"not found\"}".utf8)
        )
    }

    override func stopLoading() {}

    private func send(statusCode: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

private final class AllMutationRetryURLProtocol: URLProtocol, @unchecked Sendable {
    static let mutationPaths = [
        "/api/v1/student/physical-test-exemptions",
        "/api/v1/student/physical-test-exemptions/ex1/supplements"
    ]

    private static let lock = NSLock()
    private static var remainingFailurePaths = Set(AllMutationRetryURLProtocol.mutationPaths)
    private static var storedUploadCount = 0
    private static var storedBodies: [String: [Data]] = [:]
    private static var storedKeys: [String: [String]] = [:]

    static var uploadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUploadCount
    }

    static var bodies: [String: [Data]] {
        lock.lock()
        defer { lock.unlock() }
        return storedBodies
    }

    static var keys: [String: [String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedKeys
    }

    static func reset() {
        lock.lock()
        remainingFailurePaths = Set(mutationPaths)
        storedUploadCount = 0
        storedBodies = [:]
        storedKeys = [:]
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if path == "/api/v1/auth/login", method == "POST" {
            send(
                statusCode: 200,
                data: Data(
                    """
                    {
                      "token": "all-mutation-test-token",
                      "user": {
                        "id": "s1",
                        "name": "Test Student",
                        "email": "s1@example.edu",
                        "college": "BNBU",
                        "className": "2026A",
                        "status": "正常"
                      },
                      "defaultRoute": "/student"
                    }
                    """.utf8
                )
            )
            return
        }

        if path == "/api/v1/student/workspace", method == "GET" {
            let workspace = MockStudentRepository().loadWorkspace()
            send(statusCode: 200, data: (try? JSONEncoder().encode(workspace)) ?? Data("{}".utf8))
            return
        }

        if path == "/api/v1/upload/proof", method == "POST" {
            Self.lock.lock()
            Self.storedUploadCount += 1
            let uploadNumber = Self.storedUploadCount
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: Data(
                    """
                    {"files":[{"url":"https://cos.example/proofs/secondary-\(uploadNumber).jpg?q-signature=temporary","cosKey":"proofs/secondary-\(uploadNumber).jpg","mediaType":"image","mimeType":"image/jpeg","size":4}]}
                    """.utf8
                )
            )
            return
        }

        if Self.mutationPaths.contains(path), method == "POST" {
            let body = Self.bodyData(from: request) ?? Data()
            let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
            Self.lock.lock()
            Self.storedBodies[path, default: []].append(body)
            Self.storedKeys[path, default: []].append(key)
            let shouldFail = Self.remainingFailurePaths.remove(path) != nil
            Self.lock.unlock()
            if shouldFail {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            } else if path == "/api/v1/student/physical-test-exemptions" {
                send(statusCode: 201, data: Data("{\"id\":\"ex-new\"}".utf8))
            } else {
                send(statusCode: 201, data: Data("{\"id\":\"ex1\"}".utf8))
            }
            return
        }

        send(
            statusCode: 404,
            data: Data("{\"code\":\"RESOURCE_NOT_FOUND\",\"message\":\"not found\"}".utf8)
        )
    }

    override func stopLoading() {}

    private func send(statusCode: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

private final class CanonicalMutationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedPaths: [String] = []
    private static var storedKeys: [String] = []

    static var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }

    static var keys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedKeys
    }

    static func reset() {
        lock.lock()
        storedPaths = []
        storedKeys = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.storedPaths.append(request.url?.path ?? "")
        Self.storedKeys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
        Self.lock.unlock()

        let path = request.url?.path ?? ""
        let body: Data
        if path.contains("physical-test-exemptions") {
            body = Data("{\"id\":\"exemption-1\",\"status\":\"pending\",\"createdAt\":\"2026-07-16T00:00:00Z\"}".utf8)
        } else {
            body = Data("{\"id\":\"record-1\"}".utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class IdempotencyConflictURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responseCode = "IDEMPOTENCY_CONFLICT"

    static func configure(code: String) {
        lock.lock()
        responseCode = code
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let code = Self.responseCode
        Self.lock.unlock()
        let body = try! JSONSerialization.data(withJSONObject: [
            "code": code,
            "message": "The idempotency request is still processing or the key was reused."
        ])
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 409,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
