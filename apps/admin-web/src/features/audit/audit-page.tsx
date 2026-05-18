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
import type { AdminRecentCall } from "@/lib/admin/condominiums";
import { adminQueryKeys } from "@/lib/admin/query-keys";
import { callDirectionLabel, callStatusLabel, callStatusTone } from "@/lib/calls";
import { formatDateTime } from "@/lib/format";

type AuditRow = AdminRecentCall & {
  eventLabel: string;
};

export function AuditPage() {
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
  const auditRows = useMemo<AuditRow[]>(() => {
    return (overviewQuery.data?.recent_calls ?? []).map((call) => ({
      ...call,
      eventLabel: `${callDirectionLabel(call.origin_type, call.target_type)}: ${callStatusLabel(call.status)}`,
    }));
  }, [overviewQuery.data?.recent_calls]);

  return (
    <AppShell>
      <PageHeader
        description="Consulte a trilha operacional recente por condomínio para suporte e conferência."
        title="Auditoria"
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
              <Alert severity="warning">
                MVP: esta visão resume chamadas recentes. A leitura direta de `call_events` fica preparada para uma próxima API administrativa.
              </Alert>
            </Grid>
          </Grid>
        )}

        {overviewQuery.isLoading && <LoadingPanel label="Carregando auditoria..." />}
        {overviewQuery.isError && (
          <ErrorAlert message={overviewQuery.error.message} onRetry={() => void overviewQuery.refetch()} />
        )}

        {overviewQuery.data && (
          <ResponsiveRecordList
            columns={[
              {
                key: "event",
                header: "Evento",
                render: (row) => <Typography sx={{ fontWeight: 700 }}>{row.eventLabel}</Typography>,
              },
              {
                key: "status",
                header: "Status",
                render: (row) => <StatusChip label={callStatusLabel(row.status)} tone={callStatusTone(row.status)} />,
              },
              {
                key: "call",
                header: "Chamada",
                render: (row) => row.id.slice(0, 8),
              },
              {
                key: "created",
                header: "Registrado em",
                render: (row) => formatDateTime(row.created_at),
              },
            ]}
            description="Resumo de eventos operacionais baseado nas chamadas recentes."
            emptyDescription="Eventos aparecerão aqui conforme chamadas forem criadas."
            emptyTitle="Nenhum evento recente"
            getKey={(row) => row.id}
            items={auditRows}
            title="Eventos operacionais"
          />
        )}
      </Stack>
    </AppShell>
  );
}
