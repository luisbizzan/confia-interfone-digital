import ApartmentIcon from "@mui/icons-material/Apartment";
import CallIcon from "@mui/icons-material/Call";
import DoorFrontIcon from "@mui/icons-material/DoorFront";
import PeopleIcon from "@mui/icons-material/People";
import {
  Box,
  Card,
  CardContent,
  Chip,
  Grid,
  List,
  ListItem,
  ListItemText,
  Stack,
  Typography,
} from "@mui/material";
import { AppShell } from "@/components/app-shell";
import { PageHeader } from "@/components/page-header";
import type { SummaryMetric } from "@/lib/types";

export default function Home() {
  const metrics: SummaryMetric[] = [
    { label: "Condomínios", value: "0", helper: "Pronto para listar via admin API", tone: "info" },
    { label: "Unidades", value: "0", helper: "Cadastro entra na Fase 4", tone: "success" },
    { label: "Moradores", value: "0", helper: "Vínculo por unidade", tone: "warning" },
    { label: "Chamadas", value: "0", helper: "Realtime preparado no backend", tone: "default" },
  ];

  const icons = [
    <ApartmentIcon key="condos" />,
    <DoorFrontIcon key="units" />,
    <PeopleIcon key="people" />,
    <CallIcon key="calls" />,
  ];

  return (
    <AppShell>
      <PageHeader
        actionLabel="Novo condomínio"
        description="Base responsiva criada para operar condomínios, unidades, portaria e chamadas."
        title="Dashboard"
      />

      <Grid container spacing={2.5}>
        {metrics.map((metric, index) => (
          <Grid key={metric.label} size={{ xs: 12, sm: 6, lg: 3 }}>
            <Card>
              <CardContent>
                <Stack direction="row" spacing={2} sx={{ justifyContent: "space-between" }}>
                  <Box>
                    <Typography color="text.secondary" variant="body2">
                      {metric.label}
                    </Typography>
                    <Typography sx={{ mt: 1 }} variant="h2">
                      {metric.value}
                    </Typography>
                  </Box>
                  <Chip
                    color={metric.tone === "default" ? undefined : metric.tone}
                    icon={icons[index]}
                    label="MVP"
                  />
                </Stack>
                <Typography color="text.secondary" sx={{ mt: 2 }} variant="body2">
                  {metric.helper}
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      <Grid container spacing={2.5} sx={{ mt: 0.5 }}>
        <Grid size={{ xs: 12, lg: 7 }}>
          <Card>
            <CardContent>
              <Stack
                direction={{ xs: "column", sm: "row" }}
                spacing={1.5}
                sx={{ justifyContent: "space-between" }}
              >
                <Box>
                  <Typography variant="h3">Próximas entregas</Typography>
                  <Typography color="text.secondary" sx={{ mt: 0.75 }}>
                    A Fase 2 transforma essa base em componentes reutilizáveis.
                  </Typography>
                </Box>
                <Chip color="primary" label="Fase 1 pronta" />
              </Stack>
              <List sx={{ mt: 1 }}>
                {[
                  "Conectar dashboard ao admin-get-condominium",
                  "Criar formulários de condomínio, unidade e morador",
                  "Adicionar tabelas responsivas e cards mobile",
                  "Preparar autenticação do operador administrativo",
                ].map((item) => (
                  <ListItem key={item} disableGutters>
                    <ListItemText primary={<Typography sx={{ fontWeight: 700 }}>{item}</Typography>} />
                  </ListItem>
                ))}
              </List>
            </CardContent>
          </Card>
        </Grid>
        <Grid size={{ xs: 12, lg: 5 }}>
          <Card>
            <CardContent>
              <Typography variant="h3">Critérios responsivos</Typography>
              <Stack spacing={1.25} sx={{ mt: 2 }}>
                {[
                  "Sidebar fixa no desktop e drawer no mobile",
                  "Cards empilhados abaixo de tablet",
                  "Formulários em uma coluna no celular",
                  "Ações principais acessíveis por toque",
                ].map((item) => (
                  <Chip key={item} label={item} sx={{ justifyContent: "flex-start" }} />
                ))}
              </Stack>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </AppShell>
  );
}
