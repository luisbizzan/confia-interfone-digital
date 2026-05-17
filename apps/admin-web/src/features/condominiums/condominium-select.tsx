import { MenuItem, TextField } from "@mui/material";
import type { AdminCondominiumListItem } from "@/lib/admin/condominiums";

type CondominiumSelectProps = {
  condominiums: AdminCondominiumListItem[];
  value: string;
  onChange: (value: string) => void;
};

export function CondominiumSelect({ condominiums, value, onChange }: CondominiumSelectProps) {
  return (
    <TextField
      fullWidth
      label="Condomínio"
      onChange={(event) => onChange(event.target.value)}
      select
      value={value}
    >
      {condominiums.map((condominium) => (
        <MenuItem key={condominium.id} value={condominium.id}>
          {condominium.name}
        </MenuItem>
      ))}
    </TextField>
  );
}
