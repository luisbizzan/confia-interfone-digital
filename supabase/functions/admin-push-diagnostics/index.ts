const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-secret",
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, 405)
  }

  const adminSecret = Deno.env.get("ADMIN_API_SECRET")
  const providedSecret = req.headers.get("x-admin-secret")

  if (!adminSecret || providedSecret !== adminSecret) {
    return json({ error: "Unauthorized" }, 401)
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Missing Supabase environment variables" }, 500)
  }

  const [tokens, diagnostics] = await Promise.all([
    fetchPushTokens(supabaseUrl, serviceRoleKey),
    fetchPushDiagnostics(supabaseUrl, serviceRoleKey),
  ])

  return json({ diagnostics, tokens })
})

async function fetchPushTokens(supabaseUrl: string, serviceRoleKey: string) {
  const select = [
    "id",
    "user_id",
    "profile",
    "platform",
    "device_name",
    "app_version",
    "app_build",
    "native_push_provider",
    "expo_push_token",
    "native_push_token",
    "is_active",
    "updated_at",
    "created_at",
  ].join(",")
  const response = await fetch(`${supabaseUrl}/rest/v1/app_push_tokens?select=${select}&order=updated_at.desc&limit=20`, {
    headers: serviceHeaders(serviceRoleKey),
  })

  const rows = await readJson(response)
  if (!response.ok || !Array.isArray(rows)) {
    return { error: rows }
  }

  return rows.map((row) => ({
    ...row,
    expo_push_token: summarizeToken(row.expo_push_token),
    native_push_token: summarizeToken(row.native_push_token),
  }))
}

async function fetchPushDiagnostics(supabaseUrl: string, serviceRoleKey: string) {
  const select = [
    "id",
    "action",
    "result",
    "error_message",
    "metadata",
    "call_id",
    "user_id",
    "created_at",
  ].join(",")
  const response = await fetch(
    `${supabaseUrl}/rest/v1/app_call_diagnostics?action=in.(push_notification_dispatch,delivery_notification_dispatch,message_notification_dispatch)&select=${select}&order=created_at.desc&limit=50`,
    { headers: serviceHeaders(serviceRoleKey) },
  )

  const rows = await readJson(response)
  if (!response.ok) {
    return { error: rows }
  }

  return rows
}

function summarizeToken(token: unknown) {
  if (typeof token !== "string" || !token) {
    return null
  }

  return {
    length: token.length,
    prefix: token.slice(0, 18),
    suffix: token.slice(-8),
  }
}

function serviceHeaders(serviceRoleKey: string) {
  return {
    "Content-Type": "application/json",
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
  }
}

async function readJson(response: Response) {
  const text = await response.text()
  if (!text) return {}

  try {
    return JSON.parse(text)
  } catch {
    return { raw: text }
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
