import { fail, jws, obj, product, purchaseContext, rpc, tx, uuid, walletEndpoint } from "../_shared/district-api.ts";
import type { Fields, Identity } from "../_shared/district-api.ts";
import { productionVerifier, verifyPurchase } from "../_shared/apple-transactions.ts";

function amount(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0 || value > 637000) fail();
  return value;
}
function list(value: unknown): Fields[] {
  if (!Array.isArray(value) || value.length > 25000) fail();
  return value.map(obj);
}
function districtID(kind: unknown, value: unknown): string {
  if (kind === "build") return uuid(value);
  if (kind === "unlock" && typeof value === "string" &&
      ["district-sahara", "district-tundra", "district-rainforest"].includes(value)) return value;
  return fail();
}
function sortedUnique<T>(rows: T[], key: (row: T) => string) {
  rows.sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0);
  if (rows.some((row, index) => index > 0 && key(row) === key(rows[index - 1]))) fail();
  return rows;
}
async function legacyWallet(member: Identity, input: Fields) {
  const signedTransactions: Record<string, number> = {};
  const purchases = list(input.purchases);
  let verifier: Awaited<ReturnType<typeof productionVerifier>> | undefined;
  if (purchases.some((row) => row.signedTransaction !== undefined)) {
    try { verifier = await productionVerifier(input.signedAppTransaction); }
    catch { /* Preserve the snapshot for review when app identity cannot be verified. */ }
  }
  const records = [];
  for (const purchase of purchases) {
    const transactionID = tx(purchase.transactionID), productID = product(purchase.productID);
    records.push({ transactionID, productID, diamonds: amount(purchase.diamonds) });
    if (verifier && purchase.signedTransaction !== undefined) {
      try {
        const evidence = await verifyPurchase(verifier, jws(purchase.signedTransaction),
          transactionID, productID, member.actor);
        signedTransactions[transactionID] = evidence.quantity;
      } catch { /* Missing or invalid historical evidence never authorizes wallet credit. */ }
    }
  }
  const spends = (field: string, kind: string) => sortedUnique(list(input[field]).map((row) => ({
    id: districtID(kind, row.id), diamonds: amount(row.diamonds),
  })), (row) => row.id);
  return {
    action: "migrate", purchases: sortedUnique(records, (row) => row.transactionID),
    unlocks: spends("unlocks","unlock"), districts: spends("districts","build"), signedTransactions,
  };
}

Deno.serve(walletEndpoint(async (member, input) => {
  let body: Fields;
  switch (input.action) {
    case "migrate": body = await legacyWallet(member, input); break;
    case "balance": body = { action: "balance" }; break;
    case "intent": body = { action: "intent", intentID: uuid(input.intentID) }; break;
    case "prepare": body = { action: "prepare", ...purchaseContext(input, true) }; break;
    case "spend": body = { action: "spend", kind: input.kind, id: districtID(input.kind, input.id) }; break;
    default: return fail();
  }
  return rpc("district_wallet_action", { ...member, body });
}));
