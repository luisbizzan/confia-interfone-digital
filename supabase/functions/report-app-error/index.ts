const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

type AppErrorPayload = {
  app_version?: string | null
  call_id?: string | null
  component_stack?: string | null
  device_model?: string | null
  message?: string | null
  metadata?: Record<string, unknown> | null
  os_version?: string | null
  platform?: string | null
  profile?: string | null
  route?: string | null
  source?: string | null
  stack?: string | null
}

type UserProfile = {
  condominium_id: string | null
  role_id: string | null
}

type GithubIssue = {
  html_url: string
  number: number
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

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Missing Supabase environment variables" }, 500)
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

  const payload = await req.json().catch(() => null) as AppErrorPayload | null

  if (!payload?.message?.trim() || !payload?.source?.trim()) {
    return json({ error: "Invalid error report payload" }, 400)
  }

  const profile = await fetchUserProfile(supabaseUrl, serviceRoleKey, user.id)
  const signature = await createSignature(payload)
  const report = await insertReport(supabaseUrl, serviceRoleKey, {
    ...payload,
    condominium_id: profile?.condominium_id ?? null,
    signature,
    user_id: user.id,
  })

  const githubResult = await syncGithubIssue(supabaseUrl, serviceRoleKey, report, payload, user.id)
    .catch((error) => ({
      error: error instanceof Error ? error.message : "Unknown GitHub sync error",
      status: "failed",
    }))

  return json({
    ok: true,
    report_id: report.id,
    signature,
    github: githubResult,
  }, 201)
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

async function fetchUserProfile(supabaseUrl: string, serviceRoleKey: string, userId: string): Promise<UserProfile | null> {
  const response = await fetch(`${supabaseUrl}/rest/v1/user_profiles?id=eq.${userId}&select=condominium_id,role_id&limit=1`, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!response.ok) {
    return null
  }

  const rows = await response.json()
  return rows?.[0] ?? null
}

async function insertReport(
  supabaseUrl: string,
  serviceRoleKey: string,
  input: AppErrorPayload & { condominium_id: string | null; signature: string; user_id: string },
) {
  const response = await fetch(`${supabaseUrl}/rest/v1/app_error_reports?select=id,signature`, {
    method: "POST",
    headers: {
      ...serviceHeaders(serviceRoleKey),
      "Prefer": "return=representation",
    },
    body: JSON.stringify({
      app_version: truncate(input.app_version, 80),
      call_id: isUuid(input.call_id) ? input.call_id : null,
      component_stack: truncate(input.component_stack, 6000),
      condominium_id: input.condominium_id,
      device_model: truncate(input.device_model, 120),
      message: truncate(input.message, 1200),
      metadata: sanitizeMetadata(input.metadata ?? {}),
      os_version: truncate(input.os_version, 80),
      platform: truncate(input.platform, 40),
      profile: truncate(input.profile, 40),
      route: truncate(input.route, 120),
      signature: input.signature,
      source: truncate(input.source, 120),
      stack: truncate(input.stack, 12000),
      user_id: input.user_id,
    }),
  })

  const body = await readJson(response)

  if (!response.ok) {
    throw new Error(`Failed to insert app error report: ${JSON.stringify(body)}`)
  }

  return body[0]
}

async function syncGithubIssue(
  supabaseUrl: string,
  serviceRoleKey: string,
  report: { id: string; signature: string },
  payload: AppErrorPayload,
  userId: string,
) {
  const githubToken = Deno.env.get("GITHUB_TOKEN")
  const githubRepository = Deno.env.get("GITHUB_REPOSITORY")

  if (!githubToken || !githubRepository) {
    return { status: "skipped", reason: "missing_github_secrets" }
  }

  const existing = await findExistingIssueReport(supabaseUrl, serviceRoleKey, report.signature)

  if (existing?.github_issue_number && existing.github_issue_url) {
    const occurrenceCount = (existing.occurrence_count ?? 1) + 1
    await updateReport(supabaseUrl, serviceRoleKey, existing.id, {
      occurrence_count: occurrenceCount,
      last_seen_at: new Date().toISOString(),
    })
    await updateReport(supabaseUrl, serviceRoleKey, report.id, {
      github_issue_number: existing.github_issue_number,
      github_issue_url: existing.github_issue_url,
    })
    return {
      issue_number: existing.github_issue_number,
      issue_url: existing.github_issue_url,
      occurrence_count: occurrenceCount,
      status: "deduplicated",
    }
  }

  const issue = await createGithubIssue(githubToken, githubRepository, payload, report.signature, userId)
  await updateReport(supabaseUrl, serviceRoleKey, report.id, {
    github_issue_number: issue.number,
    github_issue_url: issue.html_url,
  })

  return {
    issue_number: issue.number,
    issue_url: issue.html_url,
    status: "created",
  }
}

async function findExistingIssueReport(supabaseUrl: string, serviceRoleKey: string, signature: string) {
  const params = [
    `signature=eq.${encodeURIComponent(signature)}`,
    "github_issue_number=not.is.null",
    "select=id,github_issue_number,github_issue_url,occurrence_count",
    "order=created_at.asc",
    "limit=1",
  ].join("&")

  const response = await fetch(`${supabaseUrl}/rest/v1/app_error_reports?${params}`, {
    headers: serviceHeaders(serviceRoleKey),
  })

  if (!response.ok) {
    return null
  }

  const rows = await response.json()
  return rows?.[0] ?? null
}

async function updateReport(supabaseUrl: string, serviceRoleKey: string, reportId: string, body: Record<string, unknown>) {
  await fetch(`${supabaseUrl}/rest/v1/app_error_reports?id=eq.${reportId}`, {
    method: "PATCH",
    headers: serviceHeaders(serviceRoleKey),
    body: JSON.stringify(body),
  })
}

async function createGithubIssue(
  githubToken: string,
  githubRepository: string,
  payload: AppErrorPayload,
  signature: string,
  userId: string,
): Promise<GithubIssue> {
  const labels = parseLabels(Deno.env.get("GITHUB_ERROR_LABELS"))
  const title = `[App Error] ${truncate(payload.message, 82) ?? "Erro inesperado"}`
  const issuePayload = {
    body: buildGithubIssueBody(payload, signature, userId),
    labels,
    title,
  }
  const response = await fetch(`https://api.github.com/repos/${githubRepository}/issues`, {
    method: "POST",
    headers: githubHeaders(githubToken),
    body: JSON.stringify(issuePayload),
  })

  if (response.status === 422 && labels.length > 0) {
    const retry = await fetch(`https://api.github.com/repos/${githubRepository}/issues`, {
      method: "POST",
      headers: githubHeaders(githubToken),
      body: JSON.stringify({ ...issuePayload, labels: undefined }),
    })
    const retryBody = await readJson(retry)

    if (!retry.ok) {
      throw new Error(`Failed to create GitHub issue: ${JSON.stringify(retryBody)}`)
    }

    return retryBody
  }

  const body = await readJson(response)

  if (!response.ok) {
    throw new Error(`Failed to create GitHub issue: ${JSON.stringify(body)}`)
  }

  return body
}

function buildGithubIssueBody(payload: AppErrorPayload, signature: string, userId: string) {
  return [
    "Erro reportado automaticamente pelo app Confia.",
    "",
    "## Contexto",
    "",
    `- Assinatura: \`${signature}\``,
    `- Usuario: \`${userId}\``,
    `- Perfil: \`${payload.profile ?? "n/a"}\``,
    `- Plataforma: \`${payload.platform ?? "n/a"}\``,
    `- OS: \`${payload.os_version ?? "n/a"}\``,
    `- Device: \`${payload.device_model ?? "n/a"}\``,
    `- Versao app: \`${payload.app_version ?? "n/a"}\``,
    `- Rota: \`${payload.route ?? "n/a"}\``,
    `- Call ID: \`${payload.call_id ?? "n/a"}\``,
    "",
    "## Mensagem",
    "",
    "```text",
    truncate(payload.message, 1200) ?? "Erro inesperado",
    "```",
    "",
    "## Stacktrace",
    "",
    "```text",
    truncate(payload.stack, 6000) ?? "Sem stacktrace",
    "```",
    "",
    "## Component stack",
    "",
    "```text",
    truncate(payload.component_stack, 4000) ?? "Sem component stack",
    "```",
    "",
    "## Metadados",
    "",
    "```json",
    JSON.stringify(sanitizeMetadata(payload.metadata ?? {}), null, 2),
    "```",
  ].join("\n")
}

async function createSignature(payload: AppErrorPayload) {
  const raw = [
    payload.source ?? "",
    payload.message ?? "",
    payload.platform ?? "",
    payload.route ?? "",
    firstStackLines(payload.stack),
    firstStackLines(payload.component_stack),
  ].join("|")

  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw))
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
}

function firstStackLines(value?: string | null) {
  return (value ?? "").split("\n").slice(0, 5).join("\n")
}

function sanitizeMetadata(value: Record<string, unknown>) {
  const safe: Record<string, unknown> = {}

  Object.entries(value).forEach(([key, item]) => {
    if (item === undefined || item === null) {
      return
    }

    if (/password|token|secret|authorization|apikey|api_key/i.test(key)) {
      safe[key] = "[redacted]"
      return
    }

    if (typeof item === "string") {
      safe[key] = redactSecrets(truncate(item, 1000) ?? "")
      return
    }

    if (typeof item === "number" || typeof item === "boolean") {
      safe[key] = item
      return
    }

    safe[key] = redactSecrets(truncate(safeJson(item), 2000) ?? "")
  })

  return safe
}

function redactSecrets(value: string) {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._-]+/g, "Bearer [redacted]")
    .replace(/eyJ[A-Za-z0-9._-]+/g, "[jwt-redacted]")
    .replace(/sb_secret_[A-Za-z0-9._-]+/g, "sb_secret_[redacted]")
}

function parseLabels(value?: string | null) {
  if (!value?.trim()) {
    return ["app-error", "auto-report"]
  }

  return value.split(",").map((label) => label.trim()).filter(Boolean)
}

function githubHeaders(token: string) {
  return {
    "Accept": "application/vnd.github+json",
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
    "User-Agent": "confia-error-reporter",
    "X-GitHub-Api-Version": "2022-11-28",
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

function truncate(value: string | null | undefined, maxLength: number) {
  if (!value) {
    return null
  }

  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value
}

function safeJson(value: unknown) {
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
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
