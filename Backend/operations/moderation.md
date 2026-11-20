# Moderation inbox

Migration 018 is deployed on the dedicated Sese database as `20261118085958`. See the [deployment record](../../Docs/Backend/Deployment.md#video-reports-and-member-blocks) for production verification. The new app waits for the moderation RPC to succeed before hiding a video or acknowledging a block.

Migration 021 keeps the durable report inbox in `private.report_receipts`. Operators can inspect the target, available source context, reason, submission time and withdrawal time there even after the source content is removed. The live rows remain in `public.reports` while their targets exist. A non-null `withdrawn_at` means the reporter has withdrawn that report. Independently, additional blocks appear in `private.block_notices` on commit. The inbox stores the two member IDs and includes the original comment ID and excerpt when the user blocked someone from a comment. Blocks from content menus also retain the source key and excerpt. Unblocking does not remove the operator's inbox entry. Only a trusted operator should set `reviewed_at`. This inbox is passive. No email, push notification, or message is sent to either member.

Run the isolated PostgreSQL checks from the repository root with Node and a local installation of `@electric-sql/pglite`:

```sh
node Backend/checks/run-moderation.mjs
```

If the module is installed elsewhere, set `PGLITE_MODULE` to its absolute ESM entry point. The runner uses disposable in-memory PostgreSQL, creates the platform roles and Auth/Storage interfaces needed for migrations, seeds legacy records before migration 018, and evaluates application access under the authenticated role. No live Supabase credentials or accounts are required.
