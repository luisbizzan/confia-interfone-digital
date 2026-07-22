# Fase 3B — contrato proposto de cadastro público

## 1. Status e autoridade

Stage: `Planejada / em revisão humana / não autorizada`.

Este documento fecha uma proposta técnica executável para revisão. Ele não
autoriza migration, RPC, Edge Function, aplicação web, tratamento de PII,
feature ou deploy. A execução futura depende de um novo contrato versionado em
`execution/CURRENT_TASK.md` e da resolução dos blockers da seção 20.

As decisões desta fase sobre base legal, textos jurídicos, retenção definitiva,
menores, domínio e chaves são propostas. Somente aprovação humana competente
pode torná-las vinculantes.

## 2. Objetivo

Planejar o cadastro público responsivo de um visitante ou prestador já
convidado na Fase 3A. O fluxo troca o token original por uma sessão pública
curta, apresenta contexto mínimo, registra ciência do aviso de privacidade e
aceite dos termos, recebe dados estruturados protegidos e conclui, numa única
transação, perfil local, participante, slot, convite, auditoria e outbox.

Não há verificação de identidade, background, elegibilidade, credencial ou
operação da Rede Confia nesta fase.

## 3. Inventário real reutilizado

- `verified_access_invitations`: hash `v1:sha256`, expiração, rotação e estados
  `PENDING`, `SENT`, `OPENED`, `COMPLETED`, `REVOKED` e `EXPIRED`;
- `verified_access_participant_slots`: vínculo composto com request e tenant,
  estados existentes e regra de capacidade;
- `verified_access_identity_profiles`: ciphertext local, HMAC por tenant,
  versões de chave e nenhuma descriptografia SQL;
- `verified_access_participants`: vínculo único com slot e máquinas de estado
  da Fase 1C;
- requests e policies versionadas, com tenant derivado e feature desligada;
- audit e outbox append-only, sanitizados e escritos na transação de domínio;
- executor roles de assinatura exata, RLS default-deny e revogação prévia;
- módulos Edge compartilhados de HTTP estrito, correlação e token opaco;
- `MessagingProvider` fake da Fase 1D e o fluxo pós-commit da Fase 3A;
- monorepo npm com workspace `apps/*` e `admin-web` em Next.js 16.2.6.

Não reutilizar `persons`. Não criar uma taxonomia paralela de participante,
slot, request ou convite.

## 4. Decisões propostas para revisão humana

1. Nome completo é obrigatório.
2. CPF é obrigatório para brasileiros maiores de idade.
3. Estrangeiros informam RNM ou passaporte com país emissor.
4. Data de nascimento é obrigatória.
5. Telefone é opcional e não identifica civilmente a pessoa.
6. Menor exige nome e vínculo do responsável, sem validação automática.
7. Não há imagem ou upload de documento.
8. Não há biometria.
9. Não há background check.
10. Não há provider real.
11. Cadastro incompleto pode existir por no máximo sete dias após expiração ou
    cancelamento; a proposta técnica não persiste PII de rascunho.
12. Retenção do cadastro submetido permanece blocker jurídico.
13. A página pública é isolada do backoffice.
14. A localização preferida é `apps/verified-access-public`, aplicação
    separada no monorepo.
15. O token de convite é trocado por sessão curta na primeira abertura válida.
16. O token original não autoriza operações posteriores ao exchange.
17. A sessão é opaca, expira, pode ser revogada e se vincula a invitation e
    slot.
18. Há uma única submissão final por convite.
19. Correção posterior fica fora da Fase 3B.
20. Registra-se ciência do aviso de privacidade e aceite dos termos, sem
    presumir consentimento como base legal.
21. O morador vê apenas status, nunca PII do participante.
22. `IdentityProvider` não é chamado.
23. `MessagingProvider` permanece fake.
24. `VERIFIED_ACCESS` permanece desligada.
25. Nenhuma migration remota é executada.

## 5. Escopo

- exchange do token original por sessão pública;
- contexto mínimo da visita e status mínimo da própria operação;
- início idempotente do cadastro sem PII persistida;
- submissão final estruturada e protegida;
- criação do identity profile local e do participant;
- associação ao slot e conclusão transacional;
- audit/outbox sem PII;
- cinco endpoints Edge públicos controlados;
- proposta de aplicação web pública isolada;
- testes futuros de banco, Edge, web, segurança, rollback e reaplicação.

## 6. Fora de escopo

OCR, upload, imagem de documento, selfie, face match, liveness, biometria,
background, elegibilidade, credencial, QR Code, check-in/out, portaria, app
mobile/Expo, Rede Confia operacional, correção posterior, provider real,
WhatsApp/SMS/e-mail real, integração externa, job de produção, migration
remota, feature habilitada e alteração de `persons`.

## 7. Fluxo público

1. O link entrega o token no fragmento da URL, como já faz o preview fake. A
   aplicação remove o fragmento imediatamente com `history.replaceState`.
2. O navegador gera com Web Crypto um session token candidato de 32 bytes,
   mantém o valor apenas em memória e o envia com o convite ao
   `verified-access-public-invitation-exchange`. O Edge envia ao banco somente
   os hashes versionados e cria a sessão curta.
3. O convite passa de `PENDING` ou `SENT` para `OPENED`; o slot permanece
   `OPEN`. A resposta contém apenas contexto mínimo e o canal de sessão.
4. `registration-get` recupera o contexto mínimo. `registration-start` muda a
   sessão de `ACTIVE` para `STARTED`, sem gravar PII.
5. O formulário fica apenas em memória no navegador. Refresh perde o rascunho;
   retomada persistente de PII exige decisão futura explícita.
6. `registration-submit` valida, cifra e fingerprinta no Edge antes da RPC e
   conclui o domínio em uma única transação.
7. `registration-status` retorna somente código de status e timestamps da
   sessão atual, nunca PII nem IDs internos desnecessários.

Erros de token inválido, inexistente, expirado, revogado ou já consumido usam a
mesma resposta pública. IDs de condomínio, request, slot e invitation são
sempre derivados no servidor.

## 8. Estados e compatibilidade

### 8.1 Sessão pública

Estados propostos:

```text
ACTIVE -> STARTED -> COMPLETED
ACTIVE -> REVOKED | EXPIRED
STARTED -> REVOKED | EXPIRED
```

`COMPLETED`, `REVOKED` e `EXPIRED` são finais. Repetição idempotente de submit
retorna o resultado já concluído sem nova escrita. Retry do exchange na mesma
página reutiliza o session token candidato em memória; depois do primeiro
exchange confirmado, o invitation token não inicia outra sessão.

### 8.2 Invitation

```text
PENDING | SENT -> OPENED -> COMPLETED
PENDING | SENT | OPENED -> REVOKED | EXPIRED
```

O exchange materializa `OPENED`; submit materializa `COMPLETED`. Revogação ou
expiração do convite revoga/expira a sessão na mesma transação. A operação de
revogação da Fase 3A deverá aceitar `OPENED` sem ampliar acesso.

### 8.3 Slot e participant

A Fase 3A mantém o slot `OPEN`. A Fase 3B também o mantém `OPEN` durante
exchange e start. No submit, usa a transição já permitida:

```text
OPEN -> CLAIMED
```

`claimed_at` recebe o timestamp da submissão. Não usar `RESERVED`, pois o
schema atual exige `claimed_at` também nesse estado e a reserva lógica já é
garantida pelo convite/sessão.

O participant nasce no submit com:

```text
registration_status = SUBMITTED
identity_status     = SELF_DECLARED
background_status   = NOT_REQUIRED
network_status      = NOT_ENABLED
eligibility_status  = PENDING
```

Não existe decisão de elegibilidade nesta fase.

## 9. Modelo de sessão pública

Tabela proposta: `verified_access_public_sessions`.

| Campo | Regra |
|---|---|
| `id uuid` | PK técnica |
| `condominium_id uuid` | derivado do convite; FK composta |
| `invitation_id uuid` | FK composta com tenant, request e slot |
| `participant_slot_id uuid` | igual ao slot do convite |
| `session_token_hash text` | somente `v1:<sha256-hex>` |
| `token_version integer` | positivo; começa em 1 |
| `status text` | allowlist da seção 8.1 |
| `expires_at timestamptz` | máximo proposto de 30 minutos e nunca além do convite |
| `last_seen_at timestamptz` | atualizado de forma limitada |
| `revoked_at timestamptz` | obrigatório somente em `REVOKED` |
| `completed_at timestamptz` | obrigatório somente em `COMPLETED` |
| `created_at`, `updated_at` | operacionais |

Índice único parcial permite uma sessão `ACTIVE` ou `STARTED` por invitation.
O token bruto tem 32 bytes CSPRNG, existe apenas na memória do navegador e no
Edge durante o exchange e nunca é persistido. Retry com a mesma idempotency key
e o mesmo hash retorna a mesma sessão; outro session hash entra em conflito.
Tabela
sem PII, com RLS, sem policies e sem grants diretos a `PUBLIC`, `anon`,
`authenticated` ou `service_role`.

## 10. Identidade local protegida

Reutilizar `verified_access_identity_profiles`. Os campos existentes atendem
nome, nascimento, CPF, RNM/passaporte, país emissor, telefone, ciphertext,
HMAC e versões de chave. A migration proposta acrescenta apenas:

- `is_minor boolean`;
- `guardian_name_ciphertext bytea`;
- `guardian_relationship_ciphertext bytea`;
- `privacy_notice_version text`;
- `terms_version text`;
- `acknowledged_at timestamptz`;
- `submitted_at timestamptz`.

Regras de uso:

- `full_name_ciphertext`, `birth_date_ciphertext`, documento, telefone e dados
  do responsável são reversíveis e cifrados fora do SQL;
- CPF usa `cpf_ciphertext` e `cpf_tenant_hmac`;
- RNM/passaporte usam `document_number_ciphertext` e
  `document_number_tenant_hmac`; passaporte exige país emissor cifrado;
- HMAC por tenant serve apenas para unicidade/lookup local de documento;
- telefone usa o índice não único já existente e permanece opcional;
- versões de aviso/termos e timestamps são metadados não sensíveis em colunas
  estruturadas; nenhuma PII entra em JSON;
- menor exige ambos os ciphertexts do responsável; adulto proíbe ambos;
- um check de bundle permite todos esses campos nulos em perfis legados 1A,
  mas exige o conjunto completo em perfil submetido pela Fase 3B;
- `identity_assurance_level` permanece `SELF_DECLARED`;
- encryption/HMAC keys ficam fora do banco e do repositório;
- não há função SQL de cifragem, HMAC ou descriptografia;
- nenhum dado é retornado ao morador ou exposto diretamente por RLS.

O tipo local continua `CPF`, `RNM` ou `PASSPORT`; para passaporte, o emissor é
obrigatório. O identificador de rede futuro `PASSPORT_WITH_ISSUER` não é criado
nem consultado nesta fase.

## 11. Comandos idempotentes

Tabela proposta: `verified_access_public_registration_commands`, sem plaintext
ou ciphertext e default-deny, para `EXCHANGE`, `START` e `SUBMIT`.

Chave única por escopo operacional, command type e idempotency key. Mesma chave
e mesmo fingerprint retorna o mesmo resultado; fingerprint diferente retorna
`IDEMPOTENCY_CONFLICT`; comando pendente retorna `COMMAND_IN_PROGRESS`.

O input fingerprint de submit é `v1:hmac-sha256` de uma representação canônica
dos campos normalizados, com chave dedicada fora do banco. Ele detecta mudança
de input sem armazenar dado reversível e não é reutilizado como HMAC de
identidade. Fingerprints nunca contêm plaintext, ciphertext, token bruto ou
payload completo e não aparecem em logs, audit ou outbox. Retries não duplicam
sessão, perfil, participant, claim, audit ou outbox.

## 12. Operações internas propostas

RPCs de assinatura exata, `security definer`, `search_path = public, pg_temp`,
owner controlado e sem acesso direto a tabelas pelos callers:

- `verified_access_public_exchange_invitation`;
- `verified_access_public_get_registration`;
- `verified_access_public_start_registration`;
- `verified_access_public_submit_registration`;
- `verified_access_public_get_registration_status`.

Todas derivam tenant/request/slot/invitation da credencial opaca, bloqueiam e
revalidam estados, feature e expiração, executam rate limit transacional e
retornam DTO allowlisted. Um role NOLOGIN
`verified_access_phase3b_public_executor` recebe `EXECUTE` somente nessas cinco
assinaturas e é herdado apenas por `service_role`, seguindo o padrão de
executor restrito já existente. A service role fica somente no secret store da
Edge Function e não recebe grants de tabela. `PUBLIC`, `anon` e `authenticated`
não recebem nenhum grant novo; portanto, o browser não pode contornar Edge,
allowlists ou rate limit por PostgREST direto.

Helpers internos de token, contexto, criptographic-envelope validation,
rate-limit, audit e outbox não recebem `EXECUTE` de runtime roles.

## 13. Edge Functions públicas

Nomes alinhados às convenções atuais:

- `verified-access-public-invitation-exchange` — `POST`, único endpoint que
  aceita token de convite;
- `verified-access-public-registration-get` — `GET`, contexto mínimo;
- `verified-access-public-registration-start` — `POST`, início idempotente;
- `verified-access-public-registration-submit` — `POST`, submissão final;
- `verified-access-public-registration-status` — `GET`, status mínimo.

Sem JWT de usuário. O gateway usa `verify_jwt = false`; o token de convite é
aceito apenas no body do exchange e apagado do cliente. As operações seguintes
usam sessão opaca em cookie `__Host-va_session`, `HttpOnly`, `Secure`,
`SameSite=Strict`, `Path=/`, sob domínio same-origin aprovado. Se esse domínio
não puder encaminhar Edge sob a mesma origem, a arquitetura para cookie/CORS é
blocker e não deve cair para armazenamento persistente no navegador.

Controles obrigatórios:

- JSON estrito, rejeição de unknown fields e body máximo de 16 KiB;
- correlation ID sintético ou sanitizado, 8–128 caracteres;
- respostas genéricas anti-enumeração;
- comparação constante quando aplicável;
- `Cache-Control: no-store`, `Pragma: no-cache` e
  `Referrer-Policy: no-referrer`;
- CORS allowlist exata do domínio público, sem wildcard e com credentials;
- CSP da seção 14 em todas as respostas web;
- nenhum log de body, token, hash, cookie, documento, nome, nascimento,
  telefone, responsável ou IP bruto;
- service role apenas no ambiente server-side da Edge Function e nenhum secret
  no navegador, resposta ou bundle.

## 14. Aplicação web proposta

Local: `apps/verified-access-public`, novo workspace Next.js isolado. Não usar
rota do `admin-web`, que permanece backoffice autenticado.

Rotas propostas:

```text
/invite#invitation=<token>  bootstrap e remoção imediata do fragmento
/register                   contexto, aviso, identificação e revisão
/status                     confirmação/status mínimo
```

O domínio público oficial e o proxy same-origin `/api/verified-access/*` são
blockers humanos. Variáveis públicas permitidas: somente origem pública do
site, base pública das Edge Functions e identificadores de versão não
sensíveis. Chaves privadas, service role, chaves de cifragem/HMAC e tokens não
podem usar prefixo público nem entrar no bundle.

Headers mínimos:

```text
Cache-Control: no-store
Referrer-Policy: no-referrer
X-Content-Type-Options: nosniff
Permissions-Policy: camera=(), microphone=(), geolocation=()
Content-Security-Policy: default-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; object-src 'none'; img-src 'self' data:; script-src 'self'; style-src 'self'; connect-src 'self' <edge-origin-approved>
```

Sem analytics, third-party scripts, pixels ou fontes remotas. Telas: convite
indisponível; contexto mínimo; aviso de privacidade; identificação; responsável
por menor; revisão; confirmação; status submetido. Fluxo mobile-first,
acessível por teclado, labels/erros associados, foco gerenciado, contraste AA,
loading estável e mensagens sem enumeração.

## 15. Transação de submissão

Sob locks de session, invitation, request e slot, uma única RPC:

1. valida sessão, convite, request, policy, feature e slot;
2. confirma idempotência e unicidade da submissão;
3. valida envelope cifrado, HMACs e versões de chave;
4. insere `verified_access_identity_profiles` protegido;
5. insere participant ligado ao request, slot e profile;
6. atualiza slot `OPEN -> CLAIMED` e `claimed_at`;
7. grava participant como `SUBMITTED`/`SELF_DECLARED`;
8. atualiza invitation `OPENED -> COMPLETED` e `consumed_at`;
9. atualiza session `STARTED|ACTIVE -> COMPLETED`;
10. escreve audit e outbox sanitizados;
11. conclui o command e retorna somente status mínimo.

Qualquer falha reverte tudo. Nenhuma chamada a IdentityProvider,
MessagingProvider ou serviço externo participa da transação.

## 16. Audit e outbox

Eventos propostos:

- `VERIFIED_ACCESS_PUBLIC_SESSION_CREATED`;
- `VERIFIED_ACCESS_REGISTRATION_STARTED`;
- `VERIFIED_ACCESS_REGISTRATION_SUBMITTED`;
- `VERIFIED_ACCESS_PARTICIPANT_CREATED`;
- `VERIFIED_ACCESS_INVITATION_COMPLETED`.

Payload allowlisted: IDs técnicos, status, códigos, versões, timestamps e
correlation ID. Proibidos: nome, CPF, RNM, passaporte, emissor, nascimento,
telefone, responsável, token/session token, hashes de token, ciphertext, HMAC
de identidade, payload bruto, texto livre ou IP bruto. Escrita na mesma
transação, append-only e com deduplication key derivada do command/event.

## 17. Rate limiting proposto

Persistência proposta: `verified_access_public_rate_limits`, tabela efêmera
default-deny com `scope`, `subject_fingerprint`, `window_started_at`,
`attempt_count` e `expires_at`. Não armazena IP, token, PII ou payload. O
fingerprint usa chave exclusiva de rate limit, rotação versionada e retenção
somente até o fechamento da janela acrescida de margem operacional aprovada.
Somente as RPCs públicas atualizam os contadores sob lock.

| Escopo | Limite/janela | Resposta |
|---|---:|---|
| exchange por fingerprint de IP com chave dedicada | 10 / 10 min | `429`, `Retry-After` |
| exchange por invitation fingerprint | 5 / 15 min | resposta genérica + `429` |
| leitura por sessão | 60 / 5 min | `429` |
| start por sessão | 5 / 10 min | replay idempotente não consome nova escrita |
| submit por sessão | 5 / 30 min | `429`; sessão não é invalidada |
| documento duplicado por tenant/HMAC | 5 / 24 h | conflito genérico, sem revelar existência |

O IP bruto não é persistido. A proposta exige fingerprint efêmero com chave e
retenção próprias. Limites, armazenamento distribuído, trusted proxy e
tratamento de IPv6 permanecem sujeitos à aprovação de segurança antes da
implementação.

## 18. Segurança, privacidade e retenção

- token original somente no fragmento e no exchange; nunca em query/log;
- sessão curta, revogável, hash-only e vinculada ao convite/slot;
- proteção contra replay, brute force, CSRF, XSS, CORS, IDOR e mass assignment;
- tenant sempre derivado e FKs compostas em todos os vínculos;
- tabelas novas com RLS, sem policies e grants default-deny;
- zero PII em logs, errors, audit, outbox, URL, command result ou fingerprints;
- rascunho de PII não é persistido na proposta;
- registros operacionais incompletos são eliminados em até sete dias após
  expiração/cancelamento, sujeito ao mecanismo futuro da Fase 3C;
- retenção do cadastro submetido, exclusão/anonimização e correção permanecem
  bloqueadas por decisão jurídica;
- ciência/aceite e suas versões são evidência operacional, não declaração da
  base legal.

## 19. Plano futuro de testes e rollback

Banco/pgTAP e integração:

- objetos, checks, FKs compostas, RLS e ACLs de assinaturas exatas;
- uma sessão ativa por invitation, expiração, revogação e rotação;
- token de convite aceito apenas no exchange e session hash-only;
- transições de invitation/session/slot/participant;
- submissão atômica, concorrente e única;
- CPF/RNM/passaporte, emissor, telefone opcional e menor/responsável;
- nenhuma PII em JSON, audit, outbox, commands e erros;
- idempotência, tenant isolation, IDOR e limites;
- preservação completa das Fases 1A–3A e de `persons`.

Edge/Deno e web:

- métodos, allowlists, unknown fields, 16 KiB, headers, CORS e cookies;
- inválido/expirado/revogado/consumido indistinguíveis externamente;
- rate limits e `Retry-After`;
- sanitização de logs e ausência de secrets no bundle;
- acessibilidade, responsividade, loading/error, CSP/no-store/no-referrer;
- fluxo fake end-to-end sem IdentityProvider ou rede externa.

CI futuro: db reset, pgTAP/integrations 1A–3B, runtime roles, db lint, Deno
fmt/lint/check/test, web lint/typecheck/build/test, log/PII guard, rollback 3B,
preservação 1A–3A, reaplicação e testes pós-reaplicação.

Rollback futuro, em ordem: remover config/endpoints do teste; revogar/drop do
executor; dropar RPCs e helpers; dropar triggers 3B; dropar commands e sessions;
remover índices/checks/colunas adicionados ao identity profile; preservar todos
os objetos 1A–3A. Reaplicar as três migrations e repetir a suíte completa.

## 20. Blockers humanos obrigatórios

- base legal definitiva;
- texto aprovado do privacy notice;
- texto aprovado dos termos;
- retenção do cadastro submetido;
- regras definitivas para menores;
- domínio público e proxy same-origin;
- gestão, rotação e custódia de chaves;
- estratégia real/distribuída de rate limiting;
- política de exclusão e anonimização;
- acesso futuro da portaria;
- processo de correção de cadastro;
- DPO/jurídico responsável pela aprovação.

Qualquer divergência nesses itens para a execução e exige revisão documental.

## 21. Migrations e allowlist futura proposta

Migrations sugeridas, ainda não autorizadas:

```text
supabase/migrations/20260723100000_verified_access_public_registration.sql
supabase/migrations/20260723101000_verified_access_public_registration_rpcs.sql
supabase/migrations/20260723102000_verified_access_public_registration_security.sql
supabase/rollback/verified_access_phase_3b_rollback.sql
```

Responsabilidades: sessions, commands, rate limits e extensões estruturadas do
identity profile; helpers e cinco RPCs transacionais; revokes, executor role e
grants exatos. Allowlist técnica futura proposta:

```text
supabase/functions/verified-access-public-invitation-exchange/index.ts
supabase/functions/verified-access-public-invitation-exchange/index.test.ts
supabase/functions/verified-access-public-registration-get/index.ts
supabase/functions/verified-access-public-registration-get/index.test.ts
supabase/functions/verified-access-public-registration-start/index.ts
supabase/functions/verified-access-public-registration-start/index.test.ts
supabase/functions/verified-access-public-registration-submit/index.ts
supabase/functions/verified-access-public-registration-submit/index.test.ts
supabase/functions/verified-access-public-registration-status/index.ts
supabase/functions/verified-access-public-registration-status/index.test.ts
supabase/functions/_shared/verified-access/public-registration/auth.ts
supabase/functions/_shared/verified-access/public-registration/contracts.ts
supabase/functions/_shared/verified-access/public-registration/crypto.ts
supabase/functions/_shared/verified-access/public-registration/http.ts
supabase/functions/_shared/verified-access/public-registration/session.ts
supabase/tests/verified_access_phase_3b.sql
supabase/tests/verified_access_phase_3b_integration.psql
supabase/tests/verified_access_phase_3b_runtime_roles.psql
.github/workflows/verified-access-phase-3b.yml
supabase/config.toml
apps/verified-access-public/package.json
apps/verified-access-public/next.config.ts
apps/verified-access-public/src/app/layout.tsx
apps/verified-access-public/src/app/invite/page.tsx
apps/verified-access-public/src/app/register/page.tsx
apps/verified-access-public/src/app/status/page.tsx
apps/verified-access-public/src/app/globals.css
apps/verified-access-public/src/lib/public-registration.ts
apps/verified-access-public/src/lib/public-registration.test.ts
package.json
package-lock.json
docs/product/verified-access/phases/PHASE_3B.md
docs/product/verified-access/execution/CURRENT_TASK.md
docs/verified-access-phase-3b-validation.md
```

Paths, datas e nomes só se tornam válidos após inspeção na execução futura e
autorização explícita. Nenhum deles foi criado por este gate documental.

## 22. Gates de autorização

Antes de autorizar implementação:

1. aprovar os blockers jurídicos, de segurança e domínio aplicáveis;
2. revisar schema, estados, RPC signatures, grants e estratégia de chave;
3. confirmar session cookie/proxy same-origin e limites de rate limiting;
4. fechar allowlist exata e commit autorizado em `CURRENT_TASK`;
5. definir evidências de testes, rollback/reaplicação e CI;
6. manter migrations remotas e feature fora do contrato.

Até lá, `CURRENT_TASK` permanece `NO ACTIVE IMPLEMENTATION`.
