# Sese

Sese is an independent Zootopia fan community. The project uses UIKit, Swift 5 and AVFoundation on portrait iPhones with iOS 16 or later.

Open `Sese.xcodeproj` and select the shared `Sese` scheme. `project.yml` is the source for XcodeGen metadata. Debug and Release use `com.sese.citycommunit` with the development team unset. The UI test target uses `com.sese.citycommunit.uitests`.

A fresh build fetches and verifies the launcher icon from Sese's Supabase project. The app loads its other artwork and licensed gallery photos over HTTPS. See [media delivery](Docs/Media.md) for the asset paths and credits.

| Tab | Features |
| --- | --- |
| Shorts | The first tab opens a full-screen vertical feed of licensed costume and fan-culture clips, with publisher avatars that open the shared user profile, an expandable search bar, and a comments sheet that opens at half height, expands on an upward swipe, and keeps the visible clip playing. Tapping a comment portrait or nickname opens the full-screen profile and Back restores the discussion. The action column displays likes, comments, saves, and completed shares. |
| Districts | Tap four districts on the city map. City Center starts open. Unlock Sahara Square, Tundratown, and Rainforest District with 30, 45, and 60 diamonds respectively, then explore six places in each district through its street map or categorized list. Mark stops as visited to track progress, and open the existing district guides. Build a named district for 120 diamonds with a desert, snow, or forest theme and up to six selectable places. Built districts, visit progress, and wallet debits are stored on this device for the signed-in account. |
| Cosplay | Browse editorial and approved member photos and videos. Submit a photo or a video from Photos, preview it, and track review status in My posts and Me → Cosplay. |
| Chats | Real mutual friends appear before their first message. An invitation appears when there are no friends. The filter opens Conversations and Archived for message history. Member discovery, text and photo messaging, Realtime updates, unread state, pin, mute, archive, and reporting are available. |
| Me | Avatar, bio, received likes and saves, following, wallet, and Settings. Switch between Shorts, Cosplay, Liked, and Saved in one row. The Shorts and Cosplay cards provide creation actions and explain what appears in an empty gallery. |

Shorts plays licensed portrait MP4s from Sese's Supabase Storage. AVPlayer loops the visible clip behind the toolbar and translucent tab bar. A cover appears while playback loads, and a progress line tracks the clip. Tap the video to pause and tap Play to resume. The video options show the source and license. Existing publisher entries retain their catalog IDs and source links for saved items and Cosplay details.

Cosplay media uses [migration 014](Backend/migrations/014_cosplay_posts.sql) and [migration 015](Backend/migrations/015_public_cosplay_media.sql) in production. Anyone with a media link can open the file as soon as it is uploaded. The gallery lists approved posts from eligible members. Uploading and removing files require the owner's account. Existing editorial content and link submissions remain available.

## Simulator acceptance

Use the exact simulator name `Sese UI Acceptance` (iPhone 17 Pro) and the `Sese` scheme. Build from the current workspace, install and launch that build before running `SeseUITests`, and turn off parallel testing to avoid cloned devices. The simulator uses local ad-hoc signing. The UI tests cover the signed-out entry, agreement consent, and both inline agreement links.

## Wallet purchases

Me → Wallet & top up shows the nine [diamond packs](App/CommunityContent/Products.json). StoreKit supplies the localized prices. Pull down to retry unavailable packs and to check for unfinished purchases. The wallet verifies each transaction, credits the signed-in account's device ledger once, and finishes the transaction after saving the credit. Its ImageGen diamond marks the balance, purchase tiers, and activity. District unlocks debit that same balance and appear in their own history. Unlocks and balance are kept on the device for the signed-in account.

The shared `Sese` scheme selects [SeseDiamonds.storekit](Configuration/SeseDiamonds.storekit) under Run → Options → StoreKit Configuration. Running from Xcode uses the local nine-pack catalog and StoreKit test transactions. The file stays outside the application bundle. Use a dedicated acceptance account on the designated simulator.

For Apple sandbox checks, select None in the same Run options and verify that the App Store Connect app for `com.sese.citycommunit` offers the exact Sese product IDs. Xcode logs the catalog result, missing product IDs, and transaction environment in the `InAppPurchase` category.

The opt-in `WalletPurchaseTests` case uses the designated simulator and local StoreKit fixture. Run `SeseUITests/WalletPurchaseTests` with parallel testing disabled and `TEST_RUNNER_SESE_STOREKIT_ACCEPTANCE=1`. It checks the nine localized prices, cancellation before checkout, verified credits, and balance persistence after relaunch.

## Configuration still needed

- Configure the release signing team for distribution and verify the development signing identity for iPhone runs.
- The agreement release is active. The operator and contact email remain blank at the owner's direction. See the [deployment record](Docs/Backend/Deployment.md#published-agreements) for the public PDFs and revision.
- First and repeat sign-in with the active agreement configuration passed on the specified simulator. See the [simulator acceptance record](Docs/SimulatorAcceptance.md). Account deletion still needs a live acceptance run.
- Verify the nine consumable product IDs, prices, and availability in App Store Connect for each Bundle ID used with Apple's catalog. The $29.99 and $69.99 IDs were generated for Sese.
- Validate source playback, the two-account chat flow and StoreKit in their real environments when authorized.

See [implementation](Docs/Implementation.md), [backend deployment](Docs/Backend/Deployment.md), and [media credits](Docs/Media.md).
