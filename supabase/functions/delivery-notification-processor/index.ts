const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
}

type DueDelivery = {
  condominium_id: string
  delivery_id: string
  next_notification_at: string
  notification_count: number
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }

  const cronSecret = Deno.env.get("CRON_SECRET")
  const providedSecret = req.headers.get("x-cron-secret")

  if (!cronSecret || providedSecret !== cronSecret) {
    return json({ error: "Unauthorized" }, 401)
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Missing Supabase environment variables" }, 500)
  }

  const dueDeliveries = await fetchDueDeliveries(supabaseUrl, serviceRoleKey)
  const results = []

  for (const delivery of dueDeliveries) {
    try {
      const notificationResult = await notifyDelivery(supabaseUrl, cronSecret, delivery.delivery_id)
      results.push({
        delivery_id: delivery.delivery_id,
        notified: notificationResult.ok,
        response: notificationResult.body,
        status: notificationResult.status,
      })
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown delivery reminder error"

      await insertDiagnostic(supabaseUrl, serviceRoleKey, null, "ERROR", {
        delivery_id: delivery.delivery_id,
        reason: "delivery_reminder_exception",
      }, message)

      results.push({
        delivery_id: delivery.delivery_id,
        error: message,
        notified: false,
      })
    }
  }

  const failedResults = results.filter((result) => !result.notified)
  await insertDiagnostic(supabaseUrl, serviceRoleKey, null, failedResults.length > 0 ? "ERROR" : "SUCCESS", {
    due: dueDeliveries.length,
    failed: failedResults.length,
    processed: results.length,
    results: results.slice(0, 25),
  }, failedResults.length > 0 ? "One or more due delivery notifications failed" : null)

  return json({
    due: dueDeliveries.length,
    processed: results.length,
    results,
  })
})

async function fetchDueDeliveries(supabaseUrl: string, serviceRoleKey: string): Promise<DueDelivery[]> {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/list_due_delivery_notifications`, {
    method: "POST",
    headers: serviceHeaders(serviceRoleKey),
    body: JSON.stringify({ p_limit: 25 }),
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch due delivery notifications: ${response.status} ${await response.text()}`)
  }

  return await response.json()
}

async function notifyDelivery(supabaseUrl: string, cronSecret: string, deliveryId: string) {
  const response = await fetch(`${supabaseUrl}/functions/v1/send-delivery-notification`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-cron-secret": cronSecret,
    },
    body: JSON.stringify({ delivery_id: deliveryId }),
  })
  const rawBody = await response.text()
  let body: unknown = rawBody

  try {
    body = rawBody ? JSON.parse(rawBody) : null
  } catch {
    // Keep the raw body for diagnostics.
  }

  return {
    body,
    ok: response.ok,
    status: response.status,
  }
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
      action: "delivery_notification_processor",
      error_message: errorMessage,
      metadata,
      result,
      user_id: userId,
    }),
  }).catch(() => {
    // Diagnostics cannot interfere with the reminder processor.
  })
}

function serviceHeaders(serviceRoleKey: string) {
  return {
    "Content-Type": "application/json",
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
