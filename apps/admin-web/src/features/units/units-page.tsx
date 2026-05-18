"use client";

import { Alert, Grid, Stack, Typography } from "@mui/material";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { AppShell } from "@/components/app-shell";
import { ResponsiveRecordList } from "@/components/data-display/responsive-record-list";
import { StatusChip } from "@/components/data-display/status-chip";
import { ErrorAlert } from "@/components/feedback/error-alert";
import { LoadingPanel } from "@/components/feedback/loading-panel";
import { PageHeader } from "@/components/page-header";
import { adminQueryKeys } from "@/lib/admin/query-keys";
import { formatDateTime } from "@/lib/format";
import { CondominiumSelect } from "@/features/condominiums/condominium-select";
import { createUnitMember, fetchCondominiumOverview, fetchCondominiums } from "@/features/condominiums/api";
import { UnitMemberDialog } from "./unit-member-dialog";
import type { CreateAdminUnitMemberInput } from "@/lib/admin/condominiums";

export function UnitsPage() {
  const [selectedCondominiumId, setSelectedCondominiumId] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const queryClient = useQueryClient();
  const condominiumsQuery = useQuery({
    queryKey: adminQueryKeys.condominiums,
    queryFn: fetchCondominiums,
  });
  const activeCondominiumId = selectedCondominiumId || condominiumsQuery.data?.[0]?.id || "";

  const overviewQuery = useQuery({
    enabled: Boolean(activeCondominiumId),
    queryKey: adminQueryKeys.condominium(activeCondominiumId),
    queryFn: () => fetchCondominiumOverview(activeCondominiumId),
  });

  const createMutation = useMutation({
    mutationFn: createUnitMember,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: adminQueryKeys.condominium(activeCondominiumId) });
      await queryClient.invalidateQueries({ queryKey: adminQueryKeys.condominiums });
      setDialogOpen(false);
    },
  });

  const units = useMemo(() => overviewQuery.data?.units ?? [], [overviewQuery.data?.units]);
  const totalMembers = useMemo(
    () => units.reduce((total, unit) => total + unit.members.length, 0),
    [units],
  );

  const handleSubmit = (input: Omit<CreateAdminUnitMemberInput, "condominium_id">) => {
    createMutation.mutate({
      ...input,
      condominium_id: activeCondominiumId,
    });
  };

  return (
    <AppShell>
      <PageHeader
        actionLabel="Nova unidade"
        description="Gerencie unidades e crie o primeiro morador autorizado no mesmo fluxo."
        onAction={() => setDialogOpen(true)}
        title="Unidades"
      />

      <Stack spacing={2.5}>
        {condominiumsQuery.isLoading && <LoadingPanel label="Carregando condomínios..." />}
        {condominiumsQuery.isError && (
          <ErrorAlert message={condominiumsQuery.error.message} onRetry={() => void condominiumsQuery.refetch()} />
        )}

        {condominiumsQuery.data && (
          <Grid container spacing={2.5}>
            <Grid size={{ xs: 12, md: 5 }}>
              <CondominiumSelect
                condominiums={condominiumsQuery.data}
                onChange={setSelectedCondominiumId}
                value={activeCondominiumId}
              />
            </Grid>
            <Grid size={{ xs: 12, md: 7 }}>
              <Alert severity="info">
                {units.length} unidade(s) e {totalMembers} morador(es) vinculados neste condomínio.
              </Alert>
            </Grid>
          </Grid>
        )}

        {overviewQuery.isLoading && <LoadingPanel label="Carregando unidades..." />}
        {overviewQuery.isError && (
          <ErrorAlert message={overviewQuery.error.message} onRetry={() => void overviewQuery.refetch()} />
        )}

        {overviewQuery.data && (
          <ResponsiveRecordList
            columns={[
                {
                  key: "unit",
                  header: "Unidade",
                render: (unit) => (
                  <Typography sx={{ fontWeight: 700 }}>
                    {unit.block ? `${unit.block} - ` : ""}
                    {unit.number}
                  </Typography>
                ),
                  tableSx: { width: "24%" },
                },
                {
                  key: "type",
                  header: "Tipo",
                  render: (unit) => (unit.type === "HOUSE" ? "Casa" : "Apartamento"),
                  tableSx: { width: "22%" },
                },
                {
                  key: "members",
                  header: "Moradores",
                  render: (unit) => unit.members.length,
                  tableSx: { width: "16%" },
                },
                {
                  key: "status",
                  header: "Chamadas",
                render: (unit) => (
                  <StatusChip
                    label={unit.members.some((member) => member.active_for_calls) ? "Ativa" : "Sem morador ativo"}
                      tone={unit.members.some((member) => member.active_for_calls) ? "success" : "warning"}
                    />
                  ),
                  tableSx: { width: "20%" },
                },
              {
                key: "created",
                header: "Criada em",
                render: (unit) => formatDateTime(unit.created_at),
                hideOnMobile: true,
              },
            ]}
            description="Unidades carregadas pelo overview administrativo do condomínio selecionado."
            emptyDescription="Use Nova unidade para criar uma unidade com morador autorizado."
            emptyTitle="Nenhuma unidade cadastrada"
            getKey={(unit) => unit.id}
            items={units}
            title="Unidades cadastradas"
          />
        )}
      </Stack>

      <UnitMemberDialog
        description="Crie uma nova unidade e vincule o primeiro morador autorizado a receber chamadas."
        errorMessage={createMutation.isError ? createMutation.error.message : undefined}
        isPending={createMutation.isPending}
        onClose={() => setDialogOpen(false)}
        onSubmit={handleSubmit}
        open={dialogOpen}
        title="Nova unidade"
        units={[]}
      />
    </AppShell>
  );
}
