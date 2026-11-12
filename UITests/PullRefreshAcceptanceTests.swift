import UIKit
import StoreKitTest
import XCTest

final class PullRefreshAcceptanceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testShortsCreatorSearchAndCommentsRefresh() {
        let app = signedInApp()
        refresh(app, on: app, name: "Shorts")
        refresh(app, on: app, name: "Shorts repeated")
        app.buttons["shorts.creator"].tap()
        XCTAssertTrue(app.staticTexts["Creator"].waitForExistence(timeout: 10))
        refresh(app, name: "Creator")
        app.buttons["Back"].tap()
        app.buttons["shorts.comments"].tap()
        XCTAssertTrue(app.staticTexts["comments.total"].waitForExistence(timeout: 10))
        let total = app.staticTexts["comments.total"]
        let loaded = NSPredicate(format: "label MATCHES %@", "[0-9]+ comments")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: total)], timeout: 15), .completed)
        let count = total.label
        let discussion = app.scrollViews["page.scroll"].firstMatch
        let visible = NSPredicate { _, _ in discussion.exists && discussion.frame.height > 150 && discussion.frame.maxY <= app.frame.maxY }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: discussion)], timeout: 8), .completed)
        for attempt in 1...3 {
            refresh(app, name: "Comments \(attempt)", startY: 0.22, endY: 0.96)
            XCTAssertEqual(app.staticTexts["comments.total"].label, count)
        }
        XCTAssertGreaterThan(discussion.frame.minY, app.frame.height * 0.4)
        let before = videoRegion(app)
        let elapsed = expectation(description: "Playback advances behind the discussion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 4)
        XCTAssertNotEqual(before, videoRegion(app), "Video frames must advance while the discussion remains open.")
        XCTAssertEqual(app.staticTexts["comments.total"].label, count)
        XCTAssertTrue(app.staticTexts["comment.body"].firstMatch.exists)
        app.buttons["Done"].tap()
        app.buttons["Search shorts"].tap()
        let field = app.textFields["Search shorts"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("fox")
        refresh(app, on: app.scrollViews["shorts.search.results"], name: "Shorts search")
        XCTAssertEqual(field.value as? String, "fox")
        XCTAssertLessThanOrEqual(app.staticTexts["refresh.status"].frame.maxY, app.buttons["All"].firstMatch.frame.minY)
        app.buttons["Cancel"].tap()
        app.buttons["Community videos"].tap()
        XCTAssertTrue(app.staticTexts["Community videos"].waitForExistence(timeout: 10))
        refresh(app, name: "Community videos")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["shorts.like"].isHittable)
    }

    func testDistrictMapAndPlacesRefresh() {
        let app = signedInApp()
        app.tabBars.buttons["Districts"].tap()
        refresh(app, name: "Districts")
        app.buttons["Explore district"].tap()
        refresh(app, name: "District exploration")
        let street = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", Street")).firstMatch
        XCTAssertTrue(street.exists)
        street.tap()
        refresh(app, name: "District place")
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        refresh(app, name: "Districts return")
    }

    func testCosplayChatsAndMembersRefresh() {
        let app = signedInApp()
        app.tabBars.buttons["Cosplay"].tap()
        refresh(app, name: "Cosplay all")
        for scope in ["My posts", "Community", "Cosplay Look"] {
            app.buttons["Filter"].tap()
            app.sheets.buttons[scope].tap()
            refresh(app, name: "Cosplay \(scope)")
        }
        app.buttons["Open Judy and Nick at Anime Expo"].tap()
        refresh(app, name: "Catalog detail")
        app.buttons["Back"].tap()
        app.tabBars.buttons["Chats"].tap()
        refresh(app, name: "Chats friends")
        for scope in ["Conversations", "Archived", "Friends"] {
            app.buttons["Conversation filters"].tap()
            app.sheets.buttons[scope].tap()
            refresh(app, name: "Chats \(scope)")
        }
        app.buttons["Find friends"].firstMatch.tap()
        refresh(app, name: "Members")
        let profile = app.scrollViews["page.scroll"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Open ", "profile")).firstMatch
        if profile.exists {
            profile.tap()
            refresh(app, name: "Member profile")
            app.buttons["Back"].tap()
        } else {
            print("No discoverable member is available for the member-profile route.")
        }
        app.buttons["Filter members"].tap()
        app.sheets.buttons["Following"].tap()
        refresh(app, name: "Members following")
    }

    func testProfileCollectionsWalletAndSettingsListsRefresh() throws {
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SeseDiamonds", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: configuration)
        let transactionCount = store.allTransactions().count
        let app = signedInApp()
        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.buttons["Wallet & top up"].waitForExistence(timeout: 15))
        refresh(app, name: "Me shorts")
        for category in ["Cosplay", "Liked", "Saved", "Shorts"] {
            app.scrollViews["page.scroll"].buttons[category].firstMatch.tap()
            refresh(app, name: "Me \(category)")
        }
        app.buttons["Wallet & top up"].tap()
        XCTAssertTrue(app.staticTexts["wallet.balance"].waitForExistence(timeout: 10))
        let balance = app.staticTexts["wallet.balance"].label
        refresh(app, name: "Wallet")
        XCTAssertEqual(app.staticTexts["wallet.balance"].label, balance)
        XCTAssertEqual(store.allTransactions().count, transactionCount)
        app.buttons["Back"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Blocked members"].tap()
        refresh(app, name: "Blocked members")
        app.buttons["Back"].tap()
        app.buttons["Media credits"].tap()
        refresh(app, name: "Media credits")
        refresh(app, name: "Media credits repeated")
    }

    private func videoRegion(_ app: XCUIApplication) -> Data? {
        guard let image = app.screenshot().image.cgImage else { return nil }
        let region = CGRect(x: CGFloat(image.width) * 0.25, y: CGFloat(image.height) * 0.2,
                            width: CGFloat(image.width) * 0.5, height: CGFloat(image.height) * 0.15)
        return image.cropping(to: region).flatMap { UIImage(cgImage: $0).pngData() }
    }

    private func signedInApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let entry = app.buttons["entry.oneTapSignIn"]
        if entry.waitForExistence(timeout: 8) {
            let consent = app.buttons["entry.consent"]
            if consent.value as? String == "Unchecked" { consent.tap() }
            entry.tap()
        }
        XCTAssertTrue(app.buttons["shorts.like"].waitForExistence(timeout: 25))
        return app
    }

    private func refresh(_ app: XCUIApplication, on surface: XCUIElement? = nil, name: String,
                         startY: CGFloat = 0.12, endY: CGFloat = 0.78,
                         file: StaticString = #filePath, line: UInt = #line) {
        let status = app.staticTexts["refresh.status"].firstMatch
        let previous = status.exists ? (status.value as? String ?? "") : ""
        let area = surface ?? app.scrollViews["page.scroll"].firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 10), name, file: file, line: line)
        print("Refresh area \(name): \(area.frame), app: \(app.frame)")
        let start = area.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: surface === app ? 0.25 : startY))
        let finish = area.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: surface === app ? 0.65 : endY))
        start.press(forDuration: 0.15, thenDragTo: finish)
        let updated = NSPredicate(format: "exists == true AND value BEGINSWITH %@ AND value != %@", "success:", previous)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated, object: status)], timeout: 30)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Refresh \(name)"
        capture.lifetime = .keepAlways
        add(capture)
        XCTAssertEqual(result, .completed, "\(name): \(status.exists ? status.label : "No refresh feedback")", file: file, line: line)
        print("Refresh verified: \(name), \(status.value as? String ?? "unavailable")")
    }
}
