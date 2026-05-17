"use client";

import CloseIcon from "@mui/icons-material/Close";
import SaveIcon from "@mui/icons-material/Save";
import {
  Button,
  Checkbox,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControlLabel,
  Grid,
  IconButton,
  MenuItem,
  Stack,
  TextField,
  Typography,
} from "@mui/material";
import { zodResolver } from "@hookform/resolvers/zod";
import { Controller, useForm, useWatch } from "react-hook-form";
import { useEffect } from "react";
import { z } from "zod";
import { ErrorAlert } from "@/components/feedback/error-alert";
import type { AdminUnit } from "@/lib/admin/condominiums";
import type { CreateAdminUnitMemberInput } from "@/lib/admin/condominiums";

const unitMemberSchema = z
  .object({
    unit_id: z.string().optional(),
    unit_type: z.string().trim().optional(),
    unit_block: z.string().trim().optional(),
    unit_number: z.string().trim().optional(),
    resident_email: z.string().trim().email("Informe um email válido para o morador"),
    resident_password: z.string().min(8, "A senha precisa ter pelo menos 8 caracteres"),
    member_type: z.string().trim().optional(),
    call_order: z.string().trim().optional(),
    active_for_calls: z.boolean(),
    can_receive_calls: z.boolean(),
    can_make_calls: z.boolean(),
  })
  .superRefine((value, context) => {
    if (!value.unit_id && !value.unit_number?.trim()) {
      context.addIssue({
        code: "custom",
        message: "Escolha uma unidade ou informe o número da nova unidade",
        path: ["unit_number"],
      });
    }
  });

export type UnitMemberFormValues = z.infer<typeof unitMemberSchema>;

const defaultValues: UnitMemberFormValues = {
  unit_id: "",
  unit_type: "APARTMENT",
  unit_block: "",
  unit_number: "",
  resident_email: "",
  resident_password: "",
  member_type: "RESIDENT",
  call_order: undefined,
  active_for_calls: true,
  can_receive_calls: true,
  can_make_calls: true,
};

type UnitMemberDialogProps = {
  open: boolean;
  title: string;
  description: string;
  units: AdminUnit[];
  selectedUnitId?: string;
  isPending: boolean;
  errorMessage?: string;
  onClose: () => void;
  onSubmit: (input: Omit<CreateAdminUnitMemberInput, "condominium_id">) => void;
};

export function UnitMemberDialog({
  open,
  title,
  description,
  units,
  selectedUnitId,
  isPending,
  errorMessage,
  onClose,
  onSubmit,
}: UnitMemberDialogProps) {
  const form = useForm<UnitMemberFormValues>({
    defaultValues: { ...defaultValues, unit_id: selectedUnitId ?? "" },
    resolver: zodResolver(unitMemberSchema),
  });
  const unitId = useWatch({ control: form.control, name: "unit_id" });

  useEffect(() => {
    if (open) {
      form.reset({ ...defaultValues, unit_id: selectedUnitId ?? "" });
    }
  }, [form, open, selectedUnitId]);

  const submit = form.handleSubmit((values) => {
    onSubmit({
      unit_id: values.unit_id || null,
      unit_type: values.unit_type || "APARTMENT",
      unit_block: values.unit_block?.trim() || null,
      unit_number: values.unit_number?.trim() || null,
      resident_email: values.resident_email.trim(),
      resident_password: values.resident_password,
      member_type: values.member_type || "RESIDENT",
      call_order: values.call_order ? Number(values.call_order) : null,
      active_for_calls: values.active_for_calls,
      can_receive_calls: values.can_receive_calls,
      can_make_calls: values.can_make_calls,
    });
  });

  return (
    <Dialog fullWidth maxWidth="md" onClose={onClose} open={open}>
      <DialogTitle>
        <Stack direction="row" sx={{ alignItems: "center", justifyContent: "space-between" }}>
          <Stack spacing={0.5}>
            <Typography variant="h3">{title}</Typography>
            <Typography color="text.secondary" variant="body2">
              {description}
            </Typography>
          </Stack>
          <IconButton aria-label="Fechar" onClick={onClose}>
            <CloseIcon />
          </IconButton>
        </Stack>
      </DialogTitle>
      <DialogContent dividers>
        <Stack component="form" id="unit-member-form" onSubmit={submit} spacing={2.5}>
          {errorMessage && <ErrorAlert message={errorMessage} />}

          <Grid container spacing={2}>
            <Grid size={{ xs: 12, md: 6 }}>
              <TextField fullWidth label="Unidade existente" select {...form.register("unit_id")}>
                <MenuItem value="">Criar nova unidade</MenuItem>
                {units.map((unit) => (
                  <MenuItem key={unit.id} value={unit.id}>
                    {unit.block ? `${unit.block} - ` : ""}
                    {unit.number}
                  </MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid size={{ xs: 12, md: 3 }}>
              <TextField disabled={Boolean(unitId)} fullWidth label="Tipo" select {...form.register("unit_type")}>
                <MenuItem value="APARTMENT">Apartamento</MenuItem>
                <MenuItem value="HOUSE">Casa</MenuItem>
              </TextField>
            </Grid>
            <Grid size={{ xs: 12, md: 3 }}>
              <TextField disabled={Boolean(unitId)} fullWidth label="Bloco" {...form.register("unit_block")} />
            </Grid>
            <Grid size={{ xs: 12, md: 4 }}>
              <TextField
                disabled={Boolean(unitId)}
                fullWidth
                label="Número da unidade"
                {...form.register("unit_number")}
                error={Boolean(form.formState.errors.unit_number)}
                helperText={form.formState.errors.unit_number?.message}
              />
            </Grid>
          </Grid>

          <Grid container spacing={2}>
            <Grid size={{ xs: 12, md: 5 }}>
              <TextField
                fullWidth
                label="Email do morador"
                type="email"
                {...form.register("resident_email")}
                error={Boolean(form.formState.errors.resident_email)}
                helperText={form.formState.errors.resident_email?.message}
              />
            </Grid>
            <Grid size={{ xs: 12, md: 4 }}>
              <TextField
                fullWidth
                label="Senha inicial"
                type="password"
                {...form.register("resident_password")}
                error={Boolean(form.formState.errors.resident_password)}
                helperText={form.formState.errors.resident_password?.message}
              />
            </Grid>
            <Grid size={{ xs: 12, md: 3 }}>
              <TextField fullWidth label="Ordem de chamada" type="number" {...form.register("call_order")} />
            </Grid>
          </Grid>

          <Grid container spacing={1}>
            <Grid size={{ xs: 12, md: 4 }}>
              <Controller
                control={form.control}
                name="active_for_calls"
                render={({ field }) => (
                  <FormControlLabel
                    control={<Checkbox checked={field.value} onChange={(event) => field.onChange(event.target.checked)} />}
                    label="Ativo para chamadas"
                  />
                )}
              />
            </Grid>
            <Grid size={{ xs: 12, md: 4 }}>
              <Controller
                control={form.control}
                name="can_receive_calls"
                render={({ field }) => (
                  <FormControlLabel
                    control={<Checkbox checked={field.value} onChange={(event) => field.onChange(event.target.checked)} />}
                    label="Recebe chamadas"
                  />
                )}
              />
            </Grid>
            <Grid size={{ xs: 12, md: 4 }}>
              <Controller
                control={form.control}
                name="can_make_calls"
                render={({ field }) => (
                  <FormControlLabel
                    control={<Checkbox checked={field.value} onChange={(event) => field.onChange(event.target.checked)} />}
                    label="Liga para portaria"
                  />
                )}
              />
            </Grid>
          </Grid>
        </Stack>
      </DialogContent>
      <DialogActions sx={{ px: 3, py: 2 }}>
        <Button onClick={onClose}>Cancelar</Button>
        <Button disabled={isPending} form="unit-member-form" startIcon={<SaveIcon />} type="submit" variant="contained">
          {isPending ? "Salvando..." : "Salvar"}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
