import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

type RequestBody = {
  action?: string;
  deviceToken?: string;
  displayName?: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const body = await request.json().catch(() => ({})) as RequestBody;
  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });

  if (body.action === "createDevice") {
    const authHeader = request.headers.get("Authorization") || "";
    const userClient = createClient(supabaseUrl, requiredEnv("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false }
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

    const deviceToken = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
    const { data, error } = await service
      .from("garmin_devices")
      .insert({
        user_id: userData.user.id,
        device_token: deviceToken,
        display_name: body.displayName || "Garmin watch"
      })
      .select("id, device_token, display_name, created_at")
      .single();

    if (error) return json({ error: error.message }, 500);
    return json({ device: data });
  }

  if (body.action === "fetchPlan") {
    const deviceToken = String(body.deviceToken || "").trim();
    if (!deviceToken) return json({ error: "Missing deviceToken" }, 400);

    const { data: device, error: deviceError } = await service
      .from("garmin_devices")
      .select("id, user_id, revoked_at")
      .eq("device_token", deviceToken)
      .maybeSingle();

    if (deviceError) return json({ error: deviceError.message }, 500);
    if (!device || device.revoked_at) return json({ error: "Invalid device" }, 401);

    await service
      .from("garmin_devices")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("id", device.id);

    const { data: plan, error: planError } = await service
      .from("garmin_plans")
      .select("id, plan")
      .eq("user_id", device.user_id)
      .eq("status", "pending")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (planError) return json({ error: planError.message }, 500);
    if (!plan) return json({ status: "empty" });

    await service
      .from("garmin_plans")
      .update({
        status: "downloaded",
        device_id: device.id,
        downloaded_at: new Date().toISOString()
      })
      .eq("id", plan.id);

    return json({ status: "ok", planId: plan.id, plan: plan.plan });
  }

  return json({ error: "Unknown action" }, 400);
});
