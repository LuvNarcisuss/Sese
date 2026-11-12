const credentialPattern = /^[a-f0-9]{64}$/;
const revisionPattern = /^sha256:[a-f0-9]{64}$/;
const accountDomain = "device.citycommunity.invalid";

function reply(status: number): Response {
  return new Response(null, { status, headers: { "Cache-Control": "no-store" } });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405);
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return reply(415);

  let credential: string;
  let revision: string;
  try {
    const payload = await request.text();
    if (payload.length > 512) return reply(413);
    const body = JSON.parse(payload);
    if (!body || typeof body.credential !== "string" || !credentialPattern.test(body.credential) ||
        typeof body.agreement_revision !== "string" || !revisionPattern.test(body.agreement_revision)) {
      return reply(400);
    }
    credential = body.credential;
    revision = body.agreement_revision;
  } catch {
    return reply(400);
  }

  const projectUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!projectUrl || !serviceKey) return reply(503);
  const headers = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };

  try {
    const reservation = await fetch(`${projectUrl}/rest/v1/rpc/reserve_device_provisioning`, {
      method: "POST",
      headers,
      body: JSON.stringify({ agreement_revision: revision }),
      signal: AbortSignal.timeout(4500),
    });
    if (!reservation.ok) return reply(503);
    const decision = await reservation.json();
    if (decision === 409 || decision === 429) return reply(decision);
    if (decision !== 204) return reply(503);

    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(credential)));
    const alias = Array.from(digest.slice(0, 24), (byte) => byte.toString(16).padStart(2, "0")).join("");
    const created = await fetch(`${projectUrl}/auth/v1/admin/users`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        email: `${alias}@${accountDomain}`,
        password: credential,
        email_confirm: true,
        app_metadata: { sign_in_method: "device" },
      }),
      signal: AbortSignal.timeout(6500),
    });
    if (created.ok) return reply(204);
    const error = await created.json().catch(() => null);
    if (error?.error_code === "email_exists" || error?.error_code === "user_already_exists") {
      // A parallel request may have created the account. Auth still verifies the password.
      return reply(204);
    }
    return reply(503);
  } catch {
    return reply(503);
  }
});
