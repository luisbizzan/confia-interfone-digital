const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

type CallRecord = {
  id: string
  condominium_id: string
  unit_id: string
  origin_type: "PORTARIA" | "UNIT"
  origin_unit_id: string | null
  origin_portaria_device_id: string | null
  target_type: "PORTARIA" | "UNIT"
  target_portaria_device_id: string | null
  status: string
  ended_at: string | null
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const livekitUrl = Deno.env.get("LIVEKIT_URL")
  const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY")
  const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET")

  if (!supabaseUrl || !serviceRoleKey || !livekitUrl || !livekitApiKey || !livekitApiSecret) {
    return json({ error: "Missing environment variables" }, 500)
  }

  const authHeader = req.headers.get("Authorization")
  const userToken = authHeader?.replace(/^Bearer\s+/i, "")

  if (!userToken) {
    return json({ error: "Unauthorized" }, 401)
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${userToken}`,
    },
  })

  if (!userResponse.ok) {
    return json({ error: "Unauthorized" }, 401)
  }

  const user = await userResponse.json()
  const userId = user?.id

  if (!userId) {
    return json({ error: "Unauthorized" }, 401)
  }

  const payload = await req.json().catch(() => null)
  const callId = payload?.call_id

  if (!isUuid(callId)) {
    return json({ error: "Invalid call_id" }, 400)
  }

  const call = await fetchCall(supabaseUrl, serviceRoleKey, callId)

  if (!call) {
    return json({ error: "Call not found" }, 404)
  }

  if (call.status !== "ANSWERED" || call.ended_at !== null) {
    return json({ error: "Call is not active" }, 409)
  }

  const canJoin = await userCanJoinCall(supabaseUrl, serviceRoleKey, call, userId)

  if (!canJoin) {
    return json({ error: "User cannot join this call" }, 403)
  }

  const roomName = `confia-call-${call.id}`
  const identity = `confia-user-${userId}`
  const token = await createLiveKitToken({
    apiKey: livekitApiKey,
    apiSecret: livekitApiSecret,
    identity,
    roomName,
    ttlSeconds: 60 * 30,
  })

  return json({
    serverUrl: livekitUrl,
    roomName,
    identity,
    token,
    expiresInSeconds: 60 * 30,
  })
})

async function fetchCall(supabaseUrl: string, serviceRoleKey: string, callId: string): Promise<CallRecord | null> {
  const select = [
    "id",
    "condominium_id",
    "unit_id",
    "origin_type",
    "origin_unit_id",
    "origin_portaria_device_id",
    "target_type",
    "target_portaria_device_id",
    "status",
    "ended_at",
  ].join(",")

  const response = await fetch(`${supabaseUrl}/rest/v1/calls?id=eq.${callId}&select=${select}&limit=1`, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!response.ok) {
    return null
  }

  const rows = await response.json()
  return rows?.[0] ?? null
}

async function userCanJoinCall(supabaseUrl: string, serviceRoleKey: string, call: CallRecord, userId: string) {
  const units = new Set<string>()
  units.add(call.unit_id)

  if (call.origin_unit_id) {
    units.add(call.origin_unit_id)
  }

  const unitIds = Array.from(units)
  const unitMembershipUrl = `${supabaseUrl}/rest/v1/unit_members?user_id=eq.${userId}&unit_id=in.(${unitIds.join(",")})&active_for_calls=eq.true&select=id&limit=1`
  const unitMembershipResponse = await fetch(unitMembershipUrl, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (unitMembershipResponse.ok) {
    const rows = await unitMembershipResponse.json()
    if (rows.length > 0) {
      return true
    }
  }

  const portariaDeviceIds = [call.origin_portaria_device_id, call.target_portaria_device_id].filter(Boolean)

  if (portariaDeviceIds.length === 0) {
    return false
  }

  const portariaUrl = `${supabaseUrl}/rest/v1/portaria_devices?user_id=eq.${userId}&id=in.(${portariaDeviceIds.join(",")})&is_active=eq.true&select=id&limit=1`
  const portariaResponse = await fetch(portariaUrl, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!portariaResponse.ok) {
    return false
  }

  const portariaRows = await portariaResponse.json()
  return portariaRows.length > 0
}

async function createLiveKitToken(input: {
  apiKey: string
  apiSecret: string
  identity: string
  roomName: string
  ttlSeconds: number
}) {
  const now = Math.floor(Date.now() / 1000)
  const header = {
    alg: "HS256",
    typ: "JWT",
  }
  const payload = {
    exp: now + input.ttlSeconds,
    iss: input.apiKey,
    nbf: now - 10,
    sub: input.identity,
    video: {
      room: input.roomName,
      roomJoin: true,
      canPublish: true,
      canPublishData: true,
      canPublishSources: ["microphone"],
      canSubscribe: true,
    },
  }

  const unsignedToken = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`
  const signature = await hmacSha256(input.apiSecret, unsignedToken)
  return `${unsignedToken}.${signature}`
}

async function hmacSha256(secret: string, value: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value))
  return base64UrlEncode(new Uint8Array(signature))
}

function base64UrlEncode(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value
  let binary = ""

  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

function serviceHeaders(serviceRoleKey: string) {
  return {
    "Content-Type": "application/json",
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
  }
}

function isUuid(value: unknown) {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
