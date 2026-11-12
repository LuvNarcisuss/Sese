# Simulator acceptance

Use the `Sese` scheme and `Sese UI Acceptance` (iPhone 17 Pro, device `0E1EA5DB-DDE2-460C-A8C9-C5E400CF1B96`). The earlier runs below record the names used at the time.

## StoreKit purchase acceptance

On November 12, 2026, Xcode 26.0.1 built the current `Sese` Debug app and UI test runner for `Sese UI Acceptance` (iPhone 17 Pro, iOS 26.0.1). The app used Bundle ID `im.seex.sao2` and ad hoc simulator signing. The app was installed and launched before XCTest, and its executable, debug library, and Info.plist matched the current build after the run.

`WalletPurchaseTests.testLocalStoreKitPurchasesPersist` passed on the designated simulator with parallel testing disabled. One test executed with zero failures or skips. All nine localized prices matched the configured USD prices. Canceling the app confirmation preserved the balance and transaction count. The nine completed purchases credited exactly 172,500 diamonds, and the balance remained 172,500 after relaunch. The current build was relaunched and left running on the welcome screen after XCTest.

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
