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

  const url = new URL(req.url)
  const condominiumId = url.searchParams.get("condominium_id")
  const rpcName = condominiumId ? "admin_get_condominium_overview" : "admin_list_condominiums"
  const body = condominiumId ? { p_condominium_id: condominiumId } : {}

  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${rpcName}`, {
    method: "POST",
    headers: serviceHeaders(serviceRoleKey),
    body: JSON.stringify(body),
  })

  const responseBody = await readJson(response)
  if (!response.ok) {
    return json({ error: "Failed to load admin condominium data", details: responseBody }, response.status)
  }

  return json(responseBody)
})

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
