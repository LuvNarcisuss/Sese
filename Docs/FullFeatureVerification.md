# Feature verification

The November 11, 2026 run used `CityCommunity UI Acceptance`, iPhone 17 Pro, iOS 26.0.1. The current workspace built successfully and the three signed-out UI cases passed. A separate acceptance build used a different bundle identifier and a loopback-only HTTP adapter with an isolated PostgreSQL database. The adapter exercised the app's screens and request flow without using the hosted project for test data.

The app's bundled agreement revision and hosted URLs are empty. The app rejects sign-in before starting authentication. The hosted device provisioning endpoint also returned HTTP 409 for an inactive revision. The bundled PDFs can still be opened as drafts.

Five signed-in UI cases passed on the isolated acceptance build:

- Shorts: like, unlike, save, unsave, post and delete a comment, reread the persisted reactions, and submit a video report.
- Districts and Cosplay: open and save a district, switch to Cosplay, and filter to photographic looks.
- Chats: read a message from the second account, send a text reply, submit a message report, and open and cancel the system photo picker.
- Safety: block a member, verify the conversation is hidden, unblock the member from Settings, and verify the conversation reappears.
- Profile and wallet: open the profile and wallet, verify the empty purchase history and unavailable top-ups, and sign out.

All eleven project migrations ran on the isolated database. Twelve checks passed. Coverage included agreement and consent guards, catalog categories, like and save persistence and isolation, comment validation and author-only deletion, mutual-follow messaging and duplicate retries, inbox preferences, private chat photo access, reports, blocking and unblocking, pending work visibility, and account deletion after photo cleanup. The local harness supplied the Auth identity and Storage operation context. It did not exercise hosted Auth, Storage transport, or Realtime delivery.

All eight video source pages returned HTTP 200, including two Disney pages that responded on retry. This checks publisher page availability. Playback and media compatibility still need verification in the publisher players.

The application has text messaging and a system photo picker. It does not implement voice or video calling, microphone recording, or camera capture. The StoreKit catalog was empty during this run, so no real purchase was attempted.
