import CoreLocation
import XCTest

final class BNBUStudentSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-authenticated",
            "-ui-testing-completed-exercise",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Temporary: captures every conditional dashboard block for the
    /// before/after comparison against the Android baseline.
    func testTempShotsDashboardBaseline() throws {
        let configurations: [(name: String, arguments: [String])] = [
            ("01-dashboard-pending", ["-ui-testing-reset", "-ui-testing-authenticated"]),
            ("02-dashboard-checked-in", ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-completed-exercise"]),
            ("03-dashboard-exercise-active", ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-active-exercise"]),
            ("04-dashboard-no-course", ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-empty-state"]),
            ("05-dashboard-en", ["-ui-testing-reset", "-ui-testing-authenticated", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        ]

        for configuration in configurations {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = configuration.arguments
            app.launch()

            XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 8), configuration.name)
            attachScreenshot(named: "\(configuration.name)-top")
            app.swipeUp()
            attachScreenshot(named: "\(configuration.name)-lower")
        }
    }

    func testStudentShellSmokeFlow() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["体育学时进度"].exists)
        XCTAssertTrue(app.staticTexts["学时构成"].exists)

        openTab(label: "课程", screenIdentifier: "screen.courses")
        XCTAssertTrue(app.staticTexts["我的课程"].waitForExistence(timeout: 3))

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        XCTAssertTrue(app.staticTexts["提交打卡"].waitForExistence(timeout: 3))

        openTab(label: "成绩", screenIdentifier: "screen.grades")
        XCTAssertTrue(app.staticTexts["成绩进度"].waitForExistence(timeout: 3))

        openTab(label: "我的", screenIdentifier: "screen.profile")
        XCTAssertTrue(app.staticTexts["申请与审核"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["组织认证与抵扣记录"].exists)
        assertProfileNavigationCardsAligned()
    }

    func testSystemLanguageChineseUpdatesCoreNavigation() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        XCTAssertEqual(tabButton("tab.dashboard").label, "首页")
        XCTAssertEqual(tabButton("tab.courses").label, "课程")
        XCTAssertEqual(tabButton("tab.checkin").label, "打卡")
        XCTAssertEqual(tabButton("tab.grades").label, "成绩")
        XCTAssertEqual(tabButton("tab.profile").label, "我的")
    }

    func testSystemLanguageEnglishUpdatesCoreNavigation() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-authenticated",
            "-ui-testing-completed-exercise",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        XCTAssertEqual(tabButton("tab.dashboard").label, "Home")
        XCTAssertEqual(tabButton("tab.courses").label, "Courses")
        XCTAssertEqual(tabButton("tab.checkin").label, "Check In")
        XCTAssertEqual(tabButton("tab.grades").label, "Grades")
        XCTAssertEqual(tabButton("tab.profile").label, "Profile")

        XCTAssertTrue(app.staticTexts["Sports credit progress"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Credit breakdown"].exists)
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "4 hr")
            ).firstMatch.exists
        )
        XCTAssertFalse(app.staticTexts["体育学时进度"].exists)

        tabButton("tab.grades").tap()
        XCTAssertTrue(screen("screen.grades").waitForExistence(timeout: 3))
        for title in [
            "PE Check-In",
            "Specialized Exam",
            "Class Performance / Attendance",
            "Physical Fitness Test"
        ] {
            let componentTitle = app.staticTexts[title]
            var found = componentTitle.waitForExistence(timeout: 1)
            if !found {
                app.swipeUp()
                found = componentTitle.waitForExistence(timeout: 1)
            }
            XCTAssertTrue(found, "Missing localized grade component: \(title)")
        }
    }

    func testEnglishLayoutRegressionScreenshots() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-authenticated",
            "-ui-testing-completed-exercise",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        attachScreenshot(named: "english-home")

        tabButton("tab.courses").tap()
        XCTAssertTrue(screen("screen.courses").waitForExistence(timeout: 3))
        attachScreenshot(named: "english-courses")

        tabButton("tab.checkin").tap()
        XCTAssertTrue(screen("screen.checkin").waitForExistence(timeout: 3))
        for label in ["Start Time", "Location", "End Time", "Eligible Hours"] {
            XCTAssertTrue(
                app.staticTexts[label].waitForExistence(timeout: 2),
                "Missing localized check-in field: \(label)"
            )
        }
        attachScreenshot(named: "english-checkin")

        tabButton("tab.grades").tap()
        XCTAssertTrue(screen("screen.grades").waitForExistence(timeout: 3))
        attachScreenshot(named: "english-grades")

        app.swipeUp()
        attachScreenshot(named: "english-grades-lower")

        tabButton("tab.profile").tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 3))
        assertProfileNavigationCardsAligned()
        attachScreenshot(named: "english-profile")
    }

    func testUnsupportedSystemLanguageFallsBackToEnglishNavigation() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-authenticated",
            "-ui-testing-completed-exercise",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()

        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        XCTAssertEqual(tabButton("tab.dashboard").label, "Home")
        XCTAssertEqual(tabButton("tab.courses").label, "Courses")
        XCTAssertEqual(tabButton("tab.checkin").label, "Check In")
        XCTAssertEqual(tabButton("tab.grades").label, "Grades")
        XCTAssertEqual(tabButton("tab.profile").label, "Profile")
    }

    func testManualLanguageSwitchUpdatesNavigationWithoutRelaunch() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        openTab(label: "我的", screenIdentifier: "screen.profile")

        let englishSegment = app.buttons["English"]
        for _ in 0..<6 where !englishSegment.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(englishSegment.waitForExistence(timeout: 2))
        englishSegment.tap()

        let homeLabelUpdated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Home"),
            object: tabButton("tab.dashboard")
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [homeLabelUpdated], timeout: 3),
            .completed
        )
        XCTAssertEqual(tabButton("tab.dashboard").label, "Home")
        XCTAssertEqual(tabButton("tab.courses").label, "Courses")
        XCTAssertEqual(tabButton("tab.checkin").label, "Check In")
        XCTAssertEqual(tabButton("tab.grades").label, "Grades")
        XCTAssertEqual(tabButton("tab.profile").label, "Profile")
    }

    func testSubmitDraftAndSubmittedRecordFlow() throws {
        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")

        app.buttons["提交"].firstMatch.tap()

        // Q&A 7/23 (Q5): the sport note is required before submitting.
        let noteEditor = app.textViews["运动说明"]
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 3))
        noteEditor.tap()
        noteEditor.typeText("操场跑步一小时")
        let noteDoneButton = app.toolbars.buttons["完成"]
        if noteDoneButton.waitForExistence(timeout: 2) {
            noteDoneButton.tap()
        }
        XCTAssertFalse(app.buttons["proof.demo.add"].exists)
        XCTAssertFalse(app.staticTexts["模拟拍摄（调试）"].exists)
        scrollToAndTap(app.buttons["保存草稿"])
        XCTAssertTrue(app.buttons["草稿已保存"].waitForExistence(timeout: 2))

        scrollToAndTap(app.buttons["checkin.submit.button"])
        XCTAssertTrue(app.staticTexts["确认提交打卡"].waitForExistence(timeout: 3))
        app.buttons.matching(identifier: "checkin.confirm.button").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["提交成功"].waitForExistence(timeout: 3))
        app.buttons["查看记录"].tap()

        XCTAssertTrue(app.staticTexts["自主运动打卡"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已提交"].exists)
        XCTAssertFalse(app.staticTexts["待审核"].exists)
        XCTAssertTrue(app.staticTexts["打卡照片 / 视频"].exists)
    }

    // Business rules 3.2.1/5.5/5.6: pause/resume, in-session capture drafts,
    // and the under-one-hour end path that keeps drafts and reopens the form.
    func testExercisePauseCaptureAndUnderHourEndFlow() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-active-exercise", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        app.buttons["提交"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["运动进行中"].waitForExistence(timeout: 5))

        // The launch fixture seeds one hidden draft without exposing a debug
        // capture control in the user interface.
        XCTAssertFalse(app.buttons["checkin.capture.demo"].exists)
        XCTAssertTrue(app.staticTexts["照片草稿 1/6"].waitForExistence(timeout: 3))

        // Pause freezes the timer; resume brings the session back.
        scrollToAndTap(app.buttons["checkin.exercise.pause"])
        XCTAssertTrue(app.staticTexts["运动已暂停"].waitForExistence(timeout: 3))
        scrollToAndTap(app.buttons["checkin.exercise.resume"])
        XCTAssertTrue(app.staticTexts["运动进行中"].waitForExistence(timeout: 3))

        // Business rule 5.6: ending always passes the anti-mistap dialog
        // first;「取消」returns to the running session with the timer intact.
        let endAlert = app.alerts["结束运动"]
        scrollToAndTap(app.buttons["checkin.exercise.end"])
        XCTAssertTrue(endAlert.waitForExistence(timeout: 3))
        endAlert.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["运动进行中"].waitForExistence(timeout: 3))

        // An under-one-hour end then shows the notice, keeps drafts, and
        // reopens the start form.
        scrollToAndTap(app.buttons["checkin.exercise.end"])
        XCTAssertTrue(endAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(endAlert.staticTexts["你确定要结束本次运动吗？当前运动时长不足 1 小时，结束后本次不计入有效打卡时长。"].exists)
        endAlert.buttons["确认结束"].firstMatch.tap()
        XCTAssertTrue(app.alerts["运动时长未满 1 小时"].waitForExistence(timeout: 3))
        app.alerts["运动时长未满 1 小时"].buttons["好"].tap()
        XCTAssertTrue(app.buttons["checkin.exercise.start"].waitForExistence(timeout: 5))
    }

    // Business rules 5.5/10.3: starting exercise fetches one best-effort GPS
    // fix and attaches it to the running session. Runs against a simulated
    // device location, driving the real CoreLocation permission + fix path.
    func testExerciseStartAttachesSimulatedGPSFix() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-location-check", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: 22.3364, longitude: 114.1655)
        )
        let monitor = addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "使用App时允许", "允许一次", "允许"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }

        app.launch()
        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        app.buttons["提交"].firstMatch.tap()

        scrollToAndTap(app.buttons["跑步"])
        scrollToAndTap(app.buttons["checkin.exercise.start"])
        XCTAssertTrue(app.staticTexts["运动进行中"].waitForExistence(timeout: 5))

        // Interruption monitors only fire on interaction; nudge the app while
        // polling so the permission alert gets answered, then wait for the
        // fix to attach and render in the session detail rows.
        let attached = app.staticTexts["已获取"]
        for _ in 0..<12 where !attached.exists {
            app.staticTexts["运动进行中"].firstMatch.tap()
            _ = attached.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(attached.exists, "开始运动后应附加一次 GPS 定位并显示“已获取”")
    }

    func testSubmittedHistoryNoticeReadAndLogoutFlow() throws {
        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")

        app.buttons["记录"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["打卡记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已提交"].firstMatch.waitForExistence(timeout: 3))
        // The mock workspace ships one teacher-invalidated record (r4);
        // its badge must render the new validity model, not review states.
        XCTAssertTrue(app.staticTexts["无效"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["待审核"].exists)
        XCTAssertFalse(app.staticTexts["已通过"].exists)
        XCTAssertFalse(app.staticTexts["被驳回"].exists)

        openTab(label: "首页", screenIdentifier: "screen.dashboard")
        app.buttons["dashboard.notifications.button"].tap()
        XCTAssertTrue(app.buttons["全部标为已读"].waitForExistence(timeout: 3))
        app.buttons["全部标为已读"].tap()
        app.buttons["关闭"].tap()

        openTab(label: "我的", screenIdentifier: "screen.profile")
        scrollToAndTap(app.buttons["profile.logout.button"], maxSwipes: 10)
        XCTAssertTrue(app.staticTexts["退出登录？"].waitForExistence(timeout: 3))
        app.buttons["profile.logout.confirm"].firstMatch.tap()
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
    }

    func testEmptyStateSmokeFlow() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-empty-state", "-ui-testing-authenticated", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        login()

        openTab(label: "课程", screenIdentifier: "screen.courses")
        XCTAssertTrue(app.staticTexts["暂无课程"].waitForExistence(timeout: 3))

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        XCTAssertTrue(app.staticTexts["提交打卡"].waitForExistence(timeout: 3))

        openTab(label: "我的", screenIdentifier: "screen.profile")
        XCTAssertTrue(app.staticTexts["暂无认证记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["申请与审核"].exists)
    }

    func testCourseJoinApplicationFlow() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        login()
        openTab(label: "课程", screenIdentifier: "screen.courses")

        let entry = app.buttons["courses.join.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()

        XCTAssertTrue(screen("screen.courseJoin").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["course.join.scan"].exists)

        let codeField = app.textFields["course.join.code.field"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        let submit = app.buttons["course.join.submit"]
        XCTAssertFalse(submit.isEnabled)

        codeField.tap()
        codeField.typeText("BNBU2026")
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertTrue(app.staticTexts["加入申请已提交"].waitForExistence(timeout: 3))
        let done = app.buttons["course.join.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()

        XCTAssertTrue(screen("screen.courses").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["待审核课程"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["等待任课老师审核"].exists)
        XCTAssertTrue(app.staticTexts["审核通过前不能开始运动打卡，本课程也不会产生有效学时。"].exists)
    }

    func testLoginPrivacyAndEnduranceEntryFlow() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["登录前请阅读《隐私政策》"].exists)
        app.buttons["登录前请阅读《隐私政策》"].tap()
        XCTAssertTrue(app.staticTexts["隐私政策"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["privacy.done"].tap()
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 3))

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        openTab(label: "我的", screenIdentifier: "screen.profile")
        scrollToAndTap(app.buttons["profile.endurance.button"])
        XCTAssertTrue(app.buttons["开始换算"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["测试项目: 800m"].exists)
        app.buttons["关闭"].tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 3))
    }

    // Temporary remote E2E check driven by env credentials; skipped when env is absent.
    func testRemoteRealLoginFlow() throws {
        guard let account = ProcessInfo.processInfo.environment["BNBU_TEST_ACCOUNT"],
              let password = ProcessInfo.processInfo.environment["BNBU_TEST_PASSWORD"],
              !account.isEmpty, !password.isEmpty else {
            throw XCTSkip("BNBU_TEST_ACCOUNT / BNBU_TEST_PASSWORD not provided")
        }

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        focusAndType(app.textFields["login.email.field"], text: account)
        focusAndType(app.secureTextFields["login.password.field"], text: password)
        acceptPrivacyIfNeeded()
        let dismissKeyboard = app.toolbars.buttons["完成"]
        if dismissKeyboard.waitForExistence(timeout: 2) {
            dismissKeyboard.tap()
        }
        let submitButton = app.buttons["login.submit.button"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 3))
        submitButton.tap()

        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 30))
        dismissSavePasswordPromptIfNeeded()
        attachScreenshot(named: "remote-dashboard")

        openTab(label: "课程", screenIdentifier: "screen.courses")
        XCTAssertTrue(app.staticTexts["我的课程"].waitForExistence(timeout: 5))
        attachScreenshot(named: "remote-courses")

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        XCTAssertTrue(app.staticTexts["提交打卡"].waitForExistence(timeout: 5))
        app.buttons["记录"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["打卡记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已提交"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["待审核"].exists)
        attachScreenshot(named: "remote-records")

        openTab(label: "成绩", screenIdentifier: "screen.grades")
        XCTAssertTrue(app.staticTexts["成绩进度"].waitForExistence(timeout: 5))
        attachScreenshot(named: "remote-grades")

        openTab(label: "我的", screenIdentifier: "screen.profile")
        XCTAssertTrue(app.staticTexts["申请与审核"].waitForExistence(timeout: 5))
        attachScreenshot(named: "remote-profile")
    }

    // Temporary remote E2E write check driven by env credentials; skipped when env is absent.
    // Writes one real check-in record to the configured Debug server.
    func testRemoteRealCheckInSubmitAndReadBackFlow() throws {
        guard let account = ProcessInfo.processInfo.environment["BNBU_TEST_ACCOUNT"],
              let password = ProcessInfo.processInfo.environment["BNBU_TEST_PASSWORD"],
              !account.isEmpty, !password.isEmpty else {
            throw XCTSkip("BNBU_TEST_ACCOUNT / BNBU_TEST_PASSWORD not provided")
        }

        app.terminate()
        app = XCUIApplication()
        // The remote hook installs a completed 1h exercise session after the
        // real login succeeds, so the new timer-based submit flow is testable
        // against the live server without waiting an hour.
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-remote-completed-exercise", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        focusAndType(app.textFields["login.email.field"], text: account)
        focusAndType(app.secureTextFields["login.password.field"], text: password)
        acceptPrivacyIfNeeded()
        let dismissKeyboard = app.toolbars.buttons["完成"]
        if dismissKeyboard.waitForExistence(timeout: 2) {
            dismissKeyboard.tap()
        }
        app.buttons["login.submit.button"].tap()
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 30))
        dismissSavePasswordPromptIfNeeded()

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        app.buttons["提交"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["提交打卡"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["运动已结束"].waitForExistence(timeout: 5))

        let noteEditor = app.textViews["运动说明"]
        if noteEditor.waitForExistence(timeout: 3) {
            noteEditor.tap()
            noteEditor.typeText("iOS联调测试 20260719 提交读回闭环，可忽略或清理")
            let doneButton = app.toolbars.buttons["完成"]
            if doneButton.waitForExistence(timeout: 2) {
                doneButton.tap()
            }
        }

        XCTAssertFalse(app.buttons["proof.demo.add"].exists)
        attachScreenshot(named: "remote-submit-form")

        scrollToAndTap(app.buttons["checkin.submit.button"])
        XCTAssertTrue(app.staticTexts["确认提交打卡"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "checkin.confirm.button").firstMatch.tap()

        // Real upload + record submission against the live server.
        let success = app.staticTexts["提交成功"].waitForExistence(timeout: 60)
        if !success {
            attachScreenshot(named: "remote-submit-failure")
        }
        XCTAssertTrue(success)
        attachScreenshot(named: "remote-submit-success")
        app.buttons["查看记录"].tap()

        XCTAssertTrue(app.staticTexts["打卡记录"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已提交"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["待审核"].exists)
        attachScreenshot(named: "remote-submit-records-readback")
    }

    // Read-only remote check: the note passed via BNBU_EXPECT_NOTE must be visible
    // in the records list. Skipped unless env credentials and the note are provided.
    func testRemoteRecordsShowExpectedNote() throws {
        guard let account = ProcessInfo.processInfo.environment["BNBU_TEST_ACCOUNT"],
              let password = ProcessInfo.processInfo.environment["BNBU_TEST_PASSWORD"],
              let expectedNote = ProcessInfo.processInfo.environment["BNBU_EXPECT_NOTE"],
              !account.isEmpty, !password.isEmpty, !expectedNote.isEmpty else {
            throw XCTSkip("BNBU_TEST_ACCOUNT / BNBU_TEST_PASSWORD / BNBU_EXPECT_NOTE not provided")
        }

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        focusAndType(app.textFields["login.email.field"], text: account)
        focusAndType(app.secureTextFields["login.password.field"], text: password)
        acceptPrivacyIfNeeded()
        let dismissKeyboard = app.toolbars.buttons["完成"]
        if dismissKeyboard.waitForExistence(timeout: 2) {
            dismissKeyboard.tap()
        }
        app.buttons["login.submit.button"].tap()
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 30))
        dismissSavePasswordPromptIfNeeded()

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        app.buttons["记录"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["打卡记录"].waitForExistence(timeout: 10))

        let noteMatch = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", expectedNote)
        ).firstMatch
        var found = noteMatch.waitForExistence(timeout: 10)
        var swipes = 0
        while !found, swipes < 8 {
            app.swipeUp()
            swipes += 1
            found = noteMatch.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(found)
        attachScreenshot(named: "remote-records-note-visible")
    }

    private func focusAndType(_ field: XCUIElement, text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for attempt in 0..<5 {
            field.tap()
            usleep(600_000)
            if fieldHasKeyboardFocus(field) {
                field.typeText(text)
                return
            }
            // A stuck keyboard from the previous field can swallow the tap.
            let dismiss = app.toolbars.buttons["完成"]
            if attempt >= 1, dismiss.exists {
                dismiss.tap()
                usleep(400_000)
            }
        }
        field.tap()
        field.typeText(text)
    }

    private func fieldHasKeyboardFocus(_ field: XCUIElement) -> Bool {
        (field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func dismissSavePasswordPromptIfNeeded() {
        let candidates = [
            app.buttons["以后"],
            app.buttons["Not Now"],
            XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["以后"],
            XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Not Now"]
        ]
        for _ in 0..<3 {
            var tapped = false
            for button in candidates where button.waitForExistence(timeout: 2) && button.isHittable {
                button.tap()
                tapped = true
                break
            }
            if !tapped { return }
            usleep(500_000)
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openTab(label: String, screenIdentifier: String) {
        let identifier: String
        switch label {
        case "首页": identifier = "tab.dashboard"
        case "课程": identifier = "tab.courses"
        case "打卡": identifier = "tab.checkin"
        case "成绩": identifier = "tab.grades"
        default: identifier = "tab.profile"
        }
        tabButton(identifier).tap()
        XCTAssertTrue(screen(screenIdentifier).waitForExistence(timeout: 3))
    }

    /// The native tab bar publishes its accessibility identifiers slightly after
    /// the first tab's content appears, so waiting here keeps a relaunch
    /// followed by an immediate tab switch from racing the tab bar.
    private func tabButton(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let button = app.buttons[identifier]
        _ = button.waitForExistence(timeout: timeout)
        return button
    }

    private func login() {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
    }

    private func acceptPrivacyIfNeeded() {
        let consent = app.buttons["login.privacy.consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 3))
        if (consent.value as? String) != "已同意" {
            consent.tap()
        }
    }

    private func screen(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func assertProfileNavigationCardsAligned(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let exemptionCard = app.buttons["profile.exemption.button"]
        let enduranceCard = app.buttons["profile.endurance.button"]
        XCTAssertTrue(exemptionCard.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(enduranceCard.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(exemptionCard.frame.minX, enduranceCard.frame.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(exemptionCard.frame.width, enduranceCard.frame.width, accuracy: 1, file: file, line: line)
    }

    private func scrollToAndTap(_ element: XCUIElement, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes {
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                tapCenter(of: element)
                return
            }
            app.swipeUp()
            usleep(250_000)
        }

        XCTAssertTrue(element.waitForExistence(timeout: 2))
        // SwiftUI can report a fully visible button inside a ScrollView as
        // non-hittable while its custom bottom safe-area bar is present.
        // A center-coordinate tap mirrors the physical touch and still lets
        // the following assertion verify that the intended action fired.
        tapCenter(of: element)
    }

    private func tapCenter(of element: XCUIElement) {
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }
}
