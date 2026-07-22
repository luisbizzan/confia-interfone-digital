# CURRENT TASK — VA-P3B-PUBLIC-REGISTRATION

## Estado

Stage: `AUTORIZADA / EM EXECUÇÃO`.

Implementar exclusivamente a Fase 3B definida em
`docs/product/verified-access/phases/PHASE_3B.md`, conforme aprovação explícita
do PO em 22 de julho de 2026. O contrato inicia no head documental
`2430ddb64712a18eff3a127afd3e91faf1fa0f10` e mantém o PR #8 como draft.

## Entrega autorizada

- exchange público do token de convite por sessão opaca de 256 bits;
- sessão hash-only, absoluta de 30 minutos e uma `ACTIVE` por invitation;
- GET, START, SUBMIT e STATUS usando somente public session token;
- START idempotente sem PII, profile ou participant e com `started_at`;
- submissão transacional única com profile protegido, participant, slot
  `CLAIMED`, invitation/session `COMPLETED`, audit e outbox sanitizados;
- aplicação Next.js isolada em `apps/verified-access-public`;
- rate limiting local/testável sem IP bruto;
- testes SQL, Edge e web, CI, rollback, reaplicação e regressões 1A–3A.

## Decisões fechadas

- estados de sessão: `ACTIVE`, `REVOKED`, `EXPIRED`, `COMPLETED`;
- START mantém `ACTIVE` e registra somente `started_at` e telemetria sanitizada;
- nova exchange válida revoga sessão `ACTIVE` anterior;
- retry após perda da resposta usa nova exchange e rotação; token bruto nunca é
  persistido ou recuperado;
- nome e nascimento obrigatórios; CPF para brasileiro adulto; RNM ou passaporte
  para estrangeiro; telefone opcional; responsável obrigatório para menor;
- nenhum rascunho de PII;
- cifragem e HMAC fora do SQL, com secrets somente no ambiente Edge;
- textos jurídicos de DEV são provisórios e não liberam produção;
- `VERIFIED_ACCESS` permanece desligada e nenhuma migration remota é autorizada.

## Allowlist exata

```text
supabase/migrations/20260722100000_verified_access_public_sessions.sql
supabase/migrations/20260722101000_verified_access_identity_profile_registration.sql
supabase/migrations/20260722102000_verified_access_public_registration_rpcs.sql
supabase/rollback/verified_access_phase_3b_rollback.sql
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
supabase/functions/_shared/verified-access/public-registration/contracts.test.ts
supabase/functions/_shared/verified-access/public-registration/crypto.test.ts
supabase/tests/verified_access_phase_3b.sql
supabase/tests/verified_access_phase_3b_integration.psql
supabase/tests/verified_access_phase_3b_runtime_roles.psql
.github/workflows/verified-access-phase-3b.yml
.github/workflows/verified-access-phase-1a.yml
supabase/config.toml
apps/verified-access-public/package.json
apps/verified-access-public/tsconfig.json
apps/verified-access-public/eslint.config.mjs
apps/verified-access-public/next.config.ts
apps/verified-access-public/next-env.d.ts
apps/verified-access-public/vitest.config.ts
apps/verified-access-public/vitest.setup.ts
apps/verified-access-public/src/app/favicon.ico
apps/verified-access-public/src/app/globals.css
apps/verified-access-public/src/app/layout.tsx
apps/verified-access-public/src/app/page.tsx
apps/verified-access-public/src/app/invite/page.tsx
apps/verified-access-public/src/app/register/page.tsx
apps/verified-access-public/src/app/status/page.tsx
apps/verified-access-public/src/components/registration-flow.tsx
apps/verified-access-public/src/lib/api.ts
apps/verified-access-public/src/lib/validation.ts
apps/verified-access-public/src/lib/validation.test.ts
apps/verified-access-public/src/components/registration-flow.test.tsx
package.json
package-lock.json
docs/product/verified-access/phases/PHASE_3B.md
docs/product/verified-access/phases/PHASE_3.md
docs/product/verified-access/execution/CURRENT_TASK.md
docs/verified-access-phase-3b-validation.md
```

Qualquer path adicional exige parada como `BLOCKED` antes da edição.

## Gates obrigatórios

- db reset, pgTAP, integrações 1A–3B, runtime roles e db lint;
- Edge fmt, lint, check e tests, incluindo sanitização de logs;
- app pública: lint, type-check, tests e build;
- preservação do admin-web;
- rollback 3B, preservação 1A–3A e `persons`, reaplicação e smoke;
- regressões 1A, 1B, 1C, 2 e 3A e Vercel Preview verdes;
- `git diff --check` e auditoria final da allowlist.

## Fora de escopo

Prova de vida, biometria, imagem/upload, `IdentityProvider`, background,
elegibilidade, provider real, credencial, QR Code, portaria, Expo/mobile, Rede
Confia operacional, correção posterior, integração externa, migration remota,
feature habilitada, alteração de `persons`, merge, mark-ready e force-push.

## Condições de parada

Parar antes de alterar fora da allowlist ou se a solução exigir plaintext
persistido, `persons`, provider, prova de vida, serviço externo, migration
remota, feature habilitada ou enfraquecimento de segurança/isolamento/rollback.

## Fechamento

Após todos os gates verdes, criar a validação real e retornar este arquivo para
`# CURRENT TASK — NO ACTIVE IMPLEMENTATION`, registrando 3B implementada,
textos jurídicos provisórios, feature desligada, migrations apenas locais e
Fases 3C/4 não autorizadas.
