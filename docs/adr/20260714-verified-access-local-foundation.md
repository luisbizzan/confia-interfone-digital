# ADR-VA-001: Fundacao local do Acesso Verificado

Data: 2026-07-14

Status: aceito para Fase 1A

## Contexto

A capacidade Acesso Verificado sera implementada de forma incremental sobre o backend Supabase existente. A Fase 1A deve criar apenas a fundacao local por condominio, sem UI, Edge Functions publicas, providers, convites, QR, credenciais ou tabelas centrais da Rede Confia.

O tenant atual do projeto e o condominio, representado por `condominium_id`. O backend existente usa Postgres como fonte de verdade, RLS, RPCs `security definer`, `text` com `CHECK` para estados, timestamps `timestamptz`, UUIDs por `gen_random_uuid()` nos dominios recentes e feature flags em `condominium_features`.

## Decisao

Criar o dominio local com prefixo `verified_access_` dentro de migrations Supabase:

- catalogo global de tipos de servico;
- configuracao de tipos de servico por condominio;
- politicas versionadas por condominio;
- solicitacoes, detalhes de prestador, vagas e participantes;
- perfis locais de identidade protegidos;
- avaliacoes de elegibilidade;
- outbox e auditoria especificas do dominio.

Todas as tabelas locais operacionais carregam `condominium_id`. Relacionamentos entre tabelas locais usam chaves compostas com `condominium_id` sempre que o schema existente permite. A tabela legada `persons` nao e reutilizada.

## Seguranca e privacidade

Dados pessoais sensiveis ficam somente em colunas `bytea` de ciphertext e fingerprints/HMAC locais separados, com versao de chave. A Fase 1A nao inclui descriptografia SQL, secrets, biometria, selfies, certidoes, payloads policiais ou providers reais.

RLS fica habilitada em todas as tabelas novas, com postura default-deny. `anon` nao recebe acesso direto. `authenticated` nao recebe escrita direta. Operacoes futuras serao abertas por RPCs especificas em fases posteriores.

## Feature flags

A Fase 1A cadastra `VERIFIED_ACCESS` e `VERIFIED_ACCESS_BACKGROUND_CHECK` no mecanismo existente `condominium_features`, sempre com `enabled = false` para todos os condominios existentes.

## Consequencias

- Nao ha funcionalidade visivel ao usuario ao final da Fase 1A.
- O schema fica pronto para as fases 1B, 1C e 1D sem criar objetos centrais de rede.
- Ativacao de policies, state machines, providers e UI permanecem fora desta fase.
