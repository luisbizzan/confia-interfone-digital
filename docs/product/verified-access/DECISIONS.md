# Decisões vinculantes — Acesso Verificado e Rede Confia

Atualizado em 23 de julho de 2026.

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

## 17. Propostas da Fase 3B para revisão humana

Esta seção não é decisão jurídica final nem autorização de implementação. Ela
registra a proposta de produto a ser confirmada por PO, segurança, privacidade
e jurídico antes de um `CURRENT_TASK` executável:

1. nome completo obrigatório;
2. CPF obrigatório para brasileiros maiores de idade;
3. RNM ou passaporte com emissor para estrangeiros;
4. data de nascimento obrigatória;
5. telefone opcional;
6. menor exige nome e vínculo do responsável, sem validação automática;
7. nenhuma imagem de documento;
8. nenhuma biometria;
9. nenhum background check;
10. nenhum provider real;
11. cadastro incompleto por no máximo sete dias após expiração/cancelamento,
    com preferência por não persistir PII de rascunho;
12. retenção de cadastro submetido permanece blocker jurídico;
13. página pública isolada do backoffice;
14. preferência por `apps/verified-access-public` no monorepo;
15. token de convite trocado por sessão curta na primeira abertura válida;
16. token original não usado nas operações seguintes;
17. sessão opaca, revogável, expirável e ligada a invitation + slot;
18. uma submissão final por convite;
19. correção posterior fora da Fase 3B;
20. ciência do privacy notice e aceite de termos, sem presumir consentimento
    como base legal;
21. morador vê somente status, nunca PII;
22. `IdentityProvider` não é chamado;
23. `MessagingProvider` permanece fake;
24. `VERIFIED_ACCESS` permanece desligada;
25. nenhuma migration remota.

Base legal, textos, retenção definitiva, menores, domínio, chaves e rate
limiting dependem de aprovação humana e permanecem blockers.

## 18. Propostas da Fase 3C para revisão humana

Esta seção registra propostas operacionais, não decisões finais nem autorização
de implementação:

1. expiração permanece validada inline e também será materializada por jobs
   idempotentes em batches limitados;
2. invitation expirada/revogada encerra sessões `ACTIVE` dependentes;
3. nenhuma PII de rascunho existe; participant/profile parcial é finding;
4. public sessions terminais podem ser removidas após 7 dias;
5. rate buckets podem ser removidos após janela e margem aprovada;
6. commands concluídos podem ser removidos após 30 dias;
7. commands presos/incompletos exigem reconciliação e prazo proposto de 7 dias;
8. invitations expiradas/revogadas têm proposta de 90 dias, sujeita a
   jurídico;
9. outbox processada tem proposta de 30 a 90 dias;
10. retenção e anonimização de PII submetida ou cancelada permanecem blockers;
11. a topologia inicial recomendada reutiliza scheduler externo -> Edge -> RPC,
    com segredo dedicado, assinatura, privilégio mínimo e fallback manual;
12. rate limiting futuro será em camadas, sem remover o limite transacional;
13. reconciliação automática só corrige estados cuja evidência estrutural é
    inequívoca e nunca cria ou move identidade;
14. observabilidade usa somente IDs/códigos e métricas agregadas sem PII;
15. rollout exige gates separados de jurídico, DPO, segurança, operação e
    migration;
16. Fase 4 exige contrato próprio e não é autorizada pela Fase 3C.

As propostas completas e seus blockers estão em
[`phases/PHASE_3C.md`](phases/PHASE_3C.md).
