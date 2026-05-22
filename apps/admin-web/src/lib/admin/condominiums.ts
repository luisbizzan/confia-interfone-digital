import { adminEdgeRequest } from "@/lib/admin-edge";

export type AdminCondominiumListItem = {
  id: string;
  name: string;
  document?: string | null;
  created_at?: string;
  unit_count?: number;
  portaria_device_count?: number;
  features?: Record<string, boolean>;
};

export type CreateAdminCondominiumInput = {
  condominium_name: string;
  condominium_document?: string | null;
  portaria_email: string;
  portaria_password: string;
  portaria_device_name?: string | null;
  intercom_enabled?: boolean;
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

export type AdminUnitMember = {
  id: string;
  user_id: string;
  member_type: string;
  active_for_calls: boolean;
  can_receive_calls: boolean;
  can_make_calls: boolean;
  call_order: number;
  created_at?: string;
};

export type AdminUnit = {
  id: string;
  type: string;
  block?: string | null;
  number: string;
  created_at?: string;
  members: AdminUnitMember[];
};

export type AdminRecentCall = {
  id: string;
  unit_id?: string | null;
  status: string;
  origin_type?: string | null;
  target_type?: string | null;
  created_at?: string;
};

export type AdminCondominiumOverview = {
  condominium: AdminCondominiumListItem;
  portaria_devices?: {
    id: string;
    user_id: string;
    user_email?: string | null;
    name: string;
    is_active: boolean;
    can_receive_calls: boolean;
    can_make_calls: boolean;
    priority_order: number;
    created_at?: string;
  }[];
  units: AdminUnit[];
  recent_calls: AdminRecentCall[];
};

export type CreateAdminUnitMemberInput = {
  condominium_id: string;
  unit_id?: string | null;
  unit_type?: string | null;
  unit_block?: string | null;
  unit_number?: string | null;
  resident_email: string;
  resident_password: string;
  member_type?: string | null;
  call_order?: number | null;
  active_for_calls?: boolean;
  can_receive_calls?: boolean;
  can_make_calls?: boolean;
};

export type CreateAdminUnitMemberResult = {
  unit_id: string;
  resident_user_id: string;
  unit_member_id: string;
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

export async function createAdminUnitMember(input: CreateAdminUnitMemberInput) {
  return adminEdgeRequest<CreateAdminUnitMemberResult>({
    path: "admin-create-unit-member",
    init: {
      method: "POST",
      body: JSON.stringify(input),
    },
  });
}
