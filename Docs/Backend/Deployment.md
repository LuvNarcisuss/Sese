# Supabase deployment

## Binding

- Stage A is partially delivered. Stage B has no configuration.
- Project: Sese, `ujclifehtfrxtrijlaia`, Tokyo (`ap-northeast-1`).
- Organization: the owner's selected gmail organization. Quoted incremental monthly cost: USD 0 at creation.
- Client integration: device-based one-tap sign-in using Supabase Swift 2.55.6 and a publishable client key.
- Project URL: https://ujclifehtfrxtrijlaia.supabase.co

## Database and media

The migrations set up RLS on the eleven public tables, participant-only message reads, mutual-follow sends, account preferences, reported targets and reviewable work submissions. The Realtime publication includes `public.messages`. The authenticated account deletion function derives its target from the caller. Consent records retain each accepted revision and its first acceptance timestamp. A read-only database check confirmed RLS on all eleven public tables, the original ten catalog items, zero profiles, zero messages, and zero work submissions. The additional editorial migration adds three official video links. No wallet fixtures were inserted.

The public `editorial` bucket serves the Anime Expo JPEG, the KodachiCon JPEG, and 21 ImageGen PNGs. All 23 object reads returned HTTP 200 and matched their expected SHA-256 digests on November 12, 2026. The same day, the catalog update recorded in migration `012_hosted_editorial_images.sql` returned the five Supabase image URLs for the district and cosplay records. See [media delivery](../Media.md) for provenance and the build-time icon workflow.

On November 12, 2026, four portrait MP4s and their four covers were uploaded to `editorial/shorts/v1/`. All eight public downloads returned HTTP 200 and matched the [Shorts media manifest](../ShortsMedia.json). Each MP4 also returned HTTP 206 for its first 1,024 bytes. The production SQL Editor returned four catalog rows with the verified MP4 and JPEG paths after applying `013_hosted_shorts.sql`. Existing publisher records retain their source URLs and IDs.

## Published agreements

The English agreements took effect on November 11, 2026. The operator and contact email fields are blank at the owner's direction. Both files are publicly readable without credentials. The welcome screen presents separate inline links with a separate, unchecked consent box. The welcome screen and Settings open the same PDF reader, which uses the matching bundled copy for immediate display and accepts the hosted response when the bytes match.

| Agreement | Source | Bundled PDF | Public PDF |
| --- | --- | --- | --- |
| Terms of Service | [Terms.md](Agreements/Terms.md) | `App/CommunityContent/Terms.pdf` | [Terms of Service](https://ujclifehtfrxtrijlaia.supabase.co/storage/v1/object/public/agreements/2026-11-11/Terms.pdf) |
| Privacy Policy | [Privacy.md](Agreements/Privacy.md) | `App/CommunityContent/Privacy.pdf` | [Privacy Policy](https://ujclifehtfrxtrijlaia.supabase.co/storage/v1/object/public/agreements/2026-11-11/Privacy.pdf) |

| Agreement | Source SHA-256 | PDF SHA-256 |
| --- | --- | --- |
| Terms of Service | `49c5288956545855b8249d5c45d653f673b33205d1b30ee881ff748f467691c6` | `ee6699223826ca267b12e3e41ee6dbdc6f7e4f3dbfb391b12502fcbb1fd73be4` |
| Privacy Policy | `b1d046249916a9565c977352c8079d3254e618cd424281a8683104614876ff3c` | `69cf272501f219da6b889aba9de08a53fd3f15eeb762f72fbf3496c8165a7084` |

Both anonymous HTTPS GETs returned HTTP 200 and `application/pdf`. The public and bundled bytes matched, and each PDF rendered as one page. `App/CommunityContent/Backend.json` and the live `private.release_settings` row contain `sha256:44b8591e100bd746270f5f0f46b166e17e3d9505a01ce044e7609ec5e8f48e3b`. The live configuration and function grants were read back after activation.

For an owner-requested update, render the two sources with `Scripts/render_agreements.py`, upload matching PDFs to a new directory in the public `agreements` bucket, and run `Scripts/verify_agreements.py --terms-url TERMS_URL --privacy-url PRIVACY_URL`. Apply the returned values to `Backend.json` and set the same revision in `private.release_settings`. Published versions remain available for reference.

## Device sign-in

The welcome screen follows Toli's checkbox and inline agreement links. Toli uses local accounts, while this app signs in to its existing Supabase project. After consent, the app loads or creates a random device credential in the iPhone Keychain. The credential produces an internal account alias and is verified through standard Supabase password authentication. Users enter no credentials. The original iPhone credential is required for repeat access. There is no cross-device recovery flow.

Migration `011_device_sign_in.sql` and Edge Function `device-sign-in` provision a non-anonymous account through the server-only Auth Admin API on first sign-in. Provisioning requires the active agreement revision and enforces a shared limit of 30 reservations per minute. The provisioning RPC is callable only by `service_role`. The client gets its session directly from Supabase Auth. Bootstrap checks server-assigned device account metadata and writes the profile and consent before the app opens the tabs.

Signing out preserves the local device credential so the same iPhone can sign in again. After the existing account deletion operation completes, the app removes the local credential. Apple and anonymous providers are disabled. Migration `009_apple_sign_in.sql` remains in the historical chain and is superseded by migration `011`.

## Private chat photos

Migration `008_private_chat_photos.sql` adds a nullable photo reference to the existing messages table and creates the private `chat-photos` bucket. Storage accepts JPEG objects up to 2 MiB. The app opens the system photo picker for a single selected image, resizes it to at most 1,600 pixels on the long edge, and encodes a fresh JPEG without carrying source metadata. The user previews the image before sending.

The object key identifies the authenticated sender, the recipient, and the message UUID. Upload and message creation both check mutual following and blocks. The message is created after Storage acknowledges the upload. A retry reuses the same ID and checks the existing bytes if the upload already succeeded. Other participants can fetch a committed attachment through their authenticated Storage request. Read authorization is evaluated on each fetch. There is no public or signed download URL.

Account deletion blocks new photo uploads for the account and removes related files through the Storage API before deleting the account. A failed cleanup can be resumed by retrying account deletion. An interrupted upload with no committed message stays sender-private until retry or account cleanup. There is no scheduled cleanup for interrupted uploads in this build.

A read-only deployment check confirmed the private JPEG-only bucket, all three Storage policies, signed-in RPC grants, no direct photo-reference insert grant, and the existing Realtime publication. The bucket contained zero files. The revised one-page Privacy PDF was checked against its source and visually reviewed. No accounts, messages, or files were created for this check.

## Cosplay media and public links

On November 12, 2026, production applied migration `014_cosplay_posts.sql` as `20261112063641` and migration `015_public_cosplay_media.sql` as `20261112064020`. The first migration added the post table, upload policies, report target, and media cleanup. The second verified the bucket was empty and enabled public downloads for `cosplay-media`. The bucket accepts JPEG and MP4 files up to 6 MiB. The app limits selected videos to 30 seconds. Existing YouTube link submissions continue to use the works table.

The uploader signs in with the existing account. The Storage upload and review submission share a stable post ID. Anyone with the file URL can open the media immediately after upload, including while the post is pending review. The app explains this before upload and provides the direct link on the post page. Pending post records are visible to their owners. The community gallery lists approved posts from discoverable members and respects blocks. Operators review pending entries in the project console. The report action can target approved posts.

Removal hides the post in the gallery, removes its file, and then deletes the row. Account deletion cleans up both chat photos and Cosplay files. Cleanup also covers files staged before a failed post submission. Chat photos continue to use their private bucket.

Production HTTP checks used generated JPEG and MP4 fixtures and two temporary, non-discoverable test accounts. An authenticated owner uploaded each file and repeated its submission under the same post ID. Each post remained a single pending row. The other account could not list the pending rows, and an owner could not approve a post directly. Unauthenticated upload attempts were rejected. Both media links returned HTTP 200 without an API key or session and matched the uploaded bytes and MIME types. The photo link stopped working after post removal. The account deletion guard blocked deletion while the video existed, then the cleanup flow removed the video and its account. The temporary accounts, profiles, posts, and files were removed.

The isolated PostgreSQL harness also verified approval visibility, blocking, and reporting. Native iPhone and simulator flows have not been run for this release.

## Outstanding

1. The app uses Bundle ID `com.sese.citycommunit`. The signing team and purchase identifiers are pending.
2. A trusted operator reviews pending link submissions and Cosplay posts from the Supabase console. The project has no automated review service or assigned moderation staff.
3. Two-account text and photo messaging, Realtime delivery, denial to outsiders, photo cleanup, and iPhone presentation are unverified. Voice and video calling require an RTC service.
4. StoreKit product IDs, device signing, purchase environments, and device-specific behavior are unverified. Wallet credit is device-local and account-scoped. No client-writable cloud balance exists.

## Evidence

Migration `011` and version 1 of `device-sign-in` were deployed. Before agreement activation, live HTTP checks confirmed password authentication was enabled, Apple and anonymous providers were disabled, malformed provisioning returned `400`, and inactive agreements returned `409`. No account was created for those checks.

Before agreement activation, a read-only database check confirmed the composite consent key, both new avatar IDs, and ten catalog records. The public Auth settings again returned HTTP 200 with anonymous sign-ins disabled. The two avatar crop previews were checked visually.

See [simulator acceptance](../SimulatorAcceptance.md) for the published agreement links and successful first and repeat device sign-in against the live backend. Account deletion, other authenticated features, and StoreKit transactions require separate acceptance.

## Shorts engagement migration

After explicit owner approval, migration `016_shorts_engagement.sql` was deployed to production on November 12, 2026 as `20261112080620`. It passed verification in an isolated PostgreSQL database before deployment. Storage policies are unchanged. It adds authenticated aggregate counts, an idempotent event for completed shares, and reactions for approved member Shorts and Cosplay videos. Received likes and saves sum those approved videos and any catalog videos assigned to the member. The migration does not assign source credits to member accounts.

The four hosted editorial clips have fixed, labeled display estimates between 20 and 50 for likes, saves, and shares. Their recorded interactions are added to those estimates. Comments never use display estimates: their count is the number of comment rows visible to the caller. Migration 016 generates no members, comments, or relationship rows. Editorial sources keep their attribution pages. Follow, Message, and Block use existing member accounts and the current mutual-follow chat rule.

The generated inactive reaction PNGs are ready for an authorized Storage upload. In the existing public `editorial` bucket, place them under `shorts/ui/25cfb986-9b53-4dbe-b40d-f6f63f0171b5/` using the names and hashes in `Docs/Artwork.json`. Use an existing authenticated project operator. Verify both public reads against their hashes before release.

If the aggregate route is unavailable with HTTP 404, the app can display its labeled editorial estimates plus the current member’s acknowledged likes and saves, the exact count of comments visible to that member, and completed shares recorded on this device. Shorts and editorial creator pages read the same cached values. Each completed share keeps a stable event ID and is submitted when the aggregate API is available. This fallback does not claim global totals. Member profiles with no published videos display zero received likes and saves.


## Prepared editorial discussions

At the owner's explicit request, migration `017_editorial_comments.sql` was deployed on November 12, 2026 as `20261112081207`. It adds 93 English, clip-specific prepared discussion entries: 24 for `fox-costume-in-motion`, 22 for `narcon-conga-line`, 26 for `costume-meetup-hug`, and 21 for `ask-before-you-snap`. Entries display the byline **Sese Editorial**. They are authored product content, not member activity or comments attributed to the original video creators. No Auth users or profiles are created.

Editorial entries have a unique stable `editorial_key` and no member author. A check constraint keeps editorial and member authorship mutually exclusive. Existing member-only column grants and RLS prevent clients from writing editorial keys, editing editorial entries, or deleting them as their own comments. Reporting remains available through the existing comment report path. The seed insert is idempotent. Existing comments and their authors remain unchanged.

The feed count, list total, and rows all derive from the same comment table and visibility rules. The app reads all comment pages with a stable creation-time and ID order. Posting and deletion refresh the list and feed after acknowledged writes. The bundled fallback sets editorial comment estimates to zero and obtains the actual count from the server.

Production readback under the authenticated role confirmed 24/22/26/21 visible rows and matching aggregate counts, with no duplicate bodies within any clip. Isolated PostgreSQL tests covered idempotent seeding, 24 -> 25 -> 24 after adding/removing a member comment, forbidden editorial impersonation, and protection from member deletion.

The post-deployment security advisor reported existing notices for the consent table's intentionally absent client policy, authenticated definer RPCs, and disabled leaked-password protection. The new aggregate wrappers are invoker functions; their private implementations validate authentication. See the [definer function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) for the existing RPC review guidance. No unrelated Auth or Storage settings were changed.


### Simulator verification after deployment

On November 12, 2026, the current workspace was built and installed on **Sese UI Acceptance**, iPhone 17 Pro, UDID `0E1EA5DB-DDE2-460C-A8C9-C5E400CF1B96`. Serial XCTest verified the prepared discussion byline and content, the live comment total changing 24 -> 25 -> 24 after publishing and deleting a test comment, and agreement between the sheet total and the feed button. A discovered composer bug was corrected: long input can no longer compress the Post button to zero width. The final targeted test passed with zero failures. Evidence: `/private/tmp/SeseCommentComposerFinal.xcresult` and `/private/tmp/sese-comment-composer-test.log`.

The preceding run verified acknowledged likes 43 -> 44 -> 43, saves 36 -> 37 -> 36, matching creator totals, and returning from another tab to the original video instead of the creator page. It also verified the comments sheet starting at 48% of screen height and continuing video motion across all captured frames. Evidence: `/private/tmp/SeseEditorialCommentsRetry.xcresult`; its comment-post test exposed the composer issue and was superseded by the passing targeted result above. An initial run was interrupted by an old defunct app process; restarting only the named simulator preserved its data and resolved that environment issue.
