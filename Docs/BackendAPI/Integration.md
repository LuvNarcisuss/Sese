# Sese Stage B integration

## Console setup

Select app `32948410` in the console for `https://sese.huisgdd.top`. Import the [two interfaces](Console/Interfaces-32948410.json) into interface management and the [14 parameters](Console/Configuration-32948410.json) into configuration management. Validate both imports and save. The [contract](contract.json) records the HTTP fields, four core Socket events, and additional inbox and Shorts events. The console app ID identifies this configuration. Apple uses its own app identifier.

Once the member accepts the entry disclosure, Supabase checks the signed-in device account and agreement revision, then sends the app version, installation UUID, available APNs token and subscription mode to the configured entry service. When the response selects external entry, the app contacts the same origin for its own session. Failure leaves the entry screen available for retry. The client handles page presentation, checkout, sign-out and link requests. Inbox and Shorts refreshes also require an external publisher that implements the contract, acknowledges receipts and supports replay.

The external web view fills the window, including the status bar and home indicator areas. The page handles its own safe-area spacing for navigation controls.

## Wallet and recovery

StoreKit 1 presents the purchase. The native wallet credits the member's Supabase balance after the server verifies the Apple-signed production transaction, account binding and product. District unlocks and construction debit that balance online. The debit and entitlement share a database transaction. The device keeps the original ledger, built maps and exploration progress. Interrupted operations resume with the same identifier.

For an external order, the app asks the member to confirm the product, price and receipt transfer before opening Apple checkout. After verification, the settlement function sends the app version, installation UUID, transaction identifier, full app receipt and optional order reference to the original order service. That service owns the external credit. If delivery has an uncertain outcome, check the original order with the provider before resolving the database record. A timeout can occur after the provider has already applied the purchase. The settlement function does not automatically resend an ambiguous confirmation.

An authorized database operator can resolve two kinds of historical records.

- **Legacy wallet.** Inspect the member's snapshot in `private.diamond_migration_reviews`. Reconcile the purchases and historical debits against independent records. Enter the exact reviewed snapshot in `private.diamond_legacy_approvals` when the remaining entitlement is established. The next wallet refresh retries the migration. Empty histories and eligible verified histories with zero remaining credit can migrate automatically.
- **Unfinished historical purchase.** Inspect the member and transaction in `private.diamond_order_reviews`. Confirm the purchase has not already contributed to the migrated balance. Match its transaction ID, member, source, product, quantity, production environment, intent, installation and order reference in `private.diamond_purchase_approvals`. The retry still requires the signed Apple evidence. Unresolved records stay pending.

The Debug simulator keeps verified local StoreKit fixture credits in a separate ledger. The production functions accept production transactions only. Apple sandbox purchases stay pending for a dedicated test settlement environment.

## Deployment and verification on November 25, 2026

| Component | Evidence |
| --- | --- |
| Supabase project `ujclifehtfrxtrijlaia` | Migration `20261125031412` deployed. Only the service role can execute the three new wallet RPCs. |
| Edge Functions | `community-entry` v2, `district-wallet` v1 and `diamond-settlement` v1 deployed. All three rejected empty, unauthenticated requests with HTTP 401. |
| Wallet database | Isolated PostgreSQL checks covered duplicate credits and debits, ownership and source conflicts, expired processing leases, reconciliation and account deletion. |
| Hosted member chat | Verified both directions, disconnect recovery, private photo access and outsider restrictions. Temporary accounts and attachments were removed. See the [deployment evidence](../Backend/Deployment.md). |
| App build | Sese Debug built and linked on Xcode 26.3 for Sese QA, iPhone 17 Pro, iOS 26.3.1. Checked the final binary, iPhone device family, resource exclusions and both bundled agreement hashes. The build emitted existing Swift concurrency warnings. No app installation, launch or UI test was performed in this pass. |

The owner confirmed both console imports. An initial run entered native Shorts. In the subsequent external session on Sese QA, the provider sent the first page event without a publisher identifier. The receiver can confirm that one page against the exact HTTPS address authorized by the active ticket response, on the matching channel. Other actions retain the configured publisher check. See [external login and rendering](../SimulatorAcceptance.md#external-login-and-page-rendering-on-sese-qa). Live external-link, sign-out, theme events and replay, on-device APNs, the Apple catalog and purchase settlement have separate acceptance requirements. A signing team is required for device and distribution signing. The published privacy PDF describes the earlier on-device purchase ledger. The entry and purchase screens disclose the new transfers, while the November 11 PDFs retain their published content.
