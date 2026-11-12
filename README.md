# Sese

Sese is an independent Zootopia fan community. The project uses UIKit, Swift 5 and AVFoundation on portrait iPhones with iOS 16 or later.

Open `Sese.xcodeproj` and select the shared `Sese` scheme. `project.yml` is the source for XcodeGen metadata. Debug uses `im.seex.sao2` and the Yu Sun signing team (`JPTS6M4T5B`). Release uses `com.sese.citycommunit`. iOS gives these builds separate app containers and device sign-in credentials. The UI test target uses `com.sese.citycommunit.uitests`.

A fresh build fetches and verifies the launcher icon from Sese's Supabase project. The app loads its other artwork and licensed gallery photos over HTTPS. See [media delivery](Docs/Media.md) for the asset paths and credits.

| Tab | Features |
| --- | --- |
| Shorts | The first tab opens a full-screen vertical feed of licensed costume and fan-culture clips, with creator credits, search, filters, likes, saves, comments, sharing, reporting, and access to member video submissions. |
| Districts | Three illustrated district guides with search, details, and saved places. |
| Cosplay | Real cosplay photographs and video sources, search, filters, and saved looks. |
| Chats | Member discovery, mutual-follow text and photo messaging, Realtime updates, unread state, pin, mute, archive, and reporting. |
| Me | Profile identity and relationship counts, saves, likes, works, wallet, and Settings. |

Shorts plays licensed portrait MP4s from Sese's Supabase Storage. AVPlayer loops the visible clip behind the toolbar and translucent tab bar. A cover appears while playback loads, and a progress line tracks the clip. Tap the video to pause and tap Play to resume. The video options show the source and license. Existing publisher entries retain their catalog IDs and source links for saved items and Cosplay details.

## Simulator acceptance

Use the exact simulator name `Sese UI Acceptance` (iPhone 17 Pro) and the `Sese` scheme. Build from the current workspace, install and launch that build before running `SeseUITests`, and turn off parallel testing to avoid cloned devices. The simulator uses local ad-hoc signing. The UI tests cover the signed-out entry, agreement consent, and both inline agreement links.

## Wallet purchases

Me → Wallet & top up shows the nine [diamond packs](App/CommunityContent/Products.json). StoreKit supplies the localized prices. Pull down to retry unavailable packs and to check for unfinished purchases. The wallet verifies each transaction, credits the signed-in account's device ledger once, and finishes the transaction after saving the credit.

The shared `Sese` scheme selects [SeseDiamonds.storekit](Configuration/SeseDiamonds.storekit) under Run → Options → StoreKit Configuration. Running from Xcode uses the local nine-pack catalog and StoreKit test transactions. The file stays outside the application bundle. Use a dedicated acceptance account on the designated simulator. Before installing Debug, verify that any existing app with `im.seex.sao2` on the destination can be replaced.

For Apple sandbox checks, select None in the same Run options and verify that the matching App Store Connect app for `im.seex.sao2` offers the exact Sese product IDs. Release uses the Apple catalog for `com.sese.citycommunit`. Xcode logs the catalog result, missing product IDs, and transaction environment in the `InAppPurchase` category.

The opt-in `WalletPurchaseTests` case uses the designated simulator and local StoreKit fixture. Run `SeseUITests/WalletPurchaseTests` with parallel testing disabled and `TEST_RUNNER_SESE_STOREKIT_ACCEPTANCE=1`. It checks the nine localized prices, cancellation before checkout, verified credits, and balance persistence after relaunch.

## Configuration still needed

- Configure the release signing team for distribution and verify the development signing identity for iPhone runs.
- The agreement release is active. The operator and contact email remain blank at the owner's direction. See the [deployment record](Docs/Backend/Deployment.md#published-agreements) for the public PDFs and revision.
- First and repeat sign-in with the active agreement configuration passed on the specified simulator. See the [simulator acceptance record](Docs/SimulatorAcceptance.md). Account deletion still needs a live acceptance run.
- Verify the nine consumable product IDs, prices, and availability in App Store Connect for each Bundle ID used with Apple's catalog. The $29.99 and $69.99 IDs were generated for Sese.
- Validate source playback, the two-account chat flow and StoreKit in their real environments when authorized.

See [implementation](Docs/Implementation.md), [backend deployment](Docs/Backend/Deployment.md), and [media credits](Docs/Media.md).
