import type { AdminRouteOverview, SummaryMetric } from "@/lib/types";

export const dashboardMetrics: SummaryMetric[] = [
  { label: "Condomínios", value: "0", helper: "Pronto para listar via admin API", tone: "info" },
  { label: "Unidades", value: "0", helper: "Cadastro entra na Fase 4", tone: "success" },
  { label: "Moradores", value: "0", helper: "Vínculo por unidade", tone: "warning" },
  { label: "Chamadas", value: "0", helper: "Realtime preparado no backend", tone: "default" },
];

export const routeOverviews: AdminRouteOverview[] = [
  {
    id: "condominios",
    title: "Condomínios",
    owner: "Administração",
    statusLabel: "Base pronta",
    statusTone: "info",
    details: "Entrada principal para cadastrar o condomínio e o usuário da portaria.",
  },
  {
    id: "unidades",
    title: "Unidades",
    owner: "Operação",
    statusLabel: "Planejado",
    statusTone: "warning",
    details: "Casas, apartamentos e vínculos de chamada com moradores.",
  },
  {
    id: "moradores",
    title: "Moradores",
    owner: "Atendimento",
    statusLabel: "Planejado",
    statusTone: "warning",
    details: "Pessoas autorizadas a receber chamadas e histórico de contato.",
  },
  {
    id: "chamadas",
    title: "Chamadas",
    owner: "Portaria",
    statusLabel: "Backend pronto",
    statusTone: "success",
    details: "Consulta operacional de chamadas, tentativas e eventos em realtime.",
  },
];
