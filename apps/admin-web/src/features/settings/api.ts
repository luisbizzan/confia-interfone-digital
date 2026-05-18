export type AdminHealth = {
  ok: boolean;
  checks: {
    supabaseUrl: boolean;
    adminSecret: boolean;
    publicAnonKey: boolean;
  };
  condominiums_count?: number;
  error?: string;
};

export async function fetchAdminHealth() {
  const response = await fetch("/api/admin/health", { cache: "no-store" });
  const payload = await response.json();

  if (!response.ok) {
    throw new Error(payload?.error ?? "Falha ao verificar configurações");
  }

  return payload as AdminHealth;
}
