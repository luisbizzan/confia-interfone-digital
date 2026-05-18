"use client";

import CallIcon from "@mui/icons-material/Call";
import PhoneCallbackIcon from "@mui/icons-material/PhoneCallback";
import PhoneMissedIcon from "@mui/icons-material/PhoneMissed";
import PhonePausedIcon from "@mui/icons-material/PhonePaused";
import { Alert, Grid, Stack, Typography } from "@mui/material";
import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { AppShell } from "@/components/app-shell";
import { ResponsiveRecordList } from "@/components/data-display/responsive-record-list";
import { StatusChip } from "@/components/data-display/status-chip";
import { MetricCard } from "@/components/dashboard/metric-card";
import { ErrorAlert } from "@/components/feedback/error-alert";
import { LoadingPanel } from "@/components/feedback/loading-panel";
import { PageHeader } from "@/components/page-header";
import { CondominiumSelect } from "@/features/condominiums/condominium-select";
import { fetchCondominiumOverview, fetchCondominiums } from "@/features/condominiums/api";
import { adminQueryKeys } from "@/lib/admin/query-keys";
import { callDirectionLabel, callStatusLabel, callStatusTone } from "@/lib/calls";
import { formatDateTime } from "@/lib/format";

export function CallsPage() {
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
    refetchInterval: 20_000,
  });
  const calls = useMemo(() => overviewQuery.data?.recent_calls ?? [], [overviewQuery.data?.recent_calls]);
  const metrics = useMemo(() => {
    const ringing = calls.filter((call) => call.status === "RINGING").length;
    const answered = calls.filter((call) => call.status === "ANSWERED").length;
    const missed = calls.filter((call) => call.status === "MISSED").length;

    return [
      { label: "Recentes", value: String(calls.length), helper: "Últimas 25 chamadas", tone: "info" as const, icon: <CallIcon key="recent" /> },
      { label: "Tocando", value: String(ringing), helper: "Chamadas em aberto", tone: "warning" as const, icon: <PhonePausedIcon key="ringing" /> },
      { label: "Atendidas", value: String(answered), helper: "Chamadas concluídas", tone: "success" as const, icon: <PhoneCallbackIcon key="answered" /> },
      { label: "Perdidas", value: String(missed), helper: "Sem atendimento", tone: "error" as const, icon: <PhoneMissedIcon key="missed" /> },
    ];
  }, [calls]);

  return (
    <AppShell>
      <PageHeader
        description="Acompanhe o histórico recente e o estado operacional das chamadas por condomínio."
        title="Chamadas"
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
              <Alert severity="info">A lista atualiza automaticamente a cada 20 segundos enquanto a tela estiver aberta.</Alert>
            </Grid>
          </Grid>
        )}

        {overviewQuery.isLoading && <LoadingPanel label="Carregando chamadas..." />}
        {overviewQuery.isError && (
          <ErrorAlert message={overviewQuery.error.message} onRetry={() => void overviewQuery.refetch()} />
        )}

        {overviewQuery.data && (
          <>
            <Grid container spacing={2.5}>
              {metrics.map((metric) => (
                <Grid key={metric.label} size={{ xs: 12, sm: 6, lg: 3 }}>
                  <MetricCard {...metric} />
                </Grid>
              ))}
            </Grid>

            <ResponsiveRecordList
              columns={[
                {
                  key: "direction",
                  header: "Fluxo",
                  render: (call) => (
                    <Typography sx={{ fontWeight: 700 }}>
                      {callDirectionLabel(call.origin_type, call.target_type)}
                    </Typography>
                  ),
                  tableSx: { width: "34%" },
                },
                {
                  key: "unit",
                  header: "Unidade",
                  render: (call) => call.unit_id?.slice(0, 8) ?? "-",
                  tableSx: { width: "20%" },
                },
                {
                  key: "status",
                  header: "Status",
                  render: (call) => <StatusChip label={callStatusLabel(call.status)} tone={callStatusTone(call.status)} />,
                  tableSx: { width: "20%" },
                },
                {
                  key: "created",
                  header: "Iniciada em",
                  render: (call) => formatDateTime(call.created_at),
                },
              ]}
              description="Chamadas recentes retornadas pelo overview administrativo do condomínio."
              emptyDescription="As chamadas aparecerão aqui quando portaria ou moradores iniciarem ligações."
              emptyTitle="Nenhuma chamada recente"
              getKey={(call) => call.id}
              items={calls}
              title="Histórico recente"
            />
          </>
        )}
      </Stack>
    </AppShell>
  );
}
