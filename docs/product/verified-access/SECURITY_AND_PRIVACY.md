# Segurança e privacidade — Acesso Verificado

## 1. Princípios

Aplicar:

- finalidade;
- necessidade;
- minimização;
- qualidade;
- transparência;
- segurança;
- prevenção;
- não discriminação;
- responsabilização.

Biometria é dado pessoal sensível.

Correlação em rede e decisões que afetam acesso exigem RIPD antes de produção.

## 2. Classificação

### Dados locais sensíveis

- CPF;
- documento;
- nascimento;
- filiação;
- telefone;
- nome;
- selfie ou referência biométrica;
- certidão;
- resultado de verificação.

### Dados de rede pseudonimizados

- sujeito UUID;
- identifier HMAC;
- key/canonicalization version;
- códigos;
- assurance;
- status;
- reason codes;
- timestamps;
- hashes de referência.

Pseudonimização não transforma o dado em anônimo.

## 3. Criptografia e HMAC

Domínios de chave separados:

```text
local encryption key
tenant HMAC key/context
network HMAC key/context
invitation token secret
credential signing key
```

Não reutilizar chaves.

Não armazenar secrets no banco, migration, fixture, log ou documentação.

Não criar função SQL de descriptografia.

## 4. RLS e grants

- RLS em todas as tabelas.
- Default-deny.
- Revogar privilégios preexistentes antes de conceder.
- Sem acesso direto de `PUBLIC`, `anon` e `authenticated`.
- Tabelas centrais de rede não têm policy por tenant.
- Na Fase 1B, nenhuma RPC pública e nenhuma escrita operacional de rede.

## 5. Logs e observabilidade

Proibido registrar:

- CPF;
- nome;
- telefone;
- documento;
- token;
- certidão;
- biometria;
- evidência;
- texto de acusação.

Usar:

- IDs técnicos;
- event/reason codes;
- provider;
- status;
- duração;
- tentativas;
- correlation ID.

Artifacts de CI precisam de sanitização.

## 6. Background

Nunca interpretar:

```text
provider error
source unavailable
homonymy
manual confirmation required
inconclusive
```

como antecedente.

Nenhum resultado adverso produz auto-deny.

## 7. Rede Confia

Sinal deve possuir:

- caso substanciado;
- categoria permitida;
- fonte;
- assurance;
- motivo;
- revisores;
- validade;
- expiração;
- revisão periódica;
- revogação;
- contestação;
- auditoria.

Casos abertos não alteram acesso.

## 8. Contestação e correção

O titular precisa de canal para:

- corrigir identidade;
- contestar vínculo;
- contestar sinal;
- receber protocolo;
- acompanhar status.

Revogação/correção deve gerar reavaliação dos acessos afetados.

## 9. Retenção

Definir separadamente:

- convite;
- cadastro;
- ciphertext;
- HMAC local;
- HMAC de rede;
- certidão;
- evidência;
- auditoria;
- evento de acesso;
- caso;
- sinal;
- contestação.

Nenhum sinal de rede é permanente.

## 10. Gates

Antes da identidade real:

- provider aprovado;
- contrato e suboperadores;
- retenção;
- liveness;
- comparação 1:1;
- segurança de webhook;
- RIPD.

Antes de background real:

- parecer jurídico;
- fontes e cobertura;
- semântica;
- revisão humana;
- RBAC;
- contestação;
- no-auto-deny.

Antes da Rede Confia operacional:

- RIPD específico;
- papel da Confia e condomínios;
- política de categorias;
- dupla aprovação;
- portal do titular;
- expiração e correção.

## 11. Gate proposto para cadastro público da Fase 3B

O cadastro público proposto usa troca única do token de convite por sessão
opaca curta. Somente hashes versionados são persistidos; token, session token e
IP bruto não entram em banco, logs, audit ou outbox. As tabelas permanecem sob
RLS default-deny e runtime roles não recebem acesso direto.

PII local reutiliza `verified_access_identity_profiles`: valores necessários à
operação futura são ciphertext reversível; CPF/documento usam HMAC por tenant
apenas para unicidade e lookup local; telefone permanece não único. Dados de
responsável por menor também são ciphertext. Não há JSON genérico com PII,
função SQL de criptografia/descriptografia, imagem, biometria, background ou
provider real.

A proposta não persiste PII de rascunho. A submissão final grava profile,
participant, slot, invitation, session, audit e outbox em uma transação. Audit
e outbox contêm somente IDs, códigos, versões, status, timestamps e correlation
ID. O morador recebe apenas status.

Antes da implementação, exigem aprovação humana: base legal, versões finais do
privacy notice e termos, menores, retenção submetida, domínio/proxy same-origin,
gestão de chaves, rate limiting distribuído, exclusão/anonimização, correção,
acesso futuro da portaria e responsável DPO/jurídico.
