const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-secret",
}

type Payload = {
  condominium_name?: string
  condominium_document?: string | null
  portaria_email?: string
  portaria_password?: string
  portaria_device_name?: string | null
  intercom_enabled?: boolean
  create_default_unit?: boolean
  default_unit_type?: string | null
  default_unit_block?: string | null
  default_unit_number?: string | null
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "POST") {
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

  let payload: Payload
  try {
    payload = await req.json()
  } catch {
    return json({ error: "Invalid JSON body" }, 400)
  }

  const validationError = validatePayload(payload)
  if (validationError) {
    return json({ error: validationError }, 400)
  }

  const authUserResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: serviceHeaders(serviceRoleKey),
    body: JSON.stringify({
      email: payload.portaria_email,
      password: payload.portaria_password,
      email_confirm: true,
      user_metadata: {
        role: "PORTARIA",
        source: "admin-create-condominium",
      },
    }),
  })

  const authUserBody = await readJson(authUserResponse)
  if (!authUserResponse.ok) {
    return json({ error: "Failed to create portaria user", details: authUserBody }, authUserResponse.status)
  }

  const onboardingResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/admin_create_condominium_with_portaria`, {
    method: "POST",
    headers: serviceHeaders(serviceRoleKey),
    body: JSON.stringify({
      p_condominium_name: payload.condominium_name,
      p_condominium_document: payload.condominium_document ?? null,
      p_portaria_user_id: authUserBody.id,
      p_portaria_device_name: payload.portaria_device_name ?? "Portaria",
      p_intercom_enabled: payload.intercom_enabled ?? true,
      p_create_default_unit: payload.create_default_unit ?? false,
      p_default_unit_type: payload.default_unit_type ?? "APARTMENT",
      p_default_unit_block: payload.default_unit_block ?? null,
      p_default_unit_number: payload.default_unit_number ?? null,
    }),
  })

  const onboardingBody = await readJson(onboardingResponse)
  if (!onboardingResponse.ok) {
    await deleteAuthUser(supabaseUrl, serviceRoleKey, authUserBody.id)
    return json({ error: "Failed to create condominium onboarding", details: onboardingBody }, onboardingResponse.status)
  }

  return json({
    condominium_id: onboardingBody.condominium_id,
    portaria_user_id: onboardingBody.portaria_user_id,
    portaria_device_id: onboardingBody.portaria_device_id,
    default_unit_id: onboardingBody.default_unit_id,
  }, 201)
})

function validatePayload(payload: Payload) {
  if (!payload.condominium_name?.trim()) return "condominium_name is required"
  if (!payload.portaria_email?.trim()) return "portaria_email is required"
  if (!payload.portaria_password?.trim()) return "portaria_password is required"
  if (payload.portaria_password.trim().length < 8) return "portaria_password must have at least 8 characters"
  return null
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

async function deleteAuthUser(supabaseUrl: string, serviceRoleKey: string, userId?: string) {
  if (!userId) return

  await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
    headers: serviceHeaders(serviceRoleKey),
  })
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
