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
import { CondominiumSelect } from "@/features/condominiums/condominium-select";
import { createUnitMember, fetchCondominiumOverview, fetchCondominiums } from "@/features/condominiums/api";
import { UnitMemberDialog } from "@/features/units/unit-member-dialog";
import type { AdminUnitMember, CreateAdminUnitMemberInput } from "@/lib/admin/condominiums";
import { adminQueryKeys } from "@/lib/admin/query-keys";
import { formatDateTime } from "@/lib/format";

type ResidentRow = AdminUnitMember & {
  unit_id: string;
  unit_label: string;
};

function shortId(value: string) {
  return value.slice(0, 8);
}

export function ResidentsPage() {
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

  const residents = useMemo<ResidentRow[]>(() => {
    return (overviewQuery.data?.units ?? []).flatMap((unit) =>
      unit.members.map((member) => ({
        ...member,
        unit_id: unit.id,
        unit_label: `${unit.block ? `${unit.block} - ` : ""}${unit.number}`,
      })),
    );
  }, [overviewQuery.data?.units]);

  const createMutation = useMutation({
    mutationFn: createUnitMember,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: adminQueryKeys.condominium(activeCondominiumId) });
      setDialogOpen(false);
    },
  });

  const handleSubmit = (input: Omit<CreateAdminUnitMemberInput, "condominium_id">) => {
    createMutation.mutate({
      ...input,
      condominium_id: activeCondominiumId,
    });
  };

  return (
    <AppShell>
      <PageHeader
        actionLabel="Novo morador"
        description="Vincule moradores às unidades e configure quem recebe ou inicia chamadas."
        onAction={() => setDialogOpen(true)}
        title="Moradores"
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
                {residents.length} morador(es) autorizado(s) nas unidades do condomínio selecionado.
              </Alert>
            </Grid>
          </Grid>
        )}

        {overviewQuery.isLoading && <LoadingPanel label="Carregando moradores..." />}
        {overviewQuery.isError && (
          <ErrorAlert message={overviewQuery.error.message} onRetry={() => void overviewQuery.refetch()} />
        )}

        {overviewQuery.data && (
          <ResponsiveRecordList
            columns={[
              {
                key: "resident",
                header: "Morador",
                render: (resident) => (
                  <Typography sx={{ fontWeight: 700 }}>Usuário {shortId(resident.user_id)}</Typography>
                ),
              },
              {
                key: "unit",
                header: "Unidade",
                render: (resident) => resident.unit_label,
              },
              {
                key: "order",
                header: "Ordem",
                render: (resident) => resident.call_order,
              },
              {
                key: "receive",
                header: "Recebe",
                render: (resident) => (
                  <StatusChip
                    label={resident.active_for_calls && resident.can_receive_calls ? "Sim" : "Não"}
                    tone={resident.active_for_calls && resident.can_receive_calls ? "success" : "warning"}
                  />
                ),
              },
              {
                key: "make",
                header: "Liga",
                render: (resident) => (resident.can_make_calls ? "Sim" : "Não"),
              },
              {
                key: "created",
                header: "Criado em",
                render: (resident) => formatDateTime(resident.created_at),
                hideOnMobile: true,
              },
            ]}
            description="Moradores carregados a partir das unidades do condomínio selecionado."
            emptyDescription="Use Novo morador para vincular um usuário a uma unidade."
            emptyTitle="Nenhum morador cadastrado"
            getKey={(resident) => resident.id}
            items={residents}
            title="Moradores vinculados"
          />
        )}
      </Stack>

      <UnitMemberDialog
        description="Escolha uma unidade existente ou crie uma nova unidade junto com o morador."
        errorMessage={createMutation.isError ? createMutation.error.message : undefined}
        isPending={createMutation.isPending}
        onClose={() => setDialogOpen(false)}
        onSubmit={handleSubmit}
        open={dialogOpen}
        title="Novo morador"
        units={overviewQuery.data?.units ?? []}
      />
    </AppShell>
  );
}
