export type StatusTone = "success" | "warning" | "error" | "info" | "default";

export type SummaryMetric = {
  label: string;
  value: string;
  helper: string;
  tone: StatusTone;
};

export type AdminRouteStatus = "ready" | "planned" | "attention";

export type AdminRouteOverview = {
  id: string;
  title: string;
  owner: string;
  statusLabel: string;
  statusTone: StatusTone;
  details: string;
};
