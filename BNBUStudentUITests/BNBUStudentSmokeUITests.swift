import CoreLocation
import UIKit
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

    /// Temporary: reproduces the demo sequence that left a black hairline at the
    /// top safe-area edge — switch to dark inside the settings sheet, close it,
    /// then scroll the page underneath.
    func testTempShotsDarkSwitchThenScrollProfile() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        tabButton("tab.profile").tap()
        app.buttons["profile.settings.button"].tap()
        XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 5))
        app.buttons["profile.appearance.dark"].tap()
        app.buttons["nav.back"].tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 5))
        attachScreenshot(named: "dark-switch-01-profile-top")

        // A short drag leaves content behind the status bar, which is where the
        // hairline showed up.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            )
        attachScreenshot(named: "dark-switch-02-profile-scrolled")
        app.swipeUp()
        attachScreenshot(named: "dark-switch-03-profile-scrolled-more")

        tabButton("tab.dashboard").tap()
        attachScreenshot(named: "dark-switch-04-dashboard")
    }

    /// Switching the appearance from the settings sheet has to repaint the sheet
    /// itself, not just the pages behind it.
    func testAppearanceSwitchRepaintsThePresentedSettingsSheet() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        tabButton("tab.profile").tap()
        app.buttons["profile.settings.button"].tap()
        XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 5))

        let sheet = screen("screen.profileSettings")
        let lightBackground = try XCTUnwrap(sheet.screenshot().image.averageBrightness)

        app.buttons["profile.appearance.dark"].tap()
        // The sheet keeps its identity, so poll its own pixels rather than
        // waiting for an element to appear.
        var darkBackground = lightBackground
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            darkBackground = try XCTUnwrap(sheet.screenshot().image.averageBrightness)
            if darkBackground < lightBackground - 0.3 { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        attachScreenshot(named: "appearance-switched-to-dark")
        XCTAssertLessThan(
            darkBackground,
            lightBackground - 0.3,
            "The settings sheet stayed on the light palette after switching to dark"
        )

        app.buttons["profile.appearance.light"].tap()
        var restored = darkBackground
        let restoreDeadline = Date().addingTimeInterval(5)
        while Date() < restoreDeadline {
            restored = try XCTUnwrap(sheet.screenshot().image.averageBrightness)
            if restored > darkBackground + 0.3 { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        attachScreenshot(named: "appearance-switched-back-to-light")
        XCTAssertGreaterThan(
            restored,
            darkBackground + 0.3,
            "The settings sheet stayed on the dark palette after switching back to light"
        )
    }

    /// Temporary: sweeps every tab plus the settings sheet in dark mode and in
    /// English, to chase down the appearance and mixed-language defects seen in
    /// the demo.
    func testTempShotsAppearanceAndLanguageAudit() throws {
        let passes: [(name: String, arguments: [String])] = [
            ("dark-zh", ["-bnbu.appearance.mode.v3", "dark", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]),
            ("dark-en", ["-bnbu.appearance.mode.v3", "dark", "-ui-testing-language-en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]),
            ("light-en", ["-ui-testing-language-en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        ]
        let tabs = ["tab.dashboard", "tab.courses", "tab.checkin", "tab.grades", "tab.profile"]

        for pass in passes {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-completed-exercise"] + pass.arguments
            app.launch()
            XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 8), pass.name)

            for (index, tab) in tabs.enumerated() {
                tabButton(tab).tap()
                attachScreenshot(named: "\(pass.name)-\(index + 1)-\(tab)")
                app.swipeUp()
                attachScreenshot(named: "\(pass.name)-\(index + 1)-\(tab)-lower")
            }

            // The settings sheet is where the appearance switch lives.
            tabButton("tab.profile").tap()
            app.buttons["profile.settings.button"].tap()
            XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 5), pass.name)
            attachScreenshot(named: "\(pass.name)-6-settings")
        }
    }

    /// Temporary: captures the check-in tab states the lead flagged as the
    /// weakest match against the Android baseline (Android_PICTURE 22 and 24).
    func testTempShotsCheckInBaseline() throws {
        func relaunch(_ arguments: [String]) {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = arguments + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            app.launch()
        }

        relaunch(["-ui-testing-reset", "-ui-testing-authenticated"])
        tabButton("tab.checkin").tap()
        XCTAssertTrue(screen("screen.checkin").waitForExistence(timeout: 8))
        attachScreenshot(named: "checkin-01-prepare-top")
        app.swipeUp()
        attachScreenshot(named: "checkin-02-prepare-lower")

        // The readiness card only appears for course-bound sessions.
        relaunch(["-ui-testing-reset", "-ui-testing-authenticated"])
        tabButton("tab.checkin").tap()
        XCTAssertTrue(screen("screen.checkin").waitForExistence(timeout: 8))
        app.buttons["checkin.category.courseRelated"].tap()
        attachScreenshot(named: "checkin-07-prepare-course")

        relaunch(["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-active-exercise"])
        tabButton("tab.checkin").tap()
        XCTAssertTrue(screen("screen.checkin").waitForExistence(timeout: 8))
        attachScreenshot(named: "checkin-03-active-top")
        app.swipeUp()
        attachScreenshot(named: "checkin-04-active-lower")

        relaunch(["-ui-testing-reset", "-ui-testing-authenticated", "-ui-testing-completed-exercise"])
        tabButton("tab.checkin").tap()
        XCTAssertTrue(screen("screen.checkin").waitForExistence(timeout: 8))
        attachScreenshot(named: "checkin-05-completed-top")
        app.swipeUp()
        attachScreenshot(named: "checkin-06-completed-lower")
    }

    /// Temporary: one screenshot per page for the full walkthrough against the
    /// 43-shot Android baseline captured on 31 July.
    func testTempShotsFullWalkthrough() throws {
        func relaunch(_ arguments: [String]) {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = arguments + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            app.launch()
        }

        func home() {
            relaunch(["-ui-testing-reset", "-ui-testing-authenticated"])
            XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 8))
        }

        relaunch(["-ui-testing-reset"])
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 8))
        attachScreenshot(named: "w01-login")

        home()
        attachScreenshot(named: "w02-dashboard-top")
        app.swipeUp()
        attachScreenshot(named: "w03-dashboard-lower")

        home()
        tabButton("tab.courses").tap()
        XCTAssertTrue(screen("screen.courses").waitForExistence(timeout: 5))
        attachScreenshot(named: "w04-courses")

        home()
        tabButton("tab.grades").tap()
        XCTAssertTrue(screen("screen.grades").waitForExistence(timeout: 5))
        attachScreenshot(named: "w05-grades-top")
        app.swipeUp()
        attachScreenshot(named: "w06-grades-lower")

        home()
        tabButton("tab.profile").tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 5))
        attachScreenshot(named: "w07-profile-top")
        app.swipeUp()
        attachScreenshot(named: "w08-profile-lower")

        home()
        tabButton("tab.profile").tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 5))
        app.buttons["profile.endurance.button"].tap()
        XCTAssertTrue(screen("screen.profile.endurance").waitForExistence(timeout: 5))
        attachScreenshot(named: "w09-endurance")

        home()
        tabButton("tab.profile").tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 5))
        app.buttons["profile.exemption.button"].tap()
        attachScreenshot(named: "w10-exemption")

        home()
        tabButton("tab.courses").tap()
        XCTAssertTrue(screen("screen.courses").waitForExistence(timeout: 5))
        let courseCard = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "GEPE101")
        ).firstMatch
        if courseCard.waitForExistence(timeout: 3) {
            tapCenter(of: courseCard)
            XCTAssertTrue(app.staticTexts["课程代码"].waitForExistence(timeout: 5))
            attachScreenshot(named: "w11-course-detail-top")
            app.swipeUp()
            attachScreenshot(named: "w12-course-detail-lower")
        }

        home()
        tabButton("tab.profile").tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 5))
        app.buttons["profile.settings.button"].tap()
        XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 5))
        scrollToAndTap(app.buttons["settings.helpCenter"])
        XCTAssertTrue(screen("screen.help").waitForExistence(timeout: 5))
        attachScreenshot(named: "w13-help-center")
    }

    /// Temporary: captures the eight pages added on 29 July for the page-by-page
    /// comparison against the Android baseline.
    func testTempShotsNewPagesBaseline() throws {
        func relaunch(_ arguments: [String]) {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = arguments + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            app.launch()
        }

        // Startup gates.
        relaunch(["-ui-testing-reset", "-ui-testing-startup-gates"])
        XCTAssertTrue(screen("screen.privacy.consent").waitForExistence(timeout: 8))
        attachScreenshot(named: "01-privacy-consent")
        app.buttons["privacy.consent.agree"].tap()
        XCTAssertTrue(screen("screen.guide.pre-login").waitForExistence(timeout: 5))
        attachScreenshot(named: "02-guide-step1")
        app.buttons["guide.next"].tap()
        XCTAssertTrue(app.staticTexts["确认并提交申请"].waitForExistence(timeout: 3))
        attachScreenshot(named: "03-guide-step2")

        // Joining a course: invite entry, course confirmation, review status.
        relaunch(["-ui-testing-reset"])
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 8))
        app.staticTexts["扫码加入课程"].firstMatch.tap()
        XCTAssertTrue(screen("screen.courseJoin").waitForExistence(timeout: 5))
        attachScreenshot(named: "04-course-join-entry")

        focusAndType(app.textFields["course.join.code.field"], text: "BNBU2026")
        app.buttons["course.join.submit"].tap()
        XCTAssertTrue(screen("screen.courseJoinConfirm").waitForExistence(timeout: 5))
        attachScreenshot(named: "05-course-join-confirm")

        focusAndType(app.textFields["courseJoinConfirm.name"], text: "林同学")
        focusAndType(app.textFields["courseJoinConfirm.studentNumber"], text: "2400987654")
        app.buttons["courseJoinConfirm.submit"].tap()
        XCTAssertTrue(screen("screen.joinRequestStatus").waitForExistence(timeout: 5))
        attachScreenshot(named: "06-course-join-pending")
        app.buttons["nav.back"].tap()
        XCTAssertTrue(app.buttons["login.joinRequest.entry"].waitForExistence(timeout: 5))
        attachScreenshot(named: "06b-login-with-pending-request")

        func openProfile() {
            relaunch(["-ui-testing-reset", "-ui-testing-authenticated"])
            XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 8))
            tabButton("tab.profile").tap()
            XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 5))
        }

        openProfile()
        app.buttons["profile.accountDetails.button"].tap()
        XCTAssertTrue(screen("screen.accountDetails").waitForExistence(timeout: 5))
        attachScreenshot(named: "07-account-details")

        openProfile()
        app.buttons["profile.settings.button"].tap()
        XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 5))
        attachScreenshot(named: "08-settings-top")
        app.swipeUp()
        attachScreenshot(named: "09-settings-lower")

        app.buttons["settings.about"].tap()
        XCTAssertTrue(screen("screen.about").waitForExistence(timeout: 5))
        attachScreenshot(named: "10-about")
        app.buttons["about.changelog"].tap()
        XCTAssertTrue(screen("screen.changelog").waitForExistence(timeout: 5))
        attachScreenshot(named: "11-changelog")
    }

    /// Temporary: captures the four endurance-run states plus the English
    /// locale for the before/after comparison against the Android baseline.
    func testTempShotsGradesBaseline() throws {
        let base = ["-ui-testing-reset", "-ui-testing-authenticated"]
        let configurations: [(name: String, arguments: [String])] = [
            ("01-grades-recorded", base),
            ("02-grades-exempt", base + ["-ui-testing-endurance-exempt"]),
            ("03-grades-absent", base + ["-ui-testing-endurance-absent"]),
            ("04-grades-unrecorded", base + ["-ui-testing-endurance-unrecorded"]),
            ("05-grades-en", base + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        ]

        for configuration in configurations {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = configuration.arguments
            app.launch()

            XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 8), configuration.name)
            tabButton("tab.grades").tap()
            XCTAssertTrue(screen("screen.grades").waitForExistence(timeout: 5), configuration.name)
            attachScreenshot(named: configuration.name)
        }
    }

    func testStudentShellSmokeFlow() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        for identifier in Self.tabIdentifiers {
            XCTAssertTrue(
                app.buttons[identifier].waitForExistence(timeout: 5),
                "Tab bar lost its accessibility identifier: \(identifier)"
            )
        }
        XCTAssertTrue(app.staticTexts["体育学时进度"].exists)
        XCTAssertTrue(app.staticTexts["学时构成"].exists)

        openTab(label: "课程", screenIdentifier: "screen.courses")
        XCTAssertTrue(app.staticTexts["我的课程"].waitForExistence(timeout: 3))

        openTab(label: "打卡", screenIdentifier: "screen.checkin")
        XCTAssertTrue(app.staticTexts["本次运动"].waitForExistence(timeout: 3))

        openTab(label: "运动进度", screenIdentifier: "screen.grades")
        XCTAssertTrue(app.staticTexts["体测与打卡"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["打卡学时"].exists)
        // §1.4: teacher-side grading rules never reach the student view.
        XCTAssertFalse(app.staticTexts["总分预估"].exists)
        XCTAssertFalse(app.staticTexts["总分计算"].exists)

        openTab(label: "我的", screenIdentifier: "screen.profile")
        XCTAssertTrue(app.staticTexts["常用服务"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["组织认证与抵扣记录"].exists)
        assertProfileNavigationCardsAligned()
    }

    /// The startup gates run in Android's order: privacy consent, then the
    /// first-launch course guide, then the sign-in page.
    func testStartupGatesRunConsentThenCourseGuideBeforeLogin() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-startup-gates",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        XCTAssertTrue(screen("screen.privacy.consent").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["开始使用前，请确认"].exists)
        XCTAssertTrue(app.staticTexts["我们如何处理你的信息"].exists)

        app.buttons["privacy.consent.full-policy"].tap()
        XCTAssertTrue(app.buttons["privacy.consent.policy.back"].waitForExistence(timeout: 3))
        app.buttons["privacy.consent.policy.back"].tap()

        app.buttons["privacy.consent.agree"].tap()

        XCTAssertTrue(screen("screen.guide.pre-login").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["先加入课程"].exists)
        app.buttons["guide.next"].tap()
        XCTAssertTrue(app.staticTexts["确认并提交申请"].waitForExistence(timeout: 3))
        app.buttons["guide.skip"].tap()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))

        // Consent and the guide are recorded per device, so a relaunch goes
        // straight to sign-in.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-startup-gates", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        XCTAssertFalse(screen("screen.privacy.consent").exists)
    }

    /// Settings, account details, about, and the changelog are separate pages
    /// reached from the profile header, matching Android's navigation.
    func testProfileHeaderOpensAccountDetailsAndSettingsPages() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        openTab(label: "我的", screenIdentifier: "screen.profile")

        // The profile tab itself no longer carries the settings block.
        XCTAssertFalse(app.staticTexts["外观模式"].exists)

        app.buttons["profile.accountDetails.button"].tap()
        XCTAssertTrue(screen("screen.accountDetails").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["账户资料"].exists)
        XCTAssertTrue(app.staticTexts["入学年份"].exists)
        app.buttons["nav.back"].firstMatch.tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 3))

        app.buttons["profile.settings.button"].tap()
        XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["账户与安全"].exists)
        XCTAssertTrue(app.staticTexts["偏好设置"].exists)
        XCTAssertTrue(app.staticTexts["帮助与支持"].exists)

        scrollToAndTap(app.buttons["settings.about"])
        XCTAssertTrue(screen("screen.about").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["BNBU 体育"].exists)

        app.buttons["about.changelog"].tap()
        XCTAssertTrue(screen("screen.changelog").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["首个可用版本"].exists)
    }

    func testSystemLanguageChineseUpdatesCoreNavigation() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        XCTAssertEqual(tabButton("tab.dashboard").label, "首页")
        XCTAssertEqual(tabButton("tab.courses").label, "课程")
        XCTAssertEqual(tabButton("tab.checkin").label, "打卡")
        XCTAssertEqual(tabButton("tab.grades").label, "运动进度")
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
        XCTAssertEqual(tabButton("tab.grades").label, "Progress")
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
        for title in ["Fitness & check-ins", "Check-in hours"] {
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 2),
                "Missing localized grade text: \(title)"
            )
        }
        XCTAssertTrue(app.staticTexts["Endurance run time"].exists)
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
        for label in ["Started", "Projected Hours", "End Time", "Eligible Hours"] {
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
        XCTAssertEqual(tabButton("tab.grades").label, "Progress")
        XCTAssertEqual(tabButton("tab.profile").label, "Profile")
    }

    func testManualLanguageSwitchUpdatesNavigationWithoutRelaunch() throws {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        openTab(label: "我的", screenIdentifier: "screen.profile")
        app.buttons["profile.settings.button"].tap()
        XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 3))

        let englishSegment = app.buttons["English"]
        for _ in 0..<6 where !englishSegment.waitForExistence(timeout: 0.5) {
            app.swipeUp()
        }
        XCTAssertTrue(englishSegment.waitForExistence(timeout: 2))
        englishSegment.tap()

        // The tab bar sits behind the settings sheet, so it has to be dismissed
        // before the navigation labels can be read.
        app.buttons["nav.back"].firstMatch.tap()
        XCTAssertTrue(screen("screen.profile").waitForExistence(timeout: 3))

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
        XCTAssertEqual(tabButton("tab.grades").label, "Progress")
        XCTAssertEqual(tabButton("tab.profile").label, "Profile")
    }

    func testSubmitDraftAndSubmittedRecordFlow() throws {
        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")

        app.buttons["运动"].firstMatch.tap()

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
        XCTAssertFalse(app.staticTexts["待审核"].exists)
        // Android's record card summarises the session instead of badging it.
        XCTAssertTrue(app.staticTexts["计入学时"].exists)
        XCTAssertTrue(app.staticTexts["运动凭证"].exists)
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
        XCTAssertTrue(app.staticTexts["记录中"].waitForExistence(timeout: 5))

        // The launch fixture seeds one hidden draft without exposing a debug
        // capture control in the user interface.
        XCTAssertFalse(app.buttons["checkin.capture.demo"].exists)
        XCTAssertTrue(app.staticTexts["照片 1/6"].waitForExistence(timeout: 3))

        // Pause freezes the timer; resume brings the session back.
        scrollToAndTap(app.buttons["checkin.exercise.pause"])
        XCTAssertTrue(app.staticTexts["已暂停"].waitForExistence(timeout: 3))
        scrollToAndTap(app.buttons["checkin.exercise.resume"])
        XCTAssertTrue(app.staticTexts["记录中"].waitForExistence(timeout: 3))

        // Business rule 5.6: ending always passes the anti-mistap dialog
        // first;「取消」returns to the running session with the timer intact.
        let endAlert = app.alerts["结束运动"]
        scrollToAndTap(app.buttons["checkin.exercise.end"])
        XCTAssertTrue(endAlert.waitForExistence(timeout: 3))
        endAlert.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["记录中"].waitForExistence(timeout: 3))

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
        app.buttons["运动"].firstMatch.tap()

        scrollToAndTap(app.buttons["跑步"])
        scrollToAndTap(app.buttons["checkin.exercise.start"])
        XCTAssertTrue(app.staticTexts["记录中"].waitForExistence(timeout: 5))

        // Interruption monitors only fire on interaction; nudge the app while
        // polling so the permission alert gets answered, then wait for the
        // fix to attach and render in the session detail rows.
        let attached = app.staticTexts["已获取位置"]
        for _ in 0..<12 where !attached.exists {
            app.staticTexts["记录中"].firstMatch.tap()
            _ = attached.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(attached.exists, "开始运动后应附加一次 GPS 定位并显示“已获取位置”")
    }

    func testSubmittedHistoryNoticeReadAndLogoutFlow() throws {
        login()
        openTab(label: "打卡", screenIdentifier: "screen.checkin")

        app.buttons["记录"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["打卡记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["计入学时"].firstMatch.waitForExistence(timeout: 3))
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
        // Signing out now lives on the separate settings page reached from the
        // gear button, matching Android's `ProfileSettingsScreen`.
        app.buttons["profile.settings.button"].tap()
        XCTAssertTrue(screen("screen.profileSettings").waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts["本次运动"].waitForExistence(timeout: 3))

        openTab(label: "我的", screenIdentifier: "screen.profile")
        XCTAssertTrue(app.staticTexts["暂无认证记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["常用服务"].exists)
    }

    // Joining a course is offered on the sign-in screen only; the courses tab
    // lists courses and carries no join or application entry.
    func testCourseJoinLivesOnTheSignInScreenOnly() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        app.staticTexts["扫码加入课程"].firstMatch.tap()

        XCTAssertTrue(screen("screen.courseJoin").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["course.join.scan"].exists)

        let codeField = app.textFields["course.join.code.field"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        let next = app.buttons["course.join.submit"]
        XCTAssertFalse(next.isEnabled)

        codeField.tap()
        codeField.typeText("BNBU2026")
        XCTAssertTrue(next.isEnabled)
        next.tap()

        // The invite resolves to a course the student confirms before typing
        // any identity details.
        XCTAssertTrue(screen("screen.courseJoinConfirm").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["确认课程信息"].exists)
        XCTAssertTrue(app.staticTexts["PE1024 / Section S02"].exists)
        XCTAssertTrue(app.staticTexts["陈老师"].exists)

        let submit = app.buttons["courseJoinConfirm.submit"]
        submit.tap()
        XCTAssertTrue(app.staticTexts["请填写姓名。"].waitForExistence(timeout: 3))

        focusAndType(app.textFields["courseJoinConfirm.name"], text: "林同学")
        submit.tap()
        XCTAssertTrue(app.staticTexts["请填写学号。"].waitForExistence(timeout: 3))

        // The email is optional, so name and student ID are enough to apply.
        XCTAssertTrue(app.textFields["courseJoinConfirm.email"].exists)
        focusAndType(app.textFields["courseJoinConfirm.studentNumber"], text: "2400987654")
        submit.tap()

        // Submitting lands on the review status; only approval opens the app.
        XCTAssertTrue(screen("screen.joinRequestStatus").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["申请状态：待教师审核"].exists)
        app.buttons["nav.back"].tap()

        // The sign-in screen reports the application until a teacher decides.
        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["login.joinRequest.entry"].waitForExistence(timeout: 3))

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["dashboard.join.scan"].exists)
        XCTAssertFalse(app.buttons["dashboard.joinRequest.entry"].exists)

        openTab(label: "课程", screenIdentifier: "screen.courses")
        XCTAssertFalse(app.buttons["courses.join.entry"].exists)
        XCTAssertFalse(app.buttons["courses.joinRequest.entry"].exists)
        XCTAssertFalse(app.staticTexts["加入新课程"].exists)
    }

    func testLoginPrivacyAndEnduranceEntryFlow() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["login.email"].exists)
        XCTAssertTrue(app.buttons["login.phone"].exists)
        XCTAssertFalse(app.buttons["login.password.route"].exists)
        XCTAssertTrue(app.buttons["login.recoveryRequest"].exists)

        app.buttons["login.email"].tap()
        XCTAssertTrue(screen("screen.login.email").waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["verification.contact"].exists)
        XCTAssertTrue(app.textFields["verification.code"].exists)
        app.buttons["nav.back"].tap()

        XCTAssertTrue(screen("screen.login").waitForExistence(timeout: 3))
        app.buttons["login.recoveryRequest"].tap()
        XCTAssertTrue(screen("screen.recoveryRequest").waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["recovery.submit"].isEnabled)
        app.buttons["nav.back"].tap()

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-authenticated", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
        openTab(label: "我的", screenIdentifier: "screen.profile")
        scrollToAndTap(app.buttons["profile.endurance.button"])
        XCTAssertTrue(app.buttons["开始换算"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["测试项目：800m"].exists)
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
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-login-password",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
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
        XCTAssertTrue(app.staticTexts["本次运动"].waitForExistence(timeout: 5))
        app.buttons["记录"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["打卡记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["计入学时"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["待审核"].exists)
        attachScreenshot(named: "remote-records")

        openTab(label: "运动进度", screenIdentifier: "screen.grades")
        XCTAssertTrue(app.staticTexts["成绩进度"].waitForExistence(timeout: 5))
        attachScreenshot(named: "remote-grades")

        openTab(label: "我的", screenIdentifier: "screen.profile")
        XCTAssertTrue(app.staticTexts["常用服务"].waitForExistence(timeout: 5))
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
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-login-password",
            "-ui-testing-remote-completed-exercise",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
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
        app.buttons["运动"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["本次运动"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["计入学时"].firstMatch.waitForExistence(timeout: 10))
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
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-login-password",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
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

    /// Tab bar order, used for the positional fallback below.
    private static let tabIdentifiers = [
        "tab.dashboard",
        "tab.courses",
        "tab.checkin",
        "tab.grades",
        "tab.profile"
    ]

    private func openTab(label: String, screenIdentifier: String) {
        let identifier: String
        switch label {
        case "首页": identifier = "tab.dashboard"
        case "课程": identifier = "tab.courses"
        case "打卡": identifier = "tab.checkin"
        case "运动进度": identifier = "tab.grades"
        default: identifier = "tab.profile"
        }
        tabButton(identifier).tap()
        XCTAssertTrue(screen(screenIdentifier).waitForExistence(timeout: 3))
    }

    /// The native tab bar publishes its accessibility identifiers slightly after
    /// the first tab's content appears, and after an in-process relaunch it
    /// sometimes republishes the items without them at all. Wait for the
    /// identifier, then fall back to the tab's fixed position, which stays
    /// correct in every interface language.
    private func tabButton(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: timeout) {
            return button
        }
        let index = Self.tabIdentifiers.firstIndex(of: identifier) ?? 0
        let positional = app.tabBars.buttons.element(boundBy: index)
        XCTAssertTrue(positional.waitForExistence(timeout: timeout), identifier)
        return positional
    }

    private func login() {
        XCTAssertTrue(screen("screen.dashboard").waitForExistence(timeout: 5))
    }

    private func acceptPrivacyIfNeeded() {
        let consent = app.buttons["login.privacy.consent"]
        guard consent.waitForExistence(timeout: 0.5) else { return }
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
        // Android renders the two service entries as an equal-width pair on one row.
        XCTAssertEqual(exemptionCard.frame.minY, enduranceCard.frame.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(exemptionCard.frame.width, enduranceCard.frame.width, accuracy: 1, file: file, line: line)
        XCTAssertLessThan(exemptionCard.frame.maxX, enduranceCard.frame.minX + 1, file: file, line: line)
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

private extension UIImage {
    /// Mean luminance, so a palette check does not depend on exact colours.
    var averageBrightness: CGFloat? {
        guard let cgImage else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return 0.299 * CGFloat(pixel[0]) / 255
            + 0.587 * CGFloat(pixel[1]) / 255
            + 0.114 * CGFloat(pixel[2]) / 255
    }
}
