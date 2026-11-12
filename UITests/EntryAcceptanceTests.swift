import XCTest

final class EntryAcceptanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOneTapSignInRequiresConsent() {
        let app = launchWelcome()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "guest")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Apple")).firstMatch.exists)

        app.buttons["entry.oneTapSignIn"].tap()

        XCTAssertTrue(app.staticTexts["Agree to the Terms of Service and Privacy Policy to continue."].exists)
        XCTAssertTrue(app.buttons["entry.consent"].isHittable)
    }

    func testConsentCanBeRevokedBeforeSignIn() {
        let app = launchWelcome()
        let consent = app.buttons["entry.consent"]
        XCTAssertEqual(consent.value as? String, "Unchecked")
        consent.tap()
        XCTAssertEqual(consent.value as? String, "Checked")
        consent.tap()
        XCTAssertEqual(consent.value as? String, "Unchecked")

        app.buttons["entry.oneTapSignIn"].tap()

        XCTAssertTrue(app.staticTexts["Agree to the Terms of Service and Privacy Policy to continue."].exists)
    }

    func testTermsAndPrivacyOpenAndReturnToSignIn() {
        let app = launchWelcome()
        for title in ["Terms of Service", "Privacy Policy"] {
            let link = app.links[title].firstMatch
            XCTAssertTrue(link.isHittable, "Missing agreement link: \(title)")
            XCTAssertFalse(app.buttons[title].exists)
            link.tap()

            let back = app.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[title].exists)
            XCTAssertFalse(app.staticTexts["This document is unavailable."].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = title
            screenshot.lifetime = .keepAlways
            add(screenshot)

            back.tap()
            XCTAssertTrue(app.buttons["entry.oneTapSignIn"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["entry.consent"].value as? String, "Unchecked")
        }
    }

    private func launchWelcome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["The city is yours."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["entry.oneTapSignIn"].isHittable)
        return app
    }
}
