import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const clean = (k: string) => (Deno.env.get(k) ?? "").trim();
const PP = clean("PAYPAL_ENV").toLowerCase() === "live"
  ? "https://api-m.paypal.com"
  : "https://api-m.sandbox.paypal.com";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const STATUS: Record<string, string> = {
  ACTIVE: "active",
  CANCELLED: "cancelled",
  EXPIRED: "cancelled",
  SUSPENDED: "past_due",
  APPROVAL_PENDING: "pending",
  APPROVED: "pending",
};

async function token() {
  const r = await fetch(`${PP}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      Authorization: "Basic " +
        btoa(`${clean("PAYPAL_CLIENT_ID")}:${clean("PAYPAL_SECRET")}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  const j = await r.json();
  if (!j.access_token) console.error("TOKEN FAILED", r.status, JSON.stringify(j));
  return j.access_token as string | undefined;
}

async function getSub(t: string, subId: string) {
  const r = await fetch(`${PP}/v1/billing/subscriptions/${subId}`, {
    headers: { Authorization: `Bearer ${t}` },
  });
  const j = await r.json();
  if (!r.ok) console.error("SUB LOOKUP FAILED", r.status, JSON.stringify(j));
  return r.ok ? j : null;
}

// Called by the app: "is my payment active yet?"
async function sync(req: Request) {
  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const { data: u } = await sb.auth.getUser(jwt);
  if (!u?.user) return reply({ error: "not signed in" }, 401);

  const { data: prof } = await sb
    .from("profiles")
    .select("company_id")
    .eq("id", u.user.id)
    .maybeSingle();
  if (!prof) return reply({ error: "no profile" }, 403);

  const { data: co } = await sb
    .from("companies")
    .select("id,paypal_subscription_id")
    .eq("id", prof.company_id)
    .maybeSingle();
  if (!co?.paypal_subscription_id) return reply({ status: "none" });

  const t = await token();
  if (!t) return reply({ error: "paypal login failed" }, 500);
  const sub = await getSub(t, co.paypal_subscription_id);
  if (!sub) return reply({ error: "lookup failed" }, 500);
  console.log("SYNC", co.paypal_subscription_id, sub.status, sub.custom_id);

  if (sub.custom_id !== co.id) return reply({ status: "mismatch" });
  const status = STATUS[sub.status];
  if (!status || status === "pending") return reply({ status: "pending" });

  const patch: Record<string, unknown> = { subscription_status: status };
  if (status === "active") patch.plan = sub.plan_id;
  const { error: updateError } = await sb.from("companies").update(patch).eq("id", co.id);
  if (updateError) {
    console.error("SYNC COMPANY UPDATE FAILED", JSON.stringify(updateError));
    return reply({ error: "subscription update failed" }, 500);
  }
  return reply({ status });
}

async function verified(req: Request, event: unknown, t: string) {
  const h = req.headers;
  const r = await fetch(`${PP}/v1/notifications/verify-webhook-signature`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${t}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      auth_algo: h.get("paypal-auth-algo"),
      cert_url: h.get("paypal-cert-url"),
      transmission_id: h.get("paypal-transmission-id"),
      transmission_sig: h.get("paypal-transmission-sig"),
      transmission_time: h.get("paypal-transmission-time"),
      webhook_id: clean("PAYPAL_WEBHOOK_ID"),
      webhook_event: event,
    }),
  });
  const j = await r.json();
  console.log("VERIFY RESULT", r.status, JSON.stringify(j));
  return j.verification_status === "SUCCESS";
}

// Called by PayPal
async function webhook(req: Request, ev: any) {
  const t = await token();
  if (!t) return new Response("auth failed", { status: 400 });

  let ok = false;
  try {
    ok = await verified(req, ev, t);
  } catch (e) {
    console.error("VERIFY CRASHED", String(e));
  }
  if (!ok) return new Response("bad signature", { status: 400 });

  const r = ev.resource ?? {};
  const subId: string | undefined =
    String(ev.event_type).startsWith("PAYMENT.SALE")
      ? r.billing_agreement_id
      : r.id;
  if (!subId || !subId.startsWith("I-")) {
    console.log("NOT A SUBSCRIPTION EVENT", ev.event_type);
    return new Response("ok");
  }

  const sub = await getSub(t, subId);
  if (!sub) return new Response("lookup failed", { status: 500 });

  const status = STATUS[sub.status];
  const companyId: string | undefined = sub.custom_id;
  console.log("SUB", subId, sub.status, companyId, "event:", ev.event_type);
  if (!status || !companyId) return new Response("ok");

  // An old, non-active subscription must not override a newer one
  const { data: co } = await sb
    .from("companies")
    .select("paypal_subscription_id")
    .eq("id", companyId)
    .maybeSingle();
  if (
    status !== "active" && co?.paypal_subscription_id &&
    co.paypal_subscription_id !== subId
  ) {
    console.log("IGNORED OLD SUBSCRIPTION", subId);
    return new Response("ok");
  }

  const patch: Record<string, unknown> = {
    subscription_status: status,
    paypal_subscription_id: subId,
  };
  if (status === "active") patch.plan = sub.plan_id;
  const { error } = await sb.from("companies").update(patch).eq("id", companyId);
  if (error) {
    console.error("COMPANY UPDATE FAILED", JSON.stringify(error));
    return new Response("db error", { status: 500 });
  }
  return new Response("ok");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return new Response("ok", { headers: CORS });

  let ev;
  try {
    ev = await req.json();
  } catch {
    console.error("BAD JSON BODY");
    return new Response("bad request", { status: 400 });
  }
  if (ev?.action === "sync") return await sync(req);
  return await webhook(req, ev);
});