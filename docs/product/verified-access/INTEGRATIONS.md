# Integrações — Acesso Verificado

## 1. Princípio arquitetural

O domínio não depende de DTOs de fornecedores.

Portas internas:

```text
IdentityProvider
BackgroundCheckProvider
MessagingProvider
AccessControlProvider
```

Adapters convertem respostas externas para estados normalizados.

## 2. Estratégia de identidade

### MVP/POC

Candidato principal:

```text
DataTrust / Link Validação Segura
```

Avaliar:

- sessão hospedada;
- prova de vida;
- documento;
- face match 1:1;
- callback/polling;
- retenção;
- SLA;
- custo;
- suboperadores.

### Evolução

```text
Datavalid V5
```

Usar como provider alternativo de identidade quando o processo comercial e regulatório estiver aprovado.

Prova de vida isolada não retorna `IDENTITY_VERIFIED`.

## 3. Background

Candidatos:

```text
DataTrust Background Check
BigDataCorp on-demand
```

Normalizar:

```text
NOT_REQUIRED
NOT_STARTED
PENDING
NEGATIVE_CERTIFICATE
ADVERSE_INFORMATION_REVIEW
MANUAL_CONFIRMATION_REQUIRED
INCONCLUSIVE
PROVIDER_ERROR
EXPIRED
```

Não criar `HAS_CRIMINAL_RECORD` como decisão automática.

Acesso direto à API da Polícia Federal não é pressuposto para empresa privada e a semântica da certidão não deve ser ampliada.

## 4. WhatsApp

Não existe adapter no projeto hoje.

Implementar futuramente por `MessagingProvider`.

Mensagem:

- condomínio/anfitrião;
- período;
- contexto geral;
- link opaco.

Não enviar:

- CPF;
- biometria;
- certidão;
- resultado de análise;
- motivo sensível.

## 5. Credencial e hardware

`AccessControlProvider` deve permitir:

- QR opaco e assinado;
- revogação;
- validade;
- check-in/out idempotentes;
- integração futura com leitores/catracas.

Credencial não contém PII no payload.

## 6. Webhooks

- assinatura validada;
- evento idempotente;
- armazenamento mínimo;
- monotonicidade;
- retry;
- polling de reconciliação;
- circuit breaker;
- dead-letter.

## 7. POC

Para cada provider, testar:

- success;
- pending;
- inconclusive;
- timeout;
- payload duplicado;
- evento fora de ordem;
- divergência cadastral;
- homonímia;
- indisponibilidade;
- retenção;
- custo;
- suporte;
- cobertura geográfica.

Nenhum adapter real entra antes dos contratos/fakes da Fase 1D.
