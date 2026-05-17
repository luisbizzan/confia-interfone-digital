import type { StatusTone } from "@/lib/types";

export type BackofficeModule = {
  title: string;
  description: string;
  actionLabel?: string;
  statusLabel: string;
  statusTone: StatusTone;
  tasks: string[];
};

export const backofficeModules: Record<string, BackofficeModule> = {
  condominios: {
    title: "Condomínios",
    description: "Cadastro e manutenção dos condomínios atendidos pelo Confia.",
    actionLabel: "Novo condomínio",
    statusLabel: "Fase 3",
    statusTone: "info",
    tasks: [
      "Listar condomínios pela função admin-get-condominium",
      "Criar formulário de condomínio com usuário da portaria",
      "Exibir dados operacionais da portaria",
    ],
  },
  unidades: {
    title: "Unidades",
    description: "Gestão das casas e apartamentos que recebem chamadas da portaria.",
    actionLabel: "Nova unidade",
    statusLabel: "Fase 4",
    statusTone: "warning",
    tasks: [
      "Criar cadastro de unidade por condomínio",
      "Vincular moradores e contatos",
      "Preparar visualização mobile em cards",
    ],
  },
  moradores: {
    title: "Moradores",
    description: "Pessoas autorizadas a receber ligações e responder pela unidade.",
    actionLabel: "Novo morador",
    statusLabel: "Fase 4",
    statusTone: "warning",
    tasks: [
      "Criar formulário com telefone e vínculo de unidade",
      "Validar duplicidade de contato",
      "Exibir status de ativação",
    ],
  },
  chamadas: {
    title: "Chamadas",
    description: "Acompanhamento das chamadas entre portaria, unidades e moradores.",
    statusLabel: "Fase 5",
    statusTone: "success",
    tasks: [
      "Listar chamadas recentes",
      "Exibir tentativa ativa e timeout",
      "Preparar painel realtime para operação",
    ],
  },
  auditoria: {
    title: "Auditoria",
    description: "Histórico de eventos importantes do backend e das chamadas.",
    statusLabel: "Fase 6",
    statusTone: "default",
    tasks: [
      "Listar eventos de call_events",
      "Adicionar filtros por condomínio e período",
      "Exibir usuário responsável quando houver",
    ],
  },
  configuracoes: {
    title: "Configurações",
    description: "Parâmetros administrativos e integrações futuras do backoffice.",
    statusLabel: "Fase 6",
    statusTone: "default",
    tasks: [
      "Preparar autenticação do operador administrativo",
      "Documentar chaves públicas do Supabase",
      "Reservar espaço para integração de voz",
    ],
  },
};
