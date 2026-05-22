"use client";

import CloseIcon from "@mui/icons-material/Close";
import SaveIcon from "@mui/icons-material/Save";
import {
  Alert,
  Box,
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
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Controller, useForm, useWatch } from "react-hook-form";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { AppShell } from "@/components/app-shell";
import { ResponsiveRecordList } from "@/components/data-display/responsive-record-list";
import { StatusChip } from "@/components/data-display/status-chip";
import { ErrorAlert } from "@/components/feedback/error-alert";
import { LoadingPanel } from "@/components/feedback/loading-panel";
import { PageHeader } from "@/components/page-header";
import { adminQueryKeys } from "@/lib/admin/query-keys";
import { formatDateTime, onlyDigits } from "@/lib/format";
import { createCondominium, fetchCondominiums } from "./api";
import { useState } from "react";

const condominiumSchema = z
  .object({
    condominium_name: z.string().trim().min(2, "Informe o nome do condomínio"),
    condominium_document: z.string().trim().optional(),
    portaria_email: z.string().trim().email("Informe um email válido para a portaria"),
    portaria_password: z.string().min(8, "A senha precisa ter pelo menos 8 caracteres"),
    portaria_device_name: z.string().trim().optional(),
    intercom_enabled: z.boolean(),
    create_default_unit: z.boolean(),
    default_unit_type: z.string().trim().optional(),
    default_unit_block: z.string().trim().optional(),
    default_unit_number: z.string().trim().optional(),
  })
  .superRefine((value, context) => {
    if (value.create_default_unit && !value.default_unit_number?.trim()) {
      context.addIssue({
        code: "custom",
        message: "Informe o número da unidade padrão",
        path: ["default_unit_number"],
      });
    }
  });

type CondominiumFormValues = z.infer<typeof condominiumSchema>;

const defaultValues: CondominiumFormValues = {
  condominium_name: "",
  condominium_document: "",
  portaria_email: "",
  portaria_password: "",
  portaria_device_name: "Portaria",
  intercom_enabled: true,
  create_default_unit: false,
  default_unit_type: "APARTMENT",
  default_unit_block: "",
  default_unit_number: "",
};

export function CondominiumsPage() {
  const [formOpen, setFormOpen] = useState(false);
  const queryClient = useQueryClient();
  const condominiumsQuery = useQuery({
    queryKey: adminQueryKeys.condominiums,
    queryFn: fetchCondominiums,
  });
  const form = useForm<CondominiumFormValues>({
    defaultValues,
    resolver: zodResolver(condominiumSchema),
  });
  const createDefaultUnit = useWatch({
    control: form.control,
    name: "create_default_unit",
  });

  const createMutation = useMutation({
    mutationFn: createCondominium,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: adminQueryKeys.condominiums });
      form.reset(defaultValues);
      setFormOpen(false);
    },
  });

  const handleSubmit = form.handleSubmit((values) => {
    createMutation.mutate({
      condominium_name: values.condominium_name.trim(),
      condominium_document: values.condominium_document ? onlyDigits(values.condominium_document) : null,
      portaria_email: values.portaria_email.trim(),
      portaria_password: values.portaria_password,
      portaria_device_name: values.portaria_device_name?.trim() || "Portaria",
      intercom_enabled: values.intercom_enabled,
      create_default_unit: values.create_default_unit,
      default_unit_type: values.default_unit_type || "APARTMENT",
      default_unit_block: values.default_unit_block?.trim() || null,
      default_unit_number: values.default_unit_number?.trim() || null,
    });
  });

  return (
    <AppShell>
      <PageHeader
        actionLabel="Novo condomínio"
        description="Cadastre o condomínio e o usuário da portaria no mesmo fluxo operacional."
        onAction={() => setFormOpen(true)}
        title="Condomínios"
      />

      <Stack spacing={2.5}>
        {condominiumsQuery.isLoading && <LoadingPanel label="Carregando condomínios..." />}

        {condominiumsQuery.isError && (
          <ErrorAlert
            message={condominiumsQuery.error.message}
            onRetry={() => void condominiumsQuery.refetch()}
          />
        )}

        {condominiumsQuery.data && (
          <>
            <Alert severity="info">
              Ao criar um condomínio, o backoffice também cria o usuário da portaria e o dispositivo vinculado.
            </Alert>

            <ResponsiveRecordList
              columns={[
                {
                  key: "name",
                  header: "Condomínio",
                  render: (item) => <Typography sx={{ fontWeight: 700 }}>{item.name}</Typography>,
                  tableSx: { width: "36%" },
                },
                {
                  key: "document",
                  header: "Documento",
                  render: (item) => item.document || "-",
                  tableSx: { width: "28%" },
                },
                {
                  key: "units",
                  header: "Unidades",
                  render: (item) => item.unit_count ?? 0,
                  tableSx: { width: "14%" },
                },
                {
                  key: "portaria",
                  header: "Portaria",
                  render: (item) => (
                    <StatusChip
                      label={(item.portaria_device_count ?? 0) > 0 ? "Configurada" : "Pendente"}
                      tone={(item.portaria_device_count ?? 0) > 0 ? "success" : "warning"}
                    />
                  ),
                  tableSx: { width: "22%" },
                },
                {
                  key: "features",
                  header: "Interfone",
                  render: (item) => (
                    <StatusChip
                      label={item.features?.INTERCOM === false ? "Desabilitado" : "Habilitado"}
                      tone={item.features?.INTERCOM === false ? "warning" : "success"}
                    />
                  ),
                  hideOnMobile: true,
                },
                {
                  key: "created",
                  header: "Criado em",
                  render: (item) => formatDateTime(item.created_at),
                  hideOnMobile: true,
                },
              ]}
              description="Lista carregada pela Edge Function administrativa admin-get-condominium."
              emptyDescription="Use o botão Novo condomínio para cadastrar o primeiro condomínio com portaria."
              emptyTitle="Nenhum condomínio cadastrado"
              getKey={(item) => item.id}
              items={condominiumsQuery.data}
              title="Condomínios cadastrados"
            />
          </>
        )}
      </Stack>

      <Dialog fullWidth maxWidth="md" onClose={() => setFormOpen(false)} open={formOpen}>
        <DialogTitle>
          <Stack direction="row" sx={{ alignItems: "center", justifyContent: "space-between" }}>
            <Box>
              <Typography variant="h3">Novo condomínio</Typography>
              <Typography color="text.secondary" variant="body2">
                O usuário da portaria será criado junto com o condomínio.
              </Typography>
            </Box>
            <IconButton aria-label="Fechar" onClick={() => setFormOpen(false)}>
              <CloseIcon />
            </IconButton>
          </Stack>
        </DialogTitle>
        <DialogContent dividers>
          <Stack component="form" id="condominium-form" onSubmit={handleSubmit} spacing={2.5}>
            {createMutation.isError && <ErrorAlert message={createMutation.error.message} />}

            <Grid container spacing={2}>
              <Grid size={{ xs: 12, md: 8 }}>
                <TextField
                  fullWidth
                  label="Nome do condomínio"
                  {...form.register("condominium_name")}
                  error={Boolean(form.formState.errors.condominium_name)}
                  helperText={form.formState.errors.condominium_name?.message}
                />
              </Grid>
              <Grid size={{ xs: 12, md: 4 }}>
                <TextField
                  fullWidth
                  label="CPF/CNPJ"
                  {...form.register("condominium_document")}
                  error={Boolean(form.formState.errors.condominium_document)}
                  helperText={form.formState.errors.condominium_document?.message}
                />
              </Grid>
            </Grid>

            <Grid container spacing={2}>
              <Grid size={{ xs: 12, md: 5 }}>
                <TextField
                  fullWidth
                  label="Email da portaria"
                  type="email"
                  {...form.register("portaria_email")}
                  error={Boolean(form.formState.errors.portaria_email)}
                  helperText={form.formState.errors.portaria_email?.message}
                />
              </Grid>
              <Grid size={{ xs: 12, md: 4 }}>
                <TextField
                  fullWidth
                  label="Senha inicial"
                  type="password"
                  {...form.register("portaria_password")}
                  error={Boolean(form.formState.errors.portaria_password)}
                  helperText={form.formState.errors.portaria_password?.message}
                />
              </Grid>
              <Grid size={{ xs: 12, md: 3 }}>
                <TextField
                  fullWidth
                  label="Dispositivo"
                  {...form.register("portaria_device_name")}
                  error={Boolean(form.formState.errors.portaria_device_name)}
                  helperText={form.formState.errors.portaria_device_name?.message}
                />
              </Grid>
            </Grid>

            <Stack
              spacing={2}
              sx={{
                border: "1px solid",
                borderColor: "divider",
                borderRadius: 1,
                p: 2,
              }}
            >
              <Controller
                control={form.control}
                name="intercom_enabled"
                render={({ field }) => (
                  <FormControlLabel
                    control={<Checkbox checked={field.value} onChange={(event) => field.onChange(event.target.checked)} />}
                    label="Habilitar Interfone Digital neste condomínio"
                  />
                )}
              />

              <Typography color="text.secondary" variant="body2">
                Os recursos contratados controlam os atalhos disponíveis no aplicativo.
              </Typography>
            </Stack>

            <Stack
              spacing={2}
              sx={{
                border: "1px solid",
                borderColor: "divider",
                borderRadius: 1,
                p: 2,
              }}
            >
              <Controller
                control={form.control}
                name="create_default_unit"
                render={({ field }) => (
                  <FormControlLabel
                    control={<Checkbox checked={field.value} onChange={(event) => field.onChange(event.target.checked)} />}
                    label="Criar unidade padrão agora"
                  />
                )}
              />

              {createDefaultUnit && (
                <Grid container spacing={2}>
                  <Grid size={{ xs: 12, md: 4 }}>
                    <TextField fullWidth label="Tipo" select {...form.register("default_unit_type")}>
                      <MenuItem value="APARTMENT">Apartamento</MenuItem>
                      <MenuItem value="HOUSE">Casa</MenuItem>
                    </TextField>
                  </Grid>
                  <Grid size={{ xs: 12, md: 4 }}>
                    <TextField fullWidth label="Bloco" {...form.register("default_unit_block")} />
                  </Grid>
                  <Grid size={{ xs: 12, md: 4 }}>
                    <TextField
                      fullWidth
                      label="Número"
                      {...form.register("default_unit_number")}
                      error={Boolean(form.formState.errors.default_unit_number)}
                      helperText={form.formState.errors.default_unit_number?.message}
                    />
                  </Grid>
                </Grid>
              )}
            </Stack>
          </Stack>
        </DialogContent>
        <DialogActions sx={{ px: 3, py: 2 }}>
          <Button onClick={() => setFormOpen(false)}>Cancelar</Button>
          <Button
            disabled={createMutation.isPending}
            form="condominium-form"
            startIcon={<SaveIcon />}
            type="submit"
            variant="contained"
          >
            {createMutation.isPending ? "Salvando..." : "Salvar condomínio"}
          </Button>
        </DialogActions>
      </Dialog>
    </AppShell>
  );
}
