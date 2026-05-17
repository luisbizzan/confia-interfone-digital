import { Chip } from "@mui/material";
import type { StatusTone } from "@/lib/types";

type StatusChipProps = {
  label: string;
  tone?: StatusTone;
};

export function StatusChip({ label, tone = "default" }: StatusChipProps) {
  return <Chip color={tone === "default" ? undefined : tone} label={label} size="small" />;
}
