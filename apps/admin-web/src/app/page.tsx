"use client";

import ApartmentIcon from "@mui/icons-material/Apartment";
import CallIcon from "@mui/icons-material/Call";
import DoorFrontIcon from "@mui/icons-material/DoorFront";
import PeopleIcon from "@mui/icons-material/People";
import { Box, Card, CardContent, Chip, Grid, List, ListItem, ListItemText, Stack, Typography } from "@mui/material";
import { AppShell } from "@/components/app-shell";
import { ResponsiveRecordList } from "@/components/data-display/responsive-record-list";
import { StatusChip } from "@/components/data-display/status-chip";
import { MetricCard } from "@/components/dashboard/metric-card";
import { PageHeader } from "@/components/page-header";
import { dashboardMetrics, routeOverviews } from "@/lib/admin/dashboard";

const metricIcons = [
  <ApartmentIcon key="condos" />,
  <DoorFrontIcon key="units" />,
  <PeopleIcon key="people" />,
  <CallIcon key="calls" />,
];

export default function Home() {
  return (
    <AppShell>
      <PageHeader
        actionHref="/condominios"
        actionLabel="Novo condomínio"
        description="Base responsiva criada para operar condomínios, unidades, portaria e chamadas."
        title="Dashboard"
      />

      <Grid container spacing={2.5}>
        {dashboardMetrics.map((metric, index) => (
          <Grid key={metric.label} size={{ xs: 12, sm: 6, lg: 3 }}>
            <MetricCard {...metric} icon={metricIcons[index]} />
          </Grid>
        ))}
      </Grid>

      <Grid container spacing={2.5} sx={{ mt: 0.5 }}>
        <Grid size={{ xs: 12, lg: 7 }}>
          <ResponsiveRecordList
            columns={[
              {
                key: "title",
                header: "Módulo",
                render: (item) => <Typography sx={{ fontWeight: 700 }}>{item.title}</Typography>,
              },
              {
                key: "owner",
                header: "Responsável",
                render: (item) => item.owner,
              },
              {
                key: "status",
                header: "Status",
                render: (item) => <StatusChip label={item.statusLabel} tone={item.statusTone} />,
              },
              {
                key: "details",
                header: "Próximo uso",
                render: (item) => item.details,
              },
            ]}
            description="Mapa inicial dos módulos que serão preenchidos nas próximas fases."
            emptyDescription="Os módulos aparecerão aqui conforme forem habilitados."
            emptyTitle="Nenhum módulo configurado"
            getKey={(item) => item.id}
            items={routeOverviews}
            title="Módulos do backoffice"
          />
        </Grid>
        <Grid size={{ xs: 12, lg: 5 }}>
          <Card sx={{ height: "100%" }}>
            <CardContent>
              <Stack
                direction={{ xs: "column", sm: "row" }}
                spacing={1.5}
                sx={{ justifyContent: "space-between" }}
              >
                <Box>
                  <Typography variant="h3">Critérios responsivos</Typography>
                  <Typography color="text.secondary" sx={{ mt: 0.75 }}>
                    Padrões que todos os próximos formulários e listas devem respeitar.
                  </Typography>
                </Box>
                <Chip color="primary" label="Fase 2" />
              </Stack>
              <List sx={{ mt: 1 }}>
                {[
                  "Sidebar fixa no desktop e drawer no mobile",
                  "Tabelas no desktop com cards equivalentes no celular",
                  "Formulários em uma coluna no celular",
                  "Ações principais acessíveis por toque",
                ].map((item) => (
                  <ListItem key={item} disableGutters>
                    <ListItemText primary={<Typography sx={{ fontWeight: 700 }}>{item}</Typography>} />
                  </ListItem>
                ))}
              </List>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </AppShell>
  );
}
