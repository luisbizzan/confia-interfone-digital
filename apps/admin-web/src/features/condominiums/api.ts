import type {
  AdminCondominiumListItem,
  CreateAdminCondominiumInput,
  CreateAdminCondominiumResult,
} from "@/lib/admin/condominiums";

async function parseResponse<T>(response: Response): Promise<T> {
  const payload = await response.json();

  if (!response.ok) {
    throw new Error(payload?.error ?? "Falha na comunicação com o backend");
  }

  return payload as T;
}

export async function fetchCondominiums() {
  const response = await fetch("/api/admin/condominiums", { cache: "no-store" });
  return parseResponse<AdminCondominiumListItem[]>(response);
}

export async function createCondominium(input: CreateAdminCondominiumInput) {
  const response = await fetch("/api/admin/condominiums/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });

  return parseResponse<CreateAdminCondominiumResult>(response);
}
