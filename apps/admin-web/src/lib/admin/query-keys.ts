export const adminQueryKeys = {
  condominiums: ["admin", "condominiums"] as const,
  condominium: (id: string) => ["admin", "condominiums", id] as const,
};
