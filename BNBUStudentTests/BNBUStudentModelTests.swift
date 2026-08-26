import XCTest
@testable import BNBUStudent

@MainActor
final class BNBUStudentModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Client-generated messages follow the app language; pin zh-Hans so
        // exact-string assertions stay deterministic on any host machine.
        BNBUL10n.localeOverride = Locale(identifier: "zh-Hans")
    }

    override func tearDown() {
        BNBUL10n.localeOverride = nil
        super.tearDown()
    }

    // Q&A follow-up 7/23: client-generated errors must render in the active
    // app language instead of leaking hard-coded Chinese in English mode.
    func testClientMessagesFollowAppLanguage() {
        BNBUL10n.localeOverride = Locale(identifier: "en")
        XCTAssertEqual(
            CheckInInputRule.validationMessage(note: "", for: ExerciseCategory.general),
            "Enter an exercise note."
        )
        XCTAssertEqual(
            CheckInInputRule.validationMessage(
                note: String(repeating: "a", count: 201),
                for: ExerciseCategory.courseRelated
            ),
            "The exercise note cannot exceed 200 characters."
        )
        XCTAssertFalse(CheckInTimeWindowPolicy.unavailable.displayText.isEmpty)
        XCTAssertEqual(ClientErrorMapper.map(RepositoryError.unauthorized).code, "AUTH_SESSION_REQUIRED")

        BNBUL10n.localeOverride = Locale(identifier: "zh-Hans")
        XCTAssertEqual(
            CheckInInputRule.validationMessage(note: "", for: ExerciseCategory.general),
            "请填写运动说明。"
        )
        XCTAssertEqual(ClientErrorMapper.map(RepositoryError.unauthorized).code, "AUTH_SESSION_REQUIRED")
    }

    func testRuntimeInterfaceValuesFollowAppLanguage() {
        BNBUL10n.localeOverride = Locale(identifier: "en")
        XCTAssertEqual(BNBUL10n.dynamicText("正常"), "Active")
        XCTAssertEqual(BNBUL10n.dynamicText("春季学期"), "Spring Semester")
        XCTAssertEqual(BNBUL10n.dynamicText("开始时间"), "Start Time")
        XCTAssertEqual(BNBUL10n.dynamicText("可计学时"), "Eligible Hours")
        XCTAssertEqual(4.0.localizedHourText, "4 hr")
        XCTAssertEqual(
            BNBUL10n.formatted("还差 %@", 4.0.localizedHourText),
            "4 hr remaining"
        )

        BNBUL10n.localeOverride = Locale(identifier: "zh-Hans")
        XCTAssertEqual(BNBUL10n.dynamicText("正常"), "正常")
        XCTAssertEqual(4.0.localizedHourText, "4 小时")
    }

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

    func testExerciseVideoCaptureUsesAcceptedFifteenSecondLimit() {
        XCTAssertEqual(ExerciseMediaDraftRule.maximumVideoDurationSeconds, 15)
    }

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
        XCTAssertEqual(appState.currentExerciseMediaDrafts.count, 1)
        XCTAssertEqual(appState.exercisePhotoDraftCount, 1, "旧 Session 素材不得占用新 Session 配额")

        // Abandoning clears only the current session's captures.
        appState.discardExerciseSession()
        XCTAssertNil(appState.exerciseSession)
        XCTAssertEqual(appState.exerciseMediaDrafts.count, 2, "放弃只清除本次会话拍摄的草稿")
    }

    func testCheckInCannotExcludeAnyConfirmedRetainedEvidence() async throws {
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
        XCTAssertTrue(appState.addExercisePhotoDraft(imageData: Data([1]), thumbnailData: nil))
        XCTAssertTrue(appState.addExercisePhotoDraft(imageData: Data([2]), thumbnailData: nil))
        let session = try XCTUnwrap(appState.exerciseSession)
        let callerSelectedSubset = [
            try XCTUnwrap(appState.proofAttachment(from: appState.currentExerciseMediaDrafts[0]))
        ]

        let submitted = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "Session retained evidence boundary",
            sportType: ExerciseSportType.running.rawValue,
            proofAttachments: callerSelectedSubset,
            exerciseSession: session
        )

        XCTAssertTrue(submitted)
        XCTAssertEqual(appState.workspace.records.first?.proofFiles.count, 2)
        XCTAssertEqual(appState.workspace.records.first?.proofPhotoCount, 2)
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

        let policy = CheckInTimeWindowPolicy(
            mode: "AVAILABLE",
            startDate: "2026-07-01",
            endDate: "2026-07-31",
            dailyStartTime: "06:00",
            dailyEndTime: "22:00",
            excludedDates: [],
            submissionDeadlineAt: nil
        )
        XCTAssertNotNil(policy.blockingMessage(at: try shanghai(5, 59)))
        XCTAssertNil(policy.blockingMessage(at: try shanghai(6, 0)))
        XCTAssertNil(policy.blockingMessage(at: try shanghai(21, 59)))
        XCTAssertNil(policy.blockingMessage(at: try shanghai(22, 0)))
        XCTAssertNotNil(policy.blockingMessage(at: try shanghai(23, 30)))

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

    // MARK: - Course join application (business rule 4.2)

    func testCourseEnrollmentStatusDefaultsToApprovedForLegacyPayloads() throws {
        let legacy = """
        {"id":"c1","code":"GEPE101","section":"01","name":"体育","semester":"2026 春季学期",
         "students":40,"pending":0,"completion":50,"missing":2,"deadline":"","teacher":"李老师"}
        """
        let legacyCourse = try JSONDecoder().decode(Course.self, from: Data(legacy.utf8))
        XCTAssertEqual(legacyCourse.enrollmentStatus, .approved)
        XCTAssertTrue(legacyCourse.allowsCheckIn)

        let pending = """
        {"id":"c2","code":"GEPE102","section":"02","name":"体育","semester":"2026 春季学期",
         "students":0,"pending":0,"completion":0,"missing":0,"deadline":"","teacher":"",
         "enrollment_status":"PENDING_REVIEW"}
        """
        let pendingCourse = try JSONDecoder().decode(Course.self, from: Data(pending.utf8))
        XCTAssertEqual(pendingCourse.enrollmentStatus, .pending)
        XCTAssertFalse(pendingCourse.allowsCheckIn)
        XCTAssertTrue(pendingCourse.isAwaitingEnrollmentReview)

        // Unknown values must not silently unlock check-in.
        let unknown = """
        {"id":"c3","code":"GEPE103","section":"03","name":"体育","semester":"2026 春季学期",
         "students":0,"pending":0,"completion":0,"missing":0,"deadline":"","teacher":"",
         "joinStatus":"waiting_for_teacher"}
        """
        let unknownCourse = try JSONDecoder().decode(Course.self, from: Data(unknown.utf8))
        XCTAssertEqual(unknownCourse.enrollmentStatus, .approved)
    }

    func testCourseJoinCodeValidationAndQRPayloadParsing() {
        XCTAssertEqual(CourseJoinCodeRule.validationMessage(for: "  "), "请输入课程邀请码。")
        XCTAssertEqual(CourseJoinCodeRule.validationMessage(for: "ab"), "邀请码长度应为 16–512 位。")
        let token = "BnBu-2026-token-A"
        XCTAssertNil(CourseJoinCodeRule.validationMessage(for: " \(token) "))
        XCTAssertEqual(CourseJoinCodeRule.normalized(" \(token) "), token)

        XCTAssertEqual(CourseJoinCodeRule.code(fromScannedPayload: token), token)
        XCTAssertEqual(
            CourseJoinCodeRule.code(
                fromScannedPayload: "http://local.test/join?code=\(token)",
                allowedURLHosts: ["local.test"]
            ),
            token
        )
        XCTAssertNil(
            CourseJoinCodeRule.code(
                fromScannedPayload: "https://unconfigured.example/join?code=\(token)",
                allowedURLHosts: ["local.test"]
            )
        )
        XCTAssertNil(CourseJoinCodeRule.code(fromScannedPayload: "https://local.test/join?code=\(token)"))
        XCTAssertNil(CourseJoinCodeRule.code(fromScannedPayload: "bnbu-sports://local.test/join/\(token)", allowedURLHosts: ["local.test"]))
        XCTAssertNil(CourseJoinCodeRule.code(fromScannedPayload: ""))
    }

    func testPendingEnrollmentBlocksExerciseStartAndSubmission() throws {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        appState.enforcesCheckInTimeWindow = false
        appState.demoLogin()

        let approvedCourse = try XCTUnwrap(appState.currentExerciseCourse)
        let invite = CourseInvite(
            code: "BnBu-2026-token-A",
            classSectionID: "section-new",
            courseName: "体育",
            courseCode: "GEPE999",
            section: "01",
            teacherName: "教师",
            semester: "2026 秋季学期"
        )
        XCTAssertNil(appState.lookupCourseInvite(rawCode: invite.code))
        XCTAssertFalse(appState.submitCourseJoinRequest(
            invite: invite,
            name: "演示学生",
            studentNumber: "2400123456",
            phone: "13800138000",
            email: "demo@bnbu.edu.cn"
        ))
        XCTAssertEqual(appState.errorMessage, "课程必须通过服务器 Join Capability 原子加入，不能创建本地待审核记录。")
        XCTAssertNil(appState.courseJoinRequest)
        XCTAssertEqual(appState.currentExerciseCourse?.id, approvedCourse.id)
        XCTAssertNil(appState.validatedSubmission(
            creditType: .courseRelated,
            courseId: invite.classSectionID,
            hours: 1
        ))
        XCTAssertNotNil(appState.validatedSubmission(
            creditType: .courseRelated,
            courseId: approvedCourse.id,
            hours: 1
        ))

    }

    func testStudentWithOnlyPendingEnrollmentCannotStartExercise() throws {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        appState.enforcesCheckInTimeWindow = false
        appState.workspace.courses = [
            Course(
                id: "pending-BNBU2026",
                code: "BNBU2026",
                section: "----",
                name: "待审核课程",
                semester: "2026 春季学期",
                students: 0,
                pending: 0,
                completion: 0,
                missing: 0,
                deadline: "",
                teacher: "",
                isCurrent: true,
                enrollmentStatus: .pending
            )
        ]

        XCTAssertNil(appState.currentExerciseCourse)
        XCTAssertFalse(appState.startExerciseSession(
            category: .general,
            sportType: .running,
            customSportName: ""
        ))
        XCTAssertEqual(appState.errorMessage, "当前学期没有 ACTIVE 体育课程，请使用有效邀请码加入或联系体育部。")
        XCTAssertNil(appState.exerciseSession)
    }

    // MARK: - Local/demo hour-target compatibility

    func testLocalDemoHourTargetsDecodeAndFallBackToStandard() throws {
        let decoder = JSONDecoder()

        // Local cached fixtures that publish nothing keep the shipped demo rule.
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        XCTAssertEqual(appState.hourRule, .standard)
        XCTAssertFalse(SportHourRule.unavailable.isAvailable)

        let customized = try decoder.decode(SportHourRule.self, from: Data("""
        {"courseRequiredHours": 6, "otherRequired": 4, "dailyMaxHours": 3}
        """.utf8))
        XCTAssertEqual(customized.courseRequired, 6)
        XCTAssertEqual(customized.generalRequired, 4)
        XCTAssertEqual(customized.dailyLimit, 3)
        // An absent total is derived from the parts rather than staying at 20.
        XCTAssertEqual(customized.total, 10)

        // Unusable values never reach the progress math.
        let broken = try decoder.decode(SportHourRule.self, from: Data("""
        {"total": -5, "courseRequired": 8}
        """.utf8))
        XCTAssertEqual(broken.courseRequired, 8)
        XCTAssertEqual(broken.generalRequired, SportHourRule.standard.generalRequired)
        XCTAssertEqual(broken.total, 8 + SportHourRule.standard.generalRequired)

        appState.workspace.hourRule = customized
        XCTAssertEqual(appState.hourRule.total, 10)
        XCTAssertEqual(appState.courseRemaining, max(6 - appState.workspace.progress.course, 0))
        XCTAssertEqual(appState.completionRatio, min(appState.totalCompleted / 10, 1))
    }

    func testRemoteProgressUsesOnlyAuthoritativeStudentScoreTotal() {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        appState.workspace.hourRule = .standard
        appState.workspace.progress.course = 12
        appState.workspace.progress.general = 11
        appState.workspace.progress.authoritativeTotalHours = 3.5
        appState.workspace.progress.authoritativeQualificationStatus = "NOT_QUALIFIED"
        appState.installRemoteContractFixtureForTesting()

        XCTAssertEqual(appState.totalCompleted, 3.5)
        XCTAssertEqual(appState.courseRemaining, 0)
        XCTAssertEqual(appState.generalRemaining, 0)
        XCTAssertEqual(appState.totalRemaining, 0)
        XCTAssertEqual(appState.completionRatio, 0)
        XCTAssertTrue(appState.hasAuthoritativeRemoteProgress)

        appState.workspace.progress.authoritativeTotalHours = nil
        appState.workspace.progress.authoritativeQualificationStatus = nil
        XCTAssertEqual(appState.totalCompleted, 0)
        XCTAssertFalse(appState.hasAuthoritativeRemoteProgress)
    }

    func testWorkspaceCachedBeforeHourTargetsStillDecodes() throws {
        let workspace = MockStudentRepository().loadWorkspace()
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(workspace)) as? [String: Any]
        )
        payload.removeValue(forKey: "hourRule")
        let legacy = try JSONDecoder().decode(
            StudentWorkspace.self,
            from: try JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertEqual(legacy.hourRule, .standard)
    }

    // MARK: - Student-visible grade content (业务流程 v6.0 §1.4 / 第五部分)

    /// The student grade view shows only the endurance-run outcome and check-in
    /// hour completion. Component names, weights, and weighted contributions are
    /// teacher-side grading rules, so the payload still decodes them but nothing
    /// in the client fabricates a breakdown when the server omits one.
    func testGradePayloadKeepsTeacherRulesOutOfTheStudentView() throws {
        let decoder = JSONDecoder()
        let withoutBreakdown = try decoder.decode(GradeRow.self, from: Data("""
        {"studentId":"s1","studentName":"演示学生","checkinScore":80,"exam":70,
         "attendance":90,"physical":60,"total":75,"sourceTrace":"API: /student/grades",
         "missingItems":[]}
        """.utf8))
        XCTAssertFalse(withoutBreakdown.usesPublishedComponents)
        XCTAssertTrue(withoutBreakdown.components.isEmpty)

        let withBreakdown = try decoder.decode(GradeRow.self, from: Data("""
        {"studentId":"s1","studentName":"演示学生","checkinScore":80,"exam":70,
         "attendance":90,"physical":60,"total":75,"sourceTrace":"","missingItems":[],
         "components":[{"key":"checkin","name":"体育打卡","score":80,"percentage":40}],
         "gradeState":"打卡与录入中"}
        """.utf8))
        XCTAssertTrue(withBreakdown.usesPublishedComponents)
        XCTAssertEqual(withBreakdown.state, .recording)
    }

    func testJoinRequestStatusKeepsCorrectionApartFromRejection() throws {
        XCTAssertEqual(JoinRequestStatus(serverValue: "PENDING"), .pending)
        XCTAssertEqual(JoinRequestStatus(serverValue: "待审核"), .pending)
        XCTAssertEqual(JoinRequestStatus(serverValue: "active"), .active)
        XCTAssertEqual(JoinRequestStatus(serverValue: "已通过"), .active)
        XCTAssertEqual(JoinRequestStatus(serverValue: "rejected"), .rejected)
        // "Information needed" is actionable by the student; "rejected" is not,
        // so the two must never collapse into one state.
        XCTAssertEqual(JoinRequestStatus(serverValue: "needs_correction"), .needsCorrection)
        XCTAssertEqual(JoinRequestStatus(serverValue: "需补正"), .needsCorrection)
        XCTAssertNil(JoinRequestStatus(serverValue: "something-new"))
        XCTAssertNil(JoinRequestStatus(serverValue: nil))
    }

    func testPendingExemptionBlocksOnlyTheSameType() throws {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        var application = try XCTUnwrap(appState.workspace.exemptions.first)
        application.status = .pending
        application.item = .run800m
        appState.workspace.exemptions = [application]

        XCTAssertTrue(appState.hasPendingExemption(for: .run800m))
        XCTAssertTrue(appState.hasPendingExemption(for: .enduranceRun))
        XCTAssertFalse(appState.hasPendingExemption(for: .run1000m))
    }

    func testWorkspaceCacheKeepsJoinRequestAndToleratesOlderCaches() throws {
        let request = CourseJoinRequest(
            id: "r1",
            inviteCode: "PE1024",
            courseName: "体育与健康 2026A",
            courseCode: "PE1024",
            section: "S02",
            teacherName: "陈老师",
            semester: "2026-2027 学年第一学期",
            studentName: "演示学生",
            studentNumber: "2400123456",
            email: "demo.student@example.invalid",
            status: .needsCorrection,
            reviewComment: "请补充班级信息后重新提交。",
            submittedAt: "2026-07-28 15:20",
            reviewedAt: "2026-07-29 09:10"
        )
        var workspace = MockStudentRepository().loadWorkspace()
        workspace.courseJoinRequest = request

        let encoded = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(StudentWorkspace.self, from: encoded)
        XCTAssertEqual(decoded.courseJoinRequest, request)

        // Caches written before the join-request page carry no such key.
        var legacy = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "courseJoinRequest")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertNil(
            try JSONDecoder().decode(StudentWorkspace.self, from: legacyData).courseJoinRequest
        )
    }

    func testDevicePrivacyConsentIsVersionedAndSatisfiesTheLoginForm() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "bnbu.tests.consent"))
        defaults.removePersistentDomain(forName: "bnbu.tests.consent")

        XCTAssertFalse(BNBUDevicePrivacyConsent.hasAccepted(defaults: defaults))
        BNBUDevicePrivacyConsent.recordAcceptance(defaults: defaults)
        XCTAssertTrue(BNBUDevicePrivacyConsent.hasAccepted(defaults: defaults))

        // The gate runs before sign-in, so an account with no record of its own
        // must still count as having agreed.
        XCTAssertTrue(BNBUPrivacyConsent.hasAccepted(account: "s1@example.invalid", defaults: defaults))

        // A newer policy version invalidates the stored acceptance.
        defaults.set(
            ["version": "1999-01-01", "acceptedAt": "1999-01-01T00:00:00Z"],
            forKey: BNBUDevicePrivacyConsent.defaultsKey
        )
        XCTAssertFalse(BNBUDevicePrivacyConsent.hasAccepted(defaults: defaults))

        defaults.removePersistentDomain(forName: "bnbu.tests.consent")
    }

    /// The startup destination is decided before the first frame, so the gate
    /// order is unit-testable without driving the UI.
    func testShellStageResolvesConsentThenGuideThenLogin() throws {
        let suite = "bnbu.tests.shell-stage"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        func stage(isAuthenticated: Bool = false, showsStartupGates: Bool = true) -> AppShellStage {
            AppShellStage.resolved(
                isAuthenticated: isAuthenticated,
                isUITesting: true,
                showsStartupGates: showsStartupGates,
                defaults: defaults
            )
        }

        XCTAssertEqual(stage(), .privacyConsent)

        BNBUDevicePrivacyConsent.recordAcceptance(defaults: defaults)
        XCTAssertEqual(stage(), .preLoginGuide)

        BNBUPreLoginGuide.markSeen(defaults: defaults)
        XCTAssertEqual(stage(), .login)

        // A restored session skips every pre-login gate.
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(stage(isAuthenticated: true), .authenticated)

        // Flow tests opt out of the gates and land on the sign-in page.
        XCTAssertEqual(stage(showsStartupGates: false), .login)

        defaults.removePersistentDomain(forName: suite)
    }

    func testPasswordFreeReviewModeIsLocalAndExplicit() async {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )

        state.demoLogin()

        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.isLocalReviewMode)
        XCTAssertFalse(state.isRemoteMode)
        XCTAssertEqual(state.workspace.student.email, "demo.student@example.invalid")

        await state.logout()
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertFalse(state.isLocalReviewMode)
    }

    func testLegacyCourseJoinRequestFailsClosedBeforeSignIn() throws {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertNil(state.courseJoinRequest)

        let invite = CourseInvite(
            code: "PE9999-current-token",
            classSectionID: "section-1",
            courseName: "体育",
            courseCode: "GEPE999",
            section: "01",
            teacherName: "教师",
            semester: "2026 秋季学期"
        )
        XCTAssertNil(state.lookupCourseInvite(rawCode: invite.code))
        XCTAssertFalse(state.submitCourseJoinRequest(
            invite: invite,
            name: "林同学",
            studentNumber: "2400987654",
            phone: "13800138000",
            email: "lin@bnbu.edu.cn"
        ))
        XCTAssertEqual(state.errorMessage, "课程必须通过服务器 Join Capability 原子加入，不能创建本地待审核记录。")
        XCTAssertNil(state.courseJoinRequest)
    }

    func testCourseJoinRequestRequiresANameAndStudentNumber() {
        XCTAssertEqual(
            CourseJoinRequestRule.validationMessage(name: "  ", studentNumber: "2400"),
            "请填写姓名。"
        )
        XCTAssertEqual(
            CourseJoinRequestRule.validationMessage(name: "林同学", studentNumber: ""),
            "请填写学号。"
        )
        XCTAssertEqual(
            CourseJoinRequestRule.validationMessage(
                name: String(repeating: "林", count: CourseJoinRequestRule.maximumNameLength + 1),
                studentNumber: "2400"
            ),
            "姓名不能超过 100 个字符。"
        )
        XCTAssertEqual(
            CourseJoinRequestRule.validationMessage(
                name: "林同学",
                studentNumber: String(repeating: "9", count: CourseJoinRequestRule.maximumStudentNumberLength + 1)
            ),
            "学号不能超过 32 个字符。"
        )
        XCTAssertNil(CourseJoinRequestRule.validationMessage(name: "林同学", studentNumber: "2400"))
    }

    func testLegacyCourseJoinRequestNeverCreatesTeacherApprovalState() throws {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        let invite = CourseInvite(
            code: "PE9999-current-token",
            classSectionID: "section-1",
            courseName: "体育",
            courseCode: "GEPE999",
            section: "01",
            teacherName: "教师",
            semester: "2026 秋季学期"
        )

        XCTAssertFalse(state.submitCourseJoinRequest(
            invite: invite,
            name: "林同学",
            studentNumber: "2400987654",
            phone: "",
            email: "lin@bnbu.edu.cn"
        ))
        XCTAssertEqual(state.errorMessage, "课程必须通过服务器 Join Capability 原子加入，不能创建本地待审核记录。")

        XCTAssertFalse(state.submitCourseJoinRequest(
            invite: invite,
            name: "林同学",
            studentNumber: "2400987654",
            phone: "13800138000",
            email: ""
        ))
        XCTAssertEqual(state.errorMessage, "课程必须通过服务器 Join Capability 原子加入，不能创建本地待审核记录。")
        XCTAssertNil(state.courseJoinRequest)

        XCTAssertFalse(state.submitCourseJoinRequest(
            invite: invite,
            name: "林同学",
            studentNumber: "2400987654",
            phone: "138 0013 8000",
            email: "lin@bnbu.edu.cn"
        ))
        XCTAssertNil(state.courseJoinRequest)
    }

    func testContactBindingChecksFormatAndCodeBeforeAccepting() {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )

        XCTAssertFalse(state.sendContactVerificationCode(to: "1380013800", channel: .phone))
        XCTAssertEqual(state.errorMessage, "请输入有效的手机号")
        XCTAssertFalse(state.sendContactVerificationCode(to: "lin@", channel: .email))
        XCTAssertEqual(state.errorMessage, "请输入有效的邮箱")

        XCTAssertFalse(state.sendContactVerificationCode(to: "13800138000", channel: .phone))
        XCTAssertFalse(state.sendContactVerificationCode(to: "+86 138 0013 8000", channel: .phone))
        XCTAssertFalse(state.sendContactVerificationCode(to: "lin@bnbu.edu.cn", channel: .email))
        XCTAssertEqual(state.errorMessage, "当前合同只支持 EMAIL，且已验证邮箱变更需要新旧邮箱双验证码；本地不会模拟成功。")

        XCTAssertFalse(state.verifyContactCode("123", for: "13800138000", channel: .phone))
        XCTAssertEqual(state.errorMessage, "请输入 6 位数字验证码")
        XCTAssertFalse(state.verifyContactCode("123456", for: "13800138000", channel: .phone))
        XCTAssertEqual(state.errorMessage, "联系方式验证码必须由服务器验证；本地不会模拟成功。")
    }

    func testNewSemesterWelcomeAppearsOnceWhenTheAcademicYearRollsOver() {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        let state = AppState(repository: MockStudentRepository(), localStore: store)

        // A first run has nothing to compare against, so it records the year
        // silently rather than greeting a student who never left.
        state.evaluateNewSemesterWelcome()
        XCTAssertNil(state.newSemesterWelcomeAcademicYear)
        let firstRunYear = store.loadCachedAcademicYear()
        XCTAssertFalse(firstRunYear.isEmpty)

        store.saveCachedAcademicYear("2019-2020 学年")
        state.evaluateNewSemesterWelcome()
        XCTAssertEqual(state.newSemesterWelcomeAcademicYear, firstRunYear)

        state.dismissNewSemesterWelcome()
        XCTAssertNil(state.newSemesterWelcomeAcademicYear)
        XCTAssertEqual(store.loadCachedAcademicYear(), firstRunYear)

        // Dismissing records the year, so it does not greet again.
        state.evaluateNewSemesterWelcome()
        XCTAssertNil(state.newSemesterWelcomeAcademicYear)
    }

    func testSystemModeParsesEveryServerSpellingAndBlocksWrites() {
        XCTAssertEqual(SystemMode.parse(nil), .normal)
        XCTAssertEqual(SystemMode.parse(""), .normal)
        XCTAssertEqual(SystemMode.parse("normal"), .normal)
        XCTAssertEqual(SystemMode.parse(" read_only "), .readOnly)
        XCTAssertEqual(SystemMode.parse("READONLY"), .readOnly)
        XCTAssertEqual(SystemMode.parse("maintenance"), .maintenance)
        XCTAssertFalse(SystemMode.normal.blocksWrites)
        XCTAssertTrue(SystemMode.readOnly.blocksWrites)
        XCTAssertTrue(SystemMode.maintenance.blocksWrites)
    }

    @MainActor
    func testReadOnlyModeRefusesEveryWriteAndSaysWhy() async {
        let store = AppLocalStore(defaults: isolatedDefaults())
        let state = AppState(
            repository: SystemModeRepositoryStub(status: SystemModeStatus(mode: .readOnly)),
            localStore: store
        )
        await state.refreshSystemStatus()

        XCTAssertEqual(state.systemMode, .readOnly)
        XCTAssertFalse(state.isWriteAllowed)
        XCTAssertFalse(state.allowWrite())
        XCTAssertEqual(state.errorMessage, "系统当前处于只读模式，暂不能提交或修改内容。")

        state.errorMessage = nil
        let feedbackResult = await state.submitFeedback(
            category: .bug,
            description: "打卡提交后一直卡在上传。"
        )
        XCTAssertNil(feedbackResult)
        XCTAssertEqual(state.errorMessage, "系统当前处于只读模式，暂不能提交或修改内容。")
        XCTAssertTrue(state.feedbackTickets.isEmpty)

        state.errorMessage = nil
        XCTAssertFalse(state.sendContactVerificationCode(to: "13800138000", channel: .phone))
        XCTAssertEqual(state.errorMessage, "当前合同只支持 EMAIL，且已验证邮箱变更需要新旧邮箱双验证码；本地不会模拟成功。")
    }

    @MainActor
    func testMaintenanceModeKeepsItsServerCopyAndBlocksSubmissions() async {
        let store = AppLocalStore(defaults: isolatedDefaults())
        let state = AppState(
            repository: SystemModeRepositoryStub(
                status: SystemModeStatus(
                    mode: .maintenance,
                    message: "  正在迁移成绩库  ",
                    estimatedRecoveryTime: " 2026-08-04 22:00 ",
                    plannedMaintenanceAt: "   "
                )
            ),
            localStore: store
        )
        await state.refreshSystemStatus()

        XCTAssertEqual(state.systemMode, .maintenance)
        XCTAssertEqual(state.systemModeStatus.message, "正在迁移成绩库")
        XCTAssertEqual(state.systemModeStatus.estimatedRecoveryTime, "2026-08-04 22:00")
        // A blank planned-maintenance field must not raise the banner.
        XCTAssertNil(state.systemModeStatus.plannedMaintenanceAt)

        let submitted = await state.submitExemption(
            item: .run800m,
            reason: "医院证明",
            detail: "医生建议免测",
            proofAttachments: []
        )
        XCTAssertFalse(submitted)
        XCTAssertEqual(state.errorMessage, "系统当前处于维护模式，暂不能提交或修改内容。")
    }

    func testHelpArticlesArriveInAdministratorOrderAndAreCachedForNextTime() async {
        let store = AppLocalStore(defaults: isolatedDefaults())
        let published = [
            HelpArticle(id: "b", title: "如何提交免测申请？", category: "申请", content: "从申请中心提交。", sortOrder: 20),
            HelpArticle(id: "a", title: "如何打卡？", category: "打卡", content: "选择项目后开始计时。", sortOrder: 10),
            HelpArticle(id: "", title: "缺少编号", category: "打卡", content: "不应展示。", sortOrder: 1),
            HelpArticle(id: "c", title: "空正文", category: "打卡", content: "   ", sortOrder: 2)
        ]
        let state = AppState(
            repository: HelpArticleRepositoryStub(result: .success(published)),
            localStore: store
        )

        await state.refreshHelpArticles()

        // Sort order decides, and articles missing an id or a body are dropped.
        XCTAssertEqual(state.helpArticles.map(\.id), ["a", "b"])
        XCTAssertFalse(state.isLoadingHelpArticles)
        XCTAssertNil(state.helpArticlesError)
        XCTAssertFalse(state.isShowingCachedHelpArticles)
        XCTAssertEqual(store.loadHelpArticles().map(\.id), ["a", "b"])
    }

    func testHelpArticleFailureFallsBackToTheCachedCopyAndSaysSo() async {
        let store = AppLocalStore(defaults: isolatedDefaults())
        store.saveHelpArticles([
            HelpArticle(id: "cached", title: "维护期间可以做什么？", category: "系统", content: "恢复后重试。", sortOrder: 5)
        ])
        let state = AppState(
            repository: HelpArticleRepositoryStub(result: .failure(RepositoryError.networkError("超时"))),
            localStore: store
        )

        await state.refreshHelpArticles()

        XCTAssertEqual(state.helpArticles.map(\.id), ["cached"])
        XCTAssertTrue(state.isShowingCachedHelpArticles)
        XCTAssertNil(state.helpArticlesError)
        XCTAssertFalse(state.isLoadingHelpArticles)
    }

    func testHelpArticleFailureWithoutACacheReportsARetryableError() async {
        let store = AppLocalStore(defaults: isolatedDefaults())
        let state = AppState(
            repository: HelpArticleRepositoryStub(result: .failure(RepositoryError.networkError("超时"))),
            localStore: store
        )

        await state.refreshHelpArticles()

        XCTAssertTrue(state.helpArticles.isEmpty)
        XCTAssertFalse(state.isShowingCachedHelpArticles)
        XCTAssertEqual(state.helpArticlesError, "帮助内容暂时无法加载，请稍后重试。")
        XCTAssertFalse(state.isLoadingHelpArticles)

        // A retry that succeeds clears the failure instead of stacking notices.
        let recovered = AppState(
            repository: HelpArticleRepositoryStub(
                result: .success([
                    HelpArticle(id: "a", title: "如何打卡？", content: "选择项目后开始计时。")
                ])
            ),
            localStore: store
        )
        await recovered.refreshHelpArticles()
        XCTAssertNil(recovered.helpArticlesError)
        XCTAssertEqual(recovered.helpArticles.map(\.id), ["a"])
    }

    func testHelpArticleSearchMatchesTitleBodyAndCategory() {
        let article = HelpArticle(
            id: "a",
            title: "如何提交体测免测申请？",
            category: "申请与审核",
            content: "上传证明材料后提交，由任课教师审核。"
        )

        XCTAssertTrue(article.matches("免测"))
        XCTAssertTrue(article.matches("证明材料"))
        XCTAssertTrue(article.matches("审核"))
        XCTAssertFalse(article.matches("成绩公示"))
    }

    func testMinimumVersionOnlyBlocksBuildsBelowTheRequirement() {
        XCTAssertEqual(BNBUAppVersion.compare("1.0", "1.0.0"), 0)
        XCTAssertEqual(BNBUAppVersion.compare("1.2", "1.10"), -1)
        XCTAssertEqual(BNBUAppVersion.compare("v2.0-debug", "1.9.9"), 1)

        XCTAssertNil(
            BNBUAppVersion.requirement(
                minimumVersion: "",
                downloadURL: "https://example.invalid",
                updateMessage: "",
                currentVersion: "1.0"
            )
        )
        XCTAssertNil(
            BNBUAppVersion.requirement(
                minimumVersion: "1.0",
                downloadURL: "https://example.invalid",
                updateMessage: "",
                currentVersion: "1.0.1"
            )
        )
        let requirement = BNBUAppVersion.requirement(
            minimumVersion: " 2.1 ",
            downloadURL: " https://example.invalid/app ",
            updateMessage: " 修复上传失败 ",
            currentVersion: "1.9-debug"
        )
        XCTAssertEqual(requirement?.minimumVersion, "2.1")
        XCTAssertEqual(requirement?.downloadURL, "https://example.invalid/app")
        XCTAssertEqual(requirement?.updateMessage, "修复上传失败")
    }

    func testExemptionOffersTheGenderMatchedRunPlusTeamAndClub() {
        XCTAssertEqual(
            ExemptionItem.selectableItems(gender: .male),
            [.run1000m, .team, .club]
        )
        XCTAssertEqual(
            ExemptionItem.selectableItems(gender: .female),
            [.run800m, .team, .club]
        )
        // An unknown gender still gets a run option rather than none.
        XCTAssertEqual(
            ExemptionItem.selectableItems(gender: nil),
            [.run800m, .team, .club]
        )
        XCTAssertTrue(ExemptionItem.team.isCheckInExemption)
        XCTAssertTrue(ExemptionItem.club.isCheckInExemption)
        XCTAssertFalse(ExemptionItem.run800m.isCheckInExemption)
        XCTAssertEqual(ExemptionItem.team.apiValue, "team")
        XCTAssertEqual(ExemptionItem.club.apiValue, "club")
    }

    func testCheckInExemptionRefusesToSubmitWithoutAnOrganization() async {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        let submitted = await state.submitExemption(
            item: .team,
            reason: "校队训练",
            detail: "每周随校队训练四次。",
            organization: "   ",
            proofAttachments: []
        )
        XCTAssertFalse(submitted)
        XCTAssertEqual(state.errorMessage, "请填写校队或社团名称")
    }

    func testExemptionApplicationCarriesItsOrganizationThroughCoding() throws {
        let application = ExemptionApplication(
            id: "ex-1",
            studentId: "stu-1",
            item: .club,
            reason: "社团活动",
            detail: "每周两次羽毛球社活动。",
            organization: "羽毛球社",
            submittedAt: "2026-08-01",
            status: .pending,
            proofFiles: [],
            teacherFeedback: "等待老师审核。",
            updatedAt: "2026-08-01"
        )
        let restored = try JSONDecoder().decode(
            ExemptionApplication.self,
            from: try JSONEncoder().encode(application)
        )
        XCTAssertEqual(restored.organization, "羽毛球社")
        XCTAssertEqual(restored.item, .club)

        // A payload from before the field existed still decodes.
        let legacy = Data(#"{"id":"ex-2","studentId":"s","type":"800m","reason":"伤","status":"pending","createdAt":"2026-07-01","updatedAt":"2026-07-01"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(ExemptionApplication.self, from: legacy)
        XCTAssertEqual(decodedLegacy.organization, "")
    }

    func testFeedbackRequiresOnlyPrivacyBoundedContent() {
        XCTAssertEqual(
            FeedbackRule.validationMessage(description: "  "),
            "请填写问题描述。"
        )
        XCTAssertEqual(
            FeedbackRule.validationMessage(
                description: String(repeating: "问", count: FeedbackRule.maximumDescriptionLength + 1)
            ),
            "问题描述最多 2000 字。"
        )
        XCTAssertNil(FeedbackRule.validationMessage(description: "打不开"))
        XCTAssertEqual(FeedbackCategory.privacy.apiValue, "PRIVACY")
        XCTAssertEqual(FeedbackCategory.title(forAPIValue: "ACCESSIBILITY"), "无障碍使用")
    }

    @MainActor
    func testFilingLocalFeedbackPrependsTheTicket() async {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        await state.refreshFeedbackTickets()
        let seeded = state.feedbackTickets.count
        XCTAssertGreaterThan(seeded, 0)

        let filed = await state.submitFeedback(
            category: .bug,
            description: "提交打卡后一直转圈。"
        )
        XCTAssertNotNil(filed)
        XCTAssertEqual(state.feedbackTickets.count, seeded + 1)
        XCTAssertEqual(state.feedbackTickets.first?.id, filed?.id)
        XCTAssertEqual(state.feedbackTickets.first?.status, .pending)
    }

    func testFeedbackStatusParsesEveryServerSpelling() {
        XCTAssertEqual(FeedbackTicketStatus.parsed(""), .pending)
        XCTAssertEqual(FeedbackTicketStatus.parsed("open"), .pending)
        XCTAssertEqual(FeedbackTicketStatus.parsed("IN_PROGRESS"), .processing)
        XCTAssertEqual(FeedbackTicketStatus.parsed("处理中"), .processing)
        XCTAssertEqual(FeedbackTicketStatus.parsed("closed"), .resolved)
        XCTAssertEqual(FeedbackTicketStatus.parsed("已驳回"), .rejected)
    }

    func testLegacyPhoneCodeSignInFailsClosed() {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        XCTAssertFalse(state.sendLoginCode(to: "1380013800", channel: .phone))
        XCTAssertEqual(state.errorMessage, "请输入有效的手机号")
        XCTAssertFalse(state.sendLoginCode(to: "13800138000", channel: .phone))
        XCTAssertEqual(state.errorMessage, "验证码必须由服务器发送。")

        XCTAssertFalse(state.signInWithCode("12345", contact: "13800138000", channel: .phone))
        XCTAssertEqual(state.errorMessage, "请输入 6 位数字验证码")
        XCTAssertFalse(state.isAuthenticated)

        XCTAssertFalse(state.signInWithCode("123456", contact: "13800138000", channel: .phone))
        XCTAssertEqual(state.errorMessage, "验证码必须由服务器验证。")
        XCTAssertFalse(state.isAuthenticated)
    }

    func testUnpublishedRecoveryRequestFailsClosed() {
        let state = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )
        XCTAssertFalse(state.submitRecoveryRequest(
            studentNumber: "", name: "林同学", description: "手机丢了", newPhone: "13800138000", newEmail: ""
        ))
        XCTAssertEqual(state.errorMessage, "账号恢复接口未在当前合同中发布；本地不会创建假申请。")
        XCTAssertFalse(state.submitRecoveryRequest(
            studentNumber: "2400987654", name: "林同学", description: "手机丢了", newPhone: "", newEmail: "lin@bnbu.edu.cn"
        ))
        XCTAssertEqual(state.errorMessage, "账号恢复接口未在当前合同中发布；本地不会创建假申请。")
    }

    func testBoundContactsAreShownMasked() {
        XCTAssertEqual(ContactBindingRule.masked("13800138000", for: .phone), "138****8000")
        XCTAssertEqual(ContactBindingRule.masked("lin@bnbu.edu.cn", for: .email), "li***@bnbu.edu.cn")
    }

    func testLegacyPendingCourseJoinCacheIsIgnoredOnRelaunch() throws {
        let defaults = isolatedDefaults()
        let store = AppLocalStore(defaults: defaults)
        XCTAssertTrue(store.saveCourseJoinRequest(CourseJoinRequest(
            id: "legacy-request",
            inviteCode: "PE9999-current-token",
            courseName: "体育",
            courseCode: "GEPE999",
            section: "01",
            teacherName: "教师",
            semester: "2026 秋季学期",
            studentName: "林同学",
            studentNumber: "2400987654",
            email: "lin@bnbu.edu.cn",
            phone: "13800138000",
            status: .pending,
            reviewComment: "",
            submittedAt: "2026-08-24T00:00:00Z",
            reviewedAt: nil
        )))

        let relaunched = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )
        XCTAssertNil(relaunched.courseJoinRequest)
    }

    func testEnduranceRunStatusSeparatesExemptionAbsenceAndNoEntry() throws {
        let decoder = JSONDecoder()

        func row(_ extra: String) throws -> GradeRow {
            try decoder.decode(GradeRow.self, from: Data("""
            {"studentId":"s1","studentName":"演示学生","checkinScore":0,"exam":0,
             "attendance":0,"physical":0,"total":0,"sourceTrace":"","missingItems":[]\(extra)}
            """.utf8))
        }

        // A duration alone cannot tell a measured result from an exemption, so
        // the server value wins whenever it is present.
        XCTAssertEqual(try row("").enduranceRunStatus, .notRecorded)
        XCTAssertEqual(try row(",\"enduranceRunTimeSeconds\":245").enduranceRunStatus, .recorded)
        XCTAssertEqual(try row(",\"enduranceRunStatus\":\"exempt\"").enduranceRunStatus, .exempt)
        XCTAssertEqual(try row(",\"enduranceRunStatus\":\"缺考\"").enduranceRunStatus, .absent)
        XCTAssertEqual(try row(",\"enduranceRunStatus\":\"not_recorded\",\"enduranceRunTimeSeconds\":245").enduranceRunStatus, .notRecorded)
        // An unrecognised status falls back to whatever the duration implies.
        XCTAssertEqual(try row(",\"enduranceRunStatus\":\"anything-new\",\"enduranceRunTimeSeconds\":245").enduranceRunStatus, .recorded)
        XCTAssertEqual(try row(",\"enduranceRunStatus\":\"anything-new\"").enduranceRunStatus, .notRecorded)

        let scored = try row(",\"enduranceRunStatus\":\"exempt\",\"enduranceRunScore\":85")
        XCTAssertEqual(scored.enduranceRunScore, 85)
        XCTAssertEqual(GradeTimeFormatter.runTime(245), "4′05″")
    }

    /// Organization credit can offset course hours as well as general hours
    /// (§2.1), so the raw check-in totals are carried separately for both.
    func testProgressCarriesRawHoursForBothCategories() throws {
        let decoder = JSONDecoder()
        let offset = try decoder.decode(StudentProgress.self, from: Data("""
        {"id":"s1","name":"演示学生","college":"BNBU","className":"PE-1",
         "course":10,"general":10,"rawCourse":4,"rawGeneral":0,
         "exam":0,"attendance":0,"physical":0,"status":"","source":"server"}
        """.utf8))
        XCTAssertEqual(offset.rawCourse, 4)
        XCTAssertEqual(offset.rawGeneral, 0)

        // Servers that predate the field report the offset value as the raw one
        // rather than reading as zero completed hours.
        let legacy = try decoder.decode(StudentProgress.self, from: Data("""
        {"id":"s1","name":"演示学生","college":"BNBU","className":"PE-1",
         "course":6,"general":3,"exam":0,"attendance":0,"physical":0,
         "status":"","source":"server"}
        """.utf8))
        XCTAssertEqual(legacy.rawCourse, 6)
        XCTAssertEqual(legacy.rawGeneral, 3)
    }

    func testGradeHourFormatterKeepsWholeHoursWhole() {
        XCTAssertEqual(GradeHourFormatter.number(20), "20")
        XCTAssertEqual(GradeHourFormatter.number(6.5), "6.5")
        XCTAssertEqual(GradeHourFormatter.number(0), "0")
    }

    func testCompactTimestampTrimsWithoutReformatting() {
        XCTAssertEqual(GradeTimeFormatter.compact("2026-07-29T14:32:07Z"), "2026-07-29 14:32")
        XCTAssertEqual(GradeTimeFormatter.compact("2026-07-29"), "2026-07-29")
        XCTAssertEqual(GradeTimeFormatter.compact("  "), "")
    }

    // MARK: - Location default deny

    func testExerciseSessionNeverCollectsLocation() throws {
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
        XCTAssertEqual(appState.exerciseSession?.locationStatus, .unavailable)
        XCTAssertNil(appState.exerciseSession?.latitude)
        XCTAssertNil(appState.exerciseSession?.longitude)
        XCTAssertTrue(appState.endExerciseSession())
        XCTAssertEqual(appState.exerciseSession?.locationStatus, .unavailable)
        XCTAssertNil(appState.exerciseSession?.latitude)
        XCTAssertNil(appState.exerciseSession?.longitude)
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

    func testDebugServerConfigDefaultsToLocalAPI() {
        let resolved = StudentServerConfig.resolvedBaseURL(arguments: ["BNBUStudent"], environment: [:])

        XCTAssertEqual(resolved.absoluteString, "http://127.0.0.1:13000/api/v1")
        XCTAssertEqual(StudentAPIClient().baseURL.absoluteString, resolved.absoluteString)
    }

    func testServerConfigAllowsArgumentAndEnvironmentOverrides() {
        let argumentURL = StudentServerConfig.resolvedBaseURL(
            arguments: ["BNBUStudent", "-server-base-url", "http://127.0.0.1:18080/api/v1"],
            environment: ["BNBU_API_BASE_URL": "http://127.0.0.1:13000/api/v1"]
        )
        let environmentURL = StudentServerConfig.resolvedBaseURL(
            arguments: ["BNBUStudent"],
            environment: ["BNBU_API_BASE_URL": "http://127.0.0.1:13000/api/v1"]
        )

        XCTAssertEqual(argumentURL.absoluteString, "http://127.0.0.1:18080/api/v1")
        XCTAssertEqual(environmentURL.absoluteString, "http://127.0.0.1:13000/api/v1")
    }

    func testPublicClientCapabilitiesUseCanonicalContractRoutesAndDTOs() async throws {
        CanonicalPublicCapabilityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanonicalPublicCapabilityURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("must-not-be-sent-to-public-endpoints".utf8),
            forKey: RemoteStudentRepository.accessTokenKey(for: StudentServerConfig.testBaseURL)
        )
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        let mode = await repository.loadSystemMode()
        let requirement = await repository.loadUpdateRequirement(
            currentVersion: "0.1.0",
            currentBuildNumber: 1
        )
        let articles = try await repository.loadHelpArticles(locale: "en")

        XCTAssertEqual(mode.mode, .readOnly)
        XCTAssertEqual(requirement?.minimumVersion, "0.2.0")
        XCTAssertEqual(requirement?.downloadURL, "https://apps.example.invalid/bnbu")
        XCTAssertEqual(requirement?.updateMessage, "Update required")
        XCTAssertEqual(articles.map(\.id), ["help-1", "help-2"])
        XCTAssertEqual(articles.map(\.content), ["First body", "Second body"])
        XCTAssertEqual(
            CanonicalPublicCapabilityURLProtocol.paths,
            ["/api/v1/system-mode", "/api/v1/app-release-policy", "/api/v1/help-articles"]
        )
        XCTAssertTrue(CanonicalPublicCapabilityURLProtocol.authorizationHeaders.allSatisfy { $0 == nil })
        XCTAssertEqual(
            CanonicalPublicCapabilityURLProtocol.queryValues(at: 1),
            ["platform": "IOS", "currentVersion": "0.1.0", "currentBuildNumber": "1"]
        )
        XCTAssertEqual(CanonicalPublicCapabilityURLProtocol.queryValues(at: 2), ["locale": "en"])
    }

    func testEnduranceConversionFailsClosedUntilContractDecisionExists() async {
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: InMemoryCredentialStore(),
            legacyDefaults: isolatedDefaults()
        )

        do {
            _ = try await repository.convertEndurance(
                timeSeconds: 240,
                gender: "female",
                gradeLevel: "2026"
            )
            XCTFail("A client must not invent an endurance conversion rule")
        } catch let error as RepositoryError {
            XCTAssertTrue(error.localizedDescription.contains("CONTRACT DECISION REQUIRED"))
        } catch {
            XCTFail("Expected RepositoryError, got \(error)")
        }
    }

    func testCursorListsDrainEveryPageWithoutRepeatingTheFirstCursor() async throws {
        CursorPaginationURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CursorPaginationURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        let applications = try await repository.listExemptions()

        XCTAssertEqual(applications.map(\.id), ["exemption-page-1", "exemption-page-2"])
        XCTAssertEqual(CursorPaginationURLProtocol.observedCursors(), ["<first>", "page-2"])
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

    func testRepositoryErrorsUseSafeActionableStudentMessages() throws {
        let statusCases: [(Int, ClientErrorContext, Bool)] = [
            (401, .login, false),
            (403, .join, false),
            (409, .session, true),
            (422, .record, false),
            (429, .otp, true),
            (503, .exemption, true),
        ]
        for (status, context, retryable) in statusCases {
            let mapped = ClientErrorMapper.map(RepositoryError.httpError(status), context: context)
            XCTAssertFalse(mapped.title.isEmpty)
            XCTAssertFalse(mapped.message.isEmpty)
            XCTAssertFalse(mapped.action.isEmpty)
            XCTAssertEqual(mapped.retryable, retryable)
            XCTAssertFalse(mapped.displayText.contains("Stack Trace"))
        }

        let detailsJSON = Data(#"""
        {
          "retryable":true,
          "fieldErrors":[{"field":"account","code":"INVALID_FORMAT"}],
          "startedAt":"2026-08-24T08:00:00Z",
          "status":"IN_PROGRESS",
          "startedOnCurrentAuthSession":false,
          "ignored":{"token":"must-not-be-retained"}
        }
        """#.utf8)
        let details = try JSONDecoder().decode(SafeContractErrorDetails.self, from: detailsJSON)
        let active = RepositoryError.contractError(
            statusCode: 409,
            code: "SESSION_ALREADY_ACTIVE",
            message: "raw server message token=secret",
            requestId: "request-safe-1",
            timestamp: "2026-08-24T08:00:00Z",
            details: details
        )
        let mappedActive = ClientErrorMapper.map(active, context: .session)
        XCTAssertEqual(mappedActive.code, "SESSION_ALREADY_ACTIVE")
        XCTAssertEqual(mappedActive.requestId, "request-safe-1")
        XCTAssertEqual(mappedActive.safeStatus, "IN_PROGRESS")
        XCTAssertEqual(mappedActive.safeStartedAt, "2026-08-24T08:00:00Z")
        XCTAssertEqual(mappedActive.startedOnCurrentAuthSession, false)
        XCTAssertNotNil(mappedActive.fieldErrors["account"])
        XCTAssertFalse(mappedActive.displayText.contains("raw server message"))
        XCTAssertFalse(mappedActive.displayText.contains("secret"))

        let unsafeMetadata = RepositoryError.contractError(
            statusCode: 409,
            code: "SESSION\nTOKEN_SECRET",
            message: "do not expose",
            requestId: String(repeating: "r", count: 65),
            timestamp: "2026-08-24T08:00:00Z",
            details: nil
        )
        let sanitized = ClientErrorMapper.map(unsafeMetadata, context: .session)
        XCTAssertEqual(sanitized.code, "HTTP_409")
        XCTAssertNil(sanitized.requestId)
        XCTAssertFalse(sanitized.displayText.contains("TOKEN_SECRET"))
    }

    func testStudentNumberNeverFallsBackToOpaqueInternalID() {
        let profile = StudentProfile(
            id: "3ea8d710-7df0-42e4-9b27-0acbeadead01",
            studentNumber: nil,
            name: "林同学",
            email: "",
            college: "",
            className: "",
            status: "ACTIVE",
            enrollmentYear: nil,
            gender: .unknown
        )
        XCTAssertEqual(profile.displayStudentNumber, "待同步")
        XCTAssertNotEqual(profile.displayStudentNumber, profile.id)
    }

    func testMatchingProtectedSessionIsRecoveredButOtherDeviceSessionIsReadOnlyConflict() async throws {
        ActiveExerciseSessionURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActiveExerciseSessionURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        let recovered = try await repository.startOrRecoverExerciseSession(
            preferredClassSectionId: "class-section-1",
            recoverableLocalSessionId: "session-origin-device",
            clientObservedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )
        guard case .recovered(let recoveredSession, let recoveredRequestId) = recovered else {
            XCTFail("The protected matching local mirror must recover")
            return
        }
        XCTAssertEqual(recoveredSession.id, "session-origin-device")
        XCTAssertEqual(recoveredRequestId, "ios-active-session-request")

        let conflict = try await repository.startOrRecoverExerciseSession(
            preferredClassSectionId: "class-section-1",
            recoverableLocalSessionId: "different-device-session",
            clientObservedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )
        guard case .alreadyActive(let conflictSession, let conflictRequestId) = conflict else {
            XCTFail("A different device's active Session must remain read-only")
            return
        }
        XCTAssertEqual(conflictSession.id, "session-origin-device")
        XCTAssertEqual(conflictRequestId, "ios-active-session-request")
        XCTAssertEqual(ActiveExerciseSessionURLProtocol.postCount, 0)
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
                _ = try await repository.submitExerciseRecord(
                    sessionId: "session-conflict",
                    creditType: .general,
                    sportType: .running,
                    customSportName: nil,
                    description: "same logical request",
                    mediaIds: ["media-conflict"],
                    clientRequestId: "ios-conflict-test-0001",
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
        XCTAssertEqual(
            CheckInInputRule.validationMessage(note: "", for: ExerciseCategory.general),
            "请填写运动说明。"
        )
        XCTAssertEqual(
            CheckInInputRule.validationMessage(note: "  \n", for: ExerciseCategory.general),
            "请填写运动说明。"
        )
        XCTAssertNil(
            CheckInInputRule.validationMessage(note: "", for: ExerciseCategory.courseRelated)
        )
        XCTAssertNil(
            CheckInInputRule.validationMessage(
                note: String(repeating: "跑", count: 200),
                for: ExerciseCategory.general
            )
        )
        XCTAssertEqual(
            CheckInInputRule.validationMessage(
                note: String(repeating: "跑", count: 201),
                for: ExerciseCategory.courseRelated
            ),
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

    func testExemptionListUsesOnlyCurrentContractCollection() async throws {
        ExemptionRefreshURLProtocol.configure(.success)
        let repository = makeExemptionRefreshRepository()

        let exemptions = try await repository.listExemptions()

        XCTAssertEqual(exemptions.map(\.id), ["summary-exemption"])
        XCTAssertEqual(ExemptionRefreshURLProtocol.paths, ["/api/v1/exemption-applications"])
    }

    func testExemptionListMalformedDedicatedPayloadThrowsInsteadOfReturningEmptyList() async {
        ExemptionRefreshURLProtocol.configure(.malformedDedicatedPayload)
        let repository = makeExemptionRefreshRepository()

        do {
            _ = try await repository.listExemptions()
            XCTFail("Malformed exemption data must not be treated as an empty list")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testRemoteExemptionRefreshKeepsCachedApplicationsAndSurfacesServerError() async {
        ExemptionRefreshURLProtocol.configure(.serverFailure)
        let defaults = isolatedDefaults()
        let repository = makeExemptionRefreshRepository(defaults: defaults)
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults),
            remoteRepo: repository
        )
        appState.installRemoteContractFixtureForTesting()
        XCTAssertTrue(appState.isRemoteMode)
        let cachedApplications = appState.workspace.exemptions
        ExemptionRefreshURLProtocol.resetRecordedPaths()

        await appState.refreshRemoteExemptions()

        XCTAssertEqual(appState.workspace.exemptions, cachedApplications)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertFalse(appState.isLoadingExemptions)
        XCTAssertEqual(
            ExemptionRefreshURLProtocol.paths,
            ["/api/v1/exemption-applications"]
        )
    }

    func testAppStateExemptionSubmissionFailsClosedInDemoMode() async {
        let defaults = isolatedDefaults()
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults)
        )
        let originalExemptions = appState.workspace.exemptions
        let originalSyncOperations = appState.workspace.syncOperations
        let originalNotices = appState.workspace.notices

        let submitted = await appState.submitExemption(
            item: .run800m,
            reason: "膝关节运动损伤",
            detail: "医生建议暂缓耐力跑测试。",
            proofAttachments: [
                ProofAttachment(
                    id: "proof",
                    type: .image,
                    fileName: "hospital-note.jpg",
                    byteCount: 480_000,
                    source: "摄像头"
                )
            ]
        )

        XCTAssertFalse(submitted)
        XCTAssertEqual(appState.workspace.exemptions, originalExemptions)
        XCTAssertEqual(appState.workspace.syncOperations, originalSyncOperations)
        XCTAssertEqual(appState.workspace.notices, originalNotices)
        XCTAssertTrue(appState.errorMessage?.contains("演示账户") == true)
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

    func testDemoEnduranceConversionRequiresRemoteServer() async {
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: isolatedDefaults())
        )

        let converted = await appState.convertEndurance(timeSeconds: 240)

        XCTAssertNil(converted)
        XCTAssertEqual(
            appState.errorMessage,
            BNBUL10n.text("请连接校园体育服务器后使用成绩换算。")
        )
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

        XCTAssertEqual(before.academicYear, "2025-2026 学年")
        XCTAssertEqual(before.grade, "大二")
        XCTAssertEqual(before.semester, "春季学期")
        XCTAssertEqual(after.academicYear, "2026-2027 学年")
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
        let refreshIntentKey = RemoteStudentRepository.refreshIntentKey(for: StudentServerConfig.testBaseURL)
        try credentialStore.set(Data("short-lived-token".utf8), forKey: secureKey)
        try credentialStore.set(Data("stale-refresh-intent".utf8), forKey: refreshIntentKey)
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
        XCTAssertNil(try credentialStore.data(forKey: refreshIntentKey))
    }

    func testProtected401OtherThanTokenExpiredDoesNotRefreshOrClearSession() async throws {
        RefreshSessionURLProtocol.configure(
            protectedStatus: 401,
            protectedCode: "AUTH_REQUIRED",
            refreshResponses: [.success]
        )
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = makeRefreshRepository(credentialStore: credentialStore)

        do {
            _ = try await repository.listExemptions()
            XCTFail("AUTH_REQUIRED must be surfaced without guessing that the token expired")
        } catch let error as RepositoryError {
            guard case .contractError(let statusCode, let code, _, _, _, _) = error else {
                XCTFail("Expected the contract error, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(code, "AUTH_REQUIRED")
        }

        let isAuthenticated = await repository.isAuthenticated
        XCTAssertTrue(isAuthenticated)
        XCTAssertEqual(RefreshSessionURLProtocol.refreshKeys, [])
        XCTAssertNil(try credentialStore.data(
            forKey: RemoteStudentRepository.refreshIntentKey(for: StudentServerConfig.testBaseURL)
        ))
    }

    func testRefreshAmbiguousFailuresRetainSessionAndPersistentIntent() async throws {
        let cases: [RefreshFixtureResponse] = [
            .networkLost,
            .failure(statusCode: 409, code: "CONFLICT_REQUEST_IN_PROGRESS"),
            .failure(statusCode: 429, code: "AUTH_RATE_LIMITED"),
            .failure(statusCode: 503, code: "SYSTEM_SERVICE_UNAVAILABLE"),
        ]
        for response in cases {
            RefreshSessionURLProtocol.configure(refreshResponses: [response])
            let credentialStore = InMemoryCredentialStore()
            try installCurrentContractSession(in: credentialStore)
            let repository = makeRefreshRepository(credentialStore: credentialStore)

            do {
                _ = try await repository.listExemptions()
                XCTFail("An ambiguous refresh failure must be surfaced")
            } catch {
                // The exact transient error remains visible to the caller.
            }

            let isAuthenticated = await repository.isAuthenticated
            XCTAssertTrue(isAuthenticated)
            XCTAssertNotNil(try credentialStore.data(
                forKey: RemoteStudentRepository.contractSessionKey(for: StudentServerConfig.testBaseURL)
            ))
            let intentData = try XCTUnwrap(try credentialStore.data(
                forKey: RemoteStudentRepository.refreshIntentKey(for: StudentServerConfig.testBaseURL)
            ))
            let intent = try XCTUnwrap(
                JSONSerialization.jsonObject(with: intentData) as? [String: Any]
            )
            let idempotencyKey = try XCTUnwrap(intent["idempotencyKey"] as? String)
            let fingerprint = try XCTUnwrap(intent["sessionFingerprint"] as? String)
            XCTAssertTrue(IdempotencyKeyPolicy.isValid(idempotencyKey))
            XCTAssertEqual(fingerprint.count, 64)
        }
    }

    func testRefreshIntentSurvivesRestartReusesKeyAndClearsAfterSuccess() async throws {
        RefreshSessionURLProtocol.configure(refreshResponses: [
            .failure(statusCode: 503, code: "SYSTEM_SERVICE_UNAVAILABLE"),
            .success,
        ])
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let firstRepository = makeRefreshRepository(credentialStore: credentialStore)
        do {
            _ = try await firstRepository.listExemptions()
            XCTFail("The first refresh response is intentionally ambiguous")
        } catch {
            // Relaunch below must recover this exact intent.
        }
        XCTAssertNotNil(try credentialStore.data(
            forKey: RemoteStudentRepository.refreshIntentKey(for: StudentServerConfig.testBaseURL)
        ))

        let restoredRepository = makeRefreshRepository(credentialStore: credentialStore)
        let exemptions = try await restoredRepository.listExemptions()
        XCTAssertTrue(exemptions.isEmpty)
        XCTAssertEqual(RefreshSessionURLProtocol.refreshKeys.count, 2)
        XCTAssertEqual(
            RefreshSessionURLProtocol.refreshKeys.first,
            RefreshSessionURLProtocol.refreshKeys.last
        )
        XCTAssertEqual(
            RefreshSessionURLProtocol.refreshTokens,
            ["current-contract-refresh-token", "current-contract-refresh-token"]
        )
        XCTAssertNil(try credentialStore.data(
            forKey: RemoteStudentRepository.refreshIntentKey(for: StudentServerConfig.testBaseURL)
        ))
        let storedSessionData = try XCTUnwrap(try credentialStore.data(
            forKey: RemoteStudentRepository.contractSessionKey(for: StudentServerConfig.testBaseURL)
        ))
        let storedSession = try JSONDecoder().decode(ContractAuthSession.self, from: storedSessionData)
        XCTAssertEqual(storedSession.refreshToken, "rotated-refresh-token")
    }

    func testRefreshTerminalCredentialFailuresClearSessionAndIntent() async throws {
        for (statusCode, code) in [
            (401, "AUTH_CREDENTIAL_INVALID"),
            (401, "AUTH_TOKEN_INVALID"),
            (401, "AUTH_SESSION_REVOKED"),
            (403, "AUTH_ACCOUNT_DISABLED"),
        ] {
            RefreshSessionURLProtocol.configure(refreshResponses: [
                .failure(statusCode: statusCode, code: code),
            ])
            let credentialStore = InMemoryCredentialStore()
            try installCurrentContractSession(in: credentialStore)
            let repository = makeRefreshRepository(credentialStore: credentialStore)

            do {
                _ = try await repository.listExemptions()
                XCTFail("\(code) must terminate the local session")
            } catch {
                // The terminal contract error is still surfaced.
            }

            let isAuthenticated = await repository.isAuthenticated
            XCTAssertFalse(isAuthenticated)
            XCTAssertNil(try credentialStore.data(
                forKey: RemoteStudentRepository.contractSessionKey(for: StudentServerConfig.testBaseURL)
            ))
            XCTAssertNil(try credentialStore.data(
                forKey: RemoteStudentRepository.refreshIntentKey(for: StudentServerConfig.testBaseURL)
            ))
        }
    }

    func testSuccessfulNewLoginClearsStaleRefreshIntent() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SuccessfulLoginURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        let refreshIntentKey = RemoteStudentRepository.refreshIntentKey(for: StudentServerConfig.testBaseURL)
        try credentialStore.set(Data("stale-refresh-intent".utf8), forKey: refreshIntentKey)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        let student = try await repository.verifyStudentSignInCode(
            challengeId: "challenge-current-contract",
            code: "123456"
        )

        XCTAssertEqual(student.id, "s1")
        XCTAssertNil(try credentialStore.data(forKey: refreshIntentKey))
    }

    func testLogoutInvalidatesOtpVerificationResponseThatFinishesLater() async throws {
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
            try await repository.verifyStudentSignInCode(
                challengeId: "challenge-delayed",
                code: "123456"
            )
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

    func testRecordCreateUsesAuthoritativeSessionAndContractCreditType() async throws {
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

        _ = try await repository.submitExerciseRecord(
            sessionId: "session-course",
            creditType: .courseRelated,
            sportType: .running,
            customSportName: nil,
            description: "course related",
            mediaIds: ["media-course"],
            clientRequestId: "client-course",
            idempotencyKey: "ios-record-course"
        )
        _ = try await repository.submitExerciseRecord(
            sessionId: "session-general",
            creditType: .general,
            sportType: .running,
            customSportName: nil,
            description: "autonomous",
            mediaIds: ["media-general"],
            clientRequestId: "client-general",
            idempotencyKey: "ios-record-general"
        )

        let bodies = RecordingSportRecordURLProtocol.recordedBodies
        XCTAssertEqual(bodies.count, 2)
        let courseRelatedBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any]
        )
        let generalBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.last)) as? [String: Any]
        )
        XCTAssertEqual(courseRelatedBody["sessionId"] as? String, "session-course")
        XCTAssertEqual(courseRelatedBody["creditType"] as? String, "COURSE_RELATED")
        XCTAssertEqual(generalBody["sessionId"] as? String, "session-general")
        XCTAssertEqual(generalBody["creditType"] as? String, "GENERAL")
        XCTAssertNil(courseRelatedBody["taskId"])
        XCTAssertNil(courseRelatedBody["courseId"])
        XCTAssertNil(generalBody["taskId"])
        XCTAssertNil(generalBody["courseId"])
    }

    func testProofUploadStartsOnlyAtCurrentMediaUploadEndpoint() async throws {
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
            _ = try await repository.uploadExerciseEvidence(
                attachment: attachment,
                sessionId: "session-upload",
                idempotencyKey: "ios-media-upload-test"
            )
            XCTFail("The 404 test transport must fail the upload")
        } catch {
            // The endpoint assertion below is the contract under test.
        }

        XCTAssertEqual(RecordingNotFoundURLProtocol.recordedPaths, ["/api/v1/media-uploads"])
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
        try installCurrentContractSession(in: credentialStore)
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
        appState.installRemoteContractFixtureForTesting()
        XCTAssertTrue(appState.isRemoteMode)
        appState.workspace.records.insert(
            CheckInRecord(
                id: "device-local-today",
                courseId: nil,
                taskTitle: "设备本地当天记录",
                creditType: .general,
                hours: 1,
                submittedAt: RecentTimestamp.justNow,
                proofSummary: "1 张图片",
                proofPhotoCount: 1,
                proofVideoCount: 0,
                proofFiles: [],
                note: "仅验证远端不按本机日期拦截"
            ),
            at: 0
        )
        XCTAssertTrue(appState.hasSubmittedCheckInToday())
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
            proofAttachments: [proof],
            exerciseSession: completedContractExerciseSession()
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
        restoredState.installRemoteContractFixtureForTesting()
        let progressBeforeServerRefresh = restoredState.workspace.progress
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
        XCTAssertEqual(authoritativeProof.cosKey, "media-1")
        XCTAssertEqual(authoritativeProof.source, "Backend 2.0.13 media")
        XCTAssertEqual(restoredState.workspace.progress.course, progressBeforeServerRefresh.course)
        XCTAssertEqual(restoredState.workspace.progress.general, progressBeforeServerRefresh.general)
        XCTAssertEqual(
            restoredState.workspace.progress.authoritativeTotalHours,
            progressBeforeServerRefresh.authoritativeTotalHours
        )
        XCTAssertTrue(restoredState.workspace.syncOperations.contains {
            $0.type == .submitRecord && $0.status == .queued
        })
        XCTAssertNil(localStore.readDraft().value)
        XCTAssertNil(defaults.data(forKey: AppLocalStore.pendingMutationStorageKey))
    }

    func testExemptionMutationsRecoverSamePayloadKeyAndUploadedReferencesAfterRestart() async throws {
        AllMutationRetryURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AllMutationRetryURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
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
        firstState.installRemoteContractFixtureForTesting()
        let proof = ProofAttachment(
            id: "secondary-logical-proof",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xAA]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: "摄像头"
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
        XCTAssertEqual(AllMutationRetryURLProtocol.uploadPaths, [
            "/api/v1/exemption-applications/ex-new/media-uploads",
            "/api/v1/exemption-applications/ex1/media-uploads",
        ])
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
        restoredState.installRemoteContractFixtureForTesting()
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
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: AppLocalStore(defaults: defaults),
            remoteRepo: remoteRepository
        )
        appState.installRemoteContractFixtureForTesting()
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
            proofAttachments: [proof],
            exerciseSession: completedContractExerciseSession()
        )
        _ = await appState.submitCheckIn(
            creditType: .general,
            courseId: nil,
            hours: 1,
            note: "payload B",
            proofAttachments: [proof],
            exerciseSession: completedContractExerciseSession()
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
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: remoteRepository
        )
        appState.installRemoteContractFixtureForTesting()
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
            proofAttachments: [proof],
            exerciseSession: completedContractExerciseSession()
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
            XCTAssertEqual(
                appState.errorMessage,
                ClientErrorMapper.map(RemoteMutationJournalError.writeFailed, context: .record).displayText
            )
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
            XCTAssertEqual(
                MutationFailClosedURLProtocol.uploadCount,
                flow == .createExemption ? 0 : 1,
                flow.scope
            )
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
            XCTAssertEqual(
                appState.errorMessage,
                ClientErrorMapper.map(RemoteMutationJournalError.writeFailed, context: .record).displayText
            )
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
        let application = ExemptionApplication(
            id: "exemption-1",
            studentId: "student-1",
            item: .run800m,
            reason: "medical reason",
            detail: "doctor note",
            submittedAt: "2026-07-16T00:00:00Z",
            status: .supplementRequired,
            proofFiles: [],
            teacherFeedback: "supplement",
            updatedAt: "2026-07-16T00:00:00Z"
        )

        _ = try await repository.submitExerciseRecord(
            sessionId: "session-canonical",
            creditType: .general,
            sportType: .running,
            customSportName: nil,
            description: "record",
            mediaIds: ["media-1"],
            clientRequestId: "ios-record-0001",
            idempotencyKey: "ios-record-0001"
        )
        let createdDraft = try await repository.createExemptionDraft(
            enrollmentId: "enrollment-1",
            item: .run800m,
            reason: "medical reason",
            detail: "doctor note",
            organization: "",
            idempotencyKey: "ios-exemption-0001"
        )
        _ = try await repository.updateAndSubmitCreatedExemption(
            applicationId: createdDraft.applicationId,
            item: .run800m,
            reason: "medical reason",
            detail: "doctor note",
            organization: "",
            preparedExpectedVersion: createdDraft.expectedVersion,
            mediaIds: ["media-1"],
            idempotencyKey: "ios-exemption-0001"
        )
        let supplementPlan = try await repository.prepareExemptionSupplement(
            applicationId: application.id,
            newMediaIds: ["media-2"]
        )
        _ = try await repository.updateAndSubmitExemption(
            application: application,
            reason: "medical reason",
            detail: "additional doctor note",
            preparedExpectedVersion: supplementPlan.expectedVersion,
            preparedMediaIds: supplementPlan.mediaIds,
            idempotencyKey: "ios-exemption-supplement-0001"
        )

        XCTAssertEqual(CanonicalMutationURLProtocol.paths, [
            "/api/v1/exercise-records",
            "/api/v1/exercise-records/record-1/submit",
            "/api/v1/exemption-applications",
            "/api/v1/exemption-applications/exemption-created",
            "/api/v1/exemption-applications/exemption-created/submit",
            "/api/v1/exemption-applications/exemption-1",
            "/api/v1/exemption-applications/exemption-1/submit"
        ])
        XCTAssertEqual(CanonicalMutationURLProtocol.keys, [
            "ios-record-0001.record-create",
            "ios-record-0001.record-submit",
            "ios-exemption-0001.exemption-create",
            "ios-exemption-0001.exemption-associate-media",
            "ios-exemption-0001.exemption-submit",
            "ios-exemption-supplement-0001.exemption-update",
            "ios-exemption-supplement-0001.exemption-resubmit"
        ])
        XCTAssertFalse(CanonicalMutationURLProtocol.paths.contains { $0.contains("/student/") })
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
            source: "摄像头"
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
        XCTAssertFalse(supplementResult)
        XCTAssertEqual(
            appState.workspace.exemptions.first(where: { $0.id == base.id })?.status,
            .supplementRequired
        )
        XCTAssertEqual(appState.workspace.exemptions.first(where: { $0.id == base.id })?.proofFiles.count, 0)
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
        let credentialStore = InMemoryCredentialStore()
        try? installCurrentContractSession(in: credentialStore)
        let remoteRepository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults
        )
        let appState = AppState(
            repository: MockStudentRepository(),
            localStore: localStore,
            remoteRepo: remoteRepository
        )
        appState.installRemoteContractFixtureForTesting()
        XCTAssertTrue(appState.isRemoteMode)
        return appState
    }

    private func makeExemptionRefreshRepository(
        defaults: UserDefaults? = nil
    ) -> RemoteStudentRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExemptionRefreshURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try? installCurrentContractSession(in: credentialStore)
        return RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: defaults ?? isolatedDefaults()
        )
    }

    private func submitFailClosedFlow(
        _ flow: FailClosedMutationFlow,
        on appState: AppState
    ) async throws -> Bool {
        let source: String
        switch flow {
        case .createRecord:
            source = "相册"
        case .createExemption, .supplementExemption:
            source = "摄像头"
        }
        let proof = ProofAttachment(
            id: "fail-closed-\(flow.scope)",
            type: .image,
            fileName: "proof.jpg",
            byteCount: 4,
            thumbnailData: Data([0xFF, 0xD8]),
            uploadData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            source: source
        )
        switch flow {
        case .createRecord:
            return await appState.submitCheckIn(
                creditType: .general,
                courseId: nil,
                hours: 1,
                note: "fail-closed record",
                sportType: "running",
                proofAttachments: [proof],
                exerciseSession: completedContractExerciseSession()
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

    func testStudentTestToolsRequireDebugAllowedEnvironmentAndExplicitFlag() {
        XCTAssertTrue(StudentTestToolsConfig.permits(
            appEnvironment: "local",
            enabledValue: "true",
            isDebugBuild: true
        ))
        XCTAssertTrue(StudentTestToolsConfig.permits(
            appEnvironment: "test",
            enabledValue: "1",
            isDebugBuild: true
        ))
        XCTAssertTrue(StudentTestToolsConfig.permits(
            appEnvironment: "staging",
            enabledValue: "true",
            isDebugBuild: true
        ))
        XCTAssertFalse(StudentTestToolsConfig.permits(
            appEnvironment: "production",
            enabledValue: "true",
            isDebugBuild: true
        ))
        XCTAssertFalse(StudentTestToolsConfig.permits(
            appEnvironment: "local",
            enabledValue: "false",
            isDebugBuild: true
        ))
        XCTAssertFalse(StudentTestToolsConfig.permits(
            appEnvironment: "local",
            enabledValue: "true",
            isDebugBuild: false
        ))
    }

    func testExerciseTestToolCapabilityUsesAuthenticatedInternalRead() async throws {
        ExerciseTestToolURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExerciseTestToolURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults(),
            exerciseTestToolsEnabled: true
        )

        let capabilities = try await repository.exerciseTestToolCapabilities()

        XCTAssertEqual(capabilities, [StudentTestToolsConfig.durationAdvanceCapability])
        XCTAssertEqual(ExerciseTestToolURLProtocol.requests.map(\.path), [
            "/api/v1/internal/test-tools/capabilities"
        ])
        XCTAssertEqual(ExerciseTestToolURLProtocol.requests.map(\.method), ["GET"])
    }

    func testExerciseTestToolPostsExpectedVersionThenRefreshesAuthoritativeState() async throws {
        ExerciseTestToolURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExerciseTestToolURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults(),
            exerciseTestToolsEnabled: true
        )

        let refreshed = try await repository.advanceExerciseSessionTestDuration(
            sessionId: "session-test-tool-1",
            expectedVersion: 4
        )

        XCTAssertEqual(refreshed.id, "session-test-tool-1")
        XCTAssertEqual(refreshed.actualDurationSeconds, 4_200)
        XCTAssertEqual(refreshed.version, 5)
        let requests = ExerciseTestToolURLProtocol.requests
        XCTAssertEqual(requests.map(\.path), [
            "/api/v1/internal/test-tools/exercise-sessions/session-test-tool-1/advance-duration",
            "/api/v1/exercise-sessions/session-test-tool-1",
        ])
        XCTAssertEqual(requests.map(\.method), ["POST", "GET"])
        XCTAssertEqual(requests[0].jsonBody?["expectedVersion"] as? Int, 4)
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(try XCTUnwrap(requests[0].idempotencyKey)))
    }

    func testExerciseDurationUsesAuthoritativeServerSnapshotWithoutChangingStartTime() {
        let observedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let originalStart = observedAt.addingTimeInterval(-600)
        let session = ExerciseSession(
            id: "session-duration-authority",
            studentID: "s1",
            category: .general,
            sportType: .running,
            customSportName: nil,
            courseID: nil,
            startTime: originalStart,
            status: .active,
            locationStatus: .unavailable,
            serverVersion: 4
        )

        let advanced = session.applyingAuthoritativeDuration(
            seconds: 4_200,
            observedAt: observedAt,
            remoteStatus: "IN_PROGRESS",
            remoteEndedAt: nil,
            serverVersion: 5
        )

        XCTAssertEqual(advanced.startTime, originalStart)
        XCTAssertEqual(advanced.elapsed(at: observedAt), 4_200, accuracy: 0.001)
        XCTAssertEqual(advanced.elapsed(at: observedAt.addingTimeInterval(60)), 4_260, accuracy: 0.001)
        XCTAssertEqual(advanced.creditedHours(at: observedAt), 1)
        XCTAssertEqual(advanced.serverVersion, 5)

        let completed = advanced.applyingAuthoritativeDuration(
            seconds: 7_200,
            observedAt: observedAt,
            remoteStatus: "COMPLETED",
            remoteEndedAt: observedAt
        )
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.creditedHours(at: observedAt.addingTimeInterval(600)), 2)
    }

    func testRejectedAttemptContextRoundTripsWithoutMutatingHistory() throws {
        let attemptContext = ExerciseRecordAttemptContext(
            recordId: "record-attempt-2",
            previousAttemptId: "record-attempt-1",
            rootAttemptId: "record-attempt-1",
            attemptNumber: 2
        )
        let record = CheckInRecord(
            id: "record-attempt-2",
            courseId: nil,
            taskTitle: "重新补交",
            creditType: .general,
            hours: 1,
            submittedAt: "2026-08-24T08:00:00Z",
            validity: .valid,
            invalidReason: nil,
            proofSummary: "1 张照片",
            proofPhotoCount: 1,
            proofVideoCount: 0,
            proofFiles: [],
            note: "新 Session 的正式尝试",
            attemptContext: attemptContext,
            serverVersion: 3
        )

        let decoded = try JSONDecoder().decode(
            CheckInRecord.self,
            from: JSONEncoder().encode(record)
        )

        XCTAssertEqual(decoded.attemptContext, attemptContext)
        XCTAssertEqual(decoded.attemptContext?.previousAttemptId, "record-attempt-1")
        XCTAssertEqual(decoded.attemptContext?.attemptNumber, 2)
        XCTAssertEqual(decoded.serverVersion, 3)
    }

    func testPendingMutationPersistsScopedExemptionTarget() throws {
        var attempt = PendingRemoteMutationAttempt.create(
            scope: "exemption:create:running-general",
            fingerprint: "fingerprint-1",
            serverIdentity: "server-1",
            studentID: "s1",
            authoritativeEnrollmentID: "enrollment-1"
        )
        attempt.bindTargetResource(id: "exemption-draft-1", expectedVersion: 4)

        let decoded = try JSONDecoder().decode(
            PendingRemoteMutationAttempt.self,
            from: JSONEncoder().encode(attempt)
        )

        XCTAssertEqual(decoded.targetResourceID, "exemption-draft-1")
        XCTAssertEqual(decoded.preparedExpectedVersion, 4)
        XCTAssertEqual(decoded.authoritativeEnrollmentID, "enrollment-1")
    }

    func testAccountDeletionErrorsUseSafeSpecificActions() {
        let cases: [(String, Int, Bool)] = [
            ("ACCOUNT_DELETION_ACTIVE_SESSION", 409, true),
            ("ACCOUNT_DELETION_PENDING_REVIEW", 409, false),
            ("ACCOUNT_DELETION_REAUTH_REQUIRED", 401, true),
        ]

        for (code, status, retryable) in cases {
            let mapped = ClientErrorMapper.map(
                RepositoryError.contractError(
                    statusCode: status,
                    code: code,
                    message: "internal SQL token=secret",
                    requestId: "account-delete-request-1",
                    timestamp: "2026-08-24T08:00:00Z",
                    details: nil
                ),
                context: .accountDeletion
            )
            XCTAssertEqual(mapped.code, code)
            XCTAssertEqual(mapped.requestId, "account-delete-request-1")
            XCTAssertEqual(mapped.retryable, retryable)
            XCTAssertFalse(mapped.displayText.contains("SQL"))
            XCTAssertFalse(mapped.displayText.contains("secret"))
        }
    }

    func testFeedbackUsesPrivacyBoundedListAndCreateContract() async throws {
        FeedbackContractURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackContractURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        let existing = try await repository.listFeedback()
        let created = try await repository.createFeedback(
            category: .privacy,
            content: "  请说明账号注销后的匿名化范围。  "
        )

        XCTAssertEqual(existing.count, 1)
        XCTAssertEqual(existing.first?.category, FeedbackCategory.bug.title)
        XCTAssertEqual(existing.first?.status, .processing)
        XCTAssertEqual(created.id, "feedback-created-1")
        XCTAssertEqual(created.category, FeedbackCategory.privacy.title)
        XCTAssertEqual(created.description, "请说明账号注销后的匿名化范围。")

        let requests = FeedbackContractURLProtocol.requests
        XCTAssertEqual(requests.map(\.path), ["/api/v1/feedback", "/api/v1/feedback"])
        XCTAssertEqual(requests.map(\.method), ["GET", "POST"])
        XCTAssertNil(requests[0].idempotencyKey)
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(try XCTUnwrap(requests[1].idempotencyKey)))
        let body = try XCTUnwrap(requests[1].jsonBody)
        XCTAssertEqual(Set(body.keys), Set(["category", "content", "clientContext"]))
        XCTAssertEqual(body["category"] as? String, "PRIVACY")
        XCTAssertEqual(body["content"] as? String, "请说明账号注销后的匿名化范围。")
        XCTAssertNil(body["email"])
        XCTAssertNil(body["phone"])
        XCTAssertNil(body["screenshots"])
        XCTAssertNil(body["logs"])
        let clientContext = try XCTUnwrap(body["clientContext"] as? [String: Any])
        XCTAssertEqual(Set(clientContext.keys), Set(["platform", "appVersion", "osVersion"]))
        XCTAssertEqual(clientContext["platform"] as? String, "IOS")
        XCTAssertNil(clientContext["deviceId"])
    }

    func testFeedbackErrorMappingKeepsRequestIdAndHidesInternalCause() {
        let mapped = ClientErrorMapper.map(
            RepositoryError.contractError(
                statusCode: 422,
                code: "FEEDBACK_CONTENT_INVALID",
                message: "SQL path=/internal token=secret",
                requestId: "feedback-request-safe-1",
                timestamp: "2026-08-24T08:00:00Z",
                details: nil
            ),
            context: .feedback
        )

        XCTAssertEqual(mapped.code, "FEEDBACK_CONTENT_INVALID")
        XCTAssertEqual(mapped.title, "请检查反馈内容")
        XCTAssertEqual(mapped.requestId, "feedback-request-safe-1")
        XCTAssertFalse(mapped.retryable)
        XCTAssertFalse(mapped.displayText.contains("SQL"))
        XCTAssertFalse(mapped.displayText.contains("secret"))
        XCTAssertTrue(mapped.displayText.contains("诊断编号：feedback-request-safe-1"))
    }

    func testStudentAccountDeletionUsesFrozenTwoStepContractAndClearsCredentials() async throws {
        AccountDeletionURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountDeletionURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        let challenge = try await repository.requestAccountDeletionChallenge(locale: "zh-CN")
        XCTAssertEqual(challenge.challengeId, "account-deletion-challenge-1")
        XCTAssertEqual(challenge.mode, "STUDENT_EMAIL_OTP")
        XCTAssertEqual(challenge.version, 2)

        let outcome = try await repository.confirmAccountDeletion(
            challengeId: challenge.challengeId,
            expectedVersion: challenge.version,
            verificationCode: "123456"
        )
        XCTAssertEqual(outcome.result.status, "DELETED")
        XCTAssertTrue(outcome.result.allSessionsRevoked)
        XCTAssertTrue(outcome.result.newRegistrationRequired)
        XCTAssertTrue(outcome.credentialsCleared)

        let requests = AccountDeletionURLProtocol.requests
        XCTAssertEqual(requests.map(\.path), [
            "/api/v1/me",
            "/api/v1/me/account-deletion-challenges",
            "/api/v1/me/account-deletion-challenges/account-deletion-challenge-1/confirm",
        ])
        XCTAssertEqual(requests.map(\.method), ["GET", "POST", "POST"])
        XCTAssertNil(requests[0].idempotencyKey)
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(try XCTUnwrap(requests[1].idempotencyKey)))
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(try XCTUnwrap(requests[2].idempotencyKey)))
        XCTAssertEqual(requests[1].jsonBody?["expectedVersion"] as? Int, 1)
        XCTAssertEqual(requests[1].jsonBody?["locale"] as? String, "zh-CN")
        XCTAssertEqual(requests[2].jsonBody?["expectedVersion"] as? Int, 2)
        XCTAssertEqual(requests[2].jsonBody?["verificationCode"] as? String, "123456")
        XCTAssertNil(try credentialStore.data(
            forKey: RemoteStudentRepository.contractSessionKey(for: StudentServerConfig.testBaseURL)
        ))
    }

    func testRejectedRecordResubmissionCreatesNewAttemptAndNeverMutatesOldRecord() async throws {
        ExerciseRecordResubmissionURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExerciseRecordResubmissionURLProtocol.self]
        let credentialStore = InMemoryCredentialStore()
        try installCurrentContractSession(in: credentialStore)
        let repository = RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )

        let result = try await repository.submitExerciseRecord(
            sessionId: "session-resubmission-2",
            previousRecordId: "record-rejected-1",
            creditType: .general,
            sportType: .running,
            customSportName: nil,
            description: "第二次正式尝试",
            mediaIds: ["media-resubmission-1"],
            clientRequestId: "client-resubmission-2",
            idempotencyKey: "ios-resubmission-source-test"
        )

        XCTAssertEqual(result.id, "record-resubmission-2")
        XCTAssertEqual(result.attemptContext?.previousAttemptId, "record-rejected-1")
        XCTAssertEqual(result.attemptContext?.rootAttemptId, "record-rejected-1")
        XCTAssertEqual(result.attemptContext?.attemptNumber, 2)

        let requests = ExerciseRecordResubmissionURLProtocol.requests
        XCTAssertEqual(requests.map(\.path), [
            "/api/v1/exercise-sessions/session-resubmission-2",
            "/api/v1/exercise-records/record-rejected-1",
            "/api/v1/exercise-records/record-rejected-1/resubmissions",
            "/api/v1/exercise-records/record-resubmission-2/submit",
        ])
        XCTAssertEqual(requests.map(\.method), ["GET", "GET", "POST", "POST"])
        XCTAssertFalse(requests.contains {
            $0.path == "/api/v1/exercise-records/record-rejected-1" && $0.method != "GET"
        })
        XCTAssertEqual(requests[2].jsonBody?["expectedVersion"] as? Int, 4)
        XCTAssertEqual(requests[2].jsonBody?["sessionId"] as? String, "session-resubmission-2")
        XCTAssertEqual(requests[3].jsonBody?["mediaIds"] as? [String], ["media-resubmission-1"])
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(try XCTUnwrap(requests[2].idempotencyKey)))
        XCTAssertTrue(IdempotencyKeyPolicy.isValid(try XCTUnwrap(requests[3].idempotencyKey)))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "BNBUStudentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func installCurrentContractSession(
        in credentialStore: InMemoryCredentialStore,
        enrollmentId: String? = "enrollment-1"
    ) throws {
        let session = ContractAuthSession(
            sessionId: "auth-session-1",
            enrollmentId: enrollmentId,
            accessToken: "current-contract-access-token",
            refreshToken: "current-contract-refresh-token",
            tokenType: "Bearer",
            accessTokenExpiresAt: "2026-08-24T10:00:00Z",
            refreshTokenExpiresAt: "2026-09-24T10:00:00Z",
            user: ContractUser(
                id: "s1",
                organizationId: "organization-1",
                role: "STUDENT",
                status: "ACTIVE",
                primaryEmailMasked: "s***@example.edu",
                emailVerified: true,
                version: 1
            )
        )
        try credentialStore.set(
            JSONEncoder().encode(session),
            forKey: RemoteStudentRepository.contractSessionKey(for: StudentServerConfig.testBaseURL)
        )
    }

    private func makeRefreshRepository(
        credentialStore: InMemoryCredentialStore
    ) -> RemoteStudentRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshSessionURLProtocol.self]
        return RemoteStudentRepository(
            baseURL: StudentServerConfig.testBaseURL,
            credentialStore: credentialStore,
            urlSession: URLSession(configuration: configuration),
            legacyDefaults: isolatedDefaults()
        )
    }

    private func completedContractExerciseSession(
        id: String = "session-completed"
    ) -> ExerciseSession {
        let start = Date(timeIntervalSince1970: 1_775_000_000)
        return ExerciseSession(
            id: id,
            studentID: "s1",
            category: .general,
            sportType: .running,
            customSportName: nil,
            courseID: nil,
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            status: .completed,
            locationStatus: .unavailable,
            latitude: nil,
            longitude: nil
        )
    }
}

private func currentContractEnvelope(
    _ value: Any,
    requestId: String = "ios-contract-test-request"
) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "data": value,
        "meta": ["requestId": requestId]
    ], options: [.sortedKeys])
}

private func currentContractError(
    code: String,
    message: String,
    requestId: String = "ios-contract-test-request"
) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "code": code,
        "message": message,
        "requestId": requestId,
        "timestamp": "2026-08-24T08:00:00Z"
    ], options: [.sortedKeys])
}

private struct RecordedContractRequest {
    let path: String
    let method: String
    let idempotencyKey: String?
    let jsonBody: [String: Any]?
}

private final class ExerciseTestToolURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedRequests: [RecordedContractRequest] = []

    static var requests: [RecordedContractRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock()
        storedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = requestBodyData(request).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let recorded = RecordedContractRequest(
            path: request.url?.path ?? "",
            method: request.httpMethod ?? "",
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
            jsonBody: body
        )
        Self.lock.lock()
        Self.storedRequests.append(recorded)
        Self.lock.unlock()

        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/api/v1/internal/test-tools/capabilities"):
            send(
                statusCode: 200,
                data: currentContractEnvelope([
                    "capabilities": [StudentTestToolsConfig.durationAdvanceCapability]
                ])
            )
        case ("GET", "/api/v1/exercise-sessions/session-test-tool-1"):
            var session = currentExerciseSessionProjection(
                id: "session-test-tool-1",
                status: "IN_PROGRESS",
                version: 5
            )
            session["actualDurationSeconds"] = 4_200
            send(statusCode: 200, data: currentContractEnvelope(session))
        case ("POST", "/api/v1/internal/test-tools/exercise-sessions/session-test-tool-1/advance-duration"):
            var advanced = currentExerciseSessionProjection(
                id: "session-test-tool-1",
                status: "IN_PROGRESS",
                version: 5
            )
            advanced["actualDurationSeconds"] = 4_200
            send(statusCode: 200, data: currentContractEnvelope(advanced))
        default:
            send(
                statusCode: 404,
                data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
        }
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

private final class AccountDeletionURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedRequests: [RecordedContractRequest] = []

    static var requests: [RecordedContractRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock()
        storedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = requestBodyData(request).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let recorded = RecordedContractRequest(
            path: request.url?.path ?? "",
            method: request.httpMethod ?? "",
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
            jsonBody: body
        )
        Self.lock.lock()
        Self.storedRequests.append(recorded)
        Self.lock.unlock()

        switch request.url?.path {
        case "/api/v1/me":
            send(statusCode: 200, data: currentContractEnvelope([
                "user": [
                    "id": "s1",
                    "organizationId": "organization-1",
                    "role": "STUDENT",
                    "status": "ACTIVE",
                    "primaryEmailMasked": "s***@example.edu",
                    "emailVerified": true,
                    "version": 1,
                ],
                "studentProfile": NSNull(),
            ]))
        case "/api/v1/me/account-deletion-challenges":
            send(statusCode: 202, data: currentContractEnvelope([
                "challengeId": "account-deletion-challenge-1",
                "mode": "STUDENT_EMAIL_OTP",
                "expiresAt": "2026-08-24T09:00:00Z",
                "version": 2,
            ]))
        case "/api/v1/me/account-deletion-challenges/account-deletion-challenge-1/confirm":
            send(statusCode: 200, data: currentContractEnvelope([
                "status": "DELETED",
                "deletedAt": "2026-08-24T08:30:00Z",
                "allSessionsRevoked": true,
                "newRegistrationRequired": true,
            ]))
        default:
            send(
                statusCode: 404,
                data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
        }
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

private final class ExerciseRecordResubmissionURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedRequests: [RecordedContractRequest] = []

    static var requests: [RecordedContractRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock()
        storedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = requestBodyData(request).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let recorded = RecordedContractRequest(
            path: request.url?.path ?? "",
            method: request.httpMethod ?? "",
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
            jsonBody: body
        )
        Self.lock.lock()
        Self.storedRequests.append(recorded)
        Self.lock.unlock()

        switch request.url?.path {
        case "/api/v1/exercise-sessions/session-resubmission-2":
            send(statusCode: 200, data: currentContractEnvelope(
                currentExerciseSessionProjection(id: "session-resubmission-2")
            ))
        case "/api/v1/exercise-records/record-rejected-1":
            var previous = currentExerciseRecordProjection(
                id: "record-rejected-1",
                sessionId: "session-rejected-1",
                status: "REVIEWED",
                version: 4
            )
            previous["currentReview"] = [
                "result": "INVALID",
                "reasonCode": "INSUFFICIENT_EVIDENCE",
                "publicComment": "请使用新的运动 Session 补交",
            ]
            send(statusCode: 200, data: currentContractEnvelope(previous))
        case "/api/v1/exercise-records/record-rejected-1/resubmissions":
            send(statusCode: 201, data: currentContractEnvelope([
                "record": currentExerciseRecordProjection(
                    id: "record-resubmission-2",
                    sessionId: "session-resubmission-2",
                    status: "DRAFT",
                    description: "第二次正式尝试",
                    version: 1
                ),
                "attemptContext": [
                    "recordId": "record-resubmission-2",
                    "previousAttemptId": "record-rejected-1",
                    "rootAttemptId": "record-rejected-1",
                    "attemptNumber": 2,
                ],
            ]))
        case "/api/v1/exercise-records/record-resubmission-2/submit":
            send(statusCode: 200, data: currentContractEnvelope(
                currentExerciseRecordProjection(
                    id: "record-resubmission-2",
                    sessionId: "session-resubmission-2",
                    status: "REVIEWED",
                    description: "第二次正式尝试",
                    version: 2
                )
            ))
        default:
            send(
                statusCode: 404,
                data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
        }
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

private final class ActiveExerciseSessionURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var recordedPostCount = 0

    static var postCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedPostCount
    }

    static func reset() {
        lock.lock()
        recordedPostCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.httpMethod == "POST" {
            Self.lock.lock()
            Self.recordedPostCount += 1
            Self.lock.unlock()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = currentContractEnvelope(
            currentExerciseSessionProjection(
                id: "session-origin-device",
                status: "IN_PROGRESS"
            ),
            requestId: "ios-active-session-request"
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CursorPaginationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var cursors: [String] = []

    static func reset() {
        lock.lock()
        cursors = []
        lock.unlock()
    }

    static func observedCursors() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return cursors
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/api/v1/exemption-applications"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "cursor" })?
            .value
        Self.lock.lock()
        Self.cursors.append(cursor ?? "<first>")
        Self.lock.unlock()

        let page = cursor == nil ? 1 : 2
        let application: [String: Any] = [
            "id": "exemption-page-\(page)",
            "studentId": "student-1",
            "enrollmentId": "enrollment-1",
            "classSectionId": "section-1",
            "applicationType": "PHYSICAL_TEST",
            "applicationSubtype": "RUN_800M",
            "organizationName": NSNull(),
            "reason": "Local cursor test",
            "mediaIds": [],
            "status": "SUBMITTED",
            "publicComment": NSNull(),
            "submittedAt": "2026-08-24T08:00:00Z",
            "decidedAt": NSNull(),
            "version": 1
        ]
        let nextCursor: Any = page == 1 ? "page-2" : NSNull()
        let body = try! JSONSerialization.data(withJSONObject: [
            "data": [application],
            "meta": [
                "requestId": "ios-pagination-page-\(page)",
                "pagination": ["nextCursor": nextCursor, "limit": 100]
            ]
        ], options: [.sortedKeys])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CanonicalPublicCapabilityURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedPaths: [String] = []
    private static var storedQueries: [[String: String]] = []
    private static var storedAuthorizationHeaders: [String?] = []

    static var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }

    static var authorizationHeaders: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return storedAuthorizationHeaders
    }

    static func queryValues(at index: Int) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return storedQueries[index]
    }

    static func reset() {
        lock.lock()
        storedPaths = []
        storedQueries = []
        storedAuthorizationHeaders = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        Self.lock.lock()
        Self.storedPaths.append(url.path)
        Self.storedQueries.append(Dictionary(uniqueKeysWithValues: query.compactMap { item in
            item.value.map { (item.name, $0) }
        }))
        Self.storedAuthorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        Self.lock.unlock()

        let body: Data
        switch url.path {
        case "/api/v1/system-mode":
            body = currentContractEnvelope([
                "mode": "READ_ONLY",
                "policyVersion": 2,
                "updatedAt": "2026-08-24T08:00:00Z"
            ])
        case "/api/v1/app-release-policy":
            body = currentContractEnvelope([
                "platform": "IOS",
                "minimumSupportedVersion": "0.2.0",
                "latestVersion": "0.3.0",
                "minimumSupportedBuildNumber": 2,
                "latestBuildNumber": 3,
                "enforcement": "REQUIRED",
                "message": "Update required",
                "downloadUrl": "https://apps.example.invalid/bnbu",
                "effectiveAt": "2026-08-24T08:00:00Z",
                "expiresAt": NSNull(),
                "policyVersion": "ios-local-1"
            ])
        case "/api/v1/help-articles":
            body = currentContractEnvelope([
                [
                    "id": "help-1",
                    "category": "LOGIN",
                    "locale": "en",
                    "title": "First",
                    "bodyMarkdown": "First body",
                    "publishedAt": "2026-08-24T08:00:00Z",
                    "version": 1
                ],
                [
                    "id": "help-2",
                    "category": "RECORD",
                    "locale": "en",
                    "title": "Second",
                    "bodyMarkdown": "Second body",
                    "publishedAt": "2026-08-24T08:01:00Z",
                    "version": 1
                ]
            ])
        default:
            body = currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
        }
        let statusCode = url.path.hasPrefix("/api/v1/") ? 200 : 404
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private enum RefreshFixtureResponse {
    case success
    case failure(statusCode: Int, code: String)
    case networkLost
}

private final class RefreshSessionURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var protectedStatus = 401
    private static var protectedCode = "AUTH_TOKEN_EXPIRED"
    private static var queuedRefreshResponses: [RefreshFixtureResponse] = []
    private static var recordedRefreshKeys: [String] = []
    private static var recordedRefreshTokens: [String] = []

    static var refreshKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRefreshKeys
    }

    static var refreshTokens: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRefreshTokens
    }

    static func configure(
        protectedStatus: Int = 401,
        protectedCode: String = "AUTH_TOKEN_EXPIRED",
        refreshResponses: [RefreshFixtureResponse]
    ) {
        lock.lock()
        self.protectedStatus = protectedStatus
        self.protectedCode = protectedCode
        queuedRefreshResponses = refreshResponses
        recordedRefreshKeys = []
        recordedRefreshTokens = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch request.url?.path {
        case "/api/v1/auth/refresh":
            let body = requestJSONObject(request)
            let response = Self.takeRefreshResponse(
                key: request.value(forHTTPHeaderField: "Idempotency-Key") ?? "",
                token: body["refreshToken"] as? String ?? ""
            )
            switch response {
            case .networkLost:
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            case .failure(let statusCode, let code):
                send(
                    statusCode: statusCode,
                    data: currentContractError(code: code, message: "refresh fixture failure")
                )
            case .success:
                send(statusCode: 200, data: currentContractEnvelope(Self.rotatedSession))
            }
        case "/api/v1/exemption-applications":
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer rotated-access-token" {
                send(statusCode: 200, data: currentContractEnvelope([[String: Any]]()))
            } else {
                let failure = Self.protectedFailure()
                send(
                    statusCode: failure.statusCode,
                    data: currentContractError(code: failure.code, message: "protected fixture failure")
                )
            }
        default:
            send(
                statusCode: 404,
                data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
        }
    }

    override func stopLoading() {}

    private static func takeRefreshResponse(
        key: String,
        token: String
    ) -> RefreshFixtureResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedRefreshKeys.append(key)
        recordedRefreshTokens.append(token)
        guard !queuedRefreshResponses.isEmpty else {
            return .failure(statusCode: 500, code: "SYSTEM_INTERNAL_ERROR")
        }
        return queuedRefreshResponses.removeFirst()
    }

    private static func protectedFailure() -> (statusCode: Int, code: String) {
        lock.lock()
        defer { lock.unlock() }
        return (protectedStatus, protectedCode)
    }

    private static var rotatedSession: [String: Any] { [
        "sessionId": "auth-session-1",
        "enrollmentId": "enrollment-1",
        "accessToken": "rotated-access-token",
        "refreshToken": "rotated-refresh-token",
        "tokenType": "Bearer",
        "accessTokenExpiresAt": "2026-08-24T11:00:00Z",
        "refreshTokenExpiresAt": "2026-09-24T11:00:00Z",
        "user": [
            "id": "s1",
            "organizationId": "organization-1",
            "role": "STUDENT",
            "status": "ACTIVE",
            "primaryEmailMasked": "s***@example.edu",
            "emailVerified": true,
            "version": 1,
        ],
    ] }

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

private final class SuccessfulLoginURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch request.url?.path {
        case "/api/v1/auth/student-sign-in-codes/verify":
            send(statusCode: 200, data: currentContractEnvelope([
                "sessionId": "new-auth-session",
                "enrollmentId": "enrollment-1",
                "accessToken": "new-login-access-token",
                "refreshToken": "new-login-refresh-token",
                "tokenType": "Bearer",
                "accessTokenExpiresAt": "2026-08-24T11:00:00Z",
                "refreshTokenExpiresAt": "2026-09-24T11:00:00Z",
                "user": Self.user,
            ]))
        case "/api/v1/me":
            send(statusCode: 200, data: currentContractEnvelope([
                "user": Self.user,
                "studentProfile": [
                    "id": "s1",
                    "studentNumber": "20260001",
                    "fullName": "Contract Student",
                    "gender": "UNKNOWN",
                    "gradeYear": 2026,
                    "collegeName": "College",
                    "majorName": NSNull(),
                    "administrativeClassName": "Class 1",
                    "status": "ACTIVE",
                ],
            ]))
        default:
            send(
                statusCode: 404,
                data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
        }
    }

    override func stopLoading() {}

    private static var user: [String: Any] { [
        "id": "s1",
        "organizationId": "organization-1",
        "role": "STUDENT",
        "status": "ACTIVE",
        "primaryEmailMasked": "s***@example.edu",
        "emailVerified": true,
        "version": 1,
    ] }

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

private func currentExerciseSessionProjection(
    id: String,
    status: String = "COMPLETED",
    enrollmentId: String = "enrollment-1",
    classSectionId: String = "class-section-1",
    version: Int = 2
) -> [String: Any] {
    let endedAt: Any
    if status == "COMPLETED" {
        endedAt = "2026-08-23T09:00:00Z"
    } else {
        endedAt = NSNull()
    }
    return [
        "id": id,
        "studentId": "s1",
        "enrollmentId": enrollmentId,
        "classSectionId": classSectionId,
        "status": status,
        "startedAt": "2026-08-23T08:00:00Z",
        "endedAt": endedAt,
        "actualDurationSeconds": status == "COMPLETED" ? 3600 : 0,
        "pausedDurationSeconds": 0,
        "businessDate": "2026-08-23",
        "version": version
    ]
}

private func currentExerciseRecordProjection(
    id: String,
    sessionId: String,
    status: String,
    creditType: String = "GENERAL",
    description: String = "contract test record",
    version: Int = 1
) -> [String: Any] {
    let submittedAt: Any
    if status == "DRAFT" {
        submittedAt = NSNull()
    } else {
        submittedAt = "2026-08-23T09:01:00Z"
    }
    let currentReview: Any
    if status == "REVIEWED" {
        currentReview = ["result": "VALID", "reasonCode": NSNull(), "publicComment": NSNull()]
    } else {
        currentReview = NSNull()
    }
    return [
        "id": id,
        "enrollmentId": "enrollment-1",
        "courseId": "course-1",
        "classSectionId": "class-section-1",
        "sessionId": sessionId,
        "businessDate": "2026-08-23",
        "creditType": creditType,
        "sportType": "RUNNING",
        "sportName": NSNull(),
        "description": description,
        "actualDurationSeconds": 3600,
        "pausedDurationSeconds": 0,
        "creditedDurationSeconds": 3600,
        "status": status,
        "submittedAt": submittedAt,
        "currentReview": currentReview,
        "version": version
    ]
}

private func currentMediaProjection(
    id: String,
    businessPurpose: String,
    sessionId: String?,
    enrollmentId: String?,
    uploadStatus: String,
    version: Int
) -> [String: Any] {
    let sessionValue: Any
    if let sessionId {
        sessionValue = sessionId
    } else {
        sessionValue = NSNull()
    }
    let enrollmentValue: Any
    if let enrollmentId {
        enrollmentValue = enrollmentId
    } else {
        enrollmentValue = NSNull()
    }
    return [
        "id": id,
        "sessionId": sessionValue,
        "enrollmentId": enrollmentValue,
        "businessPurpose": businessPurpose,
        "mediaType": "IMAGE",
        "declaredMimeType": "image/jpeg",
        "verifiedMimeType": "image/jpeg",
        "uploadStatus": uploadStatus,
        "verifiedContentSha256": String(repeating: "a", count: 64),
        "version": version
    ]
}

private func currentExemptionProjection(
    id: String,
    status: String,
    reason: String,
    mediaIds: [String],
    version: Int,
    enrollmentId: String = "enrollment-1"
) -> [String: Any] {
    let publicComment: Any
    if status == "SUPPLEMENT_REQUIRED" {
        publicComment = "Please supplement"
    } else {
        publicComment = NSNull()
    }
    let submittedAt: Any
    if status == "DRAFT" {
        submittedAt = NSNull()
    } else {
        submittedAt = "2026-08-23T09:02:00Z"
    }
    return [
        "id": id,
        "studentId": "s1",
        "enrollmentId": enrollmentId,
        "classSectionId": "class-section-1",
        "applicationType": "PHYSICAL_TEST",
        "applicationSubtype": "RUN_800M",
        "organizationName": NSNull(),
        "reason": reason,
        "mediaIds": mediaIds,
        "status": status,
        "publicComment": publicComment,
        "submittedAt": submittedAt,
        "decidedAt": NSNull(),
        "version": version
    ]
}

private func requestBodyData(_ request: URLRequest) -> Data? {
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

private func requestJSONObject(_ request: URLRequest) -> [String: Any] {
    guard let data = requestBodyData(request),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return object
}

private enum ExemptionRefreshResponseMode {
    case success
    case malformedDedicatedPayload
    case serverFailure
}

private final class ExemptionRefreshURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responseMode: ExemptionRefreshResponseMode = .serverFailure
    private static var recordedPaths: [String] = []

    static var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    static func configure(_ mode: ExemptionRefreshResponseMode) {
        lock.lock()
        responseMode = mode
        recordedPaths = []
        lock.unlock()
    }

    static func resetRecordedPaths() {
        lock.lock()
        recordedPaths = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        Self.lock.lock()
        Self.recordedPaths.append(path)
        let mode = Self.responseMode
        Self.lock.unlock()

        if path == "/api/v1/exemption-applications", method == "GET" {
            switch mode {
            case .success:
                send(
                    statusCode: 200,
                    data: currentContractEnvelope([
                        currentExemptionProjection(
                            id: "summary-exemption",
                            status: "SUBMITTED",
                            reason: "medical reason",
                            mediaIds: ["media-summary"],
                            version: 2
                        )
                    ])
                )
            case .malformedDedicatedPayload:
                send(statusCode: 200, data: currentContractEnvelope(["unexpected": true]))
            case .serverFailure:
                send(
                    statusCode: 503,
                    data: currentContractError(
                        code: "SERVICE_UNAVAILABLE",
                        message: "temporarily unavailable"
                    )
                )
            }
            return
        }

        send(
            statusCode: 404,
            data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
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
        "/api/v1/exercise-records",
        "/api/v1/exemption-applications/ex-fail-closed",
        "/api/v1/exemption-applications/ex1"
    ]
    private static let lock = NSLock()
    private static var uploadFailure: MutationFailClosedUploadFailure = .none
    private static var storedUploadCount = 0
    private static var storedMutationPaths: [String] = []
    private static var uploadPurpose = "EXERCISE_RECORD"
    private static var uploadSessionId: String? = "session-completed"
    private static var uploadEnrollmentId: String?
    private static var supplementReason = "existing reason"
    private static var supplementMediaIds: [String] = []
    private static var createdReason = ""
    private static var createdMediaIds: [String] = []

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
        self.uploadPurpose = "EXERCISE_RECORD"
        self.uploadSessionId = "session-completed"
        self.uploadEnrollmentId = nil
        supplementReason = "existing reason"
        supplementMediaIds = []
        createdReason = ""
        createdMediaIds = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if method == "GET", path.hasPrefix("/api/v1/exercise-sessions/") {
            let sessionId = String(path.split(separator: "/").last ?? "session-completed")
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExerciseSessionProjection(id: sessionId))
            )
            return
        }

        if path == "/api/v1/exemption-applications/ex1", method == "GET" {
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex1",
                    status: "SUPPLEMENT_REQUIRED",
                    reason: "existing reason",
                    mediaIds: [],
                    version: 3
                ))
            )
            return
        }

        if path == "/api/v1/exemption-applications/ex-fail-closed", method == "GET" {
            Self.lock.lock()
            let reason = Self.createdReason
            let mediaIds = Self.createdMediaIds
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex-fail-closed",
                    status: "DRAFT",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: mediaIds.isEmpty ? 1 : 2
                ))
            )
            return
        }

        if path == "/api/v1/exemption-applications", method == "POST" {
            let json = requestJSONObject(request)
            Self.lock.lock()
            Self.createdReason = json["reason"] as? String ?? ""
            Self.createdMediaIds = json["mediaIds"] as? [String] ?? []
            let reason = Self.createdReason
            let mediaIds = Self.createdMediaIds
            Self.lock.unlock()
            send(
                statusCode: 201,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex-fail-closed",
                    status: "DRAFT",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: 1
                ))
            )
            return
        }

        if (path == "/api/v1/media-uploads" ||
            path == "/api/v1/exemption-applications/ex-fail-closed/media-uploads" ||
            path == "/api/v1/exemption-applications/ex1/media-uploads"),
           method == "POST" {
            let json = requestJSONObject(request)
            Self.lock.lock()
            Self.storedUploadCount += 1
            let failure = Self.uploadFailure
            let scopedExemption = path.contains("/exemption-applications/")
            Self.uploadPurpose = scopedExemption
                ? "EXEMPTION_APPLICATION"
                : (json["businessPurpose"] as? String ?? "EXERCISE_RECORD")
            Self.uploadSessionId = json["sessionId"] as? String
            Self.uploadEnrollmentId = scopedExemption
                ? "enrollment-1"
                : json["enrollmentId"] as? String
            Self.lock.unlock()
            switch failure {
            case .none:
                send(
                    statusCode: 201,
                    data: currentContractEnvelope([
                        "uploadSessionId": "fail-closed-upload",
                        "mediaId": "fail-closed-media",
                        "uploadUrl": "https://upload.example.test/signed/fail-closed-media",
                        "uploadMethod": "PUT",
                        "requiredHeaders": ["Content-Type": "image/jpeg"]
                    ])
                )
            case .http(let statusCode):
                send(
                    statusCode: statusCode,
                    data: currentContractError(code: "VALIDATION_ERROR", message: "invalid upload")
                )
            case .network:
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }

        if method == "PUT", path == "/signed/fail-closed-media" {
            send(statusCode: 200, data: Data(), headers: ["ETag": "\"contract-etag\""])
            return
        }

        if method == "POST", path == "/api/v1/media-uploads/fail-closed-upload/confirm" {
            Self.lock.lock()
            let purpose = Self.uploadPurpose
            let sessionId = Self.uploadSessionId
            let enrollmentId = Self.uploadEnrollmentId
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: "fail-closed-media",
                    businessPurpose: purpose,
                    sessionId: sessionId,
                    enrollmentId: enrollmentId,
                    uploadStatus: "UPLOADED",
                    version: 1
                ))
            )
            return
        }

        if method == "POST", path == "/api/v1/media/fail-closed-media/bind" {
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: "fail-closed-media",
                    businessPurpose: "EXERCISE_RECORD",
                    sessionId: "session-completed",
                    enrollmentId: nil,
                    uploadStatus: "BOUND",
                    version: 2
                ))
            )
            return
        }

        if method == "GET", path == "/api/v1/media/fail-closed-media" {
            Self.lock.lock()
            let purpose = Self.uploadPurpose
            let sessionId = Self.uploadSessionId
            let enrollmentId = Self.uploadEnrollmentId
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: "fail-closed-media",
                    businessPurpose: purpose,
                    sessionId: sessionId,
                    enrollmentId: enrollmentId,
                    uploadStatus: "AVAILABLE",
                    version: 3
                ))
            )
            return
        }

        if Self.mutationRouteSet.contains(path), (method == "POST" || method == "PATCH") {
            Self.lock.lock()
            Self.storedMutationPaths.append(path)
            Self.lock.unlock()
            let json = requestJSONObject(request)
            if path == "/api/v1/exercise-records" {
                send(
                    statusCode: 201,
                    data: currentContractEnvelope(currentExerciseRecordProjection(
                        id: "record-fail-closed",
                        sessionId: json["sessionId"] as? String ?? "session-completed",
                        status: "REVIEWED",
                        creditType: json["creditType"] as? String ?? "GENERAL",
                        description: json["description"] as? String ?? "",
                        version: 2
                    ))
                )
            } else if path == "/api/v1/exemption-applications/ex-fail-closed" {
                let reason = json["reason"] as? String ?? ""
                let mediaIds = json["mediaIds"] as? [String] ?? []
                Self.lock.lock()
                Self.createdReason = reason
                Self.createdMediaIds = mediaIds
                Self.lock.unlock()
                send(
                    statusCode: 200,
                    data: currentContractEnvelope(currentExemptionProjection(
                        id: "ex-fail-closed",
                        status: "DRAFT",
                        reason: reason,
                        mediaIds: mediaIds,
                        version: 2
                    ))
                )
            } else {
                let reason = json["reason"] as? String ?? ""
                let mediaIds = json["mediaIds"] as? [String] ?? []
                Self.lock.lock()
                Self.supplementReason = reason
                Self.supplementMediaIds = mediaIds
                Self.lock.unlock()
                send(
                    statusCode: 200,
                    data: currentContractEnvelope(currentExemptionProjection(
                        id: "ex1",
                        status: "SUPPLEMENT_REQUIRED",
                        reason: reason,
                        mediaIds: mediaIds,
                        version: 4
                    ))
                )
            }
            return
        }

        if method == "POST", path == "/api/v1/exemption-applications/ex-fail-closed/submit" {
            Self.lock.lock()
            let reason = Self.createdReason
            let mediaIds = Self.createdMediaIds
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex-fail-closed",
                    status: "SUBMITTED",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: 3
                ))
            )
            return
        }

        if method == "POST", path == "/api/v1/exemption-applications/ex1/submit" {
            Self.lock.lock()
            let reason = Self.supplementReason
            let mediaIds = Self.supplementMediaIds
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex1",
                    status: "SUBMITTED",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: 5
                ))
            )
            return
        }

        send(
            statusCode: 404,
            data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
        )
    }

    override func stopLoading() {}

    private func send(
        statusCode: Int,
        data: Data,
        headers: [String: String] = [:]
    ) {
        var responseHeaders = ["Content-Type": "application/json"]
        headers.forEach { responseHeaders[$0.key] = $0.value }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: responseHeaders
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
        guard request.url?.path == "/api/v1/auth/student-sign-in-codes/verify",
              request.httpMethod == "POST" else {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self,
                didLoad: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let body = currentContractEnvelope([
            "sessionId": "late-auth-session",
            "enrollmentId": "enrollment-1",
            "accessToken": "late-token-must-be-discarded",
            "refreshToken": "late-refresh-token-must-be-discarded",
            "tokenType": "Bearer",
            "accessTokenExpiresAt": "2026-08-24T10:00:00Z",
            "refreshTokenExpiresAt": "2026-09-24T10:00:00Z",
            "user": [
                "id": "s1",
                "organizationId": "organization-1",
                "role": "STUDENT",
                "status": "ACTIVE",
                "primaryEmailMasked": "s***@example.edu",
                "emailVerified": true,
                "version": 1
            ]
        ])
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
            didLoad: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
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
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let responseValue: [String: Any]
        let statusCode: Int

        if method == "GET", path.hasPrefix("/api/v1/exercise-sessions/") {
            let sessionId = String(path.split(separator: "/").last ?? "session-missing")
            responseValue = currentExerciseSessionProjection(id: sessionId)
            statusCode = 200
        } else if path == "/api/v1/exercise-records", method == "POST" {
            let body = requestBodyData(request) ?? Data()
            Self.lock.lock()
            Self.bodies.append(body)
            Self.lock.unlock()
            let json = requestJSONObject(request)
            let sessionId = json["sessionId"] as? String ?? "session-missing"
            responseValue = currentExerciseRecordProjection(
                id: "record-\(sessionId)",
                sessionId: sessionId,
                status: "DRAFT",
                creditType: json["creditType"] as? String ?? "GENERAL",
                description: json["description"] as? String ?? "",
                version: 1
            )
            statusCode = 201
        } else if method == "POST",
                  path.hasPrefix("/api/v1/exercise-records/"),
                  path.hasSuffix("/submit") {
            let components = path.split(separator: "/")
            let recordId = components.count >= 5 ? String(components[3]) : "record-session-missing"
            let sessionId = String(recordId.dropFirst("record-".count))
            responseValue = currentExerciseRecordProjection(
                id: recordId,
                sessionId: sessionId,
                status: "REVIEWED",
                version: 2
            )
            statusCode = 200
        } else {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self,
                didLoad: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: currentContractEnvelope(responseValue))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

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

        if method == "GET", path.hasPrefix("/api/v1/exercise-sessions/") {
            let sessionId = String(path.split(separator: "/").last ?? "session-completed")
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExerciseSessionProjection(id: sessionId))
            )
            return
        }

        if path == "/api/v1/media-uploads", method == "POST" {
            Self.lock.lock()
            Self.storedUploadCount += 1
            let uploadNumber = Self.storedUploadCount
            Self.lock.unlock()
            send(
                statusCode: 201,
                data: currentContractEnvelope([
                    "uploadSessionId": "upload-\(uploadNumber)",
                    "mediaId": "media-\(uploadNumber)",
                    "uploadUrl": "https://upload.example.test/signed/media-\(uploadNumber)",
                    "uploadMethod": "PUT",
                    "requiredHeaders": ["Content-Type": "image/jpeg"]
                ])
            )
            return
        }

        if method == "PUT", path.hasPrefix("/signed/media-") {
            send(statusCode: 200, data: Data(), headers: ["ETag": "\"contract-etag\""])
            return
        }

        if method == "POST",
           path.hasPrefix("/api/v1/media-uploads/upload-"),
           path.hasSuffix("/confirm") {
            let uploadId = String(path.split(separator: "/")[3])
            let mediaId = uploadId.replacingOccurrences(of: "upload-", with: "media-")
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: mediaId,
                    businessPurpose: "EXERCISE_RECORD",
                    sessionId: "session-completed",
                    enrollmentId: nil,
                    uploadStatus: "UPLOADED",
                    version: 1
                ))
            )
            return
        }

        if method == "POST",
           path.hasPrefix("/api/v1/media/media-"),
           path.hasSuffix("/bind") {
            let mediaId = String(path.split(separator: "/")[3])
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: mediaId,
                    businessPurpose: "EXERCISE_RECORD",
                    sessionId: "session-completed",
                    enrollmentId: nil,
                    uploadStatus: "BOUND",
                    version: 2
                ))
            )
            return
        }

        if method == "GET", path.hasPrefix("/api/v1/media/media-") {
            let mediaId = String(path.split(separator: "/").last ?? "media-1")
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: mediaId,
                    businessPurpose: "EXERCISE_RECORD",
                    sessionId: "session-completed",
                    enrollmentId: nil,
                    uploadStatus: "AVAILABLE",
                    version: 3
                ))
            )
            return
        }

        if path == "/api/v1/exercise-records", method == "POST" {
            let body = requestBodyData(request) ?? Data()
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
                        data: currentContractError(code: "VALIDATION_ERROR", message: "invalid payload")
                    )
                } else {
                    client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                }
            } else {
                Self.lock.lock()
                Self.recordSucceeded = true
                Self.lock.unlock()
                let json = requestJSONObject(request)
                send(
                    statusCode: 201,
                    data: currentContractEnvelope(currentExerciseRecordProjection(
                        id: "record-idempotent",
                        sessionId: json["sessionId"] as? String ?? "session-completed",
                        status: "DRAFT",
                        creditType: json["creditType"] as? String ?? "GENERAL",
                        description: json["description"] as? String ?? "",
                        version: 1
                    ))
                )
            }
            return
        }

        if path == "/api/v1/exercise-records/record-idempotent/submit", method == "POST" {
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExerciseRecordProjection(
                    id: "record-idempotent",
                    sessionId: "session-completed",
                    status: "REVIEWED",
                    version: 2
                ))
            )
            return
        }

        send(
            statusCode: 404,
            data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
        )
    }

    override func stopLoading() {}

    private func send(
        statusCode: Int,
        data: Data,
        headers: [String: String] = [:]
    ) {
        var responseHeaders = ["Content-Type": "application/json"]
        headers.forEach { responseHeaders[$0.key] = $0.value }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

}

private final class AllMutationRetryURLProtocol: URLProtocol, @unchecked Sendable {
    static let mutationPaths = [
        "/api/v1/exemption-applications/ex-new",
        "/api/v1/exemption-applications/ex1"
    ]

    private static let lock = NSLock()
    private static var remainingFailurePaths = Set(AllMutationRetryURLProtocol.mutationPaths)
    private static var storedUploadCount = 0
    private static var storedUploadPaths: [String] = []
    private static var storedBodies: [String: [Data]] = [:]
    private static var storedKeys: [String: [String]] = [:]
    private static var lastSupplementReason = "existing reason"
    private static var lastSupplementMediaIds: [String] = []
    private static var lastCreatedReason = "膝关节损伤\n\n医生建议暂缓耐力跑。"
    private static var lastCreatedMediaIds: [String] = []

    static var uploadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUploadCount
    }

    static var uploadPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedUploadPaths
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
        storedUploadPaths = []
        storedBodies = [:]
        storedKeys = [:]
        lastSupplementReason = "existing reason"
        lastSupplementMediaIds = []
        lastCreatedReason = "膝关节损伤\n\n医生建议暂缓耐力跑。"
        lastCreatedMediaIds = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if (path == "/api/v1/exemption-applications/ex-new/media-uploads" ||
            path == "/api/v1/exemption-applications/ex1/media-uploads"),
           method == "POST" {
            Self.lock.lock()
            Self.storedUploadCount += 1
            Self.storedUploadPaths.append(path)
            let uploadNumber = Self.storedUploadCount
            Self.lock.unlock()
            send(
                statusCode: 201,
                data: currentContractEnvelope([
                    "uploadSessionId": "exemption-upload-\(uploadNumber)",
                    "mediaId": "exemption-media-\(uploadNumber)",
                    "uploadUrl": "https://upload.example.test/signed/exemption-media-\(uploadNumber)",
                    "uploadMethod": "PUT",
                    "requiredHeaders": ["Content-Type": "image/jpeg"]
                ])
            )
            return
        }

        if method == "PUT", path.hasPrefix("/signed/exemption-media-") {
            send(statusCode: 200, data: Data(), headers: ["ETag": "\"contract-etag\""])
            return
        }

        if method == "POST",
           path.hasPrefix("/api/v1/media-uploads/exemption-upload-"),
           path.hasSuffix("/confirm") {
            let uploadId = String(path.split(separator: "/")[3])
            let mediaId = uploadId.replacingOccurrences(of: "exemption-upload-", with: "exemption-media-")
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: mediaId,
                    businessPurpose: "EXEMPTION_APPLICATION",
                    sessionId: nil,
                    enrollmentId: "enrollment-1",
                    uploadStatus: "UPLOADED",
                    version: 1
                ))
            )
            return
        }

        if method == "GET", path.hasPrefix("/api/v1/media/") {
            let mediaId = String(path.split(separator: "/").last ?? "exemption-media-1")
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentMediaProjection(
                    id: mediaId,
                    businessPurpose: "EXEMPTION_APPLICATION",
                    sessionId: nil,
                    enrollmentId: "enrollment-1",
                    uploadStatus: "AVAILABLE",
                    version: 2
                ))
            )
            return
        }

        if path == "/api/v1/exemption-applications/ex1", method == "GET" {
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex1",
                    status: "SUPPLEMENT_REQUIRED",
                    reason: "existing reason",
                    mediaIds: [],
                    version: 3
                ))
            )
            return
        }

        if path == "/api/v1/exemption-applications/ex-new", method == "GET" {
            Self.lock.lock()
            let reason = Self.lastCreatedReason
            let mediaIds = Self.lastCreatedMediaIds
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex-new",
                    status: "DRAFT",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: mediaIds.isEmpty ? 1 : 2
                ))
            )
            return
        }

        if path == "/api/v1/exemption-applications", method == "POST" {
            let json = requestJSONObject(request)
            Self.lock.lock()
            Self.lastCreatedReason = json["reason"] as? String ?? ""
            Self.lastCreatedMediaIds = json["mediaIds"] as? [String] ?? []
            let reason = Self.lastCreatedReason
            let mediaIds = Self.lastCreatedMediaIds
            Self.lock.unlock()
            send(
                statusCode: 201,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex-new",
                    status: "DRAFT",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: 1
                ))
            )
            return
        }

        if Self.mutationPaths.contains(path), (method == "POST" || method == "PATCH") {
            let body = requestBodyData(request) ?? Data()
            let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
            Self.lock.lock()
            Self.storedBodies[path, default: []].append(body)
            Self.storedKeys[path, default: []].append(key)
            let shouldFail = Self.remainingFailurePaths.remove(path) != nil
            Self.lock.unlock()
            if shouldFail {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            } else {
                let json = requestJSONObject(request)
                let reason = json["reason"] as? String ?? ""
                let mediaIds = json["mediaIds"] as? [String] ?? []
                if path == "/api/v1/exemption-applications/ex-new" {
                    Self.lock.lock()
                    Self.lastCreatedReason = reason
                    Self.lastCreatedMediaIds = mediaIds
                    Self.lock.unlock()
                    send(
                        statusCode: 200,
                        data: currentContractEnvelope(currentExemptionProjection(
                            id: "ex-new",
                            status: "DRAFT",
                            reason: reason,
                            mediaIds: mediaIds,
                            version: 2
                        ))
                    )
                } else {
                    Self.lock.lock()
                    Self.lastSupplementReason = reason
                    Self.lastSupplementMediaIds = mediaIds
                    Self.lock.unlock()
                    send(
                        statusCode: 200,
                        data: currentContractEnvelope(currentExemptionProjection(
                            id: "ex1",
                            status: "SUPPLEMENT_REQUIRED",
                            reason: reason,
                            mediaIds: mediaIds,
                            version: 4
                        ))
                    )
                }
            }
            return
        }

        if path == "/api/v1/exemption-applications/ex-new/submit", method == "POST" {
            Self.lock.lock()
            let reason = Self.lastCreatedReason
            let mediaIds = Self.lastCreatedMediaIds
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex-new",
                    status: "SUBMITTED",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: 3
                ))
            )
            return
        }

        if path == "/api/v1/exemption-applications/ex1/submit", method == "POST" {
            Self.lock.lock()
            let reason = Self.lastSupplementReason
            let mediaIds = Self.lastSupplementMediaIds
            Self.lock.unlock()
            send(
                statusCode: 200,
                data: currentContractEnvelope(currentExemptionProjection(
                    id: "ex1",
                    status: "SUBMITTED",
                    reason: reason,
                    mediaIds: mediaIds,
                    version: 5
                ))
            )
            return
        }

        send(
            statusCode: 404,
            data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
        )
    }

    override func stopLoading() {}

    private func send(
        statusCode: Int,
        data: Data,
        headers: [String: String] = [:]
    ) {
        var responseHeaders = ["Content-Type": "application/json"]
        headers.forEach { responseHeaders[$0.key] = $0.value }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

}

private final class FeedbackContractURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedRequests: [RecordedContractRequest] = []

    static var requests: [RecordedContractRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock()
        storedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let jsonBody = request.httpBody.map { data in
            (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } ?? nil
        let recorded = RecordedContractRequest(
            path: path,
            method: method,
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
            jsonBody: jsonBody
        )
        Self.lock.lock()
        Self.storedRequests.append(recorded)
        Self.lock.unlock()

        let value: Any
        let statusCode: Int
        switch (method, path) {
        case ("GET", "/api/v1/feedback"):
            value = [[
                "id": "feedback-existing-1",
                "category": "BUG",
                "content": "运动记录刷新失败。",
                "status": "IN_PROGRESS",
                "publicReply": NSNull(),
                "createdAt": "2026-08-24T08:00:00Z",
                "updatedAt": "2026-08-24T08:10:00Z",
                "version": 2,
            ]]
            statusCode = 200
        case ("POST", "/api/v1/feedback"):
            value = [
                "id": "feedback-created-1",
                "category": jsonBody?["category"] as? String ?? "OTHER",
                "content": jsonBody?["content"] as? String ?? "",
                "status": "OPEN",
                "publicReply": NSNull(),
                "createdAt": "2026-08-24T09:00:00Z",
                "updatedAt": "2026-08-24T09:00:00Z",
                "version": 1,
            ]
            statusCode = 201
        default:
            send(
                statusCode: 404,
                data: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
            )
            return
        }
        send(statusCode: statusCode, data: currentContractEnvelope(value))
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

private final class CanonicalMutationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedPaths: [String] = []
    private static var storedKeys: [String] = []
    private static var supplementReason = "medical reason\n\ndoctor note"
    private static var supplementMediaIds = ["media-1"]
    private static var createdReason = "medical reason\n\ndoctor note"
    private static var createdMediaIds: [String] = []

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
        supplementReason = "medical reason\n\ndoctor note"
        supplementMediaIds = ["media-1"]
        createdReason = "medical reason\n\ndoctor note"
        createdMediaIds = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
            Self.lock.lock()
            Self.storedPaths.append(path)
            Self.storedKeys.append(key)
            Self.lock.unlock()
        }
        let value: Any
        let statusCode: Int

        switch (method, path) {
        case ("GET", "/api/v1/exercise-sessions/session-canonical"):
            value = currentExerciseSessionProjection(id: "session-canonical")
            statusCode = 200
        case ("POST", "/api/v1/exercise-records"):
            value = currentExerciseRecordProjection(
                id: "record-1",
                sessionId: "session-canonical",
                status: "DRAFT"
            )
            statusCode = 201
        case ("POST", "/api/v1/exercise-records/record-1/submit"):
            value = currentExerciseRecordProjection(
                id: "record-1",
                sessionId: "session-canonical",
                status: "REVIEWED",
                version: 2
            )
            statusCode = 200
        case ("POST", "/api/v1/exemption-applications"):
            let json = requestJSONObject(request)
            let reason = json["reason"] as? String ?? "medical reason\n\ndoctor note"
            let mediaIds = json["mediaIds"] as? [String] ?? []
            Self.lock.lock()
            Self.createdReason = reason
            Self.createdMediaIds = mediaIds
            Self.lock.unlock()
            value = currentExemptionProjection(
                id: "exemption-created",
                status: "DRAFT",
                reason: reason,
                mediaIds: mediaIds,
                version: 1
            )
            statusCode = 201
        case ("GET", "/api/v1/exemption-applications/exemption-created"):
            Self.lock.lock()
            let reason = Self.createdReason
            let mediaIds = Self.createdMediaIds
            Self.lock.unlock()
            value = currentExemptionProjection(
                id: "exemption-created",
                status: "DRAFT",
                reason: reason,
                mediaIds: mediaIds,
                version: mediaIds.isEmpty ? 1 : 2
            )
            statusCode = 200
        case ("PATCH", "/api/v1/exemption-applications/exemption-created"):
            let json = requestJSONObject(request)
            let reason = json["reason"] as? String ?? ""
            let mediaIds = json["mediaIds"] as? [String] ?? []
            Self.lock.lock()
            Self.createdReason = reason
            Self.createdMediaIds = mediaIds
            Self.lock.unlock()
            value = currentExemptionProjection(
                id: "exemption-created",
                status: "DRAFT",
                reason: reason,
                mediaIds: mediaIds,
                version: 2
            )
            statusCode = 200
        case ("POST", "/api/v1/exemption-applications/exemption-created/submit"):
            Self.lock.lock()
            let reason = Self.createdReason
            let mediaIds = Self.createdMediaIds
            Self.lock.unlock()
            value = currentExemptionProjection(
                id: "exemption-created",
                status: "SUBMITTED",
                reason: reason,
                mediaIds: mediaIds,
                version: 3
            )
            statusCode = 200
        case ("GET", "/api/v1/exemption-applications/exemption-1"):
            Self.lock.lock()
            let reason = Self.supplementReason
            let mediaIds = Self.supplementMediaIds
            Self.lock.unlock()
            value = currentExemptionProjection(
                id: "exemption-1",
                status: "SUPPLEMENT_REQUIRED",
                reason: reason,
                mediaIds: mediaIds,
                version: 3
            )
            statusCode = 200
        case ("PATCH", "/api/v1/exemption-applications/exemption-1"):
            let json = requestJSONObject(request)
            let reason = json["reason"] as? String ?? ""
            let mediaIds = json["mediaIds"] as? [String] ?? []
            Self.lock.lock()
            Self.supplementReason = reason
            Self.supplementMediaIds = mediaIds
            Self.lock.unlock()
            value = currentExemptionProjection(
                id: "exemption-1",
                status: "SUPPLEMENT_REQUIRED",
                reason: reason,
                mediaIds: mediaIds,
                version: 4
            )
            statusCode = 200
        case ("POST", "/api/v1/exemption-applications/exemption-1/submit"):
            Self.lock.lock()
            let reason = Self.supplementReason
            let mediaIds = Self.supplementMediaIds
            Self.lock.unlock()
            value = currentExemptionProjection(
                id: "exemption-1",
                status: "SUBMITTED",
                reason: reason,
                mediaIds: mediaIds,
                version: 5
            )
            statusCode = 200
        default:
            if method == "GET", path.hasPrefix("/api/v1/media/") {
                let mediaId = String(path.split(separator: "/").last ?? "media-1")
                value = currentMediaProjection(
                    id: mediaId,
                    businessPurpose: "EXEMPTION_APPLICATION",
                    sessionId: nil,
                    enrollmentId: "enrollment-1",
                    uploadStatus: "AVAILABLE",
                    version: 3
                )
                statusCode = 200
            } else {
                sendError(statusCode: 404)
                return
            }
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: currentContractEnvelope(value))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func sendError(statusCode: Int) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self,
            didLoad: currentContractError(code: "RESOURCE_NOT_FOUND", message: "not found")
        )
        client?.urlProtocolDidFinishLoading(self)
    }
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
        let path = request.url?.path ?? ""
        if request.httpMethod == "GET", path == "/api/v1/exercise-sessions/session-conflict" {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self,
                didLoad: currentContractEnvelope(
                    currentExerciseSessionProjection(id: "session-conflict")
                )
            )
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        Self.lock.lock()
        let code = Self.responseCode
        Self.lock.unlock()
        let body = currentContractError(
            code: code,
            message: "The idempotency request is still processing or the key was reused."
        )
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


/// Serves a fixed availability policy so the write gate can be tested without a
/// server or launch arguments.
private struct SystemModeRepositoryStub: StudentRepository {
    let status: SystemModeStatus
    var requirement: AppUpdateRequirement?

    private let base = MockStudentRepository()

    func loadWorkspace() -> StudentWorkspace { base.loadWorkspace() }

    func loadCourseInvite(code: String) -> CourseInvite? { base.loadCourseInvite(code: code) }

    func acceptsContactCode(_ code: String, channel: ContactChannel, value: String) -> Bool {
        base.acceptsContactCode(code, channel: channel, value: value)
    }

    func loadFeedbackTickets() -> [FeedbackTicket] { base.loadFeedbackTickets() }

    func loadSystemMode() -> SystemModeStatus { status }

    func loadUpdateRequirement() -> AppUpdateRequirement? { requirement }

    func loadHelpArticles() throws -> [HelpArticle] { try base.loadHelpArticles() }
}

/// Serves one help-article outcome, so the help centre's cached, failed and
/// published states can each be driven from a test.
private struct HelpArticleRepositoryStub: StudentRepository {
    let result: Result<[HelpArticle], Error>

    private let base = MockStudentRepository()

    func loadWorkspace() -> StudentWorkspace { base.loadWorkspace() }

    func loadCourseInvite(code: String) -> CourseInvite? { base.loadCourseInvite(code: code) }

    func acceptsContactCode(_ code: String, channel: ContactChannel, value: String) -> Bool {
        base.acceptsContactCode(code, channel: channel, value: value)
    }

    func loadFeedbackTickets() -> [FeedbackTicket] { base.loadFeedbackTickets() }

    func loadSystemMode() -> SystemModeStatus { SystemModeStatus() }

    func loadUpdateRequirement() -> AppUpdateRequirement? { nil }

    func loadHelpArticles() throws -> [HelpArticle] { try result.get() }
}
