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
  status: "RINGING" | "ANSWERED" | "MISSED" | "CANCELLED"
  ended_at: string | null
}

type PushTokenRow = {
  expo_push_token: string
  user_id: string
}

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders })
    }

    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405)
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "Missing environment variables" }, 500)
    }

    const authHeader = req.headers.get("Authorization")
    const userToken = authHeader?.replace(/^Bearer\s+/i, "")

    if (!userToken) {
      return json({ error: "Unauthorized" }, 401)
    }

    const user = await fetchAuthenticatedUser(supabaseUrl, serviceRoleKey, userToken)

    if (!user?.id) {
      return json({ error: "Unauthorized" }, 401)
    }

    const payload = await req.json().catch(() => null)
    const callId = extractCallId(payload)

    if (!isUuid(callId)) {
      await insertGenericPushDiagnostic(supabaseUrl, serviceRoleKey, user.id, "ERROR", {
        payload_shape: describePayload(payload),
        reason: "invalid_call_id",
      }, "Invalid call_id")
      return json({ error: "Invalid call_id" }, 400)
    }

    const call = await fetchCall(supabaseUrl, serviceRoleKey, callId)

    if (!call) {
      await insertGenericPushDiagnostic(supabaseUrl, serviceRoleKey, user.id, "ERROR", {
        call_id: callId,
        reason: "call_not_found",
      }, "Call not found")
      return json({ error: "Call not found" }, 404)
    }

    if (call.status !== "RINGING" || call.ended_at !== null) {
      await insertPushDiagnostic(supabaseUrl, serviceRoleKey, call, user.id, "SUCCESS", {
        call_status: call.status,
        ended_at: call.ended_at,
        reason: "call_not_ringing",
        target_type: call.target_type,
      })
      return json({ skipped: true, reason: "call_not_ringing" })
    }

    const requesterCanNotify = await userCanSeeCall(supabaseUrl, serviceRoleKey, call, user.id)

    if (!requesterCanNotify) {
      await insertPushDiagnostic(supabaseUrl, serviceRoleKey, call, user.id, "ERROR", {
        origin_portaria_device_id: call.origin_portaria_device_id,
        origin_type: call.origin_type,
        origin_unit_id: call.origin_unit_id,
        reason: "requester_cannot_notify",
        target_portaria_device_id: call.target_portaria_device_id,
        target_type: call.target_type,
        unit_id: call.unit_id,
      }, "Forbidden")
      return json({ error: "Forbidden" }, 403)
    }

    const recipients = await fetchRecipientTokens(supabaseUrl, serviceRoleKey, call, user.id)

    if (recipients.length === 0) {
      await insertPushDiagnostic(supabaseUrl, serviceRoleKey, call, user.id, "SUCCESS", {
        reason: "no_tokens",
        recipient_user_count: 0,
        target_type: call.target_type,
      })
      return json({ sent: 0, tickets: [], skipped: true, reason: "no_tokens" })
    }

    const message = buildNotificationMessage(call)
    const pushMessages = recipients.map((recipient) => ({
      to: recipient.expo_push_token,
      sound: "default",
      title: message.title,
      body: message.body,
      data: {
        call_id: call.id,
        condominium_id: call.condominium_id,
        kind: "incoming_call",
        target_type: call.target_type,
      },
      priority: "high",
      channelId: "incoming-calls",
    }))

    const tickets = await sendExpoPushNotifications(pushMessages)
      .catch(async (error) => {
        const message = error instanceof Error ? error.message : "Unknown Expo push error"
        await insertPushDiagnostic(supabaseUrl, serviceRoleKey, call, user.id, "ERROR", {
          recipient_user_count: new Set(recipients.map((recipient) => recipient.user_id)).size,
          sent_token_count: recipients.length,
          target_type: call.target_type,
        }, message)

        throw error
      })

    await insertPushDiagnostic(supabaseUrl, serviceRoleKey, call, user.id, "SUCCESS", {
      recipient_user_count: new Set(recipients.map((recipient) => recipient.user_id)).size,
      sent_token_count: recipients.length,
      target_type: call.target_type,
      tickets,
    })

    return json({ sent: recipients.length, tickets })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown send-call-notification error"
    return json({ error: message }, 500)
  }
})

async function fetchAuthenticatedUser(supabaseUrl: string, serviceRoleKey: string, userToken: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${userToken}`,
    },
  })

  if (!response.ok) {
    return null
  }

  return response.json()
}

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

async function userCanSeeCall(supabaseUrl: string, serviceRoleKey: string, call: CallRecord, userId: string) {
  const units = new Set<string>([call.unit_id])

  if (call.origin_unit_id) {
    units.add(call.origin_unit_id)
  }

  const unitIds = Array.from(units)
  const unitMembershipUrl = `${supabaseUrl}/rest/v1/unit_members?user_id=eq.${userId}&unit_id=in.(${unitIds.join(",")})&select=id&limit=1`
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

  const portariaUrl = `${supabaseUrl}/rest/v1/portaria_devices?user_id=eq.${userId}&id=in.(${portariaDeviceIds.join(",")})&select=id&limit=1`
  const portariaResponse = await fetch(portariaUrl, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!portariaResponse.ok) {
    return false
  }

  const rows = await portariaResponse.json()
  return rows.length > 0
}

async function fetchRecipientTokens(supabaseUrl: string, serviceRoleKey: string, call: CallRecord, initiatorUserId: string) {
  const recipientUserIds = await fetchRecipientUserIds(supabaseUrl, serviceRoleKey, call)
  const uniqueRecipientUserIds = Array.from(new Set(recipientUserIds.filter((userId) => userId !== initiatorUserId)))

  if (uniqueRecipientUserIds.length === 0) {
    return []
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/app_push_tokens?user_id=in.(${uniqueRecipientUserIds.join(",")})&is_active=eq.true&select=expo_push_token,user_id`,
    { headers: serviceHeaders(serviceRoleKey) },
  )

  if (!response.ok) {
    return []
  }

  return (await response.json()) as PushTokenRow[]
}

async function fetchRecipientUserIds(supabaseUrl: string, serviceRoleKey: string, call: CallRecord): Promise<string[]> {
  if (call.target_type === "PORTARIA" && call.target_portaria_device_id) {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/portaria_devices?id=eq.${call.target_portaria_device_id}&is_active=eq.true&can_receive_calls=eq.true&select=user_id`,
      { headers: serviceHeaders(serviceRoleKey) },
    )

    if (!response.ok) {
      return []
    }

    const rows = await response.json()
    return rows.map((row: { user_id: string }) => row.user_id)
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/call_attempts?call_id=eq.${call.id}&status=eq.RINGING&select=unit_member_id,unit_members(user_id,active_for_calls,can_receive_calls)`,
    { headers: serviceHeaders(serviceRoleKey) },
  )

  if (!response.ok) {
    return []
  }

  const rows = await response.json()
  return rows
    .filter((row: { unit_members?: { user_id?: string; active_for_calls?: boolean; can_receive_calls?: boolean } }) =>
      row.unit_members?.user_id && row.unit_members.active_for_calls !== false && row.unit_members.can_receive_calls !== false
    )
    .map((row: { unit_members: { user_id: string } }) => row.unit_members.user_id)
}

function buildNotificationMessage(call: CallRecord) {
  if (call.target_type === "PORTARIA") {
    return {
      title: "Chamada para a portaria",
      body: "Uma unidade esta chamando a portaria.",
    }
  }

  if (call.origin_type === "PORTARIA") {
    return {
      title: "Chamada da portaria",
      body: "A portaria esta chamando sua unidade.",
    }
  }

  return {
    title: "Chamada recebida",
    body: "Uma unidade do condominio esta chamando.",
  }
}

async function sendExpoPushNotifications(messages: unknown[]) {
  const response = await fetch("https://exp.host/--/api/v2/push/send", {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Accept-Encoding": "gzip, deflate",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(messages),
  })

  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`Expo push failed: ${response.status} ${body}`)
  }

  return response.json()
}

async function insertPushDiagnostic(
  supabaseUrl: string,
  serviceRoleKey: string,
  call: CallRecord,
  userId: string,
  result: "SUCCESS" | "ERROR",
  metadata: Record<string, unknown>,
  errorMessage: string | null = null,
) {
  await fetch(`${supabaseUrl}/rest/v1/app_call_diagnostics`, {
    method: "POST",
    headers: {
      ...serviceHeaders(serviceRoleKey),
      "Prefer": "return=minimal",
    },
    body: JSON.stringify({
      action: "push_notification_dispatch",
      call_id: call.id,
      condominium_id: call.condominium_id,
      error_message: errorMessage,
      metadata,
      result,
      user_id: userId,
    }),
  }).catch(() => {
    // Diagnostics cannot interfere with the call flow.
  })
}

async function insertGenericPushDiagnostic(
  supabaseUrl: string,
  serviceRoleKey: string,
  userId: string,
  result: "SUCCESS" | "ERROR",
  metadata: Record<string, unknown>,
  errorMessage: string | null = null,
) {
  await fetch(`${supabaseUrl}/rest/v1/app_call_diagnostics`, {
    method: "POST",
    headers: {
      ...serviceHeaders(serviceRoleKey),
      "Prefer": "return=minimal",
    },
    body: JSON.stringify({
      action: "push_notification_dispatch",
      error_message: errorMessage,
      metadata,
      result,
      user_id: userId,
    }),
  }).catch(() => {
    // Diagnostics cannot interfere with the call flow.
  })
}

function serviceHeaders(serviceRoleKey: string) {
  return {
    "Content-Type": "application/json",
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
  }
}

function isUuid(value: unknown) {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{12}$/i.test(value)
}

function extractCallId(payload: unknown) {
  if (typeof payload === "string") {
    if (isUuid(payload)) {
      return payload
    }

    const parsed = parseJsonObject(payload)
    return extractCallId(parsed)
  }

  if (!payload || typeof payload !== "object") {
    return null
  }

  const record = payload as Record<string, unknown>
  const directCallId = record.call_id ?? record.callId

  if (isUuid(directCallId)) {
    return directCallId
  }

  const nestedBody = record.body
  if (typeof nestedBody === "string") {
    return extractCallId(nestedBody)
  }

  if (nestedBody && typeof nestedBody === "object") {
    return extractCallId(nestedBody)
  }

  return null
}

function parseJsonObject(value: string) {
  try {
    return JSON.parse(value)
  } catch {
    return null
  }
}

function describePayload(payload: unknown) {
  if (payload === null) {
    return { type: "null" }
  }

  if (Array.isArray(payload)) {
    return { length: payload.length, type: "array" }
  }

  if (typeof payload === "object") {
    const record = payload as Record<string, unknown>
    return {
      keys: Object.keys(record),
      type: "object",
    }
  }

  return {
    type: typeof payload,
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
