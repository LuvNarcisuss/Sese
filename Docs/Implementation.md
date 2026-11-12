# Implementation

The app uses a new UIKit shell based on the Teto scene and feature ownership model. Bibi supplies the Shorts, inbox, mutual following and profile interaction patterns. Toti supplies relationship and wallet handling patterns. The existing projects remain read-only references.

1. Use Sese as the display name and keep one iPhone-only scheme. Leave production identity and the purchase catalog owner-configurable.
2. Bind a separate project. Verify schema grants, consent, account deletion, catalog records and private chat access before reporting deployment.
3. Deliver a Shorts feed, district catalog, cosplay gallery, conversations and member profile. Keep publisher links and editorial credits independent of community member accounts.
4. Serve generated raster artwork, licensed photos, and native portrait Shorts from Supabase Storage. Fetch the app icon during the build and bundle the custom fonts. Verify media provenance, checksums, and MP4 range responses before publishing catalog entries.
5. Present the configured diamond packs in a three-column grid with StoreKit prices. Confirm purchases in the app before presenting the Apple payment sheet. Use the current account token, verified transactions and atomic account-specific delivery. Verify the catalog in App Store Connect separately.
6. Inspect resources, metadata and API contracts statically. Record separately any authorized future app or purchase verification.
