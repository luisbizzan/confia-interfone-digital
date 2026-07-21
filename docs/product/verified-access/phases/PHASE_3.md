# Fase 3 — convite e cadastro público

**Status:** Fase 3A autorizada / Fases 3B e 3C não autorizadas

Stage: `3A autorizada / aguardando execução`.

## 1. Objetivo

Planejar o fluxo em que uma solicitação criada pelo morador na Fase 2 gera convites individuais para cada vaga de participante e permite que visitantes ou prestadores realizem um cadastro público seguro, sem autenticação prévia no aplicativo.

A Fase 3 deve preparar o cadastro preliminar do participante e o handoff para as validações de identidade da fase seguinte.

Esta fase não deve executar validação biométrica real, background check real, emissão de credencial, QR Code, check-in ou operação da portaria.

## 2. Dependências obrigatórias

A Fase 3 depende de:

- fundação local da Fase 1A;
- governança e máquinas de estado da Fase 1C;
- contratos de providers e fakes da Fase 1D;
- solicitações e participant slots da Fase 2;
- feature `VERIFIED_ACCESS` existente e desligada por padrão;
- policy `ACTIVE` do condomínio;
- tenant isolation já estabelecido.

A implementação futura deve parar caso a Fase 2 não esteja incorporada à `main`.

A Fase 2 foi incorporada à `main` pelo squash commit
`a464de1175ae924644cfc2aa71eab7f27cc61cd5`.

### 2.1 Reconciliação com o repositório

- O estado terminal de cadastro disponível hoje é `SUBMITTED`; não existe
  `COMPLETED` em `verified_access_participants.registration_status`.
- O schema local de `verified_access_identity_profiles.document_type` aceita
  `CPF`, `RNM` e `PASSPORT`. Para passaporte, o país emissor fica no campo
  protegido próprio. `PASSPORT_WITH_ISSUER` permanece a taxonomia canônica de
  identificador da Rede Confia, não um novo valor do enum local.
- A constraint atual de slots exige `claimed_at` preenchido tanto em
  `RESERVED` quanto em `CLAIMED`. A nomenclatura é legada; a Fase 3 deverá
  preservar a constraint ou obter autorização explícita para evoluí-la.
- `MessagingProvider` e `InvitationMessageInput` já existem. Seu
  `ProviderContext` exige `participantId`, mas o momento de criação do
  participante ainda não foi decidido neste plano.
- As Edge Functions da Fase 2 validam bearer token internamente, usam
  allowlists estritas, limite de 16 KiB, correlation ID e CORS configurado por
  `VERIFIED_ACCESS_ALLOWED_ORIGINS`. Operações públicas exigirão contrato
  separado e não podem herdar autenticação ou grants por inferência.
- O frontend existente é um único app Next.js 16 em `apps/admin-web`, voltado
  ao backoffice. Hospedar nele a página pública ou criar aplicação isolada
  permanece decisão humana pendente.

## 3. Escopo funcional

Planejar:

1. geração de um convite individual para cada participant slot `OPEN`;
2. token público opaco, de uso controlado e sem PII;
3. link público individual por vaga;
4. expiração do convite;
5. reenvio controlado sem criar nova vaga;
6. revogação do convite;
7. abertura da página pública;
8. aceite de termos e aviso de privacidade;
9. cadastro preliminar do participante;
10. confirmação do cadastro;
11. atualização segura dos estados da vaga e do participante;
12. acompanhamento resumido pelo morador;
13. preparação para validação de identidade fake na fase seguinte.

## 4. Fora do escopo

Não implementar nesta fase:

- WhatsApp real;
- SMS real;
- e-mail transacional real;
- provider externo real;
- captura de documento;
- OCR;
- prova de vida;
- face match;
- background check;
- consulta policial;
- decisão de elegibilidade;
- negativa automática;
- credencial;
- QR Code;
- check-in;
- check-out;
- portaria;
- Rede Confia operacional;
- UI mobile do morador;
- UI mobile da portaria;
- migration remota;
- habilitação de feature.

Mensageria deve usar somente provider fake ou mecanismo de preview local autorizado.

## 5. Atores

### Morador autenticado

Pode:

- consultar o status resumido dos convites da própria solicitação;
- solicitar envio ou reenvio quando permitido;
- revogar convite pendente quando permitido.

Não pode:

- acessar dados sensíveis preenchidos pelo participante;
- alterar identidade, background ou elegibilidade;
- visualizar token bruto;
- acessar solicitações de outro morador ou condomínio.

### Participante público

Pode:

- abrir somente o convite correspondente ao token apresentado;
- visualizar contexto mínimo da visita;
- aceitar termos;
- preencher cadastro preliminar;
- confirmar o envio;
- consultar resultado público mínimo da própria operação.

Não possui acesso a:

- dados do morador além do mínimo necessário;
- outros participantes;
- outros slots;
- outras solicitações;
- policy completa;
- audit;
- outbox;
- dados da Rede Confia.

### Backend

Deve:

- derivar a solicitação, vaga, condomínio e policy pelo token;
- nunca confiar em IDs de tenant enviados pelo público;
- validar expiração, revogação e uso;
- aplicar rate limiting;
- sanitizar logs e respostas;
- impedir enumeração.

## 6. Modelo de convite

Planejar uma entidade local equivalente a:

`verified_access_invitations`

Campos conceituais mínimos:

- `id uuid`;
- `condominium_id uuid`;
- `request_id uuid`;
- `participant_slot_id uuid`;
- `token_hash bytea/text`;
- `token_version integer`;
- `status`;
- `expires_at timestamptz`;
- `issued_at timestamptz`;
- `revoked_at timestamptz nullable`;
- `consumed_at timestamptz nullable`;
- `last_sent_at timestamptz nullable`;
- `send_count integer`;
- `created_by_user_id uuid`;
- `created_at timestamptz`;
- `updated_at timestamptz`.

Status canônicos planejados:

- `PENDING`;
- `SENT`;
- `OPENED`;
- `COMPLETED`;
- `REVOKED`;
- `EXPIRED`.

Não armazenar token bruto.

Um slot pode possuir somente um convite ativo por vez.

## 7. Token público

Regras obrigatórias:

- token aleatório criptograficamente seguro;
- entropia mínima documentada;
- token bruto exibido somente no momento da geração;
- somente hash/version persistidos;
- comparação constante quando aplicável;
- não derivar token de IDs previsíveis;
- não incluir condomínio, unidade, request ou slot;
- expiração obrigatória;
- rotação em caso de reemissão;
- revogação imediata;
- token nunca em logs, audit, outbox ou mensagens de erro;
- query string deve ser evitada quando houver alternativa segura;
- referer policy restritiva;
- proteção contra replay e brute force.

## 8. Dados preliminares do participante

Planejar coleta mínima:

- nome completo;
- CPF para brasileiros, quando juridicamente aprovado;
- data de nascimento;
- telefone, somente se necessário para contato/convite;
- tipo de documento alternativo para estrangeiro;
- aceite de termos;
- aceite/ciência do aviso de privacidade.

Decisões obrigatórias antes da implementação:

- CPF será obrigatório já na Fase 3 ou somente antes da validação?
- telefone será obrigatório ou o convite já define o canal?
- data de nascimento será coletada nesta fase?
- quais documentos alternativos serão aceitos?
- política de menores de idade;
- base legal e texto de consentimento/ciência;
- prazo de retenção.

Nenhum desses dados pode entrar em logs, audit ou outbox.

## 9. Proteção dos dados

Quando autorizado:

- dados sensíveis cifrados em repouso;
- fingerprints/HMAC separados;
- chaves versionadas;
- nenhuma PII em JSON genérico;
- nenhuma PII em URL;
- nenhuma PII em provider request ID;
- nenhuma PII em correlation ID;
- acesso restrito a operações específicas;
- RLS default-deny;
- sem grants diretos para `anon` ou `authenticated`;
- acesso público somente por funções/Edge Functions controladas.

Não reutilizar `persons`.

## 10. Fluxo de estado

### Slot

Fluxo planejado:

`OPEN -> RESERVED -> CLAIMED`

Interpretação proposta:

- `OPEN`: sem convite ativo;
- `RESERVED`: convite ativo emitido;
- `CLAIMED`: cadastro público confirmado.

A implementação deve validar compatibilidade com as máquinas de estado da Fase 1C e não criar taxonomia paralela.
Na transição para `RESERVED`, o schema atual também exige preencher
`claimed_at`; este plano não renomeia nem altera o campo.

### Registro do participante

Estados planejados conforme schema existente:

- `NOT_STARTED`;
- `INVITED`;
- `IN_PROGRESS`;
- `SUBMITTED`;
- `EXPIRED`;
- `CANCELLED`.

`COMPLETED` não é um estado válido de `registration_status` no schema atual.

### Convite

- emissão: `PENDING`;
- provider fake confirma envio: `SENT`;
- primeira abertura válida: `OPENED`;
- cadastro confirmado: `COMPLETED`;
- revogação: `REVOKED`;
- expiração: `EXPIRED`.

Transições devem ser transacionais e auditadas sem PII.

## 11. Operações autenticadas do morador

Planejar operações equivalentes a:

- `verified_access_issue_resident_invitation`;
- `verified_access_resend_resident_invitation`;
- `verified_access_revoke_resident_invitation`;
- `verified_access_list_resident_invitation_status`.

Regras:

- `auth.uid()` derivado;
- tenant derivado;
- request própria;
- slot da mesma request;
- feature habilitada;
- policy `ACTIVE` para emitir/reemitir;
- request em estado compatível;
- slot `OPEN` para primeira emissão;
- limites de reenvio;
- idempotência;
- audit/outbox sanitizados.

## 12. Operações públicas

Planejar endpoints equivalentes a:

- `verified-access-public-invitation-get`;
- `verified-access-public-registration-start`;
- `verified-access-public-registration-submit`;
- `verified-access-public-registration-status`.

Regras:

- sem JWT;
- autorização exclusivamente pelo token;
- token nunca retornado;
- resposta mínima;
- rate limiting por IP/token fingerprint;
- generic errors;
- evitar enumeração;
- body size limitado;
- allowlist estrita;
- CORS restrito ao domínio público oficial;
- CSP;
- `Referrer-Policy: no-referrer`;
- `Cache-Control: no-store`;
- proteção contra automação abusiva;
- correlation ID sanitizado.

## 13. Página pública web

A Fase 3 deve planejar a primeira interface web funcional do Acesso Verificado.

Local recomendado após inspeção do repositório:

- rota pública no `admin-web`, ou
- aplicação web pública separada.

A decisão deve considerar:

- isolamento do backoffice;
- domínio próprio;
- CSP e headers;
- bundle mínimo;
- acessibilidade;
- responsividade;
- nenhum segredo no cliente;
- nenhuma service role no navegador;
- integração somente com Edge Functions públicas autorizadas.

Fluxo de telas:

1. convite inválido/expirado;
2. contexto mínimo da visita;
3. aviso de privacidade;
4. formulário;
5. revisão;
6. confirmação;
7. status resumido.

A interface deve funcionar em celular sem exigir instalação do app.

## 14. Mensageria fake

Usar os contratos da Fase 1D:

`MessagingProvider`

Cenários:

- envio com sucesso;
- timeout;
- indisponível;
- rate limited;
- erro não retryable.

O provider fake:

- não envia mensagem real;
- retorna preview/link somente em ambiente local/teste autorizado;
- não registra telefone ou conteúdo em logs;
- não executa retry interno;
- mantém idempotência;
- permite testes determinísticos.

Blocker de arquitetura: como o contrato real de messaging exige
`ProviderContext.participantId`, o gate executável deve decidir se o
participante é criado na emissão do convite com `registration_status =
'INVITED'`, ou se o contrato do provider será versionado. Este documento não
resolve essa escolha por inferência.

## 15. Idempotência

Planejar comandos persistentes para:

- emissão;
- reenvio;
- revogação;
- início do cadastro;
- confirmação do cadastro.

Regras:

- mesma key + mesmo fingerprint = mesmo resultado;
- mesma key + fingerprint diferente = `CONFLICT`;
- operação em processamento = `COMMAND_IN_PROGRESS`;
- nenhuma duplicação de convite, participant, audit ou outbox;
- token não participa em texto aberto do fingerprint;
- dados sensíveis não entram em fingerprint reversível.

## 16. Transações

### Emissão

Mesma transação:

- comando idempotente;
- convite;
- atualização do slot para `RESERVED`;
- audit;
- outbox.

O envio fake ocorre após commit, por consumer/processador futuro ou chamada controlada, sem comprometer atomicidade do domínio.

### Cadastro público confirmado

Mesma transação:

- validação do convite;
- criação/atualização de identity profile protegido;
- criação do participant;
- associação ao slot;
- slot para `CLAIMED`;
- registration status para `SUBMITTED`;
- convite para `COMPLETED`;
- audit;
- outbox;
- comando idempotente.

Não iniciar identity/background provider nesta fase.

## 17. Auditoria e outbox

Eventos mínimos planejados:

- `VERIFIED_ACCESS_INVITATION_ISSUED`;
- `VERIFIED_ACCESS_INVITATION_RESENT`;
- `VERIFIED_ACCESS_INVITATION_OPENED`;
- `VERIFIED_ACCESS_INVITATION_REVOKED`;
- `VERIFIED_ACCESS_INVITATION_EXPIRED`;
- `VERIFIED_ACCESS_REGISTRATION_STARTED`;
- `VERIFIED_ACCESS_REGISTRATION_COMPLETED`.

Audit/outbox podem conter somente:

- IDs;
- códigos;
- status;
- timestamps;
- correlation ID;
- provider code fake;
- request/slot/invitation IDs.

Proibido:

- token;
- nome;
- CPF;
- telefone;
- nascimento;
- documento;
- texto livre;
- payload bruto;
- IP bruto, salvo decisão específica de segurança e retenção.

## 18. Jobs planejados

Planejar:

- expiração de convites;
- recuperação de envios pendentes;
- limpeza por retenção;
- reconciliação de status fake.

Jobs devem:

- ser idempotentes;
- usar locks;
- não habilitar feature;
- não executar integração real;
- produzir audit/outbox sanitizados.

## 19. Privacidade e jurídico

Blockers humanos obrigatórios:

- base legal para coleta de CPF e nascimento;
- texto de aviso de privacidade;
- política para menores;
- retenção;
- exercício de direitos;
- compartilhamento futuro com providers;
- critérios de bloqueio;
- comunicação ao morador;
- acesso da portaria a dados pessoais.

Sem aprovação, o plano deve permitir modo reduzido com dados mínimos e providers fake.

## 20. Segurança

Cobrir testes e controles para:

- token replay;
- brute force;
- token expirado;
- token revogado;
- token de outro slot;
- concorrência;
- cadastro duplicado;
- request cancelada;
- slot já claimed;
- body desconhecido;
- mass assignment;
- XSS;
- CSRF quando aplicável;
- CORS;
- CSP;
- cache;
- referer;
- rate limiting;
- tenant isolation;
- IDOR;
- logs sem PII;
- audit/outbox sem PII;
- RLS default-deny;
- grants mínimos.

## 21. Testes planejados

### Banco

- tabelas, constraints, FKs, RLS e grants;
- hash de token;
- um convite ativo por slot;
- transições;
- idempotência;
- concorrência;
- expiração;
- revogação;
- criação de participant;
- tenant isolation;
- audit/outbox sanitizados;
- rollback e reaplicação.

### Edge Functions

- token ausente;
- token inválido;
- expirado;
- revogado;
- rate limiting;
- unknown fields;
- payload excessivo;
- headers de segurança;
- nenhuma PII em logs;
- mapeamento de erros.

### Web

- responsividade;
- acessibilidade;
- validação;
- erro genérico;
- CSP;
- no-store;
- no-referrer;
- ausência de secrets;
- nenhum acesso direto ao banco;
- fluxo completo fake.

## 22. Estratégia de entrega

Sugestão de divisão:

### Fase 3A — convite local e token

- schema;
- RPCs;
- Edge Functions autenticadas;
- provider fake;
- testes.

### Fase 3B — cadastro público

- endpoints públicos;
- página web;
- persistência protegida;
- participant/slot;
- testes de segurança.

### Fase 3C — hardening

- jobs;
- rate limiting;
- retenção;
- observabilidade;
- revisão de privacidade;
- rollout fake.

A divisão deve ser confirmada antes de contrato executável.

As subseções 3A, 3B e 3C são uma proposta de planejamento, não uma autorização
nem uma decisão já aprovada.

## 23. Allowlist futura

O gate documental seguinte deve definir paths exatos para:

- migrations;
- rollback;
- RPCs;
- Edge Functions autenticadas;
- Edge Functions públicas;
- shared modules;
- página web pública;
- testes SQL;
- testes Deno;
- testes web;
- workflow CI;
- config;
- documentação.

Nenhum path técnico está autorizado por este documento.

## 24. Gates

Antes da implementação:

- decidir divisão 3A/3B/3C;
- aprovar PII mínima;
- aprovar base legal e privacy notice;
- confirmar modelo do token;
- confirmar estados;
- confirmar página web e domínio;
- confirmar provider fake;
- confirmar idempotência;
- confirmar rate limiting;
- confirmar migrations;
- confirmar rollback;
- fechar allowlist;
- criar `CURRENT_TASK` executável.

### 24.1 Blockers humanos obrigatórios

Permanecem abertos e não podem ser resolvidos por inferência:

- PII mínima a coletar;
- obrigatoriedade de CPF e em qual etapa;
- obrigatoriedade da data de nascimento e em qual etapa;
- necessidade e obrigatoriedade de telefone;
- tratamento de menores de idade;
- base legal aplicável;
- texto e versionamento do privacy notice;
- prazos e eventos de retenção e descarte;
- domínio e isolamento da página pública;
- estratégia e limites de rate limiting;
- modelo final do token, troca por sessão, uso único, rotação e recuperação;
- divisão final e ordem de autorização de 3A, 3B e 3C;
- momento de criação do participante diante do contrato real de messaging.

## 25. Confirmações

- Fase 2 está mergeada.
- Fase 3 está apenas planejada.
- `CURRENT_TASK` deve permanecer `NO ACTIVE IMPLEMENTATION`.
- Nenhuma migration remota.
- Nenhuma feature habilitada.
- Nenhuma integração real.
- Somente o escopo técnico fechado da Fase 3A na seção 26 está autorizado.

## 26. Contrato executável da Fase 3A

### 26.1 Escopo fechado

A Fase 3A implementa somente convite local, token opaco, quatro operações
autenticadas do morador e preview por `MessagingProvider` fake. Não cria
participant, identity profile, PII, sessão pública, endpoint público, página,
job externo ou integração real. As Fases 3B e 3C permanecem não autorizadas.

O slot permanece `OPEN` durante toda a Fase 3A. A tabela de convites controla a
reserva lógica por índice único parcial. A primeira emissão pode mover a request
de `DRAFT` para `INVITATIONS_PENDING`, transição já permitida pela Fase 1C. A
Fase 3A não usa `RESERVED`, `CLAIMED` ou `claimed_at`.

### 26.2 Token e expiração

- A Edge Function gera 32 bytes com CSPRNG e serializa em base64url sem padding.
- O token bruto existe apenas em memória no primeiro dispatch autorizado.
- O banco recebe e persiste somente `v1:` seguido do SHA-256 hexadecimal.
- `token_version` começa em 1 e cresce a cada reenvio/rotação.
- A expiração é o menor valor entre o fim da request e 24 horas após emissão.
- Reenvio aceita somente convite ativo, rotaciona hash e invalida o token
  anterior na mesma transação.
- Retry idempotente não recebe nem expõe novo token e não repete o fake.
- Revogação muda imediatamente o estado para `REVOKED`.
- Convites vencidos são materializados como `EXPIRED` por helper interno
  default-deny durante operações de domínio; não há job nesta fase.

### 26.3 Mensageria fake e atomicidade

O contexto de messaging passa a aceitar, de forma compatível, um alvo por
`participantId` ou por `participantSlotId` + `invitationId`. Identity e
background continuam usando participant. Nenhum ID fictício é criado.

Banco, command, invitation, audit e outbox são confirmados antes da chamada ao
fake. A resposta inicial da RPC informa `dispatchRequired = true` apenas para a
execução que criou ou rotacionou o token; replay retorna `false`. O fake não
participa da transação e não faz retry interno. Falha após commit mantém o
convite `PENDING`; nova tentativa exige `RESEND`, nova idempotency key e rotação.
Não existe worker, rede ou envio real.

### 26.4 Objetos autorizados

Migrations exatas:

```text
supabase/migrations/20260721100000_verified_access_invitations.sql
supabase/migrations/20260721101000_verified_access_invitation_rpcs.sql
```

Tabelas:

```text
verified_access_invitations
verified_access_invitation_commands
```

RPCs autenticadas:

```text
verified_access_issue_resident_invitation
verified_access_resend_resident_invitation
verified_access_revoke_resident_invitation
verified_access_list_resident_invitation_status
```

Edge Functions autenticadas:

```text
verified-access-invitation-issue
verified-access-invitation-resend
verified-access-invitation-revoke
verified-access-invitation-status-list
```

Rollback dedicado:

```text
supabase/rollback/verified_access_phase_3a_rollback.sql
```

### 26.5 Allowlist exata

```text
supabase/migrations/20260721100000_verified_access_invitations.sql
supabase/migrations/20260721101000_verified_access_invitation_rpcs.sql
supabase/rollback/verified_access_phase_3a_rollback.sql
supabase/functions/verified-access-invitation-issue/index.ts
supabase/functions/verified-access-invitation-issue/index.test.ts
supabase/functions/verified-access-invitation-resend/index.ts
supabase/functions/verified-access-invitation-resend/index.test.ts
supabase/functions/verified-access-invitation-revoke/index.ts
supabase/functions/verified-access-invitation-revoke/index.test.ts
supabase/functions/verified-access-invitation-status-list/index.ts
supabase/functions/verified-access-invitation-status-list/index.test.ts
supabase/functions/_shared/verified-access/invitations/auth.ts
supabase/functions/_shared/verified-access/invitations/contracts.ts
supabase/functions/_shared/verified-access/invitations/http.ts
supabase/functions/_shared/verified-access/invitations/token.ts
supabase/functions/_shared/verified-access/invitations/messaging.ts
supabase/functions/_shared/verified-access/providers/contracts.ts
supabase/functions/_shared/verified-access/providers/fake/fake-messaging-provider.ts
supabase/functions/_shared/verified-access/providers/tests/fake-messaging-provider.test.ts
supabase/tests/verified_access_phase_3a.sql
supabase/tests/verified_access_phase_3a_integration.psql
supabase/tests/verified_access_phase_3a_runtime_roles.psql
.github/workflows/verified-access-phase-3a.yml
.github/workflows/verified-access-phase-1a.yml
supabase/config.toml
docs/product/verified-access/phases/PHASE_3.md
docs/product/verified-access/execution/CURRENT_TASK.md
docs/verified-access-phase-3a-validation.md
```

Nenhum path adicional está autorizado. A implementação deve parar antes de
editar qualquer arquivo fora desta lista.

### 26.6 Gates

- migrations do zero, pgTAP e integração das Fases 1A a 3A;
- runtime roles, grants e RLS default-deny;
- testes Deno do fake, shared modules e quatro endpoints;
- lint, type-check e admin-web build;
- rollback 3A, preservação 1A a 2, reaplicação e smoke pós-reaplicação;
- workflow 1A com rollback cumulativo `3A -> 2 -> 1C -> 1B -> 1A`;
- nenhuma PII, participant, página pública, rede, migration remota ou feature
  habilitada.
