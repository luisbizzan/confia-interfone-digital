export type StatusTone = "success" | "warning" | "error" | "info" | "default";

export type SummaryMetric = {
  label: string;
  value: string;
  helper: string;
  tone: StatusTone;
};
