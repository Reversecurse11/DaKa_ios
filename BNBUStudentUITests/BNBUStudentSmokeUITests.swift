import XCTest

final class BNBUStudentSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-completed-exercise"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testStudentShellSmokeFlow() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["体育学时进度"].exists)
        XCTAssertTrue(app.staticTexts["最近打卡"].exists)

        openTab(label: "课程", screenIdentifier: "screen.courses")
        XCTAssertTrue(app.staticTexts["我的课程"].waitForExistence(timeout: 3))

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        XCTAssertTrue(app.staticTexts["提交打卡"].waitForExistence(timeout: 3))

        openTab(label: "成绩", screenIdentifier: "screen.grades")
        XCTAssertTrue(app.staticTexts["成绩进度"].waitForExistence(timeout: 3))

        openTab(label: "我的", screenIdentifier: "screen.profile")
        XCTAssertTrue(app.staticTexts["申请与审核"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["组织认证与抵扣记录"].exists)
    }

    func testSubmitDraftAndSubmittedRecordFlow() throws {
        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")

        app.segmentedControls.buttons["提交"].tap()
        scrollToAndTap(app.buttons["proof.demo.add"])
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
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-active-exercise"]
        app.launch()

        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        app.segmentedControls.buttons["提交"].tap()
        XCTAssertTrue(app.staticTexts["运动进行中"].waitForExistence(timeout: 5))

        // In-session simulated camera capture lands in the draft pool.
        scrollToAndTap(app.buttons["checkin.capture.demo"])
        XCTAssertTrue(app.staticTexts["照片草稿 1/6"].waitForExistence(timeout: 3))

        // Pause freezes the timer; resume brings the session back.
        scrollToAndTap(app.buttons["checkin.exercise.pause"])
        XCTAssertTrue(app.staticTexts["运动已暂停"].waitForExistence(timeout: 3))
        scrollToAndTap(app.buttons["checkin.exercise.resume"])
        XCTAssertTrue(app.staticTexts["运动进行中"].waitForExistence(timeout: 3))

        // Ending under one hour warns, keeps drafts, and reopens the form.
        scrollToAndTap(app.buttons["checkin.exercise.end"])
        XCTAssertTrue(app.staticTexts["结束运动"].firstMatch.waitForExistence(timeout: 3))
        app.buttons.matching(identifier: "checkin.exercise.end.confirm").firstMatch.tap()
        XCTAssertTrue(app.buttons["checkin.exercise.start"].waitForExistence(timeout: 5))
    }

    func testSubmittedHistoryNoticeReadAndLogoutFlow() throws {
        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")

        app.segmentedControls.buttons["记录"].tap()
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
        scrollToAndTap(app.buttons["退出登录"])
        let confirmLogoutButton = app.buttons["退出登录"].firstMatch
        XCTAssertTrue(app.staticTexts["退出登录？"].waitForExistence(timeout: 3))
        confirmLogoutButton.tap()
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
    }

    func testEmptyStateSmokeFlow() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-empty-state", "-ui-testing-authenticated"]
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

    func testLoginPrivacyAndEnduranceEntryFlow() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["登录前请阅读《隐私政策》"].exists)
        app.buttons["登录前请阅读《隐私政策》"].tap()
        XCTAssertTrue(app.staticTexts["隐私政策"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 3))

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated"]
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
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        focusAndType(app.textFields["login.email.field"], text: account)
        focusAndType(app.secureTextFields["login.password.field"], text: password)
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
        app.segmentedControls.buttons["记录"].tap()
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
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        focusAndType(app.textFields["login.email.field"], text: account)
        focusAndType(app.secureTextFields["login.password.field"], text: password)
        let dismissKeyboard = app.toolbars.buttons["完成"]
        if dismissKeyboard.waitForExistence(timeout: 2) {
            dismissKeyboard.tap()
        }
        app.buttons["login.submit.button"].tap()
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 30))
        dismissSavePasswordPromptIfNeeded()

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        app.segmentedControls.buttons["提交"].tap()
        XCTAssertTrue(app.staticTexts["提交打卡"].waitForExistence(timeout: 5))

        let noteEditor = app.textViews["运动说明"]
        if noteEditor.waitForExistence(timeout: 3) {
            noteEditor.tap()
            noteEditor.typeText("iOS联调测试 20260719 提交读回闭环，可忽略或清理")
            let doneButton = app.toolbars.buttons["完成"]
            if doneButton.waitForExistence(timeout: 2) {
                doneButton.tap()
            }
        }

        scrollToAndTap(app.buttons["proof.demo.add"])
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
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        focusAndType(app.textFields["login.email.field"], text: account)
        focusAndType(app.secureTextFields["login.password.field"], text: password)
        let dismissKeyboard = app.toolbars.buttons["完成"]
        if dismissKeyboard.waitForExistence(timeout: 2) {
            dismissKeyboard.tap()
        }
        app.buttons["login.submit.button"].tap()
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 30))
        dismissSavePasswordPromptIfNeeded()

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        app.segmentedControls.buttons["记录"].tap()
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
        app.buttons[identifier].tap()
        XCTAssertTrue(screen(screenIdentifier).waitForExistence(timeout: 3))
    }

    private func login() {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
    }

    private func screen(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scrollToAndTap(_ element: XCUIElement, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes {
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                element.tap()
                return
            }
            app.swipeUp()
        }

        XCTAssertTrue(element.waitForExistence(timeout: 2))
        element.tap()
    }
}
