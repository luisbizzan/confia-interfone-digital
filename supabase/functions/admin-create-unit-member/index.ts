const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-secret",
}

type Payload = {
  condominium_id?: string
  unit_id?: string | null
  unit_type?: string | null
  unit_block?: string | null
  unit_number?: string | null
  resident_email?: string
  resident_password?: string
  member_type?: string | null
  call_order?: number | null
  active_for_calls?: boolean
  can_receive_calls?: boolean
  can_make_calls?: boolean
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

  let unitId = payload.unit_id ?? null

  if (!unitId) {
    const unitResponse = await rpc(supabaseUrl, serviceRoleKey, "admin_create_unit", {
      p_condominium_id: payload.condominium_id,
      p_type: payload.unit_type ?? "APARTMENT",
      p_block: payload.unit_block ?? null,
      p_number: payload.unit_number,
    })

    if (!unitResponse.ok) {
      return json({ error: "Failed to create unit", details: unitResponse.body }, unitResponse.status)
    }

    unitId = unitResponse.body.id
  }

  const authUserResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: serviceHeaders(serviceRoleKey),
    body: JSON.stringify({
      email: payload.resident_email,
      password: payload.resident_password,
      email_confirm: true,
      user_metadata: {
        role: "MORADOR",
        source: "admin-create-unit-member",
      },
    }),
  })

  const authUserBody = await readJson(authUserResponse)
  if (!authUserResponse.ok) {
    return json({ error: "Failed to create resident user", details: authUserBody }, authUserResponse.status)
  }

  const memberResponse = await rpc(supabaseUrl, serviceRoleKey, "admin_create_unit_member", {
    p_condominium_id: payload.condominium_id,
    p_unit_id: unitId,
    p_user_id: authUserBody.id,
    p_member_type: payload.member_type ?? "RESIDENT",
    p_call_order: payload.call_order ?? null,
    p_active_for_calls: payload.active_for_calls ?? true,
    p_can_receive_calls: payload.can_receive_calls ?? true,
    p_can_make_calls: payload.can_make_calls ?? true,
  })

  if (!memberResponse.ok) {
    await deleteAuthUser(supabaseUrl, serviceRoleKey, authUserBody.id)
    return json({ error: "Failed to create unit member", details: memberResponse.body }, memberResponse.status)
  }

  return json({
    unit_id: unitId,
    resident_user_id: authUserBody.id,
    unit_member_id: memberResponse.body.id,
  }, 201)
})

function validatePayload(payload: Payload) {
  if (!payload.condominium_id?.trim()) return "condominium_id is required"
  if (!payload.unit_id && !payload.unit_number?.trim()) return "unit_id or unit_number is required"
  if (!payload.resident_email?.trim()) return "resident_email is required"
  if (!payload.resident_password?.trim()) return "resident_password is required"
  if (payload.resident_password.trim().length < 8) return "resident_password must have at least 8 characters"
  return null
}

async function rpc(supabaseUrl: string, serviceRoleKey: string, fn: string, body: unknown) {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: serviceHeaders(serviceRoleKey),
    body: JSON.stringify(body),
  })

  return {
    ok: response.ok,
    status: response.status,
    body: await readJson(response),
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
