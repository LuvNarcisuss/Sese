import UIKit
import StoreKitTest
import XCTest

final class PullRefreshAcceptanceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testShortsRefreshOrderAndContinuousPaging() {
        let app = signedInApp()
        let title = app.staticTexts["shorts.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let first = title.label
        app.buttons["Search shorts"].tap()
        let results = app.scrollViews["shorts.search.results"]
        XCTAssertTrue(results.buttons[first].waitForExistence(timeout: 10))
        let filters = Set(["All", "Clips", "Cosplay", "Saved"])
        let available = Set(results.buttons.allElementsBoundByIndex.map(\.label)).subtracting(filters)
        XCTAssertGreaterThan(available.count, 1)
        app.buttons["Cancel"].tap()

        var seen: Set<String> = [first]
        for _ in 1..<available.count {
            refresh(app, on: app, name: "Shorts rotation")
            XCTAssertTrue(seen.insert(title.label).inserted)
        }
        XCTAssertEqual(seen, available)
        let last = title.label
        refresh(app, on: app, name: "Shorts next round")
        XCTAssertNotEqual(title.label, last)

        let start = title.label
        var lap: Set<String> = [start]
        for step in 1...(available.count * 2) {
            let previous = title.label
            app.swipeUp()
            let advanced = NSPredicate(format: "exists == true AND label != %@", previous)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advanced, object: title)],
                                          timeout: 10), .completed)
            if step.isMultiple(of: available.count) {
                XCTAssertEqual(title.label, start)
                XCTAssertEqual(lap, available)
                lap = [start]
            } else {
                XCTAssertTrue(lap.insert(title.label).inserted)
            }
        }
        app.swipeUp()
        let later = title.label
        XCTAssertNotEqual(later, start)
        refresh(app, on: app, name: "Shorts pull from a later clip")
        XCTAssertNotEqual(title.label, later)
    }

    func testSingleFilteredShortKeepsPlayingOnRefresh() throws {
        let app = signedInApp()
        app.buttons["Search shorts"].tap()
        let results = app.scrollViews["shorts.search.results"]
        results.buttons["Clips"].tap()
        let filters = Set(["All", "Clips", "Cosplay", "Saved"])
        let clips = Set(results.buttons.allElementsBoundByIndex.map(\.label)).subtracting(filters)
        try XCTSkipUnless(clips.count == 1, "This case needs exactly one visible film clip.")
        let onlyClip = try XCTUnwrap(clips.first)
        app.buttons["Cancel"].tap()
        app.buttons["Filter shorts"].tap()
        app.otherElements["dialog.Filter shorts"].buttons["Film Clip"].tap()
        let title = app.staticTexts["shorts.title"].firstMatch
        XCTAssertEqual(title.label, onlyClip)
        refresh(app, on: app, name: "Single filtered short")
        XCTAssertEqual(title.label, onlyClip)
        app.swipeUp()
        XCTAssertEqual(title.label, onlyClip)
        let before = videoRegion(app)
        XCTAssertNotNil(before)
        let advances = NSPredicate { _, _ in
            guard let frame = self.videoRegion(app) else { return false }
            return frame != before
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advances, object: nil)],
                                      timeout: 15), .completed)
    }

    func testShortsPublisherSearchAndCommentsRefresh() throws {
        let app = signedInApp()
        refresh(app, on: app, name: "Shorts")
        refresh(app, on: app, name: "Shorts repeated")
        app.buttons["shorts.publisher"].tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 10))
        refresh(app, name: "Publisher profile")
        app.buttons["More options"].tap()
        XCTAssertTrue(app.otherElements["dialog.Profile options"].buttons["Report user"].exists)
        XCTAssertTrue(app.otherElements["dialog.Profile options"].buttons["Block user"].exists)
        app.otherElements["dialog.Profile options"].buttons["Cancel"].tap()
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

        let done = app.buttons["Done"]
        let halfHeightTop = done.frame.minY
        func openAuthorAndReturn(using identifier: String) throws {
            let author = try XCTUnwrap(app.buttons.matching(identifier: identifier).allElementsBoundByIndex.first { $0.isHittable })
            author.tap()
            let title = app.staticTexts["Profile"]
            XCTAssertTrue(title.waitForExistence(timeout: 8))
            XCTAssertLessThan(title.frame.minY, app.frame.height * 0.2)
            XCTAssertFalse(done.exists && done.isHittable)
            app.buttons["Back"].tap()
            XCTAssertTrue(done.waitForExistence(timeout: 8))
        }
        try openAuthorAndReturn(using: "comment.author.avatar")
        let restored = NSPredicate { _, _ in done.isHittable && abs(done.frame.minY - halfHeightTop) < 8 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: done)], timeout: 5), .completed)
        discussion.swipeUp()
        let expanded = NSPredicate { _, _ in done.isHittable && done.frame.minY < halfHeightTop - 100 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expanded, object: done)], timeout: 5), .completed)
        try openAuthorAndReturn(using: "comment.author.name")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expanded, object: done)], timeout: 5), .completed)
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
            app.otherElements["dialog.Filter"].buttons[scope].tap()
            refresh(app, name: "Cosplay \(scope)")
        }
        app.buttons["Open Judy and Nick at Anime Expo"].tap()
        refresh(app, name: "Catalog detail")
        app.buttons["Back"].tap()
        app.tabBars.buttons["Chats"].tap()
        refresh(app, name: "Chats friends")
        for scope in ["Conversations", "Archived", "Friends"] {
            app.buttons["Conversation filters"].tap()
            app.otherElements["dialog.Chats"].buttons[scope].tap()
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
        app.otherElements["dialog.Members"].buttons["Following"].tap()
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
        if surface === app {
            start.press(forDuration: 0.15, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0)
        } else {
            start.press(forDuration: 0.15, thenDragTo: finish)
        }
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
