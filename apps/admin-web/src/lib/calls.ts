import type { StatusTone } from "@/lib/types";

export function callStatusLabel(status: string) {
  const labels: Record<string, string> = {
    RINGING: "Tocando",
    ANSWERED: "Atendida",
    MISSED: "Perdida",
    CANCELLED: "Cancelada",
    ENDED: "Encerrada",
  };

  return labels[status] ?? status;
}

export function callStatusTone(status: string): StatusTone {
  const tones: Record<string, StatusTone> = {
    RINGING: "warning",
    ANSWERED: "success",
    MISSED: "error",
    CANCELLED: "default",
    ENDED: "info",
  };

  return tones[status] ?? "default";
}

export function callDirectionLabel(originType?: string | null, targetType?: string | null) {
  if (originType === "PORTARIA" && targetType === "UNIT") return "Portaria para unidade";
  if (originType === "UNIT" && targetType === "PORTARIA") return "Unidade para portaria";
  return "Chamada";
}
