const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const adminSecret = process.env.ADMIN_API_SECRET;

export type AdminEdgeRequestOptions = {
  path: string;
  init?: RequestInit;
};

export async function adminEdgeRequest<T>({ path, init }: AdminEdgeRequestOptions): Promise<T> {
  if (!supabaseUrl) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL is not configured");
  }

  if (!adminSecret) {
    throw new Error("ADMIN_API_SECRET is not configured");
  }

  const response = await fetch(`${supabaseUrl}/functions/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      "x-admin-secret": adminSecret,
      ...init?.headers,
    },
    cache: "no-store",
  });

  const payload = await response.json();

  if (!response.ok) {
    throw new Error(payload?.error ?? "Admin API request failed");
  }

  return payload as T;
}
