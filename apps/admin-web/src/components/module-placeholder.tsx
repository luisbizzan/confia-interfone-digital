import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import { Card, CardContent, Chip, Grid, List, ListItem, ListItemIcon, ListItemText, Typography } from "@mui/material";
import { AppShell } from "@/components/app-shell";
import { EmptyState } from "@/components/feedback/empty-state";
import { PageHeader } from "@/components/page-header";
import { backofficeModules } from "@/lib/admin/routes";

type ModulePlaceholderProps = {
  moduleId: keyof typeof backofficeModules;
};

export function ModulePlaceholder({ moduleId }: ModulePlaceholderProps) {
  const moduleConfig = backofficeModules[moduleId];

  return (
    <AppShell>
      <PageHeader
        actionLabel={moduleConfig.actionLabel}
        description={moduleConfig.description}
        title={moduleConfig.title}
      />

      <Grid container spacing={2.5}>
        <Grid size={{ xs: 12, lg: 7 }}>
          <Card>
            <CardContent>
              <Chip
                color={moduleConfig.statusTone === "default" ? undefined : moduleConfig.statusTone}
                label={moduleConfig.statusLabel}
              />
              <Typography sx={{ mt: 2 }} variant="h3">
                Escopo da próxima entrega
              </Typography>
              <List sx={{ mt: 1 }}>
                {moduleConfig.tasks.map((task) => (
                  <ListItem key={task} disableGutters>
                    <ListItemIcon sx={{ minWidth: 36 }}>
                      <CheckCircleIcon color="primary" fontSize="small" />
                    </ListItemIcon>
                    <ListItemText primary={<Typography sx={{ fontWeight: 700 }}>{task}</Typography>} />
                  </ListItem>
                ))}
              </List>
            </CardContent>
          </Card>
        </Grid>
        <Grid size={{ xs: 12, lg: 5 }}>
          <EmptyState
            description="A estrutura visual já está pronta para receber dados reais, formulários e estados de carregamento."
            title="Tela preparada"
          />
        </Grid>
      </Grid>
    </AppShell>
  );
}
