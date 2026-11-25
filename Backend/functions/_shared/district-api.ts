const origin = "https://ujclifehtfrxtrijlaia.supabase.co";
const uuidPattern = /^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i;
const transactionPattern = /^[1-9]\d{0,19}$/;
const errors: Record<string, [number, string]> = {
  auth_required: [401, "Sign in to your original account."],
  invalid_request: [400, "Invalid wallet request."],
  intent_not_found: [404, "Purchase intent not found."],
  wallet_migration_required: [409, "Open your wallet to synchronize its history."],
  migration_review: [409, "Your previous wallet history is awaiting reconciliation."],
  transaction_review: [409, "Your purchase evidence is awaiting verification."],
  ownership_conflict: [409, "The original purchase details do not match."],
  insufficient_balance: [409, "You do not have enough diamonds."],
  processing: [409, "This order is being confirmed."],
  reconciliation: [409, "This order is awaiting reconciliation."],
  upstream_declined: [422, "The order service declined this purchase."],
  environment_mismatch: [422, "This wallet requires a production App Store purchase."],
  service_unavailable: [503, "The wallet service is temporarily unavailable."],
};

export class WalletFailure extends Error {
  constructor(reason: string) { super(reason); }
}
export function fail(reason = "invalid_request"): never { throw new WalletFailure(reason); }

export type Fields = Record<string, unknown>;
export type Identity = { actor: string; session_key: string };
export function obj(value: unknown): Fields {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail();
  return value as Fields;
}
export function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) fail();
  return value.toLowerCase();
}
export function tx(value: unknown): string {
  if (typeof value !== "string" || !transactionPattern.test(value) || BigInt(value) > 18446744073709551615n) fail();
  return value;
}
export function jws(value: unknown): string {
  if (typeof value !== "string" || value.length > 32768 || !/^[A-Za-z\d_-]+(?:\.[A-Za-z\d_-]+){2}$/.test(value)) fail();
  return value;
}
export function product(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9._-]{1,100}$/.test(value)) fail();
  return value;
}
export function purchaseContext(input: Fields, preparing = false): Fields {
  const source = input.orderSource;
  const quantity = input.packQuantity;
  if (source !== "districtWallet" && source !== "communityOrder") fail();
  if (typeof quantity !== "number" || !Number.isInteger(quantity) || quantity < 1 || quantity > (preparing ? 1 : 10)) fail();
  if (typeof input.cityEdition !== "string" || !/^\d+(?:\.\d+){0,3}$/.test(input.cityEdition) || input.cityEdition.length > 32) fail();
  const result: Fields = {
    orderSource: source, catalogPack: product(input.catalogPack), packQuantity: quantity,
    installationID: uuid(input.installationID), cityEdition: input.cityEdition,
  };
  if ("intentID" in input) result.intentID = uuid(input.intentID);
  if ((preparing || source === "communityOrder") && !result.intentID) fail();
  if ("districtOrder" in input) {
    const order = input.districtOrder;
    if (source !== "communityOrder" || typeof order !== "string" || order.trim() !== order ||
        !order || order.length > 256 || /[\x00-\x1f\x7f]/.test(order)) fail();
    result.districtOrder = order;
  }
  return result;
}

async function readJSON(body: ReadableStream<Uint8Array> | null, limit: number): Promise<unknown> {
  if (!body) fail();
  const reader = body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let size = 0, text = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) { await reader.cancel(); fail(); }
      text += decoder.decode(value, { stream: true });
    }
    return JSON.parse(text + decoder.decode());
  } finally { reader.releaseLock(); }
}
export async function remoteJSON(response: Response, limit = 8192): Promise<Fields> {
  return obj(await readJSON(response.body, limit));
}

function settings() {
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!anon || !service || Deno.env.get("SUPABASE_URL") !== origin) fail("service_unavailable");
  return { anon, service };
}
async function identity(request: Request): Promise<Identity> {
  const jwt = request.headers.get("Authorization") ?? "";
  if (!/^Bearer [\w-]+\.[\w-]+\.[\w-]+$/.test(jwt) || jwt.length > 16384) fail("auth_required");
  const { anon } = settings();
  const result = await fetch(origin + "/auth/v1/user", {
    headers: { apikey: anon, Authorization: jwt }, redirect: "error", signal: AbortSignal.timeout(4500),
  });
  if (result.status === 401 || result.status === 403) fail("auth_required");
  if (!result.ok) fail("service_unavailable");
  try {
    const user = await remoteJSON(result, 65536);
    // Auth has verified this exact token. Its session must still exist at write time.
    const claims = obj(JSON.parse(atob(jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))));
    if (claims.sub !== user.id || claims.role !== "authenticated" || user.is_anonymous !== false ||
        obj(user.app_metadata).sign_in_method !== "device") fail("auth_required");
    return { actor: uuid(user.id), session_key: uuid(claims.session_id) };
  } catch { fail("auth_required"); }
}

export async function rpc(name: string, args: Fields): Promise<Fields> {
  const { service } = settings();
  const response = await fetch(origin + "/rest/v1/rpc/" + name, {
    method: "POST", headers: { apikey: service, Authorization: "Bearer " + service, "Content-Type": "application/json" },
    body: JSON.stringify(args), signal: AbortSignal.timeout(7000), redirect: "error",
  });
  const result = await remoteJSON(response, 8192);
  if (!response.ok) {
    if (typeof result.message === "string" && Object.hasOwn(errors, result.message)) fail(result.message);
    fail("service_unavailable");
  }
  if (typeof result.reason === "string" && Object.hasOwn(errors, result.reason)) fail(result.reason);
  return result;
}

export function walletEndpoint(handle: (member: Identity, request: Fields) => Promise<Fields>) {
  return async (request: Request) => {
    const headers = { "Cache-Control": "no-store" };
    if (request.method !== "POST") return Response.json({ code: 405, message: "POST required." }, { status: 405, headers });
    if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
      return Response.json({ code: 415, message: "JSON required." }, { status: 415, headers });
    }
    try {
      const member = await identity(request);
      let input: Fields;
      try { input = obj(await readJSON(request.body, 4 * 1024 * 1024)); } catch { fail(); }
      const data = await handle(member, input);
      if (!Number.isSafeInteger(data.balance) || (data.balance as number) < 0) fail("service_unavailable");
      return Response.json({ code: 0, message: "ok", data }, { headers });
    } catch (error) {
      const reason = error instanceof WalletFailure && Object.hasOwn(errors, error.message) ? error.message : "service_unavailable";
      const [status, message] = errors[reason];
      return Response.json({ code: status, reason, message }, { status, headers });
    }
  };
}
