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
  const anonKey = requiredEnv("SUPABASE_ANON_KEY");
  const body = await request.json().catch(() => ({})) as RequestBody;

  if (body.action === "createDevice") {
    const authHeader = request.headers.get("Authorization") || "";
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false }
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

    const deviceToken = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
    const { data, error } = await userClient
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

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false }
    });
    const { data, error } = await client.rpc("garmin_fetch_pending_plan", {
      p_device_token: deviceToken
    });

    if (error) return json({ error: error.message }, 500);
    if (data?.error) return json({ error: data.error }, 401);
    return json(data || { status: "empty" });
  }

  return json({ error: "Unknown action" }, 400);
});
