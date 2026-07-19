# Fase 1D — contratos e providers fake

## 1. Status

Este documento é um plano para revisão humana. Ele descreve contratos e gates
que poderão ser autorizados por um contrato versionado futuro, mas não autoriza
implementação.

`execution/CURRENT_TASK.md` permanece como `CURRENT TASK — NO ACTIVE
IMPLEMENTATION`. Nenhuma interface, fake, adapter, Edge Function, migration ou
teste técnico é criado por este plano.

Stage: `Planejada / revisão documental final / não autorizada`.

## 2. Objetivo

Preparar portas internas estáveis e independentes de fornecedor para identidade,
background e mensageria, acompanhadas futuramente por fakes determinísticos e
testes Deno. A futura implementação deverá permitir validar contratos antes de
qualquer integração externa, sem entregar decisão de elegibilidade aos providers.

Resultado esperado quando uma execução futura for autorizada:

```text
contratos normalizados e versionáveis
+ erros e limites operacionais comuns
+ fakes determinísticos sem rede
+ relógio injetável
+ testes de contrato e segurança
+ zero dependência de DTO de fornecedor no domínio
```

Não há migration obrigatória na Fase 1D.

## 3. Princípios vinculantes

- Providers coletam ou transportam evidências; não decidem elegibilidade.
- Liveness, documento e face match 1:1 são evidências separadas.
- Liveness isolado nunca resulta em `IDENTITY_VERIFIED`.
- Face match é exclusivamente 1:1 contra documento ou referência autorizada.
- Resultado adverso de background exige revisão humana e nunca nega acesso
  automaticamente.
- Timeout, indisponibilidade ou erro técnico exige retry controlado e, esgotado
  o limite, revisão; não equivale a fraude ou negativa.
- Contratos usam tipos normalizados da Confia, sem DTO de DataTrust,
  BigDataCorp, Datavalid ou outro fornecedor.
- Fakes não acessam rede, Supabase, filesystem, secrets ou relógio global.
- Nenhum contrato aceita ou produz `AUTO_DENY_NETWORK`.

## 4. Tipos transversais planejados

Os nomes abaixo são o contrato conceitual exato a ser materializado somente por
execução futura. A implementação deverá seguir a convenção real de
`supabase/functions/_shared` e Deno usada pelo repositório.

```ts
type CorrelationId = string;
type IdempotencyKey = string;
type IsoTimestamp = string;

type ProviderInputFingerprint = {
  version: 1;
  value: string;
};

type ProviderContext = {
  condominiumId: string;
  requestId: string;
  participantId: string;
  correlationId: CorrelationId;
  idempotencyKey: IdempotencyKey;
  inputFingerprint: ProviderInputFingerprint;
  requestedAt: IsoTimestamp;
};

type SanitizedMetadata = Record<string, string | number | boolean | null>;

type ProviderErrorCode =
  | "INVALID_INPUT"
  | "UNSUPPORTED_CAPABILITY"
  | "UNAVAILABLE"
  | "TIMEOUT"
  | "RATE_LIMITED"
  | "AUTHENTICATION_FAILED"
  | "INVALID_PROVIDER_RESPONSE"
  | "NOT_FOUND"
  | "CONFLICT"
  | "CANCELLED";

type ProviderError = {
  code: ProviderErrorCode;
  retryable: boolean;
  correlationId: CorrelationId;
  providerCode?: string;
  retryAfterMs?: number;
  metadataSanitized?: SanitizedMetadata;
};

type ProviderSuccess<T> = {
  ok: true;
  value: T;
};

type ProviderFailure = {
  ok: false;
  error: ProviderError;
};

type ProviderResult<T> = ProviderSuccess<T> | ProviderFailure;

type ProviderReadContext = Pick<
  ProviderContext,
  "condominiumId" | "requestId" | "participantId" | "correlationId"
>;

type ProviderMutationContext = ProviderReadContext & {
  idempotencyKey: IdempotencyKey;
  inputFingerprint: ProviderInputFingerprint;
  requestedAt: IsoTimestamp;
};

type IdentityCapabilities = {
  documentVerification: boolean;
  liveness: boolean;
  faceMatchOneToOne: boolean;
  polling: boolean;
  cancellation: boolean;
};

type IdentitySessionInput = {
  context: ProviderContext;
  documentType: "CPF" | "RNM" | "PASSPORT_WITH_ISSUER";
  issuerCountry?: string;
  requestedChecks: Array<
    "DOCUMENT_VERIFICATION" | "LIVENESS" | "FACE_MATCH_ONE_TO_ONE"
  >;
  sensitiveInputReference: string;
  callbackReference?: string;
};

type IdentitySession = {
  providerSessionId: string;
  providerCode: string;
  status: "PENDING";
  correlationId: CorrelationId;
  createdAt: IsoTimestamp;
  expiresAt: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
};

type ProviderIdentityLevel =
  | "UNVERIFIED"
  | "CONTACT_VERIFIED"
  | "LIVENESS_VERIFIED"
  | "IDENTITY_VERIFIED";

type IdentityAssuranceLevel = ProviderIdentityLevel | "MANUAL_VERIFIED";

type IdentityResult = {
  providerSessionId: string;
  providerCode: string;
  correlationId: CorrelationId;
  status: "VERIFIED" | "INCONCLUSIVE" | "TECHNICAL_ERROR" | "EXPIRED";
  level: ProviderIdentityLevel;
  documentStatus: "NOT_PERFORMED" | "VALID" | "INVALID" | "INCONCLUSIVE";
  livenessStatus: "NOT_PERFORMED" | "PASSED" | "FAILED" | "INCONCLUSIVE";
  faceMatchStatus: "NOT_PERFORMED" | "MATCH" | "NO_MATCH" | "INCONCLUSIVE";
  reasonCode: string;
  occurredAt: IsoTimestamp;
  expiresAt?: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
};

type IdentityCancellation = {
  providerSessionId: string;
  status: "CANCELLED" | "ALREADY_TERMINAL";
  correlationId: CorrelationId;
  occurredAt: IsoTimestamp;
};

type BackgroundCapabilities = {
  coverageCodes: string[];
  polling: boolean;
};

type BackgroundCheckInput = {
  context: ProviderContext;
  verifiedIdentityReference: string;
  scopeCodes: string[];
  approvalReference: string;
  cutoffAt: IsoTimestamp;
};

type BackgroundCheckRequest = {
  providerRequestId: string;
  providerCode: string;
  status: "PENDING";
  correlationId: CorrelationId;
  requestedAt: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
};

type BackgroundCheckResult = {
  providerRequestId: string;
  providerCode: string;
  correlationId: CorrelationId;
  status:
    | "NEGATIVE_CERTIFICATE"
    | "ADVERSE_INFORMATION_REVIEW"
    | "MANUAL_CONFIRMATION_REQUIRED"
    | "INCONCLUSIVE"
    | "PROVIDER_ERROR"
    | "EXPIRED";
  reasonCode: string;
  coverageCodes: string[];
  occurredAt: IsoTimestamp;
  expiresAt?: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
};

type InvitationMessageInput = {
  context: ProviderContext;
  channel: "SMS" | "WHATSAPP" | "EMAIL";
  ephemeralDestination: string;
  templateCode: string;
  condominiumDisplayName: string;
  hostDisplayName?: string;
  accessWindowLabel: string;
  opaqueInvitationLink: string;
};

type StatusMessageInput = {
  context: ProviderContext;
  channel: "SMS" | "WHATSAPP" | "EMAIL";
  ephemeralDestination: string;
  templateCode: string;
  operationalStatusCode: string;
};

type MessageDelivery = {
  providerMessageId: string;
  providerCode: string;
  status: "ACCEPTED" | "DELIVERED";
  correlationId: CorrelationId;
  acceptedAt: IsoTimestamp;
  deliveredAt?: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
};

type MessageDeliveryStatus = {
  providerMessageId: string;
  status: "PENDING" | "DELIVERED" | "FAILED" | "EXPIRED";
  correlationId: CorrelationId;
  reasonCode?: string;
  occurredAt: IsoTimestamp;
};
```

Regras comuns:

- `correlationId` é obrigatório e atravessa toda operação e resultado.
- `idempotencyKey` é obrigatória em operações com efeito externo.
- Repetir uma operação com a mesma chave e mesmo input retorna o mesmo resultado
  lógico; mesma chave com input diferente retorna `CONFLICT`.
- Timestamps são ISO 8601 UTC produzidos pelo relógio injetável.
- `metadataSanitized` aceita somente escalares sem PII, biometria, documento,
  token, secret, URL assinada, payload bruto ou narrativa livre.
- Erros esperados são dados estruturados. Mensagens livres de fornecedor não
  atravessam a porta nem são persistidas ou registradas em log.
- Toda operação assíncrona de provider retorna `Promise<ProviderResult<T>>`.
  Erros esperados são `ProviderFailure` e não são lançados. Exceção lançada fica
  reservada a defeito de programação ou violação irrecuperável de invariante e
  deve falhar o teste, nunca representar resposta normal de fornecedor.

### 4.1 Fingerprint de input

`ProviderInputFingerprint.value` é um digest opaco, versionado e não reversível
da representação canônica do input idempotente. A representação usa JSON UTF-8
com chaves em ordem lexicográfica, arrays ordenados quando a ordem não possuir
semântica, ausência de propriedades `undefined` e timestamps normalizados em UTC
no formato ISO 8601.

Ficam sempre fora do fingerprint:

- `correlationId`;
- `requestedAt`;
- `idempotencyKey`.

PII nunca integra o JSON canônico em texto aberto. O orquestrador futuro deve
fornecer referências opacas ou fingerprints previamente produzidos pelo
componente autorizado. Provider e fake recebem `ProviderInputFingerprint` como
dado opaco; o fake não lê PII nem calcula hash de CPF, documento, telefone,
nome, destino de mensagem ou biometria.

IDs fake são derivados deterministicamente de:

```text
providerCode + operation + condominiumId + idempotencyKey + inputFingerprint
```

A mesma chave no mesmo provider, operação e condomínio com fingerprint igual
retorna o resultado lógico já armazenado. Fingerprint diferente retorna
`ProviderFailure` com `error.code = "CONFLICT"`.

### 4.2 Allowlists por operação

Somente estes campos entram na representação canônica de cada operação:

| Operação | Allowlist exata do fingerprint |
|---|---|
| `createSession` | `documentType`, `issuerCountry`, `requestedChecks` ordenados, `sensitiveInputReferenceFingerprint`, `callbackReference` opaca |
| `cancelSession` | `providerSessionId` |
| `requestCheck` | `verifiedIdentityReferenceFingerprint`, `scopeCodes` ordenados, `approvalReference`, `cutoffAt` em UTC |
| `sendInvitation` | `channel`, `destinationReferenceFingerprint`, `templateCode`, `messagePayloadFingerprint`, `opaqueInvitationLinkReference` |
| `sendStatusUpdate` | `channel`, `destinationReferenceFingerprint`, `templateCode`, `operationalStatusCode`, `messagePayloadFingerprint` |

Os campos terminados em `Fingerprint` são produzidos pelo componente futuro
autorizado e chegam opacos ao fake. Nenhum campo de contexto fora da allowlist,
metadata livre, timestamp de tentativa ou dado pessoal aberto pode influenciar
o fingerprint.

## 5. `IdentityProvider`

### 5.1 Interface exata planejada

```ts
interface IdentityProvider {
  capabilities(): IdentityCapabilities;
  createSession(
    input: IdentitySessionInput,
  ): Promise<ProviderResult<IdentitySession>>;
  getResult(
    providerSessionId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<IdentityResult>>;
  cancelSession(
    providerSessionId: string,
    context: ProviderMutationContext,
  ): Promise<ProviderResult<IdentityCancellation>>;
}
```

Não haverá webhook nesta fase. `verifyWebhook` e `parseWebhook` permanecem
extensões futuras, fora da interface mínima autorizável da 1D.

### 5.2 Operações

| Operação | Parâmetros | Retorno | Timeout planejado | Idempotência | Erros relevantes |
|---|---|---|---|---|---|
| `capabilities` | nenhum | suporte a documento, liveness, face 1:1, polling e cancelamento | síncrono, sem I/O | n/a | nenhum; configuração inválida impede construir a instância |
| `createSession` | `context`, tipo de documento permitido, operações solicitadas e referência opaca de callback futuro | ID opaco da sessão, status `PENDING`, expiração, provider code e metadata sanitizada | 15 s | obrigatória por `context.idempotencyKey` | input inválido, capability ausente, timeout, indisponibilidade, rate limit, autenticação, resposta inválida |
| `getResult` | ID opaco da sessão e contexto de leitura | `IdentityResult` normalizado | 10 s | leitura naturalmente idempotente | not found, timeout, indisponibilidade, resposta inválida |
| `cancelSession` | ID opaco da sessão, correlation ID e idempotency key | estado `CANCELLED` ou resultado terminal já existente | 10 s | obrigatória | not found, conflict, timeout, indisponibilidade |

`IdentitySessionInput` contém apenas referências necessárias ao transporte
futuro e o material sensível em memória pelo menor tempo possível. Ele não será
serializado em audit, outbox ou logs. O provider retorna somente IDs opacos,
códigos, estados, timestamps e metadata sanitizada.

### 5.3 Contrato de verificação de documento

Entradas planejadas:

- contexto operacional;
- `documentType`: somente `CPF`, `RNM` ou `PASSPORT_WITH_ISSUER` quando a
  operação exigir identificador;
- frente/verso ou páginas exigidas como referências efêmeras, nunca como
  conteúdo de log;
- país emissor obrigatório para passaporte;
- consentimento/aprovação já validado pelo orquestrador futuro.

Resultado normalizado:

```text
NOT_PERFORMED | VALID | INVALID | INCONCLUSIVE
```

`INVALID` é evidência para revisão e não decisão de fraude. O retorno inclui
`reasonCode`, provider request/session ID, `occurredAt`, `expiresAt` opcional e
metadata sanitizada. Imagem ou OCR bruto não integra o retorno persistível.

### 5.4 Contrato de liveness

Resultado normalizado:

```text
NOT_PERFORMED | PASSED | FAILED | INCONCLUSIVE
```

`PASSED` comprova apenas a execução da prova de vida. Sem documento válido e
demais regras do orquestrador, não eleva identidade para `IDENTITY_VERIFIED`.
`FAILED` e `INCONCLUSIVE` exigem correção, retry ou revisão conforme política;
não criam case ou signal automaticamente.

Nenhuma imagem, vídeo, template, embedding ou amostra biométrica será persistida
pela porta ou pelo fake.

### 5.5 Contrato de face match 1:1

Resultado normalizado:

```text
NOT_PERFORMED | MATCH | NO_MATCH | INCONCLUSIVE
```

A comparação é exclusivamente entre a captura da sessão e o documento ou
referência autorizada da mesma sessão. Busca 1:N, galeria global, identificação
silenciosa e correlação entre condomínios são proibidas. `NO_MATCH` exige
revisão; não confirma fraude nem produz negativa automática.

### 5.6 Resultado agregado de identidade

```text
status: VERIFIED | INCONCLUSIVE | TECHNICAL_ERROR | EXPIRED
provider level: UNVERIFIED | CONTACT_VERIFIED | LIVENESS_VERIFIED |
                IDENTITY_VERIFIED
domain-only future level: MANUAL_VERIFIED
```

O resultado mantém `documentStatus`, `livenessStatus` e `faceMatchStatus`
separados. `MANUAL_VERIFIED` pertence exclusivamente a uma revisão humana
futura, autorizada e auditada. Provider automático e fake não podem retornar
esse nível. O fake não calcula elegibilidade nem cria vínculo de rede.

## 6. `BackgroundCheckProvider`

### 6.1 Interface exata planejada

```ts
interface BackgroundCheckProvider {
  capabilities(): BackgroundCapabilities;
  requestCheck(
    input: BackgroundCheckInput,
  ): Promise<ProviderResult<BackgroundCheckRequest>>;
  getResult(
    providerRequestId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<BackgroundCheckResult>>;
}
```

### 6.2 Operações

| Operação | Parâmetros | Retorno | Timeout planejado | Idempotência | Erros relevantes |
|---|---|---|---|---|---|
| `capabilities` | nenhum | fontes/cobertura abstratas, polling e limites suportados | síncrono, sem I/O | n/a | nenhum; configuração inválida impede construir a instância |
| `requestCheck` | contexto, referência efêmera de identidade verificada, escopo autorizado, approval reference e data de corte | ID opaco, `PENDING`, timestamps e metadata sanitizada | 20 s | obrigatória | input inválido, unsupported, timeout, indisponibilidade, rate limit, autenticação, resposta inválida |
| `getResult` | ID opaco e contexto de leitura | resultado normalizado | 10 s | leitura naturalmente idempotente | not found, timeout, indisponibilidade, resposta inválida |

### 6.3 Resultado normalizado

```text
NEGATIVE_CERTIFICATE
ADVERSE_INFORMATION_REVIEW
MANUAL_CONFIRMATION_REQUIRED
INCONCLUSIVE
PROVIDER_ERROR
EXPIRED
```

- `NEGATIVE_CERTIFICATE` significa somente o resultado e a cobertura da fonte
  consultada na data registrada.
- `ADVERSE_INFORMATION_REVIEW` nunca equivale a condenação, fraude ou negativa;
  exige revisão humana autorizada.
- `MANUAL_CONFIRMATION_REQUIRED` sinaliza ambiguidade ou necessidade de validar
  a fonte.
- `INCONCLUSIVE`, `PROVIDER_ERROR` e timeout não geram signal, case ou bloqueio
  de rede.
- O retorno não carrega certidão, narrativa, lista de ocorrências ou payload
  bruto. Ele contém códigos estruturados, cobertura sanitizada, IDs e
  timestamps.

## 7. `MessagingProvider`

### 7.1 Interface exata planejada

```ts
interface MessagingProvider {
  sendInvitation(
    input: InvitationMessageInput,
  ): Promise<ProviderResult<MessageDelivery>>;
  sendStatusUpdate(
    input: StatusMessageInput,
  ): Promise<ProviderResult<MessageDelivery>>;
  getDeliveryStatus(
    providerMessageId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<MessageDeliveryStatus>>;
}
```

### 7.2 Operações

| Operação | Parâmetros | Retorno | Timeout planejado | Idempotência | Erros relevantes |
|---|---|---|---|---|---|
| `sendInvitation` | contexto, canal abstrato, destino efêmero, template code, condomínio/anfitrião, período e link opaco | provider message ID, `ACCEPTED` ou `DELIVERED`, timestamps e metadata sanitizada | 10 s | obrigatória | input inválido, unsupported, timeout, indisponibilidade, rate limit, autenticação, resposta inválida |
| `sendStatusUpdate` | contexto, canal, destino efêmero, template code e status operacional não sensível | mesmo contrato de delivery | 10 s | obrigatória | mesmos erros de envio |
| `getDeliveryStatus` | provider message ID e contexto | `PENDING`, `DELIVERED`, `FAILED` ou `EXPIRED` | 10 s | leitura naturalmente idempotente | not found, timeout, indisponibilidade, resposta inválida |

Mensagens podem conter condomínio/anfitrião, período, contexto geral e link
opaco. Não podem conter CPF, documento, biometria, certidão, resultado de
background, razão sensível, network subject ou signal.

## 8. Fakes determinísticos e configuráveis

Cada fake futuro recebe configuração explícita e relógio injetável. Nenhum
cenário é escolhido por CPF, telefone, nome ou outro dado real. A seleção usa
scenario code sintético fornecido pelo teste.

### 8.1 Cenários de identidade

| Código | Resultado |
|---|---|
| `IDENTITY_SUCCESS` | documento válido, liveness aprovado e face 1:1 compatível |
| `IDENTITY_INCONCLUSIVE` | resultado agregado inconclusivo sem elevar assurance |
| `IDENTITY_TIMEOUT` | erro estruturado `TIMEOUT`, retryable |
| `IDENTITY_PROVIDER_ERROR` | `TECHNICAL_ERROR` ou erro `UNAVAILABLE`, conforme etapa |
| `DOCUMENT_INVALID_REVIEW` | documento inválido, sem declarar fraude |
| `LIVENESS_INCONCLUSIVE` | liveness inconclusivo, identidade não verificada |
| `LIVENESS_FAILED_REVIEW` | liveness falhou, sem case/signal automático |
| `FACE_NO_MATCH_REVIEW` | face 1:1 sem match, revisão necessária |

### 8.2 Cenários de background

| Código | Resultado |
|---|---|
| `BACKGROUND_SUCCESS` | `NEGATIVE_CERTIFICATE` dentro da cobertura simulada |
| `BACKGROUND_INCONCLUSIVE` | `INCONCLUSIVE` |
| `BACKGROUND_TIMEOUT` | erro `TIMEOUT`, retryable |
| `BACKGROUND_PROVIDER_ERROR` | `PROVIDER_ERROR`/`UNAVAILABLE` |
| `BACKGROUND_ADVERSE_REVIEW` | `ADVERSE_INFORMATION_REVIEW`, nunca negativa automática |
| `BACKGROUND_MANUAL_CONFIRMATION` | `MANUAL_CONFIRMATION_REQUIRED` |

### 8.3 Cenários de mensageria

| Código | Resultado |
|---|---|
| `MESSAGE_SUCCESS` | entrega determinística aceita/entregue |
| `MESSAGE_TIMEOUT` | erro `TIMEOUT`, retryable |
| `MESSAGE_PROVIDER_ERROR` | erro `UNAVAILABLE` ou delivery `FAILED` |
| `MESSAGE_DUPLICATE` | mesma chave retorna o mesmo provider message ID |

Configuração futura mínima: scenario, latência simulada, número de falhas antes
do sucesso e timestamps do relógio injetável. Não haverá aleatoriedade. Todos os
IDs fake seguem a derivação definida na seção 4.1, sem incorporar PII.

### 8.4 Estado, store e relógio dos fakes

```ts
type FakeProviderStoreKey = {
  providerCode: string;
  operation: string;
  condominiumId: string;
  idempotencyKey: IdempotencyKey;
};

type FakeProviderStoreEntry<T> = {
  inputFingerprint: ProviderInputFingerprint;
  result: ProviderResult<T>;
  storedAt: IsoTimestamp;
};

interface FakeProviderStore {
  get<T>(key: FakeProviderStoreKey): FakeProviderStoreEntry<T> | undefined;
  put<T>(
    key: FakeProviderStoreKey,
    entry: FakeProviderStoreEntry<T>,
  ): "STORED" | "LIMIT_REACHED";
  clear(): void;
}

interface Clock {
  now(): Date;
  sleep(ms: number): Promise<void>;
}
```

- Estado é sempre por instância e sem estado global; não existe singleton, cache
  estático, variável global mutável ou registro compartilhado entre testes.
- O storage in-memory é injetado pelo chamador e particionado por condomínio,
  provider e operação. A chave de idempotência nunca atravessa essas partições.
- Cada instância recebe seu próprio `FakeProviderStore` por padrão. Compartilhar
  store exige opção explícita do teste e não altera a partição lógica.
- `clear()` fornece cleanup determinístico e deve ser executado no teardown,
  inclusive quando o teste falhar.
- Testes paralelos usam stores e clocks distintos, sem interferência.
- O store não usa filesystem, Supabase, banco ou rede.
- A implementação futura deve exigir limite positivo configurável de registros;
  ao atingir o limite, `put` retorna `LIMIT_REACHED` sem lançar erro esperado ou
  descartar entrada silenciosamente. A porta converte esse estado em
  `ProviderFailure` estruturado.
- O clock fake avança tempo virtual em `sleep(ms)` e nunca espera tempo real.
  Valores negativos ou não finitos são defeitos de input de teste.

## 9. Segurança e privacidade

- Nenhum log contém PII, documento, contato, conteúdo de mensagem, imagem,
  biometria, certidão, token, secret ou payload bruto.
- Nenhuma imagem biométrica é persistida; referências efêmeras são descartadas
  após a operação simulada.
- Não existem chaves reais, chamadas HTTP, SDK externo ou credencial.
- Não existe endpoint público, webhook, polling externo ou Edge Function
  pública.
- Não existe busca facial 1:N, galeria global ou busca de pessoa na rede.
- Nenhum resultado produz `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` ou blacklist.
- `MANUAL_VERIFIED` não pode ser produzido por provider automático nem fake.
- Fakes usam somente dados sintéticos versionados e não podem ser selecionados
  por identificador civil real.
- Metadata e logs usam allowlist, não remoção por blacklist.

## 10. Persistência futura autorizável

Uma fase posterior poderá persistir somente:

- provider request/session/message ID opaco;
- provider code não sensível;
- status normalizado;
- `requested_at`, `completed_at`, `expires_at` e `occurred_at`;
- reason code estruturado;
- hash aprovado de referência ou payload, sem permitir reconstrução de PII;
- correlation ID e idempotency key;
- metadata sanitizada por allowlist;
- versão do contrato/provider adapter.

Não persistir payload bruto, OCR, documento, imagem, vídeo, template ou
embedding biométrico, certidão, narrativa, resposta HTTP, headers, token,
secret, URL assinada ou mensagem completa. Qualquer necessidade adicional exige
revisão de segurança e privacidade e novo contrato versionado.

## 11. Limites de responsabilidade

O provider e seu fake nunca:

- calculam ou decidem `eligibility_status`;
- concedem ou negam acesso;
- ativam, suspendem ou revogam network signal;
- criam ou substanciam security case automaticamente;
- vinculam network subject;
- alteram policy ou feature flag;
- emitem credencial;
- propagam decisão local.

Um orquestrador futuro, fora da Fase 1D, mapeará resultados normalizados para
estados do participante segundo policy ativa, feature flags, aprovação,
idempotência e revisão humana. Esse mapeamento deverá gravar audit/outbox na
mesma transação de domínio por caminho autorizado próprio.

## 12. Estratégia de adapters

```text
domínio/orquestrador futuro
        -> porta normalizada Confia
        -> fake determinístico ou adapter selecionado por configuração
        -> fornecedor externo futuro
```

- Identity: fake primeiro; adapter futuro candidato para DataTrust/Link
  Validação Segura e alternativa Datavalid V5.
- Background: fake primeiro; adapters futuros candidatos para DataTrust
  Background Check e BigDataCorp on-demand.
- Messaging: fake primeiro; provider real e canal, inclusive WhatsApp, somente
  após contrato, opt-in, templates, custos, webhook e secrets aprovados.
- Cada adapter traduz DTO externo na borda. DTO de fornecedor não entra no
  domínio nem na persistência normalizada.
- Nenhum adapter real, SDK, fixture de sandbox ou chamada externa integra esta
  etapa documental.

### 12.1 Layout futuro autorizável

Quando houver contrato executável, os arquivos planejados ficarão em:

```text
supabase/functions/_shared/verified-access/providers/
├── contracts.ts
├── result.ts
├── clock.ts
├── identity-provider.ts
├── background-check-provider.ts
├── messaging-provider.ts
├── fake/
│   ├── fake-provider-store.ts
│   ├── fake-identity-provider.ts
│   ├── fake-background-check-provider.ts
│   ├── fake-messaging-provider.ts
│   └── scenarios.ts
└── tests/
    ├── provider-result.test.ts
    ├── provider-contracts.test.ts
    ├── fake-identity-provider.test.ts
    ├── fake-background-check-provider.test.ts
    └── fake-messaging-provider.test.ts
```

Esse layout é planejamento. Nenhum desses paths ou arquivos é criado neste
gate documental.

## 13. Configuração e falha operacional

- Todas as feature flags permanecem desligadas.
- A escolha do provider será feita futuramente por configuração validada, nunca
  por condicionais espalhadas no domínio.
- Fake será o padrão apenas em ambiente local e de teste. Produção sem provider
  explicitamente autorizado deve falhar na inicialização/configuração.
- Kill switch de ambiente será obrigatório para qualquer integração real.
- Timeout e indisponibilidade falham de modo técnico fechado: não avançam
  verificação, background ou envio como sucesso.
- Falhar tecnicamente fechado não significa negar acesso. O domínio futuro
  mantém o fluxo pendente ou em revisão conforme policy e nunca produz negativa
  automática.

### 13.1 Ownership de tentativa, timeout e retry

- Cada chamada de uma porta representa exatamente uma tentativa.
- Provider e fake não fazem retry, backoff ou jitter internamente.
- Timeout limita uma tentativa e retorna `ProviderFailure` com `TIMEOUT`; não
  dispara nova tentativa dentro da porta.
- Retry, backoff, jitter e limite de tentativas pertencem exclusivamente ao
  futuro orquestrador.
- O orquestrador reutiliza a mesma idempotency key e o mesmo input fingerprint
  em todas as tentativas da mesma operação lógica.
- `retryAfterMs` é somente recomendação do provider; não agenda nem obriga retry.
- Erro com `retryable = false` não é repetido automaticamente.
- Falha técnica esgotada permanece técnica ou exige revisão. Nunca é convertida
  em fraude, case, signal ou negativa de acesso.

## 14. Observabilidade planejada

Métricas sem PII:

- contagem e latência por provider code, operação, status e ambiente;
- taxa de timeout, indisponibilidade, retry e erro normalizado;
- entregas aceitas, concluídas e falhas por canal abstrato;
- resultados agregados por código normalizado, sem dimensão individual;
- correlation ID para rastreamento técnico controlado;
- tentativas idempotentes e conflitos de chave.

Logs estruturados usam correlation ID, operação, provider code, duração,
status e error code. Não incluem input sensível, output bruto ou conteúdo de
mensagem.

Audit e outbox de chamadas operacionais são futuros. Quando autorizados, devem
ser sanitizados, append-only/idempotentes e gravados pelo orquestrador na mesma
transação da alteração de domínio; providers não escrevem diretamente nessas
tabelas.

## 15. Plano de testes futuro

### 15.1 Contrato

- As três implementações fake satisfazem exatamente as interfaces.
- `ProviderSuccess<T>` e `ProviderFailure` são discriminados por `ok`.
- Toda operação assíncrona retorna `ProviderResult`; nenhum erro esperado é
  lançado.
- DTOs e códigos de fornecedores não vazam para tipos normalizados.
- Campos obrigatórios, tipos, reason codes e timestamps são validados.
- Correlation ID atravessa sucesso e erro.
- Metadata fora da allowlist é rejeitada.

### 15.2 Fakes determinísticos

- Cada scenario code retorna sempre os mesmos IDs, estados e timestamps para a
  mesma entrada e relógio.
- `MANUAL_VERIFIED` não é retornado por provider automático nem fake.
- Não há rede, Supabase, filesystem, secret, aleatoriedade ou dado real.
- Liveness isolado não produz `IDENTITY_VERIFIED`.
- Documento inválido e face sem match não confirmam fraude.
- Background adverso produz revisão, nunca auto-deny.

### 15.3 Timeout, retry e indisponibilidade

- Timeout respeita o limite de cada operação.
- Uma chamada produz uma única tentativa; provider e fake não repetem
  internamente.
- Harness de orquestrador prova retry com a mesma idempotency key e fingerprint.
- Backoff, jitter e limite são exercitados somente no teste do orquestrador.
- Clock fake executa timeout e backoff com zero espera de tempo real.
- Limite de retry encerra em resultado técnico/revisão, sem negativa.
- Provider indisponível não cria case, signal ou elegibilidade.

### 15.4 Idempotência

- Mesma chave e mesmo input retornam o mesmo ID e resultado lógico.
- Fingerprint canônico permanece estável apesar da ordem das chaves JSON e da
  normalização equivalente de timestamps UTC.
- Mesma chave e fingerprint diferente retornam `ProviderFailure` com
  `CONFLICT`.
- Retry não duplica sessão, consulta ou mensagem.
- Leituras repetidas são estáveis com relógio congelado.

### 15.5 Sanitização e isolamento

- Logs e metadata rejeitam aliases de PII e payload bruto.
- Nenhuma imagem ou biometria aparece em memória persistente, fixture gerada,
  snapshot ou relatório de teste.
- Contexto de tenant A não recupera resultado criado para tenant B.
- IDs e idempotency keys não permitem colisão cross-tenant.
- Stores distintos isolam instâncias e não existe estado global.
- `clear()` remove deterministicamente todos os registros da instância.
- Testes paralelos com stores/clocks próprios não interferem entre si.
- Limite de registros é aplicado deterministicamente.
- Mensagem não contém dado sensível ou resultado de análise.
- Fingerprint e IDs fake não contêm PII; o fake não calcula hash de PII.

### 15.6 Preservação do domínio

- Nenhum fake decide elegibilidade.
- Nenhum cenário ativa signal ou cria case.
- `AUTO_DENY_NETWORK` não existe nos tipos ou resultados.
- Features continuam desligadas.
- Testes existentes das Fases 1A, 1B e 1C permanecem verdes.

## 16. Gates de uma execução futura

Uma implementação da Fase 1D só poderá ser aceita quando:

1. houver `CURRENT_TASK.md` versionado autorizando paths, branch e base SHA;
2. os contratos forem aprovados antes de adapters reais;
3. Deno format, lint, type-check e testes passarem;
4. todos os cenários fake forem determinísticos;
5. testes comprovarem timeout, retry, idempotência e tenant isolation;
6. varredura comprovar ausência de PII, biometria, secrets e payload bruto;
7. não houver rede, Supabase, endpoint público ou provider real;
8. workflows 1A, 1B e 1C permanecerem verdes;
9. features permanecerem desligadas;
10. revisão humana confirmar ausência de auto-deny e busca 1:N.

## 17. Condições de parada e blockers

Parar sem contornar o problema se:

- a implementação exigir migration, alteração de schema ou migration remota;
- for necessário habilitar feature ou integrar Supabase;
- um contrato exigir PII em log, metadata, audit ou outbox;
- um provider exigir persistir imagem biométrica ou payload bruto;
- o fake depender de rede, secret, SDK externo ou dado real;
- a solução exigir endpoint público, webhook ou Edge Function operacional;
- background adverso for mapeado para negativa automática;
- liveness isolado for tratado como identidade verificada;
- houver busca 1:N, correlação facial global ou `AUTO_DENY_NETWORK`;
- a solução exigir alterar `persons`, app Expo ou UI;
- o contrato não puder garantir idempotência e isolamento por tenant;
- testes existentes das Fases 1A, 1B ou 1C regredirem.

## 18. Fora de escopo explícito

- Implementar a Fase 1D a partir deste plano.
- Provider ou adapter real.
- Credencial, secret, SDK ou chamada externa.
- DataTrust, BigDataCorp, Datavalid ou WhatsApp operacionais.
- API, endpoint público, webhook, polling ou Edge Function.
- Orquestrador de identidade, background ou mensageria.
- Persistência de provider, migration ou alteração de schema.
- Processador de outbox, fila, cron ou job.
- HMAC real, criptografia de aplicação ou gestão de chaves.
- Captura de documento, selfie, vídeo, liveness ou face match reais.
- Busca facial 1:N, biometria global ou pesquisa de pessoa na rede.
- Background real, certidão real ou decisão humana operacional.
- Convite ou notificação operacional, inclusive WhatsApp.
- API pública, UI administrativa ou app Expo.
- Alteração de `persons`.
- Migration remota ou feature habilitada.
- Solicitação do morador, credencial, QR Code, portaria ou check-in/out.
- Fase 2 ou qualquer etapa posterior.

## 19. Condição de autorização futura

A Fase 1D só começa quando um novo contrato versionado substituir
`CURRENT TASK — NO ACTIVE IMPLEMENTATION` e autorizar explicitamente arquivos,
interfaces, testes, CI, branch, base SHA, gates e formato de relatório.

Este documento, isoladamente, não autoriza execução técnica.
