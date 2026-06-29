const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

type DeliveryRecord = {
  id: string
  condominium_id: string
  unit_id: string
  status: string
  package_source: string | null
  package_description: string
  received_by_user_id: string
}

type PushTokenRow = {
  expo_push_token: string
  native_push_provider: string | null
  native_push_token: string | null
  user_id: string
}

type FirebaseServiceAccount = {
  client_email: string
  private_key: string
  project_id: string
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
    const deliveryId = extractDeliveryId(payload)

    if (!isUuid(deliveryId)) {
      return json({ error: "Invalid delivery_id" }, 400)
    }

    const delivery = await fetchDelivery(supabaseUrl, serviceRoleKey, deliveryId)

    if (!delivery) {
      return json({ error: "Delivery not found" }, 404)
    }

    if (delivery.received_by_user_id !== user.id) {
      return json({ error: "Forbidden" }, 403)
    }

    const recipientUserIds = await fetchDeliveryRecipientUserIds(supabaseUrl, serviceRoleKey, delivery.id)
    const recipients = await fetchRecipientTokens(supabaseUrl, serviceRoleKey, recipientUserIds)

    if (recipients.length === 0) {
      await insertDiagnostic(supabaseUrl, serviceRoleKey, user.id, "SUCCESS", {
        delivery_id: delivery.id,
        reason: "no_tokens",
        recipient_user_count: recipientUserIds.length,
      })
      return json({ sent: 0, skipped: true, reason: "no_tokens" })
    }

    const unitLabel = await fetchUnitLabel(supabaseUrl, serviceRoleKey, delivery.unit_id)
    const body = [delivery.package_source, delivery.package_description].filter(Boolean).join(" - ")
    const notification = {
      title: `Encomenda para ${unitLabel}`,
      body: body.length > 110 ? `${body.slice(0, 107)}...` : body,
    }
    const expoMessages = recipients.map((recipient) => ({
      to: recipient.expo_push_token,
      sound: "default",
      channelId: "deliveries-v1",
      title: notification.title,
      body: notification.body,
      data: {
        delivery_id: delivery.id,
        kind: "delivery",
      },
      priority: "high",
    }))
    const fcmMessages = recipients
      .filter((recipient) => isFcmProvider(recipient.native_push_provider) && recipient.native_push_token)
      .map((recipient) => ({
        token: recipient.native_push_token as string,
        notification,
        data: {
          body: notification.body,
          delivery_id: delivery.id,
          kind: "delivery",
          title: notification.title,
        },
      }))

    const tickets = await sendExpoPushNotifications(expoMessages)
    const fcmResults = await sendNativeFcmNotifications(fcmMessages)
    await markDeliveryNotified(supabaseUrl, serviceRoleKey, delivery.id, recipientUserIds)
    await insertDiagnostic(supabaseUrl, serviceRoleKey, user.id, "SUCCESS", {
      delivery_id: delivery.id,
      fcm_results: fcmResults,
      fcm_token_count: fcmMessages.length,
      recipient_user_count: recipientUserIds.length,
      sent_token_count: recipients.length,
      tickets,
    })

    return json({ sent: recipients.length, tickets })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown send-delivery-notification error"
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

async function fetchDelivery(supabaseUrl: string, serviceRoleKey: string, deliveryId: string): Promise<DeliveryRecord | null> {
  const select = "id,condominium_id,unit_id,status,package_source,package_description,received_by_user_id"
  const response = await fetch(`${supabaseUrl}/rest/v1/deliveries?id=eq.${deliveryId}&select=${select}&limit=1`, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!response.ok) {
    return null
  }

  const rows = await response.json()
  return rows?.[0] ?? null
}

async function fetchDeliveryRecipientUserIds(supabaseUrl: string, serviceRoleKey: string, deliveryId: string) {
  const response = await fetch(`${supabaseUrl}/rest/v1/delivery_recipients?delivery_id=eq.${deliveryId}&select=user_id`, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!response.ok) {
    return []
  }

  const rows = await response.json()
  return Array.from(new Set(rows.map((row: { user_id: string }) => row.user_id).filter(Boolean))) as string[]
}

async function fetchRecipientTokens(supabaseUrl: string, serviceRoleKey: string, userIds: string[]) {
  if (userIds.length === 0) {
    return []
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/app_push_tokens?user_id=in.(${userIds.join(",")})&is_active=eq.true&select=expo_push_token,native_push_token,native_push_provider,user_id`,
    { headers: serviceHeaders(serviceRoleKey) },
  )

  if (!response.ok) {
    return []
  }

  return (await response.json()) as PushTokenRow[]
}

async function fetchUnitLabel(supabaseUrl: string, serviceRoleKey: string, unitId: string) {
  const response = await fetch(`${supabaseUrl}/rest/v1/units?id=eq.${unitId}&select=block,number&limit=1`, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!response.ok) {
    return "unidade"
  }

  const rows = await response.json()
  const unit = rows?.[0]
  return [unit?.block, unit?.number].filter(Boolean).join(" - ") || "unidade"
}

async function markDeliveryNotified(supabaseUrl: string, serviceRoleKey: string, deliveryId: string, userIds: string[]) {
  const now = new Date().toISOString()

  await fetch(`${supabaseUrl}/rest/v1/deliveries?id=eq.${deliveryId}`, {
    method: "PATCH",
    headers: {
      ...serviceHeaders(serviceRoleKey),
      "Prefer": "return=minimal",
    },
    body: JSON.stringify({
      first_notified_at: now,
      last_notified_at: now,
      next_notification_at: null,
      notification_count: 1,
      status: "NOTIFIED",
      updated_at: now,
    }),
  }).catch(() => null)

  if (userIds.length > 0) {
    await fetch(`${supabaseUrl}/rest/v1/delivery_recipients?delivery_id=eq.${deliveryId}&user_id=in.(${userIds.join(",")})`, {
      method: "PATCH",
      headers: {
        ...serviceHeaders(serviceRoleKey),
        "Prefer": "return=minimal",
      },
      body: JSON.stringify({
        notified_at: now,
        notification_count: 1,
      }),
    }).catch(() => null)
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

async function sendNativeFcmNotifications(
  messages: Array<{ token: string; notification: { title: string; body: string }; data: Record<string, string> }>,
) {
  if (messages.length === 0) {
    return { skipped: true, reason: "no_native_tokens" }
  }

  const serviceAccount = getFirebaseServiceAccount()

  if (!serviceAccount) {
    return { skipped: true, reason: "missing_firebase_service_account", token_count: messages.length }
  }

  const accessToken = await getFirebaseAccessToken(serviceAccount)
  const results = []

  for (const message of messages) {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          android: {
            priority: "HIGH",
            ttl: "300s",
          },
          data: message.data,
          token: message.token,
        },
      }),
    })

    const body = await response.json().catch(async () => ({ raw: await response.text().catch(() => "") }))
    results.push({
      body,
      ok: response.ok,
      status: response.status,
      token_prefix: message.token.slice(0, 12),
    })
  }

  return results
}

function getFirebaseServiceAccount(): FirebaseServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")

  if (!raw) {
    return null
  }

  try {
    const parsed = JSON.parse(raw) as Partial<FirebaseServiceAccount>

    if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
      return null
    }

    return {
      client_email: parsed.client_email,
      private_key: parsed.private_key,
      project_id: parsed.project_id,
    }
  } catch {
    return null
  }
}

async function getFirebaseAccessToken(serviceAccount: FirebaseServiceAccount) {
  const now = Math.floor(Date.now() / 1000)
  const jwtHeader = { alg: "RS256", typ: "JWT" }
  const jwtClaim = {
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  }
  const unsignedJwt = `${base64UrlEncode(JSON.stringify(jwtHeader))}.${base64UrlEncode(JSON.stringify(jwtClaim))}`
  const key = await importPrivateKey(serviceAccount.private_key)
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsignedJwt))
  const assertion = `${unsignedJwt}.${base64UrlEncode(signature)}`
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      assertion,
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    }).toString(),
  })

  const body = await response.json()

  if (!response.ok || !body.access_token) {
    throw new Error(`Firebase auth failed: ${response.status} ${JSON.stringify(body)}`)
  }

  return body.access_token as string
}

async function importPrivateKey(privateKey: string) {
  const pem = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "")
  const binary = Uint8Array.from(atob(pem), (char) => char.charCodeAt(0))

  return crypto.subtle.importKey(
    "pkcs8",
    binary,
    {
      hash: "SHA-256",
      name: "RSASSA-PKCS1-v1_5",
    },
    false,
    ["sign"],
  )
}

function base64UrlEncode(value: string | ArrayBuffer) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value)
  let binary = ""

  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

function isFcmProvider(provider: string | null) {
  return provider === "fcm" || provider === "android"
}

async function insertDiagnostic(
  supabaseUrl: string,
  serviceRoleKey: string,
  userId: string | null,
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
      action: "delivery_notification_dispatch",
      error_message: errorMessage,
      metadata,
      result,
      user_id: userId,
    }),
  }).catch(() => {
    // Diagnostics cannot interfere with the delivery flow.
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

function extractDeliveryId(payload: unknown) {
  if (!payload || typeof payload !== "object") {
    return null
  }

  const record = payload as Record<string, unknown>
  return record.delivery_id ?? record.deliveryId ?? null
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
