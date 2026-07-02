// Pushes an updated capsule to a device's Live Activity via APNs.
// Called by the iOS monitor extension on each usage-threshold event.
//
// Secrets required (supabase secrets set ...):
//   APNS_KEY       contents of the AuthKey_XXXX.p8 (PEM)
//   APNS_KEY_ID    the key's 10-char Key ID
//   APNS_TEAM_ID   your Apple Developer Team ID
//   APNS_BUNDLE_ID app bundle id, e.g. com.sodhera.capsule
//   APNS_HOST      api.sandbox.push.apple.com (dev builds) or
//                  api.push.apple.com (TestFlight/App Store)   [optional]
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { device_id, app_nickname, used_minutes, limit_minutes } = await req.json();
    if (!device_id) return json({ error: "device_id required" }, 400);

    const missing = ["APNS_KEY", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID"]
      .filter((k) => !Deno.env.get(k));
    if (missing.length) return json({ error: `APNs not configured: missing ${missing.join(", ")}` }, 503);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data, error } = await supabase
      .from("capsule_tokens").select("token").eq("device_id", device_id).single();
    if (error || !data) return json({ error: "no token for device" }, 404);

    const host = Deno.env.get("APNS_HOST") ?? "api.sandbox.push.apple.com";
    const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
    const now = Math.floor(Date.now() / 1000);

    const payload = {
      aps: {
        timestamp: now,
        event: "update",
        "content-state": {
          appNickname: app_nickname ?? "",
          usedMinutes: used_minutes ?? 0,
          limitMinutes: limit_minutes ?? 0,
          updatedAt: now,
        },
        "stale-date": now + 135,
      },
    };

    const jwt = await apnsJWT();
    const res = await fetch(`https://${host}/3/device/${data.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": `${bundleId}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "apns-expiration": "0",
      },
      body: JSON.stringify(payload),
    });

    if (res.status !== 200) {
      const body = await res.text();
      return json({ error: `APNs ${res.status}`, apns: body, apnsId: res.headers.get("apns-id") }, 502);
    }
    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

// --- APNs provider JWT (ES256), cached ~30 min ---------------------------

let cachedJWT: { token: string; at: number } | null = null;

async function apnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.at < 1800) return cachedJWT.token;

  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;

  const key = await importP8(Deno.env.get("APNS_KEY")!);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const token = `${signingInput}.${b64urlBytes(new Uint8Array(sig))}`;
  cachedJWT = { token, at: now };
  return token;
}

async function importP8(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function b64url(s: string): string {
  return b64urlBytes(new TextEncoder().encode(s));
}

function b64urlBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}
