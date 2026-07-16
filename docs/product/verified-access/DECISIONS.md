# Decisões vinculantes — Acesso Verificado e Rede Confia

Atualizado em 16 de julho de 2026.

## 1. Linguagem e semântica

O produto não classifica pessoas como “íntegras”, “não íntegras”, “seguras” ou “perigosas”.

O sistema registra:

- nível de identidade;
- resultado técnico;
- fonte;
- validade;
- inconclusão;
- revisão;
- decisão;
- credencial;
- evento de acesso.

Não criar score moral ou cor que comunique certeza não suportada.

## 2. Tenant local e rede

Dados operacionais e PII permanecem isolados por `condominium_id`.

A Rede Confia pode manter uma referência pseudonimizada central para:

- correlação de identidade verificada;
- prevenção a fraude;
- credencial comprometida;
- revalidação de segurança.

A rede não expõe histórico de visitas, decisões locais, documentos ou evidências de um condomínio a outro.

## 3. Regra central

```text
LOCAL_DENIED não cria NETWORK_SIGNAL.
```

Não propagam:

- cancelamento;
- chegada fora do horário;
- falta de autorização local;
- política local mais restritiva;
- falha técnica;
- homonímia;
- provider indisponível;
- background inconclusivo;
- decisão subjetiva.

## 4. Casos e sinais são entidades diferentes

```text
caso = investigação
sinal = conclusão operacional temporária
```

Caso `REPORTED`, `TRIAGE` ou `UNDER_REVIEW` não produz efeito em outro condomínio.

Um sinal só pode surgir de caso substanciado, com revisão, motivo, validade e expiração.

## 5. Efeitos permitidos

```text
INFORM_AUTHORIZED_REVIEWER
REVALIDATE_IDENTITY
REQUERY_OFFICIAL_SOURCE
REQUIRE_MANUAL_REVIEW
HOLD_CREDENTIAL
```

`HOLD_CREDENTIAL` impede emissão enquanto a revisão estiver pendente; não significa negativa definitiva.

## 6. Efeitos proibidos

```text
AUTO_DENY_NETWORK
GLOBAL_DENIED
PERMANENT_BLACKLIST
```

Não criar blacklist privada permanente.

## 7. Identidade de rede

A correlação usa HMAC com chave exclusiva da plataforma e versionamento.

Não usar SHA simples de CPF.

Somente identificadores verificados podem gerar vínculo de rede:

```text
CPF
RNM
PASSPORT_WITH_ISSUER
```

Não usar como chave global isolada:

- telefone;
- e-mail;
- nome;
- nascimento;
- filiação;
- endereço;
- fotografia;
- template facial;
- embedding facial.

## 8. Telefone

Telefone é contato, não identificador civil forte.

Duas pessoas do mesmo condomínio podem compartilhar telefone.

HMAC de telefone pode ser usado para lookup local, nunca como chave única de pessoa ou sujeito de rede.

## 9. Biometria

Permitido:

- prova de vida;
- comparação facial 1:1 com documento ou referência válida.

Proibido:

- reconhecimento facial 1:N;
- galeria facial global;
- deduplicação de rede por rosto;
- busca silenciosa em câmeras;
- armazenamento local de template/embedding biométrico.

## 10. Background

Estados inconclusivos, erro de provider, ausência de certidão e homonímia não geram negativa automática.

Informação adversa exige revisão humana.

A API/serviço da Polícia Federal não deve ser interpretada como confirmação positiva automática de antecedentes.

## 11. Policy versionada

Policy é versionada por condomínio e separa visitante de prestador.

Identidade diferente de `DISABLED` exige referência de aprovação de privacidade.

Background diferente de `DISABLED` exige referência de aprovação correspondente.

Rede diferente de `DISABLED` exige aprovação da operação de rede.

Policy ativa é imutável; evolução ocorre por nova versão.

## 12. PII

PII local usa ciphertext e HMAC separado por finalidade.

Não descriptografar em SQL.

Chaves ficam fora do banco e do repositório.

Outbox e auditoria recebem somente IDs, códigos e metadata sanitizada.

## 13. Autorização

Tabelas locais usam RLS e grants mínimos.

Tabelas centrais da rede não possuem acesso de tenant.

Na Fase 1B, nem `service_role` recebe escrita operacional direta nas tabelas centrais; operações serão adicionadas por portas restritas na Fase 1C.

## 14. Revisão sensível

Não reutilizar autenticação genérica do backoffice para revisão.

Antes da operação real, exigir:

- identidade estável do operador;
- RBAC `REVIEWER`;
- autenticação reforçada;
- auditoria de visualização;
- separação de funções;
- dupla aprovação para alta criticidade;
- canal de correção e contestação.

## 15. Feature flags

```text
VERIFIED_ACCESS
VERIFIED_ACCESS_BACKGROUND_CHECK
VERIFIED_ACCESS_NETWORK_IDENTITY
VERIFIED_ACCESS_NETWORK_SIGNALS
VERIFIED_ACCESS_NETWORK_HOLD
```

Todas nascem desligadas.

Feature de rede depende da feature base.

Nenhuma migration habilita condomínio automaticamente.

## 16. Deployment

Merge no Git/Vercel não aplica migrations Supabase.

Migrations do Acesso Verificado não serão aplicadas remotamente antes da reconciliação do migration drift histórico e de gate específico de staging.
