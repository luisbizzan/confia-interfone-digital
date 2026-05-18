"use client";

import { Alert, Grid, Stack, Typography } from "@mui/material";
import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { AppShell } from "@/components/app-shell";
import { ResponsiveRecordList } from "@/components/data-display/responsive-record-list";
import { StatusChip } from "@/components/data-display/status-chip";
import { ErrorAlert } from "@/components/feedback/error-alert";
import { LoadingPanel } from "@/components/feedback/loading-panel";
import { PageHeader } from "@/components/page-header";
import { CondominiumSelect } from "@/features/condominiums/condominium-select";
import { fetchCondominiumOverview, fetchCondominiums } from "@/features/condominiums/api";
import { adminQueryKeys } from "@/lib/admin/query-keys";
import { formatDateTime } from "@/lib/format";

function shortId(value: string) {
  return value.slice(0, 8);
}

export function PortariaPage() {
  const [selectedCondominiumId, setSelectedCondominiumId] = useState("");
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
  const devices = useMemo(() => overviewQuery.data?.portaria_devices ?? [], [overviewQuery.data?.portaria_devices]);

  return (
    <AppShell>
      <PageHeader
        description="Consulte o usuário e o dispositivo de portaria criados no onboarding do condomínio."
        title="Portaria"
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
                O login do app modo portaria usa o usuário criado junto com o condomínio. Esta tela confirma o vínculo do dispositivo.
              </Alert>
            </Grid>
          </Grid>
        )}

        {overviewQuery.isLoading && <LoadingPanel label="Carregando portaria..." />}
        {overviewQuery.isError && (
          <ErrorAlert message={overviewQuery.error.message} onRetry={() => void overviewQuery.refetch()} />
        )}

        {overviewQuery.data && (
          <ResponsiveRecordList
            columns={[
                {
                  key: "name",
                  header: "Dispositivo",
                  render: (device) => <Typography sx={{ fontWeight: 700 }}>{device.name}</Typography>,
                  tableSx: { width: "20%" },
                },
                {
                  key: "user",
                  header: "Login app",
                  render: (device) => device.user_email ?? `ID ${shortId(device.user_id)}`,
                  tableSx: { width: "38%" },
                },
                {
                  key: "active",
                header: "Status",
                  render: (device) => (
                    <StatusChip label={device.is_active ? "Ativo" : "Inativo"} tone={device.is_active ? "success" : "warning"} />
                  ),
                  tableSx: { width: "14%" },
                },
                {
                  key: "receive",
                  header: "Recebe",
                  render: (device) => (device.can_receive_calls ? "Sim" : "Não"),
                  tableSx: { width: "12%" },
                },
                {
                  key: "make",
                  header: "Liga",
                  render: (device) => (device.can_make_calls ? "Sim" : "Não"),
                  tableSx: { width: "10%" },
                },
              {
                key: "created",
                header: "Criado em",
                render: (device) => formatDateTime(device.created_at),
                hideOnMobile: true,
              },
            ]}
            description="Dispositivos de portaria vinculados ao condomínio selecionado."
            emptyDescription="Crie um condomínio para gerar o primeiro usuário e dispositivo da portaria."
            emptyTitle="Nenhuma portaria configurada"
            getKey={(device) => device.id}
            items={devices}
            title="Dispositivos da portaria"
          />
        )}
      </Stack>
    </AppShell>
  );
}
