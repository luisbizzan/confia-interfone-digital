"use client";

import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import ErrorIcon from "@mui/icons-material/Error";
import { Alert, Card, CardContent, Grid, List, ListItem, ListItemIcon, ListItemText, Stack, Typography } from "@mui/material";
import { useQuery } from "@tanstack/react-query";
import { AppShell } from "@/components/app-shell";
import { StatusChip } from "@/components/data-display/status-chip";
import { ErrorAlert } from "@/components/feedback/error-alert";
import { LoadingPanel } from "@/components/feedback/loading-panel";
import { PageHeader } from "@/components/page-header";
import { fetchAdminHealth } from "./api";

const rolloutItems = [
  "Condomínios com usuário e dispositivo de portaria",
  "Unidades com moradores e regras de chamada",
  "Chamadas recentes com atualização operacional",
  "Auditoria MVP baseada em chamadas recentes",
  "Segredos administrativos isolados em rotas server-side",
];

export function SettingsPage() {
  const healthQuery = useQuery({
    queryKey: ["admin", "health"],
    queryFn: fetchAdminHealth,
    refetchInterval: 60_000,
  });
  const checks = [
    { label: "URL do Supabase", ok: healthQuery.data?.checks.supabaseUrl },
    { label: "Segredo administrativo", ok: healthQuery.data?.checks.adminSecret },
    { label: "Chave pública do Supabase", ok: healthQuery.data?.checks.publicAnonKey },
  ];

  return (
    <AppShell>
      <PageHeader
        description="Valide o ambiente administrativo e acompanhe o estado de fechamento do MVP."
        title="Configurações"
      />

      <Stack spacing={2.5}>
        {healthQuery.isLoading && <LoadingPanel label="Verificando ambiente..." />}
        {healthQuery.isError && (
          <ErrorAlert message={healthQuery.error.message} onRetry={() => void healthQuery.refetch()} />
        )}

        {healthQuery.data && (
          <Grid container spacing={2.5}>
            <Grid size={{ xs: 12, lg: 5 }}>
              <Card sx={{ height: "100%" }}>
                <CardContent>
                  <Stack direction="row" sx={{ alignItems: "center", justifyContent: "space-between", mb: 2 }}>
                    <Typography variant="h3">Saúde do ambiente</Typography>
                    <StatusChip label={healthQuery.data.ok ? "Operacional" : "Atenção"} tone={healthQuery.data.ok ? "success" : "warning"} />
                  </Stack>
                  <List>
                    {checks.map((check) => (
                      <ListItem key={check.label} disableGutters>
                        <ListItemIcon sx={{ minWidth: 36 }}>
                          {check.ok ? <CheckCircleIcon color="success" /> : <ErrorIcon color="warning" />}
                        </ListItemIcon>
                        <ListItemText
                          primary={<Typography sx={{ fontWeight: 700 }}>{check.label}</Typography>}
                          secondary={check.ok ? "Configurado" : "Pendente"}
                        />
                      </ListItem>
                    ))}
                  </List>
                  <Alert severity="info" sx={{ mt: 2 }}>
                    Condomínios acessíveis pela API administrativa: {healthQuery.data.condominiums_count ?? 0}
                  </Alert>
                </CardContent>
              </Card>
            </Grid>
            <Grid size={{ xs: 12, lg: 7 }}>
              <Card sx={{ height: "100%" }}>
                <CardContent>
                  <Typography variant="h3">Checklist MVP</Typography>
                  <List sx={{ mt: 1 }}>
                    {rolloutItems.map((item) => (
                      <ListItem key={item} disableGutters>
                        <ListItemIcon sx={{ minWidth: 36 }}>
                          <CheckCircleIcon color="primary" />
                        </ListItemIcon>
                        <ListItemText primary={<Typography sx={{ fontWeight: 700 }}>{item}</Typography>} />
                      </ListItem>
                    ))}
                  </List>
                </CardContent>
              </Card>
            </Grid>
          </Grid>
        )}
      </Stack>
    </AppShell>
  );
}
