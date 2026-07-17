# Plano de Execução — Fase 1 do Acesso Verificado e Rede Confia

> **Documento complementar à especificação principal**
> **Versão:** 2.0
> **Data:** 14 de julho de 2026
> **Projeto:** Confia
> **Repositório-alvo desta fase:** `C:\Projetos\Confia\repo-github`
> **Especificação principal:** `C:\Projetos\Confia\ACESSO_VERIFICADO_VISITANTES_PRESTADORES\ESPECIFICACAO_ACESSO_VERIFICADO_VISITANTES_PRESTADORES.md`
> **Status:** pronto para execução incremental no Codex
> **Substitui integralmente:** versão 1.0 deste plano

---

## 0. Finalidade e precedência

Este documento transforma a descoberta da Fase 0 e as decisões posteriores sobre a **Rede Confia** em um plano executável, específico para a arquitetura real do projeto.

O Codex deve ler:

1. a especificação funcional e técnica principal;
2. este plano de execução;
3. os `AGENTS.md` existentes no repositório que estiver sendo alterado.

Este documento não substitui a especificação funcional completa. Porém, em caso de conflito, ele **substitui qualquer regra anterior que limitava a deduplicação exclusivamente ao mesmo `condominium_id`**.

A nova decisão é:

> Os dados operacionais e os perfis de identidade permanecem isolados por condomínio. A plataforma poderá manter, opcionalmente, uma identidade pseudonimizada em nível de rede para correlação antifraude e sinais de segurança. Negativas locais não serão propagadas. Somente sinais objetivos, fundamentados, revisados, temporários e contestáveis poderão produzir efeitos em outros condomínios.

A Fase 1 passa a ter quatro entregas independentes:

- **Fase 1A — fundação local do Acesso Verificado;**
- **Fase 1B — fundação pseudonimizada da Rede Confia;**
- **Fase 1C — invariantes, políticas, auditoria e outbox;**
- **Fase 1D — contratos internos e providers fake.**

Não executar todas as subfases em uma única alteração. Cada subfase deve ser revisada e aprovada antes da próxima.

---

# 1. Decisão estratégica: Rede Confia

## 1.1 Proposta de valor

A Confia poderá reconhecer, de forma protegida, que uma identidade já foi verificada em outro condomínio participante e que existe um sinal de segurança relevante associado a ela.

O valor estratégico é o efeito de rede:

```text
Uma fraude de identidade confirmada em um condomínio
        ↓
gera um sinal de segurança revisado e temporário
        ↓
outros condomínios participantes exigem revalidação ou revisão
        ↓
nenhuma nova credencial é emitida enquanto o caso não for resolvido
```

O produto não deve ser descrito internamente como uma lista de “pessoas indesejadas” ou “pessoas não íntegras”.

A semântica correta é:

```text
IDENTIDADE DE REDE
+
SINAL OBJETIVO DE SEGURANÇA
+
POLÍTICA CONFIGURADA PELO CONDOMÍNIO
+
REVISÃO E CONTESTAÇÃO
```

## 1.2 Regra central

A seguinte regra é obrigatória:

```text
LOCAL_DENIED não cria NETWORK_SIGNAL.
```

Uma decisão local pode decorrer de cancelamento, horário, falta de autorização, regra interna, indisponibilidade técnica ou qualquer outro contexto que não deva afetar terceiros.

Somente um caso de segurança devidamente apurado poderá originar um sinal de rede.

## 1.3 Eventos que não podem ser propagados

| Evento local | Efeito na Rede Confia |
|---|---|
| Morador cancelou a visita | Nenhum |
| Chegada fora da janela autorizada | Nenhum |
| Prestador não estava autorizado para aquele serviço | Nenhum |
| Condomínio aplicou uma política local mais restritiva | Nenhum |
| Falha de câmera ou prova de vida | Nenhum |
| Provider indisponível | Nenhum |
| Certidão não emitida | Nenhum bloqueio de rede |
| Homonímia | Nenhum sinal ativo |
| Resultado inconclusivo | Nenhum sinal ativo |
| Morador ou síndico simplesmente não deseja receber a pessoa | Nenhum |
| Negativa manual sem evento objetivo de segurança | Nenhum |

## 1.4 Eventos que podem originar um caso de segurança

A abertura de um caso ainda não produz efeito em outros condomínios.

Categorias iniciais permitidas:

```text
IDENTITY_IMPERSONATION_SUSPECTED
DOCUMENT_FRAUD_SUSPECTED
CREDENTIAL_COMPROMISE_SUSPECTED
ACCOUNT_TAKEOVER_SUSPECTED
REPEATED_IDENTITY_MANIPULATION_SUSPECTED
PLATFORM_SECURITY_INCIDENT
OFFICIAL_SOURCE_REVALIDATION_REQUIRED
```

Após apuração, um caso substanciado poderá gerar um sinal com uma das categorias:

```text
IDENTITY_IMPERSONATION_CONFIRMED
DOCUMENT_FRAUD_CONFIRMED
CREDENTIAL_COMPROMISED
ACCOUNT_TAKEOVER_CONFIRMED
REPEATED_IDENTITY_MANIPULATION_CONFIRMED
PLATFORM_SECURITY_SUSPENSION
OFFICIAL_SOURCE_REVALIDATION_REQUIRED
```

Não criar categorias vagas ou moralizantes, como:

```text
DANGEROUS_PERSON
BAD_PERSON
UNTRUSTWORTHY
UNWANTED
NOT_INTEGRAL
CRIMINAL_PERSON
```

## 1.5 Efeitos permitidos de um sinal

Um sinal ativo pode solicitar somente:

```text
INFORM_AUTHORIZED_REVIEWER
REVALIDATE_IDENTITY
REQUERY_OFFICIAL_SOURCE
REQUIRE_MANUAL_REVIEW
HOLD_CREDENTIAL
```

Não implementar:

```text
AUTO_DENY_NETWORK
GLOBAL_DENIED
PERMANENT_BLACKLIST
```

`HOLD_CREDENTIAL` significa:

- não emitir uma nova credencial;
- manter o caso em revisão;
- permitir correção, contestação e revalidação;
- não declarar automaticamente que a pessoa está proibida em definitivo.

## 1.6 Regra de visibilidade

Um condomínio não poderá consultar:

- quais outros condomínios a pessoa visitou;
- quem registrou um caso;
- o histórico de decisões de outro condomínio;
- documentos, fotos ou certidões de outro tenant;
- detalhes livres da acusação;
- identidade de denunciantes;
- evidências brutas.

A superfície operacional deve retornar apenas um resultado normalizado, por exemplo:

```text
NO_ACTIVE_NETWORK_SIGNAL
NETWORK_REVALIDATION_REQUIRED
NETWORK_MANUAL_REVIEW_REQUIRED
NETWORK_CREDENTIAL_HOLD
NETWORK_SIGNAL_EXPIRED
NETWORK_SIGNAL_REVOKED
```

## 1.7 Decisão final

Cada condomínio mantém sua política de acesso.

Entretanto, quando a política configurada utilizar `HOLD_CREDENTIAL`, a Confia não emitirá credencial até que a revisão exigida seja concluída.

A Confia não copiará uma negativa local. Ela aplicará uma regra de segurança da rede com justificativa técnica, validade, auditoria e possibilidade de contestação.

---

# 2. Descobertas aprovadas da Fase 0

As decisões deste plano partem dos seguintes fatos levantados no workspace:

- `C:\Projetos\Confia` não é a raiz de um único repositório Git.
- Os repositórios reais são:
  - `repo-github`: Supabase, Edge Functions e backoffice;
  - `confia-interfone-app`: Expo/React Native.
- `repo-github` já possui alterações locais anteriores à implementação.
- O backend usa:
  - Supabase Postgres 17;
  - Auth;
  - RLS;
  - RPCs transacionais `security definer`;
  - Storage privado;
  - Realtime;
  - Edge Functions Deno 2.
- O tenant é o próprio condomínio e é representado por `condominium_id`.
- `current_user_condominium_id()` resolve o condomínio do usuário autenticado.
- Existe o mecanismo `condominium_features` e a função `condominium_feature_enabled`.
- Não existe outbox genérica.
- Não existe adapter de WhatsApp.
- Não existe provider de identidade ou background check.
- Não existe QR de acesso, credencial temporária ou check-in/check-out de visitantes.
- A tabela existente `persons` representa contatos locais de unidade e não deve ser reutilizada como identidade sensível.
- O backoffice atual não possui autenticação e RBAC suficientes para revisão de dados sensíveis.
- As Edge Functions atuais usam `verify_jwt = false` e fazem validação internamente.
- Não existe uma suíte automatizada madura; a nova capacidade deve criar cobertura desde o início.

---

# 3. Regras de segurança operacional para o Codex

Antes de qualquer alteração:

1. Trabalhar somente dentro do repositório indicado pelo prompt da subfase.
2. Na Fase 1, o repositório padrão é `C:\Projetos\Confia\repo-github`.
3. Executar e registrar:
   - `git status --short`;
   - `git branch --show-current`;
   - `git diff --stat`.
4. Não executar:
   - `git reset`;
   - `git restore` sobre arquivos não criados nesta tarefa;
   - `git clean`;
   - `git stash`;
   - rebase;
   - commit;
   - push.
5. Não sobrescrever alterações locais preexistentes.
6. Não alterar `confia-interfone-app` nesta fase.
7. Não alterar UI do backoffice nesta fase.
8. Não executar migrations em ambiente remoto.
9. Não usar dados pessoais reais.
10. Não criar Edge Function pública nesta fase.
11. Não adicionar provider real, credencial, secret ou chamada externa.
12. Não alterar a tabela legada `persons`.
13. Não ativar nenhuma feature para condomínios automaticamente.
14. Não criar correlação de rede baseada apenas em nome, telefone, data de nascimento ou selfie.
15. Não armazenar template biométrico, embedding facial ou hash de face para correlação entre condomínios.
16. Não criar uma API que permita procurar uma pessoa na rede.
17. Não criar RPC de decisão humana ou ativação de sinal enquanto o RBAC reforçado não estiver resolvido.

No relatório final, o Codex deve separar:

- arquivos que já estavam modificados antes;
- arquivos criados ou modificados pela subfase;
- arquivos deliberadamente não alterados;
- validações executadas;
- limitações que permaneceram.

---

# 4. Decisões arquiteturais vinculantes

## ADR-VA-001 — Limites dos repositórios

A Fase 1 modifica somente `repo-github`.

O aplicativo Expo e as telas administrativas serão tratados em fases posteriores. Não criar dependências cruzadas, cópias de tipos ou stubs no app nesta fase.

## ADR-VA-002 — Fonte de verdade do domínio

O Postgres/Supabase será a fonte de verdade para:

- solicitações;
- vagas;
- participantes;
- políticas;
- estados;
- avaliações de elegibilidade;
- auditoria;
- outbox;
- sujeitos pseudonimizados de rede;
- casos e sinais de segurança.

Regras transacionais críticas devem permanecer em constraints, triggers e RPCs, seguindo o padrão atual do repositório.

Edge Functions serão usadas posteriormente para:

- comunicação externa;
- webhooks;
- jobs;
- providers;
- criptografia de aplicação;
- HMAC e correlação;
- endpoints públicos.

Nenhuma Edge Function deve se tornar a única responsável por uma invariante que possa ser garantida no banco.

## ADR-VA-003 — Namespace

Todos os objetos novos devem usar o prefixo:

```text
verified_access_
```

Exemplos:

```text
verified_access_requests
verified_access_identity_profiles
verified_access_network_subjects
verified_access_outbox_events
```

Não criar tabelas genéricas chamadas `persons`, `events`, `policies`, `signals` ou `outbox`.

## ADR-VA-004 — Separação entre domínio local e domínio de rede

O modelo terá duas camadas.

### Camada local do condomínio

Contém:

- solicitação;
- vaga;
- participante;
- perfil de identidade criptografado;
- política;
- decisão local;
- eventos operacionais.

Todas as tabelas locais carregam `condominium_id`.

### Camada pseudonimizada da Rede Confia

Contém:

- sujeito de rede;
- identificadores HMAC;
- vínculos com perfis locais;
- casos de segurança;
- sinais;
- revisões;
- contestações.

As tabelas centrais de rede não são pertencentes a um único condomínio e não devem ser expostas por RLS a usuários de tenant.

## ADR-VA-005 — Feature flags

Usar o mecanismo existente `condominium_features`.

Cadastrar, sem habilitar automaticamente:

```text
VERIFIED_ACCESS
VERIFIED_ACCESS_NETWORK_IDENTITY
VERIFIED_ACCESS_NETWORK_SIGNALS
VERIFIED_ACCESS_NETWORK_HOLD
VERIFIED_ACCESS_BACKGROUND_CHECK
```

Dependências:

```text
VERIFIED_ACCESS_NETWORK_IDENTITY
    depende de VERIFIED_ACCESS

VERIFIED_ACCESS_NETWORK_SIGNALS
    depende de VERIFIED_ACCESS_NETWORK_IDENTITY

VERIFIED_ACCESS_NETWORK_HOLD
    depende de VERIFIED_ACCESS_NETWORK_SIGNALS

VERIFIED_ACCESS_BACKGROUND_CHECK
    depende de VERIFIED_ACCESS
```

Regras:

- todas desligadas por padrão;
- nenhuma migration habilita condomínio existente;
- não criar um segundo sistema de feature flags;
- integrações reais também exigirão kill switch de ambiente;
- `NETWORK_HOLD` não pode funcionar antes dos gates jurídicos e de revisão.

## ADR-VA-006 — Dados pessoais locais

A tabela legada `persons` não será reutilizada.

Criar:

```text
verified_access_identity_profiles
```

Nenhuma coluna de PII deve ser armazenada em texto aberto.

Usar:

- campos criptografados em `bytea`;
- HMAC local em colunas separadas;
- `encryption_key_version`;
- `hmac_key_version`;
- criptografia e descriptografia em Edge Function;
- nenhum secret no banco, migration ou repositório;
- nenhuma função SQL de descriptografia.

## ADR-VA-007 — Identidade de rede

A correlação global será representada por um sujeito pseudonimizado.

Não armazenar CPF aberto no domínio de rede.

O identificador de rede deve ser calculado com HMAC usando uma chave exclusiva da plataforma e contexto específico.

Exemplo conceitual:

```text
canonical_identifier
    = "CPF|12345678909"

network_hmac
    = HMAC(platform_network_key_vN, canonical_identifier)
```

Não implementar SHA-256 simples de CPF. CPF possui espaço de busca pequeno e um hash sem segredo é suscetível a enumeração.

A criação ou vinculação de um sujeito de rede só pode ocorrer depois de uma identidade atingir o nível mínimo configurado, preferencialmente:

```text
DOCUMENT_VERIFIED
ou
IDENTITY_VERIFIED
```

Um CPF apenas digitado pelo participante não pode criar vínculo global.

## ADR-VA-008 — Identificadores aceitos

Identificadores iniciais:

```text
CPF
RNM
PASSPORT_WITH_ISSUER
```

Para passaporte, a canonicalização deve incluir país emissor.

Não usar como identificador global isolado:

- nome;
- telefone;
- e-mail;
- data de nascimento;
- nome da mãe;
- fotografia;
- template biométrico;
- embedding facial;
- endereço.

## ADR-VA-009 — Não realizar reconhecimento facial entre condomínios

A biometria será usada para autenticação e comparação 1:1 com documento ou referência válida.

Não criar:

- galeria facial global;
- busca 1:N de visitantes;
- embedding facial de rede;
- comparação de uma face contra todos os visitantes;
- identificação silenciosa por câmera;
- deduplicação de rede baseada em rosto.

## ADR-VA-010 — Negativa local não é sinal de rede

Nenhuma destas ações cria automaticamente caso ou sinal:

```text
CANCEL_REQUEST
LOCAL_DENY
OUTSIDE_ACCESS_WINDOW
NO_LOCAL_AUTHORIZATION
PROVIDER_TIMEOUT
LIVENESS_TECHNICAL_ERROR
BACKGROUND_INCONCLUSIVE
MANUAL_LOCAL_DECISION
```

O sistema deve exigir uma operação específica de abertura de caso, com categoria permitida, origem, evidência e auditoria.

Essa operação será implementada somente depois do RBAC e da governança.

## ADR-VA-011 — Casos e sinais são entidades diferentes

Um caso representa uma investigação.

Um sinal representa uma conclusão operacional temporária.

Fluxo:

```text
REPORTED CASE
    ↓
TRIAGE
    ↓
UNDER_REVIEW
    ↓
SUBSTANTIATED ou DISMISSED
    ↓
DRAFT SIGNAL
    ↓
INDEPENDENT REVIEWS
    ↓
ACTIVE SIGNAL
```

Um caso aberto nunca deve afetar automaticamente outro condomínio.

## ADR-VA-012 — Sem negativa automática de rede

Mesmo um sinal ativo não gera `DENIED_MANUAL`.

O efeito máximo automático permitido é:

```text
NETWORK_CREDENTIAL_HOLD
```

A credencial permanece não emitida enquanto houver revisão ou revalidação exigida.

Uma negativa definitiva exige decisão humana autorizada, motivo estruturado e auditoria.

## ADR-VA-013 — Expiração, revogação e correção

Todo sinal deve possuir:

- início de validade;
- expiração;
- revisão periódica;
- possibilidade de suspensão;
- possibilidade de revogação;
- trilha de decisão;
- canal de contestação.

Quando um sinal for revogado ou corrigido, a outbox deve publicar um evento para reavaliar todas as autorizações pendentes afetadas.

Não criar sinal permanente sem data de expiração.

## ADR-VA-014 — Outbox própria

Criar:

```text
verified_access_outbox_events
```

Ela será gravada na mesma transação das mudanças relevantes.

Nesta fase:

- criar tabela, constraints, índices e helpers;
- não criar processador externo;
- não criar framework genérico;
- não migrar processadores existentes;
- payload somente com IDs, códigos e metadados sanitizados;
- nunca inserir CPF, nome, telefone, documento, token, certidão ou biometria.

O processamento posterior seguirá o padrão atual:

```text
GitHub Actions ou pg_cron
        ↓
Edge Function autenticada com segredo interno
        ↓
claim transacional da outbox
        ↓
provider ou serviço interno
```

## ADR-VA-015 — Estados

Seguir o padrão dominante do repositório.

Na ausência de convenção clara:

```text
text + CHECK constraint
```

em vez de enum nativo do Postgres.

Transições críticas serão protegidas no banco.

## ADR-VA-016 — Autorização e revisão sensível

Não implementar ainda:

- decisão humana de background;
- ativação de sinal de rede por usuário do backoffice;
- consulta detalhada de caso;
- exibição de evidências;
- contestação pública;
- pesquisa global de sujeitos.

O backoffice atual, baseado em `BACKOFFICE_USERS_JSON`, não atende sozinho aos requisitos.

Gate obrigatório:

- identidade estável do operador;
- papel específico `REVIEWER`;
- autenticação reforçada;
- MFA ou mecanismo equivalente aprovado;
- rate limit;
- sessão auditável;
- escopo de acesso;
- registro de visualização;
- separação de funções;
- dupla aprovação em sinais de alta criticidade.

A Fase 1 pode preparar os campos e constraints, mas não abrir as operações.

## ADR-VA-017 — RLS padrão-deny

Todas as novas tabelas terão RLS habilitada.

Nesta fase:

- `anon` não acessa nenhuma tabela;
- `authenticated` não escreve diretamente;
- dados sensíveis não possuem `SELECT` direto;
- tabelas centrais de rede não são visíveis ao tenant;
- operações futuras serão expostas por RPCs específicas;
- funções `security definer` terão `search_path` fixo;
- execução será revogada de `public`;
- grants serão mínimos.

Não criar:

```sql
USING (true)
```

## ADR-VA-018 — Providers fake

Criar contratos e fakes determinísticos, sem rede e sem aleatoriedade.

Nenhum fake será conectado a Edge Function pública nesta fase.

Cenários de identidade:

```text
SUCCESS
PENDING
INCONCLUSIVE
TECHNICAL_ERROR
EXPIRED
LIVENESS_ONLY
DOCUMENT_INCONCLUSIVE
FACE_NO_MATCH
```

Cenários de background:

```text
NEGATIVE
PENDING
ADVERSE_REVIEW
MANUAL_CONFIRMATION
INCONCLUSIVE
PROVIDER_ERROR
EXPIRED
```

Nenhum fake produz negativa automática.

## ADR-VA-019 — Testes desde a fundação

Criar a menor infraestrutura de testes compatível com o Supabase CLI do projeto.

Preferência:

- testes SQL/RPC locais;
- pgTAP quando suportado;
- testes Deno nativos;
- fixtures sintéticas;
- testes negativos de tenant isolation;
- testes específicos de não propagação de negativas locais.

Não iniciar Playwright na Fase 1.

## ADR-VA-020 — Gate de governança da Rede Confia

As estruturas da Rede Confia podem ser implementadas inertes.

Não ativar produção até existirem:

- RIPD específico da rede;
- definição do papel da Confia e dos condomínios;
- base legal e finalidades documentadas;
- aviso de privacidade específico;
- política de retenção;
- política de categorias;
- procedimento de apuração;
- canal de correção e contestação;
- processo de resposta a incidente;
- contrato e responsabilidades;
- aprovação formal da operação.

---

# 5. Arquitetura-alvo

## 5.1 Fluxo local

```text
Morador
    ↓
Solicitação no condomínio
    ↓
Vagas e participantes
    ↓
Cadastro individual
    ↓
Identidade e background
    ↓
Elegibilidade local
    ↓
Credencial
    ↓
Portaria
```

## 5.2 Correlação de rede

```text
Identidade local verificada
    ↓
Identificador canônico validado
    ↓
HMAC de rede em Edge Function
    ↓
Network Subject
    ↓
Link pseudonimizado com perfil local
```

Os dados pessoais continuam no perfil local criptografado.

## 5.3 Caso e sinal

```text
Incidente local ou de plataforma
    ↓
Caso de segurança
    ↓
Triagem
    ↓
Apuração
    ↓
Caso substanciado
    ↓
Proposta de sinal
    ↓
Revisão independente
    ↓
Sinal ativo com expiração
```

## 5.4 Avaliação em outro condomínio

```text
Novo participante verificado
    ↓
Resolução do Network Subject
    ↓
Consulta interna de sinais ativos
    ↓
Política do condomínio
    ↓
Sem sinal:
    fluxo normal

Sinal REVALIDATE_IDENTITY:
    nova validação

Sinal REQUERY_OFFICIAL_SOURCE:
    nova consulta

Sinal REQUIRE_MANUAL_REVIEW:
    NETWORK_REVIEW_REQUIRED

Sinal HOLD_CREDENTIAL:
    NETWORK_CREDENTIAL_HOLD
    nenhuma credencial é emitida
```

A API destinada ao tenant não devolve o histórico da rede. Ela devolve somente a ação normalizada.

---

# 6. Escopo total da Fase 1

Ao final das Fases 1A a 1D, devem existir:

- feature base e features de rede cadastradas e desligadas;
- ADRs;
- catálogo de serviços;
- política versionada com configuração local e de rede;
- solicitação;
- detalhe de prestador;
- vagas;
- participantes;
- perfil local de identidade sensível;
- sujeito pseudonimizado de rede;
- identificadores de rede;
- vínculos entre identidade local e rede;
- casos;
- sinais;
- revisões;
- contestações;
- avaliações de elegibilidade;
- estados normalizados;
- validação de transições;
- auditoria;
- outbox;
- contratos de providers;
- providers fake;
- testes SQL e Deno;
- documentação de rollback.

Não deve existir ainda:

- tela;
- endpoint público;
- convite;
- WhatsApp real;
- token público;
- coleta de CPF;
- biometria real;
- consulta criminal real;
- pesquisa de pessoa na rede;
- ativação operacional de sinal;
- revisão humana real;
- QR Code;
- credencial;
- check-in;
- check-out;
- integração externa.

---

# 7. Modelo local de dados

Os nomes abaixo são recomendados e só devem ser adaptados para seguir uma convenção consolidada encontrada no repositório.

## 7.1 `verified_access_service_types`

Catálogo global controlado pelo produto.

Campos mínimos:

```text
id uuid PK
code text UNIQUE NOT NULL
default_name text NOT NULL
requires_description boolean NOT NULL DEFAULT false
is_active boolean NOT NULL DEFAULT true
sort_order integer NOT NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Seeds:

```text
CONSTRUCTION
GARDENING
PLUMBING
ELECTRICAL
POOL
CLEANING
ELEVATOR_MAINTENANCE
TELECOM
DELIVERY_ASSEMBLY
OTHER
```

`OTHER` deve possuir `requires_description = true`.

## 7.2 `verified_access_condominium_service_types`

Customização por condomínio.

```text
condominium_id uuid NOT NULL
service_type_id uuid NOT NULL
is_enabled boolean NOT NULL DEFAULT true
display_name_override text NULL
sort_order_override integer NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
PRIMARY KEY (condominium_id, service_type_id)
```

## 7.3 `verified_access_policies`

Política versionada por condomínio.

Campos mínimos:

```text
id uuid PK
condominium_id uuid NOT NULL
version integer NOT NULL
status text NOT NULL
schema_version integer NOT NULL DEFAULT 2
timezone text NOT NULL

visitor_identity_mode text NOT NULL
service_identity_mode text NOT NULL
visitor_background_mode text NOT NULL
service_background_mode text NOT NULL

network_identity_mode text NOT NULL
network_signal_mode text NOT NULL
network_signal_min_severity text NOT NULL
network_signal_rules jsonb NOT NULL DEFAULT '[]'
network_hold_enabled boolean NOT NULL DEFAULT false

invitation_ttl_minutes integer NOT NULL
public_session_ttl_minutes integer NOT NULL
max_visitor_participants integer NOT NULL
max_service_participants integer NOT NULL
max_request_duration_minutes integer NOT NULL
min_notice_minutes integer NOT NULL
max_notice_days integer NOT NULL
allow_open_slots boolean NOT NULL

privacy_approval_reference text NULL
background_approval_reference text NULL
network_approval_reference text NULL

retention_settings jsonb NOT NULL DEFAULT '{}'
additional_settings jsonb NOT NULL DEFAULT '{}'
content_checksum text NOT NULL

created_by_actor_type text NOT NULL
created_by_actor_id text NOT NULL
created_at timestamptz NOT NULL
activated_by_actor_type text NULL
activated_by_actor_id text NULL
activated_at timestamptz NULL
retired_at timestamptz NULL
```

Valores:

```text
status:
DRAFT
ACTIVE
RETIRED

identity_mode:
DISABLED
OPTIONAL
REQUIRED

background_mode:
DISABLED
REVIEW_ONLY
REQUIRED

network_identity_mode:
DISABLED
OPTIONAL
REQUIRED

network_signal_mode:
DISABLED
OBSERVE
APPLY_CONFIGURED_EFFECT

severity:
LOW
MEDIUM
HIGH
CRITICAL
```

Constraints:

- versão positiva;
- versão única por condomínio;
- no máximo uma política `ACTIVE`;
- policy ativa imutável;
- background diferente de `DISABLED` exige `background_approval_reference`;
- rede diferente de `DISABLED` exige `network_approval_reference`;
- `network_hold_enabled = true` exige:
  - feature `VERIFIED_ACCESS_NETWORK_HOLD`;
  - `network_signal_mode = APPLY_CONFIGURED_EFFECT`;
  - aprovação formal;
- `network_signal_rules` não pode conter `AUTO_DENY_NETWORK`;
- regras devem referenciar somente categorias e efeitos permitidos.

Exemplo de `network_signal_rules`:

```json
[
  {
    "category": "CREDENTIAL_COMPROMISED",
    "minimumSeverity": "HIGH",
    "effect": "HOLD_CREDENTIAL"
  },
  {
    "category": "OFFICIAL_SOURCE_REVALIDATION_REQUIRED",
    "minimumSeverity": "MEDIUM",
    "effect": "REQUERY_OFFICIAL_SOURCE"
  }
]
```

A estrutura JSON deve ser validada por função ou constraint compatível com o padrão do projeto.

## 7.4 `verified_access_requests`

```text
id uuid PK
condominium_id uuid NOT NULL
unit_id uuid NOT NULL
requested_by_user_id uuid NOT NULL
request_type text NOT NULL
status text NOT NULL
starts_at timestamptz NOT NULL
ends_at timestamptz NOT NULL
timezone text NOT NULL
participant_limit integer NOT NULL
policy_id uuid NOT NULL
notes text NULL
version integer NOT NULL DEFAULT 1
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
cancelled_at timestamptz NULL
expires_at timestamptz NOT NULL
```

Valores:

```text
request_type:
VISITOR
SERVICE_PROVIDER

status:
DRAFT
INVITATIONS_PENDING
IN_PROGRESS
PARTIALLY_ELIGIBLE
ELIGIBLE
COMPLETED
CANCELLED
EXPIRED
```

## 7.5 `verified_access_service_request_details`

```text
request_id uuid PK
condominium_id uuid NOT NULL
service_type_id uuid NOT NULL
other_description text NULL
company_name text NULL
company_document_ciphertext bytea NULL
company_document_hmac text NULL
company_document_hmac_key_version integer NULL
work_description text NULL
destination_area text NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

## 7.6 `verified_access_participant_slots`

```text
id uuid PK
condominium_id uuid NOT NULL
request_id uuid NOT NULL
slot_number integer NOT NULL
status text NOT NULL
claimed_at timestamptz NULL
cancelled_at timestamptz NULL
version integer NOT NULL DEFAULT 1
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Valores:

```text
AVAILABLE
CLAIMED
CANCELLED
```

## 7.7 `verified_access_identity_profiles`

Dados pessoais locais protegidos.

```text
id uuid PK
condominium_id uuid NOT NULL

full_name_ciphertext bytea NULL
full_name_normalized_ciphertext bytea NULL
cpf_ciphertext bytea NULL
cpf_tenant_hmac text NULL
birth_date_ciphertext bytea NULL
mother_name_ciphertext bytea NULL
father_name_ciphertext bytea NULL

document_type text NULL
document_number_ciphertext bytea NULL
document_number_tenant_hmac text NULL
document_issuer_country_ciphertext bytea NULL

phone_ciphertext bytea NULL
phone_tenant_hmac text NULL

encryption_key_version integer NOT NULL
tenant_hmac_key_version integer NOT NULL

identity_assurance_level text NOT NULL
retention_until timestamptz NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Valores de `identity_assurance_level`:

```text
SELF_DECLARED
CONTACT_VERIFIED
DOCUMENT_CAPTURED
DOCUMENT_VERIFIED
LIVENESS_VERIFIED
IDENTITY_VERIFIED
MANUAL_VERIFIED
```

Regras:

- nenhum campo equivalente em plaintext;
- HMAC local único somente dentro do condomínio, quando aplicável;
- nenhuma leitura direta;
- nenhuma descriptografia em SQL;
- `SELF_DECLARED` não pode criar link de rede;
- criação de link de rede exige nível configurado.

## 7.8 `verified_access_participants`

```text
id uuid PK
condominium_id uuid NOT NULL
request_id uuid NOT NULL
slot_id uuid NOT NULL UNIQUE
identity_profile_id uuid NULL

initial_name_ciphertext bytea NULL
phone_ciphertext bytea NULL
phone_tenant_hmac text NULL

registration_status text NOT NULL
identity_status text NOT NULL
background_status text NOT NULL
network_status text NOT NULL
eligibility_status text NOT NULL
eligibility_reason_code text NULL

eligibility_expires_at timestamptz NULL
version integer NOT NULL DEFAULT 1
cancelled_at timestamptz NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Valores:

```text
registration_status:
CREATED
INVITED
LINK_OPENED
DATA_PENDING
DATA_SUBMITTED
CANCELLED
EXPIRED

identity_status:
NOT_STARTED
SESSION_CREATED
PENDING
LIVENESS_VERIFIED
VERIFIED
INCONCLUSIVE
TECHNICAL_ERROR
MANUAL_VERIFIED
EXPIRED

background_status:
NOT_REQUIRED
NOT_STARTED
PENDING
NEGATIVE_CERTIFICATE
ADVERSE_INFORMATION_REVIEW
MANUAL_CONFIRMATION_REQUIRED
INCONCLUSIVE
PROVIDER_ERROR
EXPIRED

network_status:
NOT_ENABLED
NOT_RESOLVED
NO_ACTIVE_SIGNAL
REVALIDATION_REQUIRED
OFFICIAL_REQUERY_REQUIRED
MANUAL_REVIEW_REQUIRED
CREDENTIAL_HOLD
SIGNAL_EXPIRED
SIGNAL_REVOKED
PROVIDER_ERROR

eligibility_status:
PENDING
ELIGIBLE
REVIEW_REQUIRED
NETWORK_REVIEW_REQUIRED
CORRECTION_REQUIRED
DENIED_MANUAL
REVOKED
EXPIRED
```

Regras:

- `DENIED_MANUAL` não pode ser criado por update comum;
- `CREDENTIAL_HOLD` não equivale a `DENIED_MANUAL`;
- rede desabilitada deve resultar em `NOT_ENABLED`;
- negativa local não altera `network_status`;
- participantes cancelados não reabrem.

## 7.9 `verified_access_eligibility_evaluations`

Registro explicável de cada avaliação.

```text
id uuid PK
condominium_id uuid NOT NULL
request_id uuid NOT NULL
participant_id uuid NOT NULL
policy_id uuid NOT NULL
policy_version integer NOT NULL

trigger_event_type text NOT NULL
identity_status text NOT NULL
background_status text NOT NULL
network_status text NOT NULL

outcome text NOT NULL
reason_codes jsonb NOT NULL DEFAULT '[]'
decision_source text NOT NULL
actor_type text NOT NULL
actor_id text NOT NULL

input_snapshot_sanitized jsonb NOT NULL DEFAULT '{}'
created_at timestamptz NOT NULL
```

Valores de `decision_source`:

```text
RULE
HUMAN
SYSTEM_SECURITY
```

Não armazenar:

- CPF;
- nome;
- telefone;
- certidão;
- payload bruto;
- descrição livre de incidente.

## 7.10 `verified_access_outbox_events`

```text
id uuid PK
condominium_id uuid NULL
scope text NOT NULL
aggregate_type text NOT NULL
aggregate_id uuid NOT NULL
event_type text NOT NULL
event_version integer NOT NULL
deduplication_key text NOT NULL UNIQUE
payload_sanitized jsonb NOT NULL
status text NOT NULL
attempt_count integer NOT NULL DEFAULT 0
next_attempt_at timestamptz NOT NULL
locked_at timestamptz NULL
locked_by text NULL
processed_at timestamptz NULL
last_error_code text NULL
created_at timestamptz NOT NULL
```

Valores:

```text
scope:
CONDOMINIUM
NETWORK
PLATFORM

status:
PENDING
PROCESSING
PROCESSED
FAILED
DEAD_LETTER
```

`condominium_id` é obrigatório quando `scope = CONDOMINIUM` e deve ser nulo ou apenas informativo controlado nos eventos centrais conforme decisão implementada.

## 7.11 `verified_access_audit_events`

```text
id uuid PK
condominium_id uuid NULL
scope text NOT NULL
aggregate_type text NOT NULL
aggregate_id uuid NOT NULL
event_type text NOT NULL
actor_type text NOT NULL
actor_id text NOT NULL
reason_code text NULL
correlation_id uuid NULL
metadata_sanitized jsonb NOT NULL DEFAULT '{}'
occurred_at timestamptz NOT NULL
created_at timestamptz NOT NULL
```

Valores iniciais:

```text
scope:
CONDOMINIUM
NETWORK
PLATFORM

actor_type:
AUTH_USER
BACKOFFICE_USER
SYSTEM
PROVIDER
CRON
PRIVACY_OFFICER
```

Auditoria é append-only.

---

# 8. Modelo pseudonimizado da Rede Confia

## 8.1 `verified_access_network_subjects`

Representa uma pessoa correlacionável sem conter seus dados civis.

```text
id uuid PK
status text NOT NULL
identity_assurance_level text NOT NULL
first_verified_at timestamptz NOT NULL
last_verified_at timestamptz NOT NULL
revalidation_due_at timestamptz NULL
retention_until timestamptz NULL
merged_into_subject_id uuid NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Valores:

```text
status:
ACTIVE
UNDER_REVIEW
DISPUTED
MERGED
RETIRED
```

Não armazenar nesta tabela:

- nome;
- CPF;
- data de nascimento;
- telefone;
- fotografia;
- biometria;
- documento;
- filiação;
- endereço.

## 8.2 `verified_access_network_subject_identifiers`

Permite rotação de HMAC e identificadores múltiplos.

```text
id uuid PK
network_subject_id uuid NOT NULL
identifier_type text NOT NULL
identifier_hmac text NOT NULL
hmac_key_version integer NOT NULL
canonicalization_version integer NOT NULL
status text NOT NULL
is_primary boolean NOT NULL DEFAULT false
verified_at timestamptz NOT NULL
expires_at timestamptz NULL
revoked_at timestamptz NULL
created_at timestamptz NOT NULL
```

Valores:

```text
identifier_type:
CPF
RNM
PASSPORT_WITH_ISSUER

status:
ACTIVE
ROTATING
REVOKED
EXPIRED
```

Constraints:

- identificador HMAC único por tipo, versão e valor;
- um identificador ativo não aponta para dois sujeitos;
- HMAC não pode ser calculado no banco;
- nenhum dado canônico é armazenado;
- rotação preserva a vinculação ao mesmo sujeito;
- identificador revogado não resolve novos vínculos.

## 8.3 `verified_access_network_subject_links`

Vínculo entre perfil local e sujeito de rede.

```text
id uuid PK
network_subject_id uuid NOT NULL
condominium_id uuid NOT NULL
identity_profile_id uuid NOT NULL
link_status text NOT NULL
link_reason text NOT NULL
identity_assurance_level text NOT NULL
linked_at timestamptz NOT NULL
unlinked_at timestamptz NULL
created_at timestamptz NOT NULL
```

Valores:

```text
link_status:
ACTIVE
DISPUTED
UNLINKED

link_reason:
IDENTITY_VERIFIED
MANUAL_VERIFIED
IDENTIFIER_ROTATION
SUBJECT_MERGE
CORRECTION
```

Regras:

- um perfil local possui no máximo um link ativo;
- o perfil deve pertencer ao condomínio informado;
- link exige assurance suficiente;
- tenant não pode consultar links de outros condomínios;
- usuário de tenant não recebe `network_subject_id`.

## 8.4 `verified_access_network_security_cases`

Caso de apuração.

```text
id uuid PK
network_subject_id uuid NOT NULL
source_type text NOT NULL
source_condominium_id uuid NULL
source_participant_id uuid NULL

category text NOT NULL
severity text NOT NULL
status text NOT NULL
evidence_assurance_level text NOT NULL
summary_code text NOT NULL

reported_by_actor_type text NOT NULL
reported_by_actor_id text NOT NULL
reported_at timestamptz NOT NULL

triaged_by_actor_id text NULL
triaged_at timestamptz NULL
review_due_at timestamptz NULL
substantiated_at timestamptz NULL
dismissed_at timestamptz NULL
closed_at timestamptz NULL

evidence_reference_hash text NULL
metadata_sanitized jsonb NOT NULL DEFAULT '{}'
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Valores:

```text
source_type:
CONDOMINIUM_REPORT
PLATFORM_SECURITY
IDENTITY_PROVIDER
BACKGROUND_PROVIDER
PRIVACY_CORRECTION

status:
REPORTED
TRIAGE
UNDER_REVIEW
SUBSTANTIATED
DISMISSED
CLOSED
EXPIRED
```

Regras:

- caso `REPORTED`, `TRIAGE` ou `UNDER_REVIEW` não produz efeito de rede;
- `SUBSTANTIATED` exige revisão autorizada futura;
- `DISMISSED` não pode gerar sinal;
- evidência bruta não vai para JSON;
- `source_condominium_id` não será exposto a outros tenants;
- background adverso pode abrir caso, mas não substanciá-lo automaticamente.

## 8.5 `verified_access_network_signals`

Conclusão operacional temporária.

```text
id uuid PK
network_subject_id uuid NOT NULL
source_case_id uuid NOT NULL
category text NOT NULL
severity text NOT NULL
effect text NOT NULL
status text NOT NULL

policy_version integer NOT NULL
reason_code text NOT NULL
valid_from timestamptz NOT NULL
expires_at timestamptz NOT NULL
review_due_at timestamptz NOT NULL

proposed_by_actor_type text NOT NULL
proposed_by_actor_id text NOT NULL
proposed_at timestamptz NOT NULL

activated_by_actor_id text NULL
activated_at timestamptz NULL
suspended_at timestamptz NULL
revoked_at timestamptz NULL
revocation_reason_code text NULL

created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Valores:

```text
status:
DRAFT
UNDER_REVIEW
ACTIVE
SUSPENDED
REVOKED
EXPIRED
REJECTED

effect:
INFORM_AUTHORIZED_REVIEWER
REVALIDATE_IDENTITY
REQUERY_OFFICIAL_SOURCE
REQUIRE_MANUAL_REVIEW
HOLD_CREDENTIAL
```

Constraints:

- `expires_at > valid_from`;
- nenhum sinal sem expiração;
- sinal só pode ser proposto a partir de caso `SUBSTANTIATED`;
- `DISMISSED` não origina sinal;
- `ACTIVE` exige revisões suficientes;
- ator que propôs não pode sozinho satisfazer todas as aprovações;
- `REVOKED` e `EXPIRED` não afetam novas avaliações;
- `HOLD_CREDENTIAL` nunca vira `DENIED_MANUAL`;
- não existe efeito `AUTO_DENY_NETWORK`.

## 8.6 `verified_access_network_signal_reviews`

```text
id uuid PK
signal_id uuid NOT NULL
reviewer_actor_id text NOT NULL
reviewer_role text NOT NULL
decision text NOT NULL
reason_code text NOT NULL
reviewed_at timestamptz NOT NULL
created_at timestamptz NOT NULL
UNIQUE (signal_id, reviewer_actor_id)
```

Valores:

```text
decision:
APPROVE
REJECT
REQUEST_CHANGES
```

Regras planejadas:

- severidade `LOW` ou `MEDIUM`: pelo menos uma aprovação independente;
- severidade `HIGH` ou `CRITICAL`: pelo menos duas aprovações de revisores distintos;
- proponente não conta como aprovação independente;
- essas operações não serão abertas até o RBAC reforçado.

## 8.7 `verified_access_network_appeals`

```text
id uuid PK
network_subject_id uuid NOT NULL
signal_id uuid NULL
status text NOT NULL
request_reference_hash text NOT NULL
opened_at timestamptz NOT NULL
review_due_at timestamptz NOT NULL
resolution_code text NULL
resolved_by_actor_id text NULL
resolved_at timestamptz NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Valores:

```text
status:
OPEN
UNDER_REVIEW
UPHELD
AMENDED
REVOKED
CLOSED
```

Regras:

- não armazenar texto livre do titular nesta tabela;
- conteúdo detalhado ficará em canal protegido futuro;
- resolução `REVOKED` revoga o sinal correspondente;
- correção publica evento de reavaliação;
- tenant não acessa diretamente.

---

# 9. Integridade referencial e isolamento

## 9.1 Relações locais

Sempre que possível:

```sql
UNIQUE (id, condominium_id)
```

no pai e:

```sql
FOREIGN KEY (request_id, condominium_id)
REFERENCES verified_access_requests (id, condominium_id)
```

no filho.

Aplicar a:

- request → policy;
- detail → request;
- slot → request;
- participant → request;
- participant → slot;
- participant → identity profile;
- evaluation → participant;
- evaluation → policy.

## 9.2 Relações de rede

As tabelas centrais de rede não devem ser expostas ao tenant.

`network_subject_links` deve validar:

- existência do perfil local;
- mesmo `condominium_id`;
- assurance suficiente;
- ausência de link ativo conflitante.

`network_security_cases.source_participant_id` deve, quando preenchido:

- pertencer ao `source_condominium_id`;
- estar vinculado ao mesmo sujeito;
- nunca ser exibido a outro condomínio.

## 9.3 Proibição de IDOR

Testar explicitamente:

- usuário A tentando request do condomínio B;
- usuário A tentando profile do B;
- tenant A tentando resolver `network_subject_id`;
- tenant A tentando ler signal;
- tenant A tentando descobrir que o tenant B possui vínculo;
- tentativa de vincular profile A a subject usando RPC de outro tenant;
- tentativa de enviar `network_subject_id` diretamente por API.

---

# 10. Máquinas de estado

## 10.1 Solicitação

```text
DRAFT
  -> INVITATIONS_PENDING
  -> CANCELLED
  -> EXPIRED

INVITATIONS_PENDING
  -> IN_PROGRESS
  -> CANCELLED
  -> EXPIRED

IN_PROGRESS
  -> PARTIALLY_ELIGIBLE
  -> ELIGIBLE
  -> CANCELLED
  -> EXPIRED

PARTIALLY_ELIGIBLE
  -> ELIGIBLE
  -> CANCELLED
  -> EXPIRED

ELIGIBLE
  -> COMPLETED
  -> CANCELLED
  -> EXPIRED
```

Estados finais:

```text
COMPLETED
CANCELLED
EXPIRED
```

## 10.2 Vaga

```text
AVAILABLE -> CLAIMED
AVAILABLE -> CANCELLED
CLAIMED   -> CANCELLED
```

## 10.3 Cadastro

```text
CREATED      -> INVITED
CREATED      -> CANCELLED
CREATED      -> EXPIRED

INVITED      -> LINK_OPENED
INVITED      -> DATA_PENDING
INVITED      -> CANCELLED
INVITED      -> EXPIRED

LINK_OPENED  -> DATA_PENDING
LINK_OPENED  -> DATA_SUBMITTED
LINK_OPENED  -> CANCELLED
LINK_OPENED  -> EXPIRED

DATA_PENDING -> DATA_SUBMITTED
DATA_PENDING -> CANCELLED
DATA_PENDING -> EXPIRED

DATA_SUBMITTED -> CANCELLED
DATA_SUBMITTED -> EXPIRED
```

## 10.4 Identidade

```text
NOT_STARTED       -> SESSION_CREATED
NOT_STARTED       -> MANUAL_VERIFIED
NOT_STARTED       -> EXPIRED

SESSION_CREATED   -> PENDING
SESSION_CREATED   -> TECHNICAL_ERROR
SESSION_CREATED   -> EXPIRED

PENDING           -> LIVENESS_VERIFIED
PENDING           -> VERIFIED
PENDING           -> INCONCLUSIVE
PENDING           -> TECHNICAL_ERROR
PENDING           -> EXPIRED

LIVENESS_VERIFIED -> VERIFIED
LIVENESS_VERIFIED -> INCONCLUSIVE
LIVENESS_VERIFIED -> TECHNICAL_ERROR
LIVENESS_VERIFIED -> EXPIRED

TECHNICAL_ERROR   -> SESSION_CREATED
TECHNICAL_ERROR   -> INCONCLUSIVE
TECHNICAL_ERROR   -> EXPIRED

INCONCLUSIVE      -> MANUAL_VERIFIED
INCONCLUSIVE      -> EXPIRED
```

## 10.5 Background

```text
NOT_STARTED -> PENDING
NOT_STARTED -> EXPIRED

PENDING -> NEGATIVE_CERTIFICATE
PENDING -> ADVERSE_INFORMATION_REVIEW
PENDING -> MANUAL_CONFIRMATION_REQUIRED
PENDING -> INCONCLUSIVE
PENDING -> PROVIDER_ERROR
PENDING -> EXPIRED

PROVIDER_ERROR -> PENDING
PROVIDER_ERROR -> INCONCLUSIVE
PROVIDER_ERROR -> EXPIRED
```

`NOT_REQUIRED` é final para a política aplicada.

## 10.6 Rede no participante

```text
NOT_ENABLED -> NOT_ENABLED

NOT_RESOLVED -> NO_ACTIVE_SIGNAL
NOT_RESOLVED -> REVALIDATION_REQUIRED
NOT_RESOLVED -> OFFICIAL_REQUERY_REQUIRED
NOT_RESOLVED -> MANUAL_REVIEW_REQUIRED
NOT_RESOLVED -> CREDENTIAL_HOLD
NOT_RESOLVED -> PROVIDER_ERROR

PROVIDER_ERROR -> NOT_RESOLVED
PROVIDER_ERROR -> MANUAL_REVIEW_REQUIRED

REVALIDATION_REQUIRED -> NOT_RESOLVED
OFFICIAL_REQUERY_REQUIRED -> NOT_RESOLVED
MANUAL_REVIEW_REQUIRED -> NO_ACTIVE_SIGNAL
CREDENTIAL_HOLD -> NO_ACTIVE_SIGNAL
CREDENTIAL_HOLD -> SIGNAL_EXPIRED
CREDENTIAL_HOLD -> SIGNAL_REVOKED
```

`SIGNAL_EXPIRED` e `SIGNAL_REVOKED` devem provocar nova avaliação, não permanência indefinida.

## 10.7 Elegibilidade

```text
PENDING -> ELIGIBLE
PENDING -> REVIEW_REQUIRED
PENDING -> NETWORK_REVIEW_REQUIRED
PENDING -> CORRECTION_REQUIRED
PENDING -> REVOKED
PENDING -> EXPIRED

REVIEW_REQUIRED -> ELIGIBLE
REVIEW_REQUIRED -> CORRECTION_REQUIRED
REVIEW_REQUIRED -> DENIED_MANUAL
REVIEW_REQUIRED -> REVOKED
REVIEW_REQUIRED -> EXPIRED

NETWORK_REVIEW_REQUIRED -> ELIGIBLE
NETWORK_REVIEW_REQUIRED -> CORRECTION_REQUIRED
NETWORK_REVIEW_REQUIRED -> DENIED_MANUAL
NETWORK_REVIEW_REQUIRED -> REVOKED
NETWORK_REVIEW_REQUIRED -> EXPIRED

CORRECTION_REQUIRED -> PENDING
CORRECTION_REQUIRED -> REVIEW_REQUIRED
CORRECTION_REQUIRED -> NETWORK_REVIEW_REQUIRED
CORRECTION_REQUIRED -> REVOKED
CORRECTION_REQUIRED -> EXPIRED

ELIGIBLE -> REVOKED
ELIGIBLE -> EXPIRED
```

`DENIED_MANUAL` requer função privilegiada futura.

## 10.8 Sujeito de rede

```text
ACTIVE -> UNDER_REVIEW
ACTIVE -> DISPUTED
ACTIVE -> MERGED
ACTIVE -> RETIRED

UNDER_REVIEW -> ACTIVE
UNDER_REVIEW -> DISPUTED
UNDER_REVIEW -> MERGED
UNDER_REVIEW -> RETIRED

DISPUTED -> ACTIVE
DISPUTED -> MERGED
DISPUTED -> RETIRED
```

## 10.9 Caso de segurança

```text
REPORTED -> TRIAGE
REPORTED -> DISMISSED
REPORTED -> EXPIRED

TRIAGE -> UNDER_REVIEW
TRIAGE -> DISMISSED
TRIAGE -> EXPIRED

UNDER_REVIEW -> SUBSTANTIATED
UNDER_REVIEW -> DISMISSED
UNDER_REVIEW -> EXPIRED

SUBSTANTIATED -> CLOSED
DISMISSED -> CLOSED
```

## 10.10 Sinal

```text
DRAFT -> UNDER_REVIEW
DRAFT -> REJECTED

UNDER_REVIEW -> ACTIVE
UNDER_REVIEW -> REJECTED
UNDER_REVIEW -> DRAFT

ACTIVE -> SUSPENDED
ACTIVE -> REVOKED
ACTIVE -> EXPIRED

SUSPENDED -> ACTIVE
SUSPENDED -> REVOKED
SUSPENDED -> EXPIRED
```

## 10.11 Contestação

```text
OPEN -> UNDER_REVIEW
UNDER_REVIEW -> UPHELD
UNDER_REVIEW -> AMENDED
UNDER_REVIEW -> REVOKED
UPHELD -> CLOSED
AMENDED -> CLOSED
REVOKED -> CLOSED
```

---

# 11. Tabela de decisão de rede

| Entrada | Pode criar caso? | Pode criar sinal ativo automaticamente? | Efeito em outro condomínio |
|---|---:|---:|---|
| Cancelamento pelo morador | Não | Não | Nenhum |
| Negativa local | Não | Não | Nenhum |
| Chegada fora do horário | Não | Não | Nenhum |
| Falha técnica de liveness | Não | Não | Nova tentativa local |
| Homonímia | Pode exigir correção local | Não | Nenhum |
| Provider indisponível | Não | Não | Retry/revisão local |
| Background inconclusivo | Pode exigir revisão local | Não | Nenhum |
| Documento incompatível não confirmado | Sim | Não | Nenhum enquanto em apuração |
| Uso de identidade de terceiro confirmado | Sim | Não | Sinal somente após revisão |
| Documento fraudulento confirmado | Sim | Não | Sinal somente após revisão |
| Credencial comprometida confirmada | Sim | Não | Hold temporário após ativação |
| Incidente de plataforma confirmado | Sim | Não | Efeito configurado após ativação |
| Sinal revogado | Não aplicável | Não | Reavaliação e liberação conforme regras |
| Sinal expirado | Não aplicável | Não | Não afeta nova autorização |

---

# 12. Funções, triggers e RPCs

## 12.1 Funções internas locais

Criar funções para:

- validar transição de request;
- validar transição de slot;
- validar transições do participante;
- validar escopo de condomínio;
- tornar policy ativa imutável;
- validar JSON de regras de rede;
- impedir efeito proibido;
- inserir audit sanitizado;
- inserir outbox sanitizada;
- atualizar `updated_at`.

## 12.2 Funções internas de rede

Criar funções sem grant público para:

- validar assurance antes de link;
- validar vínculo profile → subject;
- validar transição de subject;
- validar transição de case;
- validar transição de signal;
- validar transição de appeal;
- verificar se o caso está `SUBSTANTIATED`;
- verificar número de revisões;
- impedir proponente como único aprovador;
- expirar sinais;
- marcar reavaliação após revogação;
- impedir sinal sem data final;
- impedir `AUTO_DENY_NETWORK`.

Não criar função SQL que receba CPF e retorne sujeito.

A resolução HMAC será feita por Edge Function futura.

## 12.3 RPCs administrativas de policy

Na Fase 1C, no máximo:

```text
verified_access_create_policy_draft
verified_access_activate_policy
verified_access_retire_policy
```

Regras:

- não conceder a `anon`;
- não conceder genericamente a `authenticated`;
- ativar e aposentar na mesma transação;
- gerar audit e outbox;
- impedir policy de outro condomínio;
- validar dependências de features;
- não habilitar feature automaticamente.

## 12.4 RPCs de rede proibidas nesta fase

Não criar ainda:

```text
search_network_subject
report_network_case
substantiate_network_case
propose_network_signal
activate_network_signal
deny_network_subject
list_network_history
view_network_evidence
open_network_appeal
resolve_network_appeal
```

Essas operações dependem de RBAC, governança e portal seguro.

---

# 13. RLS e grants

## 13.1 Tabelas locais

| Objeto | `anon` | `authenticated` | papel interno/service |
|---|---:|---:|---:|
| Catálogo | nenhum direto | nenhum direto nesta fase | controlado |
| Configuração por condomínio | nenhum | nenhum | controlado |
| Policies | nenhum | nenhum | RPC restrita |
| Requests | nenhum | nenhum | controlado |
| Slots | nenhum | nenhum | controlado |
| Participants | nenhum | nenhum | controlado |
| Identity profiles | nenhum | nenhum | estritamente controlado |
| Evaluations | nenhum | nenhum | controlado |
| Outbox | nenhum | nenhum | processador futuro |
| Audit | nenhum | nenhum | leitura futura restrita |

## 13.2 Tabelas de rede

| Objeto | tenant | backoffice atual | serviço central futuro |
|---|---:|---:|---:|
| Network subjects | nenhum | nenhum | controlado |
| Identifiers | nenhum | nenhum | estritamente controlado |
| Links | nenhum | nenhum | controlado |
| Cases | nenhum | nenhum | reviewer futuro |
| Signals | nenhum | nenhum | reviewer/evaluator futuro |
| Reviews | nenhum | nenhum | reviewer futuro |
| Appeals | nenhum | nenhum | privacy/reviewer futuro |

Mesmo `service_role` contornando RLS, manter RLS habilitada.

Nenhuma view de tenant deve expor:

- `network_subject_id`;
- `source_condominium_id`;
- `source_participant_id`;
- `source_case_id`;
- reviewer;
- detalhes do sinal.

---

# 14. Criptografia e HMAC

## 14.1 Chaves separadas

Usar domínios criptográficos separados:

```text
local encryption key
tenant HMAC key/context
network HMAC key/context
invitation token secret
credential signing key
```

Não reutilizar a mesma chave.

## 14.2 HMAC local

Objetivo:

- deduplicação dentro do condomínio;
- busca controlada;
- prevenção de duplicidade local.

Contexto conceitual:

```text
verified-access:tenant:{condominium_id}:{identifier_type}:vN
```

## 14.3 HMAC de rede

Objetivo:

- correlação entre condomínios participantes;
- somente após identidade suficientemente verificada.

Contexto conceitual:

```text
verified-access:network:{identifier_type}:vN
```

## 14.4 Rotação

A tabela de identificadores de rede suporta:

- chave nova;
- versão nova;
- associação ao mesmo subject;
- período de coexistência;
- revogação do identificador antigo;
- auditoria da rotação.

Não executar rotação real na Fase 1.

## 14.5 Proibições

- não logar valor canônico;
- não retornar HMAC ao cliente;
- não armazenar HMAC em analytics;
- não aceitar HMAC enviado por app;
- não usar hash sem segredo;
- não usar biometria para chave global;
- não usar CPF autodeclarado para link.

---

# 15. Eventos de domínio e outbox

Eventos locais iniciais:

```text
VerifiedAccessPolicyDraftCreated
VerifiedAccessPolicyActivated
VerifiedAccessPolicyRetired
VerifiedAccessRequestCreated
VerifiedAccessRequestCancelled
VerifiedAccessParticipantCreated
VerifiedAccessParticipantStateChanged
VerifiedAccessEligibilityEvaluated
```

Eventos de rede:

```text
VerifiedAccessNetworkSubjectCreated
VerifiedAccessNetworkIdentifierAdded
VerifiedAccessNetworkSubjectLinked
VerifiedAccessNetworkSubjectLinkDisputed
VerifiedAccessNetworkSecurityCaseReported
VerifiedAccessNetworkSecurityCaseSubstantiated
VerifiedAccessNetworkSecurityCaseDismissed
VerifiedAccessNetworkSignalProposed
VerifiedAccessNetworkSignalActivated
VerifiedAccessNetworkSignalSuspended
VerifiedAccessNetworkSignalRevoked
VerifiedAccessNetworkSignalExpired
VerifiedAccessNetworkAppealOpened
VerifiedAccessNetworkAppealResolved
VerifiedAccessNetworkReevaluationRequested
```

Payload permitido:

```json
{
  "aggregateId": "uuid",
  "eventCode": "VerifiedAccessNetworkSignalRevoked",
  "reasonCode": "EVIDENCE_CORRECTED",
  "policyVersion": 2
}
```

Payload proibido:

```json
{
  "cpf": "...",
  "name": "...",
  "phone": "...",
  "certificate": "...",
  "face": "...",
  "accusationText": "..."
}
```

---

# 16. Contratos de provider e fakes

Criar sob a convenção real de `_shared`, preferencialmente:

```text
supabase/functions/_shared/verified-access/
  domain-types.ts
  provider-errors.ts
  identity-provider.ts
  background-check-provider.ts
  messaging-provider.ts
  network-types.ts
  fake/
    fake-identity-provider.ts
    fake-background-check-provider.ts
    fake-messaging-provider.ts
```

## 16.1 Requisitos comuns

- TypeScript estrito;
- sem rede;
- sem acesso ao banco;
- sem secrets;
- sem aleatoriedade;
- clock injetável;
- erros com código estável;
- resultados normalizados;
- sem PII em logs;
- cenário escolhido por código sintético.

## 16.2 Fake de identidade

`SUCCESS` retorna:

```text
status = VERIFIED
assuranceLevel = IDENTITY_VERIFIED
livenessStatus = PASSED
documentStatus = VALID
faceMatchStatus = MATCH
```

`LIVENESS_ONLY` nunca retorna `IDENTITY_VERIFIED`.

## 16.3 Fake de background

Estados:

```text
NEGATIVE_CERTIFICATE
PENDING
ADVERSE_INFORMATION_REVIEW
MANUAL_CONFIRMATION_REQUIRED
INCONCLUSIVE
PROVIDER_ERROR
EXPIRED
```

Nunca retorna `DENIED_MANUAL`.

## 16.4 Fake de mensageria

- sem rede;
- ID determinístico;
- sucesso e falha técnica;
- telefone nunca em log;
- não cria token.

## 16.5 Tipos de rede

Criar apenas tipos puros para:

```text
NetworkSubjectResolutionResult
NetworkSignalAssessment
NetworkRequiredAction
NetworkSignalCategory
NetworkSignalEffect
```

Não criar provider externo para a Rede Confia. Ela é um domínio interno.

---

# 17. Plano de migrations

Ajustar timestamps ao padrão real.

## Fase 1A

```text
*_verified_access_local_foundation.sql
*_verified_access_local_security.sql
```

Criar:

- feature `VERIFIED_ACCESS`;
- feature `VERIFIED_ACCESS_BACKGROUND_CHECK`;
- catálogo;
- policy;
- requests;
- service details;
- slots;
- identity profiles;
- participants;
- eligibility evaluations;
- outbox;
- audit;
- RLS local padrão-deny;
- testes locais.

## Fase 1B

```text
*_verified_access_network_foundation.sql
*_verified_access_network_security.sql
```

Criar:

- features de rede;
- network subjects;
- identifiers;
- links;
- cases;
- signals;
- reviews;
- appeals;
- RLS central padrão-deny;
- constraints estáticas;
- testes de isolamento e não propagação.

## Fase 1C

```text
*_verified_access_state_machines.sql
*_verified_access_policy_rpcs.sql
*_verified_access_outbox_audit.sql
```

Criar:

- funções de transição;
- triggers;
- tenant validation;
- policy immutability;
- validação de regras de rede;
- helpers de audit/outbox;
- RPCs de policy;
- testes de rollback e idempotência.

## Fase 1D

Sem migration obrigatória.

Criar contratos, fakes e testes Deno.

Não misturar migration com UI ou integração externa.

---

# 18. Plano de testes

## 18.1 Testes locais

- feature base existe e está desligada;
- seeds existem;
- `OTHER` exige descrição;
- não há coluna plaintext sensível;
- índices e uniques existem;
- tenant A não usa policy, unit, slot, profile ou participant do B;
- `anon` não lê;
- `authenticated` não escreve;
- policy ativa é imutável;
- só existe uma policy ativa;
- background exige aprovação;
- network policy exige aprovação;
- JSON de rules rejeita efeito proibido;
- transições inválidas falham;
- estado final não reabre;
- audit é append-only;
- outbox é idempotente.

## 18.2 Testes de identidade de rede

- CPF autodeclarado não cria subject;
- assurance insuficiente não cria link;
- identity verificada cria link somente por caminho interno;
- HMAC duplicado resolve o mesmo subject;
- profile local não recebe acesso ao subject ID;
- tenant não busca por HMAC;
- chave/versionamento fazem parte da unicidade;
- identificador revogado não resolve novo vínculo;
- face não é aceita como identifier type;
- telefone não é aceito como identifier type;
- mesmo subject pode possuir links em condomínios distintos sem expor os links.

## 18.3 Testes de não propagação

Estes testes são obrigatórios:

- `LOCAL_DENIED` não cria case;
- cancelamento não cria case;
- fora do horário não cria case;
- falha de liveness não cria case;
- provider indisponível não cria signal;
- background inconclusivo não cria signal;
- homonímia não cria signal;
- case `REPORTED` não afeta participant de outro condomínio;
- case `UNDER_REVIEW` não afeta participant de outro condomínio;
- case `DISMISSED` não origina signal;
- signal `DRAFT` não afeta outro condomínio;
- signal `UNDER_REVIEW` não afeta outro condomínio;
- apenas signal `ACTIVE`, vigente e compatível com policy produz ação.

## 18.4 Testes de sinal

- sinal exige caso substanciado;
- sinal exige expiração;
- `AUTO_DENY_NETWORK` é rejeitado;
- proponente não aprova sozinho sinal crítico;
- sinal crítico exige dois revisores distintos;
- signal expirado não afeta avaliação;
- signal revogado não afeta avaliação;
- revogação gera evento de reavaliação;
- `HOLD_CREDENTIAL` produz `NETWORK_REVIEW_REQUIRED`, não `DENIED_MANUAL`;
- tenant recebe ação normalizada, não detalhes;
- feature desligada resulta em `NOT_ENABLED`.

## 18.5 Testes de RLS central

- tenant não lê subjects;
- tenant não lê identifiers;
- tenant não lê links;
- tenant não lê cases;
- tenant não lê signals;
- backoffice atual também não possui acesso implícito;
- somente função interna futura poderá avaliar sinal;
- `network_subject_id` não aparece em resposta pública.

## 18.6 Testes Deno

- todos os cenários de identidade;
- liveness isolado não vira identidade;
- todos os cenários de background;
- background adverso não nega;
- messaging não usa rede;
- network types rejeitam efeitos inválidos;
- clock determinístico;
- nenhum log contém PII.

## 18.7 Validação

Executar no mínimo:

```powershell
cd C:\Projetos\Confia\repo-github
npx supabase db push --dry-run
npm run admin:lint
npm run admin:build
```

Quando houver ambiente local isolado:

- aplicar migrations do zero;
- aplicar sobre schema atual;
- executar testes SQL;
- executar testes Deno.

Não executar `db push` remoto.

---

# 19. Fase 1A — Fundação local

## Objetivo

Criar a fundação local do Acesso Verificado, sem correlação de rede operacional.

## Inclui

- ADRs gerais;
- feature `VERIFIED_ACCESS`;
- feature `VERIFIED_ACCESS_BACKGROUND_CHECK`;
- catálogo;
- policy com campos de rede já modelados;
- requests;
- service details;
- slots;
- identity profiles;
- participants;
- eligibility evaluations;
- outbox e audit;
- constraints estáticas;
- índices;
- RLS padrão-deny;
- testes locais e tenant isolation;
- rollback.

## Não inclui

- tabelas centrais de rede;
- state machines completas;
- policy RPCs;
- providers;
- UI;
- integrações.

## Gate

- migrations aplicam;
- feature desligada;
- nenhum campo plaintext;
- tenant isolation passa;
- nenhum acesso direto indevido.

---

# 20. Fase 1B — Fundação da Rede Confia

## Objetivo

Criar as estruturas inertes da identidade pseudonimizada e dos sinais de rede.

## Inclui

- ADR específico da rede;
- três features de rede desligadas;
- subjects;
- identifiers;
- links;
- security cases;
- signals;
- reviews;
- appeals;
- constraints estáticas;
- RLS central padrão-deny;
- testes de isolamento;
- testes de não propagação;
- comentários de sensibilidade;
- rollback.

## Não inclui

- HMAC real;
- Edge Function;
- busca;
- link operacional;
- ativação de sinal;
- revisão humana;
- API;
- UI.

## Gate

- tenant não vê nenhuma tabela central;
- não existe API de busca;
- sinais exigem expiração;
- efeito proibido não existe;
- negativa local não possui FK, trigger ou automação que crie signal;
- todas as features continuam desligadas.

---

# 21. Fase 1C — Invariantes, policy, audit e outbox

## Objetivo

Proteger estados e operações com transações.

## Inclui

- funções de transição local e de rede;
- triggers;
- tenant validation;
- policy immutability;
- validação de `network_signal_rules`;
- RPCs de policy;
- helpers audit/outbox;
- deduplication key;
- eventos de reavaliação;
- testes de rollback;
- testes de idempotência;
- testes de state machine.

## Não inclui

- RPC operacional de signal;
- processador da outbox;
- request do morador;
- convite;
- provider;
- UI.

## Gate

- policy atômica;
- transições inválidas falham;
- audit/outbox na mesma transação;
- `AUTO_DENY_NETWORK` impossível;
- caso não substanciado não origina signal ativo;
- signal expirado/revogado não afeta avaliação;
- nenhuma função sensível aberta ao backoffice atual.

---

# 22. Fase 1D — Contratos e fakes

## Objetivo

Criar portas estáveis antes das integrações externas.

## Inclui

- tipos;
- erros;
- `IdentityProvider`;
- `BackgroundCheckProvider`;
- `MessagingProvider`;
- tipos internos da rede;
- fakes;
- clock;
- testes Deno;
- README.

## Não inclui

- Edge Function pública;
- banco;
- rede;
- segredo;
- provider real;
- webhook;
- polling;
- orquestração.

## Gate

- todos os cenários determinísticos;
- nenhuma rede;
- nenhum dado real;
- tipos independentes de fornecedor;
- liveness isolado não comprova identidade;
- background adverso não nega;
- efeito de rede não produz auto-deny.

---

# 23. Prompt pronto — Codex Fase 1A

```text
Leia integralmente:

1. C:\Projetos\Confia\ACESSO_VERIFICADO_VISITANTES_PRESTADORES\
   ESPECIFICACAO_ACESSO_VERIFICADO_VISITANTES_PRESTADORES.md

2. C:\Projetos\Confia\ACESSO_VERIFICADO_VISITANTES_PRESTADORES\
   PLANO_EXECUCAO_FASE_1_ACESSO_VERIFICADO.md

Execute somente a Fase 1A da versão 2.0 do segundo documento.

Repositório:
C:\Projetos\Confia\repo-github

Restrições:

- Não altere confia-interfone-app.
- Preserve todas as alterações locais preexistentes.
- Não execute reset, restore, stash, clean, commit ou push.
- Não implemente UI, Edge Function, convite, WhatsApp, QR, identidade real,
  background real ou credencial.
- Não altere a tabela persons.
- Use prefixo verified_access_.
- Todas as tabelas locais carregam condominium_id.
- Use as features existentes, desligadas.
- RLS padrão-deny.
- Nenhum campo plaintext de CPF, nome, nascimento, telefone, filiação ou
  documento.
- Não crie ainda tabelas centrais da Rede Confia; isso pertence à Fase 1B.
- Não execute migration remota.

Antes de editar, apresente:

1. git status;
2. arquivos exatos;
3. convenções encontradas;
4. migrations planejadas;
5. estratégia de testes;
6. riscos de conflito.

Implemente:

- ADRs gerais;
- VERIFIED_ACCESS;
- VERIFIED_ACCESS_BACKGROUND_CHECK;
- catálogo de serviços;
- configuração por condomínio;
- policies versão de schema 2, incluindo campos de rede inertes;
- requests;
- service request details;
- participant slots;
- identity profiles protegidos;
- participants;
- eligibility evaluations;
- outbox;
- audit;
- constraints;
- índices;
- comentários;
- RLS e grants padrão-deny;
- testes locais e tenant isolation;
- rollback.

Não implemente state machines completas ou RPCs de policy.

Execute dry-run, testes SQL seguros, lint e build.

Na resposta final, comprove:

- features desligadas;
- nenhum plaintext sensível;
- persons intocada;
- RLS em todas as tabelas;
- tenant isolation;
- alterações locais preservadas.
```

---

# 24. Prompt pronto — Codex Fase 1B

```text
Leia a especificação principal e a versão 2.0 do
PLANO_EXECUCAO_FASE_1_ACESSO_VERIFICADO.md.

Revise a Fase 1A e execute somente a Fase 1B.

Repositório:
C:\Projetos\Confia\repo-github

Implemente:

- ADR da Rede Confia;
- VERIFIED_ACCESS_NETWORK_IDENTITY;
- VERIFIED_ACCESS_NETWORK_SIGNALS;
- VERIFIED_ACCESS_NETWORK_HOLD;
- network subjects;
- network subject identifiers;
- network subject links;
- network security cases;
- network signals;
- network signal reviews;
- network appeals;
- constraints estáticas;
- índices;
- comentários;
- RLS central padrão-deny;
- testes de isolamento e não propagação;
- rollback.

Restrições:

- todas as features desligadas;
- não calcular HMAC real;
- não criar Edge Function;
- não criar API de busca;
- não criar RPC de report, review ou signal;
- não armazenar PII no domínio de rede;
- não armazenar face ou template biométrico;
- negativa local não cria case ou signal;
- case aberto não afeta outro condomínio;
- somente sinal ativo futuro poderá produzir ação;
- não existe AUTO_DENY_NETWORK;
- todo sinal exige expiração;
- tenant e backoffice atual não acessam as tabelas centrais;
- não executar migration remota.

Antes de editar, mostre migrations, tabelas, constraints e testes exatos.

Na resposta final, comprove:

1. tenant não lê domínio de rede;
2. nenhuma tabela central contém PII civil;
3. signal sem expiração falha;
4. efeito proibido é impossível;
5. negativa local não tem automação de propagação;
6. features permanecem desligadas.
```

---

# 25. Prompt pronto — Codex Fase 1C

```text
Leia novamente os dois documentos e execute somente a Fase 1C.

Repositório:
C:\Projetos\Confia\repo-github

Implemente:

- funções e triggers das máquinas de estado locais;
- funções e triggers de subject, case, signal e appeal;
- validação de tenant;
- validação de assurance para link;
- policy ativa imutável;
- validação de network_signal_rules;
- bloqueio explícito de AUTO_DENY_NETWORK;
- RPCs restritas de draft/activate/retire policy;
- helpers de audit e outbox;
- eventos de reavaliação após revogação/expiração;
- testes de transição, autorização, rollback e idempotência.

Não implemente:

- report case;
- substantiate case;
- propose signal;
- activate signal;
- appeal pública;
- provider;
- UI;
- processador de outbox.

Regras:

- security definer com search_path fixo;
- revogar execução de public;
- não conceder a anon;
- não abrir funções sensíveis ao authenticated;
- case REPORTED ou UNDER_REVIEW não produz efeito;
- sinal exige case SUBSTANTIATED;
- sinal HIGH/CRITICAL exige duas revisões distintas quando a ativação for
  implementada;
- proponente não pode ser o único aprovador;
- HOLD_CREDENTIAL não produz DENIED_MANUAL;
- sinal revogado ou expirado não afeta nova avaliação;
- features continuam desligadas.

Na resposta final, demonstre os invariantes com testes.
```

---

# 26. Prompt pronto — Codex Fase 1D

```text
Leia os documentos e execute somente a Fase 1D.

Repositório:
C:\Projetos\Confia\repo-github

Crie sob a convenção real de supabase/functions/_shared:

- domain types;
- provider errors;
- IdentityProvider;
- BackgroundCheckProvider;
- MessagingProvider;
- network types;
- fake identity;
- fake background;
- fake messaging;
- clock injetável;
- testes Deno;
- README.

Restrições:

- sem Edge Function pública;
- sem rede;
- sem Supabase;
- sem secrets;
- sem aleatoriedade;
- sem dados reais;
- sem DTO de fornecedor;
- sem HMAC real;
- sem biometria;
- liveness isolado não vira IDENTITY_VERIFIED;
- background adverso não vira negativa;
- network action não possui AUTO_DENY;
- nenhuma feature é habilitada.

Execute testes Deno e validadores existentes.
```

---

# 27. Checklist de revisão humana

## Após 1A

- [ ] Alterações locais preservadas.
- [ ] Feature base desligada.
- [ ] App não alterado.
- [ ] UI não criada.
- [ ] `persons` intocada.
- [ ] Sem plaintext sensível.
- [ ] RLS em todas as tabelas locais.
- [ ] Tenant isolation testado.
- [ ] Migrations reversíveis.
- [ ] Nenhuma execução remota.

## Após 1B

- [ ] Três features de rede desligadas.
- [ ] Domínio central sem PII.
- [ ] Tenant não acessa subject, identifier, link, case ou signal.
- [ ] Não existe API de busca.
- [ ] Não existe facial 1:N.
- [ ] Negativa local não propaga.
- [ ] Case aberto não afeta rede.
- [ ] Sinal exige expiração.
- [ ] Não existe efeito de auto-deny.
- [ ] Backoffice atual não ganhou acesso implícito.

## Após 1C

- [ ] Transições inválidas falham.
- [ ] Estados finais não reabrem.
- [ ] Policy ativa imutável.
- [ ] Uma policy ativa por condomínio.
- [ ] Regras de rede validadas.
- [ ] Audit append-only.
- [ ] Outbox atômica e idempotente.
- [ ] Signal exige case substanciado.
- [ ] Revogação gera reavaliação.
- [ ] HOLD não vira DENIED.

## Após 1D

- [ ] Fakes sem rede.
- [ ] Fakes determinísticos.
- [ ] Nenhum dado real.
- [ ] Contratos independentes.
- [ ] Liveness isolado não comprova identidade.
- [ ] Background adverso exige revisão.
- [ ] Tipos de rede não aceitam auto-deny.
- [ ] Nenhuma função pública criada.

---

# 28. Critérios para autorizar a Fase 2

A Fase 2 só começa quando:

1. Fases 1A a 1D aprovadas;
2. migrations estáveis;
3. tenant isolation passa;
4. domínio de rede inacessível ao tenant;
5. policy versionada funcional;
6. estados protegidos;
7. audit e outbox atômicos;
8. contracts e fakes estáveis;
9. features desligadas;
10. nenhuma PII plaintext;
11. nenhuma propagação de negativa local;
12. nenhum auto-deny de rede.

A Fase 2 poderá implementar:

- RPC de criação de solicitação;
- vínculo do morador com unidade;
- criação atômica de N vagas;
- visitante;
- prestador;
- catálogo;
- consulta resumida;
- alteração e cancelamento.

O app Expo será tratado em alteração separada.

---

# 29. Gates posteriores

## Antes da página pública

- criptografia real;
- gestão e rotação de chaves;
- rate limit;
- anti-enumeração;
- retenção;
- domínio e headers;
- aviso de privacidade.

## Antes da identidade de rede operacional

- provider de identidade validado;
- assurance mínimo;
- canonicalização aprovada;
- HMAC em secret manager;
- rotação;
- função interna de resolução;
- feature por condomínio;
- transparência ao participante.

## Antes dos sinais de rede operacionais

- RIPD;
- política de categorias;
- procedimento de evidência;
- RBAC;
- autenticação forte;
- dupla aprovação;
- portal de contestação;
- expiração;
- processo de correção;
- termos com condomínios;
- feature flags.

## Antes de background real

- parecer jurídico;
- fontes e cobertura;
- semântica;
- revisão humana;
- autenticação reforçada;
- política de não auto-deny.

## Antes de WhatsApp real

- provider;
- templates;
- opt-in;
- webhook;
- custo;
- fallback;
- secrets.

## Antes de QR e portaria

- formato;
- assinatura;
- revogação;
- leitor;
- idempotência;
- indisponibilidade;
- integração com `PORTARIA`.

---

# 30. Semântica comercial que o código deve preservar

Mensagem válida:

> Uma fraude de identidade confirmada em um condomínio ajuda a proteger toda a Rede Confia.

Mensagem válida:

> O acesso é decidido conforme a política de cada condomínio, enquanto a inteligência de segurança protege toda a rede.

Mensagem que o produto não deve prometer:

> Quem foi negado em um condomínio nunca entra em nenhum outro.

Mensagem que o código deve implementar:

```text
Perfil local isolado
        +
identidade de rede pseudonimizada
        +
caso apurado
        +
sinal ativo e temporário
        +
efeito configurado
        +
revisão e contestação
```

---

# 31. Resultado esperado da Fase 1

Ao final, ainda não haverá tela visível. Isso é intencional.

A fundação correta será:

```text
features desligadas
        +
schema local isolado
        +
identidade pseudonimizada de rede
        +
negativa local sem propagação
        +
casos e sinais separados
        +
sem auto-deny
        +
política versionada
        +
estados protegidos
        +
audit e outbox transacionais
        +
dados sensíveis sem plaintext
        +
contracts independentes
        +
providers fake
        +
testes
```

Somente depois dessa fundação o Codex deverá implementar a criação de solicitações pelo morador e, em fases posteriores, a correlação operacional da Rede Confia.
