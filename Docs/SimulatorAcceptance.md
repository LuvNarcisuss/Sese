# Simulator acceptance

Use the `Sese` scheme and `Sese QA` (iPhone 17 Pro). Resolve its local UDID by name and use that device for the build, installation and launch. The earlier runs below record the names used at the time.

On November 25, 2026, Xcode 26.3 built the current Debug app for the newly created `Sese QA` simulator (iPhone 17 Pro, iOS 26.3.1, UDID `B7B910B4-06F4-4B84-A392-B3131E44E5D0`). Installation and launch of `com.sese.citycommunit` succeeded. The running process was verified on that device. This run covered build, installation and launch.

## Stage B after console import

On November 25, 2026, the owner confirmed saving both templates for app `32948410`. The current Debug app was built and installed on Sese QA. The cold launch showed native Shorts. A serial UI check observed the app for 100 seconds and found native tabs with no external web view. A second check signed out through Settings, selected the agreement checkbox and tapped One-tap sign in. The app returned to the native tabs. Both checks failed their external-page acceptance condition.

Between 11:20 and 11:27:30 China Standard Time, the project logged two HTTP 200 responses from `community-entry` and zero calls to `diamond-settlement`. The native completion marker agrees with the visible route. In the deployed function, a successful preflight response without `data.communityPage` selects native entry. The external provider's response body was not captured. That first observation did not exercise external authentication, WebSocket attachment or page rendering. No checkout control was used.

## External login and page rendering on Sese QA

Later on November 25 the external service selected its web route. The app reproduced the reported “This item is no longer available.” error after consent. The iPhone client authenticated directly with the external service, connected to its WebSocket and received a channel attachment acknowledgement. Its first page event supplied a message identifier and an HTTPS destination, with no publisher identifier. The initial receiver rejected it and the login wait expired. The destination was byte-for-byte identical to the address in the same authenticated HTTPS response.

The receiver now accepts this confirmation once per login, using the current ticket and attached channel. An isolated regression run on Sese QA exercised the actual receiver with altered addresses, a different channel and generation, an explicit unknown sender, conflicting event types, repeated page notices, purchase, sign-out and external-link events. Only the first matching confirmation and a subsequent page from the configured publisher passed. The two console exports were regenerated and compared byte for byte with the imported files.

WebKit also supplied a normalized URL from an opaque source document when opening the initial page. The app now permits the app-initiated main-frame GET chain on its authorized HTTPS origin until the first document commits. The original WebKit rendering mode loaded the main document with HTTP 200, then its content process exited on this Intel simulator. Three separate system crash reports implicated JavaScriptCore. Applying WebKit's restricted mode to the `center.hkguimao.com` directory allowed it to display its live directory. The device-wide setting and other origins retain their usual preferences.

The final serial Sese QA UI check closed the restored web page, signed out through native Settings, selected consent and tapped One-tap sign in. The external origin bar and web view appeared. After a further 20 seconds both remained visible and the page had no load error. One case passed with zero failures. The rendered directory showed its All, Live, New and Follow sections. No external purchase, call, profile or checkout control was used. Hosted function logs recorded zero settlement calls from 11:29 through 11:49:30 China Standard Time.

## StoreKit purchase acceptance

On November 12, 2026, Xcode 26.0.1 built the `Sese` Debug app and UI test runner for `Sese UI Acceptance` (iPhone 17 Pro, iOS 26.0.1). This run used the temporary Bundle ID `im.seex.sao2` and ad hoc simulator signing. The app was installed and launched before XCTest, and its executable, debug library, and Info.plist matched that build after the run.

`WalletPurchaseTests.testLocalStoreKitPurchasesPersist` passed on the designated simulator with parallel testing disabled. One test executed with zero failures or skips. All nine localized prices matched the configured USD prices. Canceling the app confirmation preserved the balance and transaction count. The nine completed purchases credited exactly 172,500 diamonds, and the balance remained 172,500 after relaunch. The test build was relaunched and left running on the welcome screen after XCTest.

StoreKit Test used `Configuration/SeseDiamonds.storekit` with native payment dialogs disabled. Native payment sheet behavior, physical iPhone signing, Apple sandbox, and production purchases remain unverified.

## Sese name change

On November 12, 2026, Xcode 26.0.1 built `Sese.app` and `SeseUITests` for iOS 26.0.1. The app was installed over the previous build on the same simulator with the existing Bundle ID. The built app declared the display name `Sese`, the scene delegate `Sese.SceneDelegate`, and the iPhone device family. The three serial entry tests passed, covering required consent, consent revocation, and both agreement links. The installed executable and Info.plist matched the build byte for byte, and the app remained open on the welcome screen showing `Sese`.

## Vertically paged Shorts

On November 11, 2026, the current app and a separate loopback acceptance build compiled for `CityCommunity UI Acceptance` (iPhone 17 Pro, iOS 26.0.1). Two serial UI cases passed. The first publisher player reported that it was playing without a tap. The cases exercised upward and downward paging, publisher avatars, the Publisher videos filter, likes, saves, posting a comment, and opening the system share sheet. The acceptance account and social writes used the isolated database. The player streamed the original video from YouTube.

## Published agreements and live device sign-in

On November 11, 2026, Xcode 26.0.1 built the current workspace with the `CityCommunity` Debug scheme, installed it, and launched it on `CityCommunity UI Acceptance` (iPhone 17 Pro, iOS 26.0.1, device `0E1EA5DB-DDE2-460C-A8C9-C5E400CF1B96`). XCTest used the same device with parallel testing disabled. The installed executable, debug library, agreement configuration, and both PDFs matched the build byte for byte.

- The live sign-in case passed. First sign-in entered Shorts, signing out in Settings returned to the welcome screen, and a second sign-in on the same device entered Shorts again. The live backend started with zero device accounts. After the test it contained one device account created during the test, one profile, and one consent for the active agreement revision. The simulator's test account was retained.
- Both inline links opened their corresponding PDFs, and returning to the welcome screen left the consent box unchecked. The first combined run lost the agreement screen before its Back assertion. The unchanged link case passed on a separate serial rerun with zero failures and zero skips. Screenshots confirmed the contents of both PDFs rendered in the app.
- After testing, the same installed build was relaunched and left running on the specified simulator. This run did not cover account deletion or physical iPhone behavior.

## Earlier device-based entry baseline

Xcode 26.0.1 built and installed the updated `CityCommunity` Debug app on `CityCommunity UI Acceptance` (iPhone 17 Pro, iOS 26.0.1). The serial XCTest run passed all three cases with zero failures. It verified that one-tap entry requires consent, consent can be revoked, and both inline agreement links open their respective bundled PDFs and return without selecting the checkbox. The links are exposed as links in the accessibility hierarchy.

This simulator run predated the [published agreement release](Backend/Deployment.md#published-agreements). It covered the signed-out UI and bundled PDFs.

## Initial Apple entry baseline (superseded)

On November 11, 2026, Xcode 26.0.1 built the earlier Apple entry with the shared `CityCommunity` scheme and local simulator signing. The destination was `CityCommunity UI Acceptance`, iPhone 17 Pro, iOS 26.0.1 (23A8464), device `0E1EA5DB-DDE2-460C-A8C9-C5E400CF1B96`. Xcode reported the same device in the test result. Parallel testing was disabled.

The app was installed and launched before the tests, and relaunched on the same device afterward. The installed executable and debug library matched the test build byte for byte. The built app declared device family `[1]` (iPhone only).

Three XCTest UI cases passed, with zero failures and zero skips:

- The Apple sign-in button requires consent, and the entry screen has no guest button.
- Consent can be selected and revoked before sign-in; revocation restores the consent requirement.
- Both bundled agreements open and return to sign-in. Simulator screenshots confirmed that the PDFs rendered.

The test build used cached upstream packages after GitHub transport failed. The Swift package lockfile records the resolved versions. Renaming the top-level bundle directory to `CommunityContent` resolved a code-signing failure without changing the resource files. The XcodeGen settings explicitly select iPhone at the app and test targets.

The baseline did not verify authentication, authenticated tabs, media playback, messaging, or purchases. The app now uses device-based sign-in. See the [current deployment record](Backend/Deployment.md).
