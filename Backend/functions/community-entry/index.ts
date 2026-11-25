const projectOrigin = "https://ujclifehtfrxtrijlaia.supabase.co";
type ConsoleBinding = { origin: string; appID: string };
function consoleBinding(): ConsoleBinding | null {
  // A deployment without an external console returns the native empty configuration.
  return { origin: "https://sese.huisgdd.top", appID: "32948410" };
}
const uuid = /^[a-f\d]{8}-(?:[a-f\d]{4}-){3}[a-f\d]{12}$/i;

function reply(status: number, code: number, message: string, data?: object) {
  return Response.json({ code, message, ...(data && { data }) }, {
    status, headers: { "Cache-Control": "no-store" },
  });
}

async function readJSON(body: ReadableStream<Uint8Array> | null, limit: number) {
  if (!body) throw new Error("Missing response");
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) {
        await reader.cancel();
        throw new Error("Body limit exceeded");
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405, 405, "POST required");
  if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json") {
    return reply(415, 415, "JSON required");
  }
  const jwt = request.headers.get("Authorization");
  if (!jwt?.startsWith("Bearer ")) return reply(401, 401, "Sign in required");
  let input;
  try { input = await readJSON(request.body, 4096); }
  catch { return reply(400, 400, "Invalid entry request"); }
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      typeof input.cityEdition !== "string" || !/^\d+(?:\.\d+){0,3}$/.test(input.cityEdition) ||
      typeof input.installationID !== "string" || !uuid.test(input.installationID) ||
      typeof input.cityPushToken !== "string" || !/^(?:[a-f0-9]{2}){0,256}$/.test(input.cityPushToken) ||
      input.subscriptionMode !== 2 || typeof input.agreement_revision !== "string" ||
      !/^sha256:[a-f0-9]{64}$/.test(input.agreement_revision)) return reply(400, 400, "Invalid entry request");

  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!key || Deno.env.get("SUPABASE_URL") !== projectOrigin) return reply(503, 503, "Configuration unavailable");
  try {
    const result = await fetch(projectOrigin + "/rest/v1/rpc/bootstrap", {
      method: "POST", headers: { apikey: key, Authorization: jwt, "Content-Type": "application/json" },
      body: JSON.stringify({ agreement_revision: input.agreement_revision }), redirect: "error",
      signal: AbortSignal.timeout(8000),
    });
    if (!result.ok) return reply(result.status === 401 || result.status === 403 ? result.status : 502, 1, "Account entry failed");
    const record = await readJSON(result.body, 2048);
    if (record?.code !== 0 || !record.data || Array.isArray(record.data) ||
        typeof record.data !== "object") return reply(502, 2, "Account entry failed");

    const console = consoleBinding();
    if (!console) return reply(200, 0, "ok", {});
    const { cityEdition, installationID, cityPushToken, subscriptionMode } = input;
    const response = await fetch(console.origin + "/community/member/entry", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ cityEdition, installationID, cityPushToken, subscriptionMode }),
      redirect: "error", signal: AbortSignal.timeout(10000),
    });
    if (!response.ok && response.status !== 401) return reply(502, 3, "Entry service unavailable");
    const resultBody = await readJSON(response.body, 1024 * 1024);
    if (!Number.isSafeInteger(resultBody?.code) || !resultBody.data || Array.isArray(resultBody.data) ||
        typeof resultBody.data !== "object") return reply(502, 4, "Invalid entry response");
    const external = Object.hasOwn(resultBody.data, "communityPage");
    if (!external && (!response.ok || resultBody.code !== 0)) return reply(502, 5, "Entry declined");
    return reply(200, 0, "ok", { communityOrigin: external ? console.origin : projectOrigin, communityApp: console.appID });
  } catch {
    return reply(502, 6, "Entry service unavailable");
  }
});
