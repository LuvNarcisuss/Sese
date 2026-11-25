import { fail, jws, purchaseContext, remoteJSON, rpc, tx, uuid, walletEndpoint } from "../_shared/district-api.ts";
import { productionVerifier, verifyPurchase } from "../_shared/apple-transactions.ts";

const confirmURL = "https://sese.huisgdd.top/community/wallet/confirm-order";

Deno.serve(walletEndpoint(async (member, input) => {
  const context = purchaseContext(input);
  if (input.storeEnvironment !== "Production") fail("environment_mismatch");
  const transaction = tx(input.storeTransaction);
  const receipt = input.storeReceipt;
  if (typeof receipt !== "string" || receipt.length < 4 || receipt.length > 3 * 1024 * 1024 ||
      receipt.length % 4 !== 0 || !/^[A-Za-z\d+/]+={0,2}$/.test(receipt)) fail();
  const claim = { ...context, storeTransaction: transaction, storeEnvironment: "Production" };
  const existing = await rpc("diamond_order_claim", { ...member, body: claim, apple_verified: false });
  if (existing.verify !== true) return existing;
  const verifier = await productionVerifier(input.signedAppTransaction);
  const evidence = await verifyPurchase(verifier, jws(input.signedTransaction), transaction,
    context.catalogPack as string, (context.intentID ?? member.actor) as string);
  if (evidence.quantity !== context.packQuantity) fail("ownership_conflict");
  const result = await rpc("diamond_order_claim", { ...member, body: { ...claim, purchaseDate: evidence.purchaseDate }, apple_verified: true });
  if (!("dispatch" in result)) return result;
  if (context.orderSource !== "communityOrder") fail("reconciliation");
  const claimToken = uuid(result.dispatch);

  // No retry here. The original service owns assignment of this order to the
  // device and any external credit. An ambiguous response needs reconciliation.
  let outcome = "reconciliation";
  try {
    const response = await fetch(confirmURL, {
      method: "POST", headers: { "Content-Type": "application/json" }, redirect: "error",
      body: JSON.stringify({ cityEdition: context.cityEdition, installationID: context.installationID,
        storeTransaction: transaction, storeReceipt: receipt, ...(typeof context.districtOrder === "string" ? { districtOrder: context.districtOrder } : {}) }),
      signal: AbortSignal.timeout(9000),
    });
    if (response.ok) {
      const reply = await remoteJSON(response, 16384);
      if (typeof reply.code === "number" && Number.isSafeInteger(reply.code)) {
        outcome = reply.code === 0 ? "settled" : "declined";
      }
    }
  } catch { /* Preserve the original transaction for operator reconciliation. */ }
  return rpc("diamond_order_finish", { tx_key: transaction, claim_token: claimToken, outcome });
}));
