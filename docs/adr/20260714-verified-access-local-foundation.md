# ADR-VA-001: Fundacao local do Acesso Verificado

Data: 2026-07-14

Status: aceito para Fase 1A-H

## Contexto

A capacidade Acesso Verificado sera implementada de forma incremental sobre o backend Supabase existente. A Fase 1A cria apenas a fundacao local por condominio, sem UI, Edge Functions publicas, providers, convites, QR, credenciais ou tabelas centrais da Rede Confia.

O tenant atual do projeto e o condominio, representado por `condominium_id`. O backend existente usa Postgres como fonte de verdade, RLS, RPCs `security definer`, `text` com `CHECK` para estados, timestamps `timestamptz`, UUIDs por `gen_random_uuid()` nos dominios recentes e feature flags em `condominium_features`.

## Decisao

Criar o dominio local com prefixo `verified_access_` dentro de migrations Supabase:

- catalogo global de tipos de servico;
- configuracao de tipos de servico por condominio;
- politicas versionadas por condominio;
- solicitacoes, detalhes de prestador, vagas e participantes;
- perfis locais de identidade protegidos;
- avaliacoes de elegibilidade;
- outbox e auditoria especificas do dominio.

Todas as tabelas locais operacionais carregam `condominium_id`. Relacionamentos entre tabelas locais usam chaves compostas para impedir mistura de tenant, request, slot, participant e policy version. A tabela legada `persons` nao e reutilizada.

## Policy V2

A policy local guarda configuracoes separadas para visitante e prestador:

- identidade de visitante e prestador;
- background de visitante e prestador;
- limites de participantes por tipo;
- TTLs, janela maxima, antecedencia e timezone;
- referencias de aprovacao;
- retencao e ajustes adicionais em JSON objeto;
- campos de rede inertes.

Os campos de rede existem para compatibilidade futura, mas nao criam tabelas de rede, nao ativam efeito operacional e rejeitam `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` e `PERMANENT_BLACKLIST`.

## Seguranca e privacidade

Dados pessoais sensiveis ficam somente em colunas `bytea` de ciphertext e HMACs locais separados para identificadores com finalidade concreta: CPF, documento e telefone. Nome, filiacao e nascimento nao possuem HMAC por minimizacao. Todas as colunas criptografadas/HMAC exigem versao de chave quando preenchidas.

A Fase 1A nao inclui descriptografia SQL, secrets, biometria, selfies, certidoes, payloads policiais, HMAC de rede ou providers reais.

Checks de blacklist em JSON sao defesa em profundidade. Eles reduzem vazamentos acidentais em audit/outbox/evaluation, mas nao sao detector universal de PII. Por isso os JSONs operacionais sao limitados a objetos e os campos livres recebem comentarios de finalidade e tamanho.

## Invariantes estruturais

Foram escolhidas FKs compostas quando a invariante pode ser declarativa:

- `request.policy_id + condominium_id + policy_version`;
- `participant.slot_id + request_id + condominium_id`;
- `evaluation.participant_id + request_id + condominium_id`;
- `evaluation.policy_id + condominium_id + policy_version`.

Triggers `security invoker` com `search_path` fixo cobrem invariantes cross-row:

- validar `SERVICE_PROVIDER` e `OTHER` em detalhes de servico;
- limitar `slot_number` ao `participant_limit`;
- impedir alteracao de payload de negocio na outbox;
- impedir update, delete e truncate na auditoria.

## RLS e grants

RLS fica habilitada em todas as tabelas novas, com postura default-deny. `anon` e `authenticated` nao recebem grants diretos. Operacoes futuras serao abertas por RPCs especificas em fases posteriores.

`service_role` recebe grants minimos por tabela. `DELETE` nao foi concedido por padrao, porque cancelamento, revogacao e retencao controlada devem ser modelados como transicoes futuras, nao exclusao livre.

## Feature flags

A Fase 1A cadastra `VERIFIED_ACCESS` e `VERIFIED_ACCESS_BACKGROUND_CHECK` no mecanismo existente `condominium_features`, sempre com `enabled = false` para todos os condominios existentes.

## Consequencias

- Nao ha funcionalidade visivel ao usuario ao final da Fase 1A.
- O schema fica revisavel com banco descartavel e rollback.
- A ativacao de policies, state machines completas, providers e UI permanecem fora desta fase.
- O backoffice atual nao ganha acesso implicito a dados sensiveis.
