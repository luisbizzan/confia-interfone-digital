import "server-only";

const supabaseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const adminSecret = process.env.ADMIN_API_SECRET;

export class AdminEdgeError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "AdminEdgeError";
    this.status = status;
  }
}

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
    throw new AdminEdgeError(payload?.error ?? "Admin API request failed", response.status);
  }

  return payload as T;
}
