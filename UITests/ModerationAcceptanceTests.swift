#if DEBUG && targetEnvironment(simulator) && SESE_SAFETY_ACCEPTANCE
import XCTest

final class ModerationAcceptanceTests: XCTestCase {
    private let author = "15000000-0000-4000-8000-000000000002"
    private let reportedVideo = "Paper costume"
    private let otherByAuthor = "Midnight mask"
    private let unrelated = "Plaza dance"

    override func setUpWithError() throws { continueAfterFailure = false }

    func testUnblockPreservesReportUntilWithdrawn() {
        exercise(unblockFirst: true)
    }

    func testWithdrawReportPreservesBlockUntilUnblocked() {
        exercise(unblockFirst: false)
    }

    func testCommentReportUpdatesThreadAndCanBeWithdrawn() {
        let app = XCUIApplication()
        app.launchArguments = ["-ModerationAcceptance", "-PublicCommentAuthor", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let entry = app.buttons["entry.moderationAcceptance"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.buttons["entry.consent"].tap()
        entry.tap()
        app.buttons["Search shorts"].tap()
        let results = app.scrollViews["shorts.search.results"]
        let clip = results.buttons[unrelated]
        XCTAssertTrue(clip.waitForExistence(timeout: 10))
        clip.tap()
        app.buttons["shorts.comments"].tap()
        let commentMenu = app.buttons["Comment options"].firstMatch
        XCTAssertTrue(commentMenu.waitForExistence(timeout: 10))
        commentMenu.tap()
        app.otherElements["dialog.Comment options"].buttons["Report author"].tap()
        let userReasons = app.otherElements["dialog.Report user"]
        let namedAccount = NSPredicate(format: "label BEGINSWITH %@", "Night Weaver")
        XCTAssertTrue(userReasons.staticTexts.matching(namedAccount).firstMatch.waitForExistence(timeout: 5))
        tapSettled(userReasons.buttons["Spam"])
        let userResult = app.otherElements["dialog.User reported."]
        XCTAssertTrue(userResult.staticTexts.matching(namedAccount).firstMatch.waitForExistence(timeout: 10))
        userResult.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Midnight costume rehearsal."].exists)

        commentMenu.tap()
        app.otherElements["dialog.Comment options"].buttons["Block author"].tap()
        tapSettled(app.otherElements["dialog.Block Night Weaver?"].buttons["Cancel"])
        commentMenu.tap()
        app.otherElements["dialog.Comment options"].buttons["Report comment"].tap()
        let reasons = app.otherElements["dialog.Report comment"]
        let excerpt = "“Midnight costume rehearsal.”"
        XCTAssertTrue(reasons.staticTexts[excerpt].waitForExistence(timeout: 5))
        tapSettled(reasons.buttons["Spam"])
        let saved = app.otherElements["dialog.Comment reported."]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.staticTexts[excerpt].exists)
        saved.buttons["OK"].tap()
        XCTAssertEqual(app.staticTexts["comments.total"].label, "0 comments")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts[unrelated].exists)
        app.tabBars.buttons["Me"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Reported comments"].tap()
        let record = app.buttons["safety.comment.comment:15000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.label.contains("Midnight costume rehearsal."))
        record.press(forDuration: 1)
        app.buttons["Withdraw report"].firstMatch.tap()
        app.otherElements["dialog.Withdraw report?"].buttons["Withdraw report"].tap()
        XCTAssertTrue(app.staticTexts["No reported comments"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Shorts"].tap()
        app.buttons["shorts.comments"].tap()
        XCTAssertTrue(app.staticTexts["Midnight costume rehearsal."].waitForExistence(timeout: 10))
    }

    private func exercise(unblockFirst: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-ModerationAcceptance", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        // An ordinary build has no such entry point. Never drive a production account.
        let fixtureEntry = app.buttons["entry.moderationAcceptance"]
        XCTAssertTrue(fixtureEntry.waitForExistence(timeout: 10))
        app.buttons["entry.consent"].tap()
        fixtureEntry.tap()
        let options = app.buttons["Video options"].firstMatch
        XCTAssertTrue(app.staticTexts[reportedVideo].waitForExistence(timeout: 10))
        options.tap()
        app.otherElements["dialog.Video options"].buttons["Report video"].tap()
        let reasons = app.otherElements["dialog.Report video"]
        let reason = reasons.buttons["Harassment"]
        tapSettled(reason)
        XCTAssertTrue(reasons.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[unrelated].waitForExistence(timeout: 10))
        let submitted = app.otherElements["dialog.Video reported."]
        XCTAssertTrue(submitted.waitForExistence(timeout: 10))
        submitted.buttons["OK"].tap()
        verifyVideos(app, reported: false, other: true)

        app.buttons["shorts.comments"].tap()
        let sheet = app.scrollViews["page.scroll"].firstMatch
        let block = sheet.buttons["Comment options"].firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10))
        if !block.isHittable { sheet.swipeUp() }
        block.tap()
        app.otherElements["dialog.Comment options"].buttons["Block author"].tap()
        app.otherElements["dialog.Block this member?"].buttons["Block"].tap()
        let success = app.otherElements["dialog.User blocked."]
        XCTAssertTrue(success.waitForExistence(timeout: 10))
        success.buttons["OK"].tap()
        XCTAssertFalse(sheet.exists)
        verifyVideos(app, reported: false, other: false)
        undo(app, unblock: unblockFirst)
        verifyVideos(app, reported: false, other: unblockFirst)
        undo(app, unblock: !unblockFirst)
        verifyVideos(app, reported: true, other: true)
    }

    // UIKit can publish the second action sheet's AX tree while the first sheet is still dismissing.
    private func tapSettled(_ button: XCUIElement) {
        var lastFrame = CGRect.null
        var settledSince = Date()
        let stable = NSPredicate { _, _ in
            guard button.exists, button.isHittable else { settledSince = Date(); return false }
            let frame = button.frame
            if frame != lastFrame { lastFrame = frame; settledSince = Date(); return false }
            return Date().timeIntervalSince(settledSince) >= 0.5
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stable, object: nil)], timeout: 8), .completed)
        button.tap()
    }

    private func verifyVideos(_ app: XCUIApplication, reported: Bool, other: Bool) {
        app.tabBars.buttons["Shorts"].tap()
        app.buttons["Search shorts"].tap()
        let results = app.scrollViews["shorts.search.results"].firstMatch
        XCTAssertTrue(results.buttons[unrelated].waitForExistence(timeout: 10))
        let expected = NSPredicate { _, _ in
            results.buttons[self.reportedVideo].exists == reported && results.buttons[self.otherByAuthor].exists == other
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: nil)], timeout: 8), .completed)
        app.buttons["Cancel"].firstMatch.tap()
    }

    private func undo(_ app: XCUIApplication, unblock: Bool) {
        app.tabBars.buttons["Me"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let list = unblock ? "Blocked members" : "Reported videos"
        app.buttons[list].tap()
        let id = unblock ? "safety.block." + author : "safety.report.catalog:paper"
        let row = app.buttons[id]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains(unblock ? "City Resident" : reportedVideo))
        row.press(forDuration: 1.0)
        let verb = unblock ? "Unblock" : "Withdraw report"
        let action = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", verb)).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        app.otherElements["dialog." + verb + "?"].buttons[verb].tap()
        let empty = unblock ? "No blocked members" : "No reported videos"
        XCTAssertTrue(app.staticTexts[empty].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
import XCTest

final class ReportedCoverAcceptanceTests: XCTestCase {
    func testExistingReportShowsCompactCoverAndUndoMenu() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let login = app.buttons["entry.oneTapSignIn"]
        if login.waitForExistence(timeout: 8) {
            let box = app.buttons["entry.consent"]
            if box.value as? String == "Unchecked" { box.tap() }
            login.tap()
        }
        let profile = app.tabBars.buttons["Me"]
        XCTAssertTrue(profile.waitForExistence(timeout: 40))
        profile.tap()
        app.buttons["Settings"].tap()
        app.buttons["Reported videos"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "safety.report."))
        if !cards.firstMatch.waitForExistence(timeout: 15) {
            try XCTSkipIf(app.staticTexts["No reported videos"].exists, "No existing reports on this account.")
            XCTFail("Report history did not load.")
            return
        }
        let congaLine = app.buttons["safety.report.catalog:narcon-conga-line"]
        let card = congaLine.exists ? congaLine : cards.firstMatch
        XCTAssertFalse(card.label.isEmpty)
        XCTAssertLessThan(card.frame.width, app.frame.width * 0.55)
        XCTAssertGreaterThan(card.frame.height, card.frame.width * 0.85)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Reported video cover grid"
        capture.lifetime = .keepAlways
        add(capture)
        card.press(forDuration: 1)
        let action = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Withdraw report")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        let confirm = app.otherElements["dialog.Withdraw report?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.buttons["Cancel"].tap()
        XCTAssertTrue(card.exists)
    }
}
#endif
