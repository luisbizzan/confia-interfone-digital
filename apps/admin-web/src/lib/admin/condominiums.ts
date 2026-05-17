import { adminEdgeRequest } from "@/lib/admin-edge";

export type AdminCondominiumListItem = {
  id: string;
  name: string;
  status?: string;
  created_at?: string;
  units_count?: number;
  members_count?: number;
};

export type AdminCondominiumOverview = {
  condominium: AdminCondominiumListItem;
  portaria_user?: {
    id: string;
    full_name?: string;
    email?: string;
  };
  units?: unknown[];
  members?: unknown[];
};

export async function listAdminCondominiums() {
  return adminEdgeRequest<AdminCondominiumListItem[]>({
    path: "admin-get-condominium",
    init: { method: "GET" },
  });
}

export async function getAdminCondominium(condominiumId: string) {
  const params = new URLSearchParams({ condominium_id: condominiumId });

  return adminEdgeRequest<AdminCondominiumOverview>({
    path: `admin-get-condominium?${params.toString()}`,
    init: { method: "GET" },
  });
}
