import { adminEdgeRequest } from "@/lib/admin-edge";

export type AdminCondominiumListItem = {
  id: string;
  name: string;
  document?: string | null;
  created_at?: string;
  unit_count?: number;
  portaria_device_count?: number;
};

export type CreateAdminCondominiumInput = {
  condominium_name: string;
  condominium_document?: string | null;
  portaria_email: string;
  portaria_password: string;
  portaria_device_name?: string | null;
  create_default_unit?: boolean;
  default_unit_type?: string | null;
  default_unit_block?: string | null;
  default_unit_number?: string | null;
};

export type CreateAdminCondominiumResult = {
  condominium_id: string;
  portaria_user_id: string;
  portaria_device_id: string;
  default_unit_id?: string | null;
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

export async function createAdminCondominium(input: CreateAdminCondominiumInput) {
  return adminEdgeRequest<CreateAdminCondominiumResult>({
    path: "admin-create-condominium",
    init: {
      method: "POST",
      body: JSON.stringify(input),
    },
  });
}

export async function getAdminCondominium(condominiumId: string) {
  const params = new URLSearchParams({ condominium_id: condominiumId });

  return adminEdgeRequest<AdminCondominiumOverview>({
    path: `admin-get-condominium?${params.toString()}`,
    init: { method: "GET" },
  });
}
