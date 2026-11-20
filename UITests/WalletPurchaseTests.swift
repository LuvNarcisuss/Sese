import StoreKit
import StoreKitTest
import XCTest

final class WalletPurchaseTests: XCTestCase {
    @MainActor
    func testLocalStoreKitPurchasesPersist() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SESE_STOREKIT_ACCEPTANCE"] == "1",
                          "Enable the local StoreKit acceptance run on the designated simulator.")
        continueAfterFailure = false
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SeseDiamonds", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        defer { session.resetToDefaultState() }

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        openWallet(in: app)

        let balance = app.staticTexts["wallet.balance"]
        var expectedBalance = try XCTUnwrap(Int(balance.label.replacingOccurrences(of: ",", with: "")))
        let originalTransactionCount = session.allTransactions().filter { $0.state == .purchased }.count
        let tiers = [(400, "$0.99"), (800, "$1.99"), (2450, "$4.99"), (5150, "$9.99"),
                     (10800, "$19.99"), (16900, "$29.99"), (29400, "$49.99"), (42900, "$69.99"), (63700, "$99.99")]

        let firstPack = app.buttons["wallet.package.400"]
        await expect(firstPack, matches: "enabled == true")
        firstPack.tap()
        let cancel = app.otherElements["dialog.Buy 400 diamonds?"].buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertEqual(balance.label, formatted(expectedBalance))
        XCTAssertEqual(session.allTransactions().filter { $0.state == .purchased }.count, originalTransactionCount)

        for (diamonds, price) in tiers {
            let pack = app.buttons["wallet.package.\(diamonds)"]
            await expect(pack, matches: "enabled == true")
            XCTAssertEqual(pack.value as? String, price)
            for _ in 0..<4 where !pack.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(pack.isHittable)
            pack.tap()
            let confirmation = app.otherElements["dialog.Buy \(diamonds.formatted()) diamonds?"]
            XCTAssertTrue(confirmation.buttons["Continue"].waitForExistence(timeout: 5))
            XCTAssertTrue(confirmation.staticTexts[price].exists)
            confirmation.buttons["Continue"].tap()
            expectedBalance += diamonds
            await expect(balance, matches: "label == %@", value: formatted(expectedBalance))
        }
        XCTAssertEqual(session.allTransactions().filter { $0.state == .purchased }.count, originalTransactionCount + tiers.count)

        app.terminate()
        openWallet(in: app)
        await expect(balance, matches: "label == %@", value: formatted(expectedBalance))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Wallet balance after relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func openWallet(in app: XCUIApplication) {
        app.launch()
        let consent = app.buttons["entry.consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 15))
        if consent.value as? String == "Unchecked" { consent.tap() }
        app.buttons["entry.oneTapSignIn"].tap()
        let profile = app.tabBars.buttons["Me"]
        XCTAssertTrue(profile.waitForExistence(timeout: 30))
        profile.tap()
        let wallet = app.buttons["Wallet & top up"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 20))
        wallet.tap()
        XCTAssertTrue(app.staticTexts["wallet.balance"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func expect(_ element: XCUIElement, matches format: String, value: String? = nil,
                        file: StaticString = #filePath, line: UInt = #line) async {
        let predicate = NSPredicate(format: format, argumentArray: value.map { [$0] })
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 30)
        XCTAssertEqual(result, .completed, "\(element.debugDescription) did not match \(predicate).", file: file, line: line)
    }

    private func formatted(_ amount: Int) -> String {
        amount.formatted(.number.locale(Locale(identifier: "en_US")))
    }
}
