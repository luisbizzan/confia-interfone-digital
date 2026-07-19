# CURRENT TASK — VA-1D-PROVIDER-CONTRACTS-AND-FAKES

## 1. Estado e autorização

A Fase 1D está autorizada exclusivamente para implementar contratos internos de
providers, fakes determinísticos e seus testes Deno, conforme
`docs/product/verified-access/phases/PHASE_1D.md`.

Contexto da execução futura:

```text
Worktree: C:\Projetos\Confia\repo-github-phase-1d
Branch: agent/verified-access-phase-1d
PR: https://github.com/luisbizzan/confia-interfone-digital/pull/5
Base da Fase 1D: commit que contém esta autorização documental
```

Este contrato não autoriza integração externa, persistência, orquestração,
feature habilitada ou mudança de fase.

## 2. Objetivo autorizado

Implementar, em TypeScript compatível com Deno e independente de fornecedor:

1. `IdentityProvider`;
2. `BackgroundCheckProvider`;
3. `MessagingProvider`;
4. tipos compartilhados e resultados discriminados;
5. `FakeIdentityProvider`;
6. `FakeBackgroundCheckProvider`;
7. `FakeMessagingProvider`;
8. cenários sintéticos definidos no plano da Fase 1D;
9. testes Deno de contrato, segurança, idempotência e isolamento.

Não criar Edge Function, endpoint ou adapter real. Os arquivos são módulos
internos inertes sob `_shared`.

## 3. Paths autorizados

Somente estes arquivos podem ser criados ou alterados na execução técnica:

```text
supabase/functions/_shared/verified-access/providers/contracts.ts
supabase/functions/_shared/verified-access/providers/result.ts
supabase/functions/_shared/verified-access/providers/clock.ts
supabase/functions/_shared/verified-access/providers/identity-provider.ts
supabase/functions/_shared/verified-access/providers/background-check-provider.ts
supabase/functions/_shared/verified-access/providers/messaging-provider.ts
supabase/functions/_shared/verified-access/providers/fake/fake-provider-store.ts
supabase/functions/_shared/verified-access/providers/fake/fake-identity-provider.ts
supabase/functions/_shared/verified-access/providers/fake/fake-background-check-provider.ts
supabase/functions/_shared/verified-access/providers/fake/fake-messaging-provider.ts
supabase/functions/_shared/verified-access/providers/fake/scenarios.ts
supabase/functions/_shared/verified-access/providers/tests/provider-result.test.ts
supabase/functions/_shared/verified-access/providers/tests/provider-contracts.test.ts
supabase/functions/_shared/verified-access/providers/tests/fake-identity-provider.test.ts
supabase/functions/_shared/verified-access/providers/tests/fake-background-check-provider.test.ts
supabase/functions/_shared/verified-access/providers/tests/fake-messaging-provider.test.ts
```

Qualquer arquivo adicional exige novo contrato versionado. Não alterar este
`CURRENT_TASK.md`, o plano, o ROADMAP, workflows ou documentação durante a
execução técnica, salvo novo gate explícito.

## 4. Tipos obrigatórios

Implementar os contratos definidos no plano, incluindo:

- `ProviderContext`;
- `ProviderReadContext`;
- `ProviderMutationContext`;
- `ProviderResult<T>`;
- `ProviderSuccess<T>`;
- `ProviderFailure`;
- `ProviderError` e seus códigos permitidos;
- `ProviderInputFingerprint`;
- `Clock`;
- `FakeProviderStore` e tipos de chave/entrada;
- inputs, capabilities e resultados normalizados das três portas.

Operações assíncronas de provider retornam sempre:

```ts
Promise<ProviderResult<T>>
```

Erros esperados são retornados como `ProviderFailure`. Não lançar erro esperado,
status HTTP, corpo de fornecedor ou mensagem livre sensível. Exceções ficam
restritas a defeito de programação ou invariante irrecuperável e devem falhar o
teste.

## 5. Contratos das portas

### 5.1 `IdentityProvider`

Implementar somente:

- `capabilities`;
- `createSession`;
- `getResult`;
- `cancelSession`.

Documento, liveness e face match 1:1 permanecem evidências distintas.
Liveness isolado nunca produz `IDENTITY_VERIFIED`. Busca facial 1:N, galeria,
embedding, template biométrico e correlação por rosto são proibidos.

`MANUAL_VERIFIED` é estado exclusivo de revisão humana futura. O tipo de nível
retornado por provider automático e fake não pode conter `MANUAL_VERIFIED`.

### 5.2 `BackgroundCheckProvider`

Implementar somente:

- `capabilities`;
- `requestCheck`;
- `getResult`.

Resultado adverso retorna `ADVERSE_INFORMATION_REVIEW` e exige revisão futura.
Inconclusão, homonímia, timeout, indisponibilidade e erro de provider nunca
equivalem a antecedente, fraude ou negativa.

### 5.3 `MessagingProvider`

Implementar somente:

- `sendInvitation`;
- `sendStatusUpdate`;
- `getDeliveryStatus`.

Mensagens fake usam somente dados sintéticos e referências opacas. Não criar
integração com SMS, e-mail, WhatsApp ou qualquer transporte real.

## 6. Fingerprint e idempotência

Implementar exatamente:

```ts
type ProviderInputFingerprint = {
  version: 1;
  value: string;
};
```

Regras obrigatórias:

- representação canônica em JSON UTF-8;
- chaves em ordem lexicográfica;
- arrays ordenados quando a ordem não tiver semântica;
- timestamps em UTC ISO 8601;
- propriedades `undefined` ausentes;
- `correlationId`, `requestedAt` e `idempotencyKey` fora do fingerprint;
- nenhuma PII em texto aberto;
- fake recebe o fingerprint opaco e não calcula hash de PII;
- mesma chave e fingerprint iguais retornam o resultado lógico armazenado;
- mesma chave e fingerprint diferente retornam `CONFLICT`;
- IDs fake derivam deterministicamente de provider, operação, condomínio,
  idempotency key e fingerprint, sem PII.

Usar somente as allowlists do `PHASE_1D.md` para:

- `createSession`;
- `cancelSession`;
- `requestCheck`;
- `sendInvitation`;
- `sendStatusUpdate`.

Metadata livre, timestamp da tentativa ou campo fora da allowlist não pode
alterar o fingerprint.

## 7. Fakes e cenários

Implementar somente estes fakes:

- `FakeIdentityProvider`;
- `FakeBackgroundCheckProvider`;
- `FakeMessagingProvider`.

Cenários de identidade:

```text
IDENTITY_SUCCESS
IDENTITY_INCONCLUSIVE
IDENTITY_TIMEOUT
IDENTITY_PROVIDER_ERROR
DOCUMENT_INVALID_REVIEW
LIVENESS_INCONCLUSIVE
LIVENESS_FAILED_REVIEW
FACE_NO_MATCH_REVIEW
```

Cenários de background:

```text
BACKGROUND_SUCCESS
BACKGROUND_INCONCLUSIVE
BACKGROUND_TIMEOUT
BACKGROUND_PROVIDER_ERROR
BACKGROUND_ADVERSE_REVIEW
BACKGROUND_MANUAL_CONFIRMATION
```

Cenários de mensageria:

```text
MESSAGE_SUCCESS
MESSAGE_TIMEOUT
MESSAGE_PROVIDER_ERROR
MESSAGE_DUPLICATE
```

Todos os cenários são sintéticos, configuráveis e determinísticos. Nenhum
cenário é selecionado por CPF, documento, telefone, nome ou outro dado real.

## 8. Estado, store e clock

- Estado somente por instância e sem estado global.
- Proibidos singleton, cache estático e variável global mutável.
- `FakeProviderStore` in-memory injetado pelo chamador.
- Isolamento por condomínio, provider e operação.
- Store e clock distintos por teste paralelo.
- `clear()` obrigatório para cleanup determinístico, inclusive após falha.
- Limite positivo e configurável de registros.
- Ao atingir o limite, retornar resultado explícito sem descartar registro ou
  lançar erro esperado.
- Proibidos filesystem, Supabase, banco e rede.
- `Clock.now()` usa tempo injetado.
- `Clock.sleep(ms)` avança tempo virtual e não espera tempo real.

## 9. Tentativa, timeout e retry

- Cada chamada de uma porta equivale exatamente a uma tentativa.
- Provider e fake não executam retry, backoff ou jitter internamente.
- Timeout encerra a tentativa com `ProviderFailure` e código `TIMEOUT`.
- Retry, backoff, jitter e limite pertencem ao futuro orquestrador, que está fora
  do escopo desta tarefa.
- Retentativa futura reutiliza a mesma idempotency key e o mesmo fingerprint.
- `retryAfterMs` é somente recomendação e não agenda retry.
- Erro não retryable não é repetido automaticamente.
- Falha técnica nunca vira fraude, case, signal ou negativa.

## 10. Limites de domínio e segurança

Provider e fake nunca:

- decidem ou alteram elegibilidade;
- concedem ou negam acesso;
- criam, substanciam ou alteram security case;
- criam, ativam, suspendem ou revogam network signal;
- vinculam network subject;
- alteram policy ou feature flag;
- gravam audit ou outbox operacional;
- emitem credencial;
- propagam decisão local.

Regras adicionais:

- nenhuma negativa automática;
- nenhum `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` ou blacklist;
- nenhuma PII em logs, IDs, fingerprints, snapshots, fixtures ou metadata;
- nenhum documento, imagem, vídeo, biometria, certidão ou payload bruto;
- nenhum secret, chave, token, URL assinada ou credencial;
- nenhuma rede, filesystem, Supabase, SDK ou integração externa;
- nenhum endpoint público, webhook ou polling externo;
- nenhuma feature habilitada;
- nenhuma migration local ou remota.

## 11. Testes obrigatórios

Criar testes Deno que comprovem:

- `ProviderResult` discriminado por `ok`;
- nenhum erro esperado lançado;
- contratos das três portas;
- todos os cenários determinísticos;
- fingerprint estável para representação canônica equivalente;
- chave igual com fingerprint diferente retorna `CONFLICT`;
- `correlationId` não altera fingerprint;
- isolamento por condomínio;
- isolamento entre instâncias;
- ausência de estado global;
- cleanup determinístico;
- testes paralelos sem interferência;
- clock virtual;
- zero espera de tempo real;
- uma tentativa por chamada;
- ausência de retry interno;
- retry pertence somente ao futuro orquestrador;
- `MANUAL_VERIFIED` nunca retornado por provider ou fake;
- liveness isolado sem `IDENTITY_VERIFIED`;
- background adverso sem negativa automática;
- nenhuma PII em logs, IDs, fingerprints, snapshots ou metadata;
- nenhuma rede ou filesystem;
- limite determinístico do store;
- mesma chave e fingerprint iguais não duplicam operação lógica.

Usar somente fixtures sintéticas. Testes não recebem permissão de rede,
filesystem, ambiente ou Supabase.

## 12. Validações obrigatórias

Executar sobre todos os arquivos autorizados:

```text
deno fmt --check
deno lint
deno check
deno test
```

No mínimo, registrar separadamente os resultados reais de `deno check` e
`deno test`. Não declarar aprovação para comando não executado.

Também validar:

- `git diff --check`;
- somente os 16 paths autorizados foram alterados;
- nenhuma importação de rede, filesystem, Supabase ou SDK externo;
- nenhuma PII, secret ou integração real foi introduzida;
- `persons`, app Expo, migrations, feature flags e código runtime existente
  permanecem intocados.

Nenhum arquivo de workflow está autorizado. Executar CI existente quando ele
for disparado pelo push, sem alterar workflows para acomodar esta fase.

## 13. Fora de escopo

- migrations ou banco;
- função SQL, trigger ou RPC;
- provider ou adapter real;
- DataTrust;
- BigDataCorp;
- Datavalid;
- WhatsApp, SMS ou e-mail real;
- Edge Function pública;
- API, endpoint, webhook ou polling externo;
- UI ou backoffice;
- app Expo;
- orquestrador;
- solicitação do morador;
- alteração de estado no banco;
- audit ou outbox operacional;
- HMAC real, criptografia ou gestão de chaves;
- reconhecimento facial 1:N;
- credencial, QR Code, portaria ou check-in/out;
- Fase 2 ou fase posterior;
- feature habilitada;
- migration remota;
- qualquer arquivo fora da allowlist da seção 3.

## 14. Condições de parada

Parar antes de ampliar o escopo se:

- algum path adicional for necessário;
- a solução exigir dependência externa, rede, filesystem, Supabase ou secret;
- o fake precisar persistir PII, biometria ou payload bruto;
- a implementação exigir migration, RPC, Edge Function ou orquestrador;
- `MANUAL_VERIFIED` precisar entrar no retorno automático;
- liveness isolado for tratado como identidade verificada;
- background adverso for tratado como negativa;
- uma chamada exigir retry interno;
- não for possível provar isolamento e ausência de estado global;
- qualquer teste das regras obrigatórias falhar;
- a implementação exigir habilitar feature ou executar migration remota.

Não contornar blocker reduzindo segurança ou removendo teste negativo.

## 15. Critérios de conclusão

A execução técnica futura só estará concluída quando:

1. somente os 16 paths autorizados tiverem sido alterados;
2. contratos e três fakes estiverem implementados;
3. todos os cenários sintéticos estiverem cobertos;
4. `deno check` e `deno test` estiverem verdes;
5. formatação e lint estiverem verdes;
6. idempotência, fingerprint, isolamento e clock virtual estiverem comprovados;
7. nenhuma PII, rede, filesystem, Supabase, SDK ou secret existir;
8. nenhuma decisão automática, case, signal, policy ou feature for alterada;
9. nenhuma migration local ou remota for criada ou executada;
10. PR permanecer draft até gate posterior específico.

O relatório final deve listar SHA inicial/final, commits, arquivos, contratos,
cenários, testes realmente executados, resultados de CI, blockers e todas as
confirmações de segurança e escopo.
