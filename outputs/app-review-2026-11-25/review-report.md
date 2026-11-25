# App Store review comparison

**25 November 2026** · Sese, Roro and Vava

The exact stage of Roro and Vava is unresolved. All three workflows require a separate review submission. If review has begun, credentials, accurate descriptions of social features, purchase value and media rights are the strongest points to verify. The repositories do not explain an Apple queue delay or establish a duplicate-app decision.

## Identify the review stage

| Screen or status | Interpretation and next evidence |
| --- | --- |
| Codemagic only | Match the production workflow, commit and publishing log. Each signing-validation workflow has empty publishing settings. |
| Build Uploads — Processing or Failed | Read the upload details and ITMS email. Apple recommends contacting support if build processing exceeds 24 hours. |
| Prepare for Submission or Ready for Review | Verify that the selected build and any first consumable are in the same submission, then check whether the final Submit for Review action was taken. |
| Waiting for Review | Apple has received the submission and has yet to start review. A manual-submit omission is ruled out for this submission. Check its ID, timestamp and any message from Apple. |
| In Review | Apple has started. Verify reviewer access, backend availability and actual product claims. |
| Rejected, Metadata Rejected or Unresolved Issues | Read Messages for the affected item, guideline and requested action. Check whether the issue concerns an IAP, a listing or the app binary. |

## Side-by-side comparison

| Dimension | Sese | Roro | Vava |
| --- | --- | --- | --- |
| Native UI | UIKit | SwiftUI with UIKit presenters | UIKit |
| Account | Device credential, one-tap Supabase authentication | Existing email and password at cold launch | Existing email and password at cold launch |
| First product screen | Hosted Shorts | Photography journal and discovery | Training academy |
| Distinctive task | Explore, unlock and build city districts; submit cosplay for moderation | Import photos and videos, keep a private journal and browse Topics | Follow structured practice steps, track courses and contact nearby players |
| Communication | Backend messages, photos and Realtime | Local history and camera/microphone previews | Encrypted nearby messaging and audiovisual calls after mutual following |
| Content | Hosted editorial media, separate member submissions | Bundled catalog with fictional identities, local imports | Bundled training and clips, replay links and private notes |
| Purchase | StoreKit 2 with verified transactions | StoreKit 1 with device POST to legacy receipt verification | StoreKit 1 with local signed-receipt validation |
| Package | Supabase Swift 2.55.6 | SwiftASN1 1.5.1 | TPInAppReceipt 4.0.2 |
| Nominal project build | 1 | 4 | 1 |

All three declare version 0.1.0, iPhone portrait and iOS 16+. CI assigns the real build number on each run. Sese has prepared editorial activity as well as genuine member routes. Its reported approval is an outcome for an unidentified build.

## Findings

### AR-001 · Existing credentials gate both apps

**P1 · needs verification · high confidence in the described evidence**

Roro welcome or Vava launch leads to a password grant before opening the local library or the tabs. Reviewers and ordinary newcomers can be blocked from all product-specific content.

- Password authentication precedes account access. [Roro/ios/Roro/Native/JournalStore.swift, line 131](/Users/mac/Desktop/Roro/ios/Roro/Native/JournalStore.swift:131)
- The dock is installed after authentication succeeds. [Vava/Vava/App/Core/VavaApplication.swift, line 192](/Users/mac/Desktop/Vava/Vava/App/Core/VavaApplication.swift:192)
- A historical test exercised one real account. [Roro/docs/moderation-acceptance-2026-11-24.md, line 49](/Users/mac/Desktop/Roro/docs/moderation-acceptance-2026-11-24.md:49)
- The November 23 snapshot recorded zero Auth users and no end-to-end login check. [Vava/Vava/Docs/Verification.md, line 14](/Users/mac/Desktop/Vava/Vava/Docs/Verification.md:14)

Supply a working dedicated review account for each app and explain legitimate onboarding. Give access to independent offline tools where account identity is unnecessary. Using the credentials actually listed in ASC and a fresh installation of that build, reach the tabs, free content and wallet. Verify the ordinary customer onboarding route.

Responsible team — Product and submission owner. Estimated effort — Small to verify; larger if onboarding changes. The ASC credentials, current user counts and submitted builds are unavailable.

[2.1(a) and 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/)

### AR-002 · Roro seeds an incoming request and labels local previews as calls

**P1 · confirmed · high confidence in the described evidence**

Creating a journal copies a fictional follower and incoming request. Acceptance unlocks a local thread, with voice and video buttons opening capture previews. A user can reasonably understand a prepared invitation as another person's action and a local preview as a real call.

- Catalog labels the personas fictional and includes a fixed follower and incoming request. [Roro/Assets/community/catalog.json, line 21](/Users/mac/Desktop/Roro/Assets/community/catalog.json:21)
- Fresh journals copy catalog relationships. [Roro/ios/Roro/Native/PhotoLibrary.swift, line 78](/Users/mac/Desktop/Roro/ios/Roro/Native/PhotoLibrary.swift:78)
- Message mutation updates local history. [Roro/ios/Roro/Native/PhotoLibrary.swift, line 303](/Users/mac/Desktop/Roro/ios/Roro/Native/PhotoLibrary.swift:303)
- Voice call and Video call invoke preview. [Roro/ios/Roro/UI/AccountChats.swift, line 328](/Users/mac/Desktop/Roro/ios/Roro/UI/AccountChats.swift:328)
- Credits discloses fictional identities. [Roro/ios/Roro/UI/AccountWallet.swift, line 263](/Users/mac/Desktop/Roro/ios/Roro/UI/AccountWallet.swift:263)

Align the new-account state and interaction labels with a private journal, or implement acknowledged participant-to-participant service for any marketed social actions. Open on two fresh devices and trace a claimed interaction from its origin to the intended recipient. For an offline journal, verify every relevant entry accurately describes a private note or preview.

Responsible team — Roro product and iOS. Estimated effort — Small for local positioning; large for real messaging. The actual ASC marketing copy and Apple observations are unknown.

[2.1 and 2.3.1](https://developer.apple.com/app-store/review/guidelines/)

### AR-003 · Roro sends receipts directly from the app to the legacy verification endpoint

**P1 · confirmed · high confidence in the described evidence**

SKPaymentQueue purchased callback reads the receipt and POSTs it from the device to Apple's legacy verification service. The implementation departs from Apple's explicit verification guidance. Receipt verification or networking failures leave delivery pending.

- Release dispatches an Apple receipt request. [Roro/ios/Roro/Native/PurchaseService.swift, line 307](/Users/mac/Desktop/Roro/ios/Roro/Native/PurchaseService.swift:307)
- The client selects the deprecated production or sandbox verifyReceipt URL. [Roro/ios/Roro/Native/PurchaseService.swift, line 358](/Users/mac/Desktop/Roro/ios/Roro/Native/PurchaseService.swift:358)
- A failure retains the unfinished transaction. [Roro/ios/Roro/Native/PurchaseService.swift, line 352](/Users/mac/Desktop/Roro/ios/Roro/Native/PurchaseService.swift:352)

Keep StoreKit 1 checkout if required and validate the signed transaction or receipt through an Apple-supported trusted path before idempotent delivery. Exercise success, cancellation, temporary verification failure and callback replay with the submitted identifier and sandbox products.

Responsible team — Roro payments. Estimated effort — Medium. No Apple processing error or failed live purchase was observed.

[Apple StoreKit verification guidance](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)

### AR-004 · Vava ships coach portraits and event thumbnails with incomplete rights evidence

**P1 · needs verification · high confidence in the described evidence**

Academy presents two downloaded and cropped coach photos. Watch displays six bundled thumbnails and then opens the publisher replay. The uses require rights that cover in-app redistribution and presentation of the depicted sources.

- The first portrait has no listed reuse license; the second record at line 14 has the same limitation. [Vava/Vava/Assets/Content/publisher-photo-sources.json, line 6](/Users/mac/Desktop/Vava/Vava/Assets/Content/publisher-photo-sources.json:6)
- Six YouTube thumbnail URLs are listed. [Vava/Vava/Assets/Content/replay-cover-sources.json, line 2](/Users/mac/Desktop/Vava/Vava/Assets/Content/replay-cover-sources.json:2)
- Content media is a release resource. [Vava/Vava/project.yml, line 49](/Users/mac/Desktop/Vava/Vava/project.yml:49)

Document rights by file and use, or replace under-documented images with owned or appropriately licensed materials. Keep the distinction between coaches, sources and app members clear. Match each displayed image to its rights record; verify how names and affiliations appear on the paid lesson and profile screens.

Responsible team — Vava content owner. Estimated effort — Small to reconcile; dependent on external licenses. Private licenses may exist. The third portrait and the four match clips have separate license records.

[5.2.1 and 5.2.2](https://developer.apple.com/app-store/review/guidelines/)

### AR-005 · Roro sells per-work access to two Pexels photos

**P1 · needs verification · high confidence in the described evidence**

Topics charges 10 or 20 coins for one work, then offers the full photo and sharing. The documented general license may not cover sale or distribution of substantially unchanged standalone photos.

- First work costs 10 coins; line 798 sets the second to 20. [Roro/Assets/community/catalog.json, line 750](/Users/mac/Desktop/Roro/Assets/community/catalog.json:750)
- Both source entries identify the Pexels License; see also line 151. [Roro/Assets/photos/manifest.json, line 127](/Users/mac/Desktop/Roro/Assets/photos/manifest.json:127)
- The app offers sharing of the first image. [Roro/ios/Roro/UI/PhotographyDiscussion.swift, line 215](/Users/mac/Desktop/Roro/ios/Roro/UI/PhotographyDiscussion.swift:215)
- The selected work or category debits the local wallet. [Roro/ios/Roro/Native/PurchaseService.swift, line 124](/Users/mac/Desktop/Roro/ios/Roro/Native/PurchaseService.swift:124)

Confirm separate authorization for this sale and distribution, or offer original photography with documented commercial rights for the single-work unlock. Trace both paid files to the applicable license, creator, scope and delivered asset, including the share action.

Responsible team — Roro content owner. Estimated effort — Small to inspect; replacement depends on assets. Whether separate permission or sufficient creative transformation exists is unknown.

[5.2.1 and 5.2.2](https://developer.apple.com/app-store/review/guidelines/)

### AR-006 · Vava's local safety record does not reach an operator

**P2 · needs verification · high confidence in the described evidence**

Real nearby players can exchange messages and calls. Catalog reporting stores a local record; nearby profile blocking affects the device. A participant may lack a timely route to report abusive user interactions to the service operator.

- The peer session requires encryption and supports real transport. [Vava/Vava/App/Core/ChatTransport.swift, line 10](/Users/mac/Desktop/Vava/Vava/App/Core/ChatTransport.swift:10)
- The audit log is local, with no operator inbox or staff notification. [Vava/Vava/Docs/Integration.md, line 63](/Users/mac/Desktop/Vava/Vava/Docs/Integration.md:63)
- Real messaging requires two confirmed nearby players who mutually follow. [Vava/Vava/Docs/Integration.md, line 77](/Users/mac/Desktop/Vava/Vava/Docs/Integration.md:77)

Verify the operator contact and response path for peer abuse. Provide an actionable reporting route and make the function of local hides explicit. Use two consented physical devices to confirm delivery and blocking, then trace an abuse report to an authorized handler and response.

Responsible team — Vava product and operations. Estimated effort — Medium. Other channels, staffing and the submitted app's contact details are unknown.

[1.2](https://developer.apple.com/app-store/review/guidelines/)

## Coverage

**Build configuration**. All three generated Xcode projects specify Swift 5 mode, iPhone family 1, iOS 16.0 and version 0.1.0. Their release workflows select Xcode 26.5 on an M2 Mac mini and App Store signing. Sese uses get-latest-build-number with the IOS platform. Roro and Vava use get-latest-testflight-build-number. All override CURRENT_PROJECT_VERSION and leave review submission manual. A green signing-validation run uploads nothing.

**Frameworks and dependencies**. Sese uses UIKit, AVFoundation, StoreKit 2 and supabase-swift 2.55.6. Roro uses SwiftUI with UIKit presenters, AVFoundation, StoreKit 1, direct Supabase Auth HTTP and SwiftASN1 1.5.1. Vava uses UIKit, AVFoundation, MultipeerConnectivity, StoreKit 1, direct Supabase Auth HTTP and TPInAppReceipt 4.0.2. The latter locks SwiftASN1 1.7.4, Swift Certificates 1.21.1 and Swift Crypto 4.5.2. No active React Native, Flutter or HTML application target was identified. Historical migration records describe earlier designs.

**Binary identity**. The local Roro device Release .app is unsigned, arm64, 0.1.0 (3), SDK 26.2 and Xcode 26.3. It differs from the current project in resources and toolchain. Its main executable declares cryptid 0, with no decompilation or directory hash. Vava has a Debug simulator product under the current identifier. No matching submission IPA or archive was identified in the three workspaces or in the named Xcode Archives search. The approved Sese build number is unknown.

**First launch and accounts**. Sese provisions a device credential, authenticates through Supabase and exposes remote account deletion. Roro and Vava require an existing confirmed email/password account each cold launch. Their Settings actions clear the local journal/profile. Establish where public accounts are created and whether the app supports account creation before applying the account deletion requirement.

**Features and content storage**. Sese offers eleven hosted Shorts, City Center exploration and district construction, moderated Cosplay submissions, mutual-friend messaging and Me. Roro offers a private photography journal, Topics, local video import/playback, collections and local interactions. Its catalog contains nine fictional identities, 25 photo works, 12 Shorts and 90 prepared comments. Its empty release marker selects bundled media. Vava includes six courses, six external replays, four bundled clips and real nearby-device communication. Vava separates labeled editorial estimates and private notes.

**Product overlap**. Roro and Vava share a five-tab layout, central Shorts, Chats, Me and nine consumable tiers. Seven credit quantities match across all three catalogs, and product IDs differ. Vava explicitly cites Toli as its navigation reference in Docs/Product.md, line 5. SHA-256 comparison across the three first-party Swift directories found zero byte-identical cross-project Swift files (21 Sese, 25 Roro, 18 Vava). Roro and Vava also shared zero exact hashes across the 116 and 51 tracked selected runtime raster/video files checked. The selection excludes fonts, editorial documentation, remote content and generated artwork archives. Exact equality does not measure UI or product similarity.

**Content moderation**. Sese writes reports to a backend RPC, has an operator workflow, and filters pending Cosplay posts from the approved gallery. Roro and Vava persist personal content reports locally. Vava has a real nearby messaging surface. Roro's local messages and private imports do not establish a public UGC service. Timely staff access and public contact information require separate evidence where applicable.

**Payments**. Three separate catalogs contain nine consumables each. Roro's visible single-work prices total 30 coins, or category passes can be bought. Vava's five paid plans cost 45, 55, 65, 75 and 85 coins, totaling 325. The smallest pack in each app is 400, the largest is 63,700. Sese spends diamonds on unlocking and building districts. These calculations describe the shipped catalogs and do not impose a pricing rule.

**Privacy and permissions**. Roro and Vava include first-party manifests declaring linked email and user ID for app functionality and no tracking. Both declare microphone and camera usage; Vava additionally declares local networking and Bonjour for discovery. Sese directly uses UserDefaults (App/Features/DistrictExplorePage.swift, line 178); its source tree did not contain a first-party PrivacyInfo.xcprivacy. Inspect the Sese archive and uploader messages before drawing a conclusion about the approved build. Its agreement record also documents blank operator and contact fields (Docs/Backend/Deployment.md, line 21). ASC privacy answers and actual public support contacts are unknown.

**Web and remote behavior**. Sese uses remote editorial media and Supabase Auth/database/storage. Roro has native screens, web agreement links and a bundled catalog fallback. Vava has web agreements and a publisher link for the replay itself. The reviewed routes do not establish a reviewer-specific feature switch. Remote service availability and final binary behavior were not exercised.

**Coverage and limitations**. Static inventories completed for supported file types without signal truncation; vendored source and unsupported binary formats were outside scanner coverage. Product routes were traced manually. No build, typecheck, runtime test, account sign-in, payment, backend operation, ASC access or external submission was performed. No storefront, account status, review correspondence, listing screenshots or CI upload logs were supplied.

## Evidence still needed

- **Which stage has each specific build reached?** Build Uploads result and ITMS text, App Review submission ID, storefront/platform, build number, first submission and last status timestamps, plus Messages. Redact personal details.
- **Which code was built and signed?** Codemagic workflow ID, commit, log and IPA or archive for each corresponding Apple build. Map Sese's approved build in the same way.
- **Are these consumables visible for the correct products and app versions?** Paid Apps agreement status, pricing and availability, first consumable linked to the app version, and a sandbox run with the local StoreKit configuration disabled. Vava's integration record calls for reconciling seven IDs and creating two.
- **What product does each listing promise?** Compare the submitted descriptions, first screenshots, age ratings, review notes and intended audience for all three apps. Check the first customer task and how product-specific value differs under 4.2/4.3.
- **Do app disclosures match actual account and media handling?** Public access to both agreements, deletion route if account creation is supported, ASC privacy declarations, support contact and the privacy reports of the signed archives.
- **Can Vava's nearby functions be reviewed and the scope of Roro's local tools understood?** Two-iPhone steps or demo recording, account-specific login instructions and annotated routes for the actual paid content. Read the real review correspondence first.

## Source notes

- Functional access, accurate presentation, UGC, duplicate apps, privacy and rights. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Submission stages. [App and submission statuses](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses/)
- Final submission action. [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- Processing, Complete and Failed. [View builds and metadata](https://developer.apple.com/help/app-store-connect/manage-builds/view-builds-and-metadata/)
- Credentials and access instructions. [Provide information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/)
- First consumable and app version association. [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)
- Apple guidance on direct legacy receipt requests. [Validating receipts with the App Store](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)
- Application and SDK manifest responsibilities. [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- The upload and review options have different meanings. [Codemagic publishing documentation](https://docs.codemagic.io/yaml-publishing/app-store-connect/)
- License conditions for standalone sale or distribution apply to the two paid photos. [Pexels license guidance](https://help.pexels.com/hc/en-us/articles/900005880463-What-are-the-Terms-and-Conditions)

Sese 35e46fd and Roro 835bee1 clean at inspection. Vava 96b69ca had pre-existing Finder metadata and Xcode user-state changes.

