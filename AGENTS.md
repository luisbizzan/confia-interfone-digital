# Confia — instruções do repositório para agentes

Estas regras valem para todo o repositório. Um `AGENTS.md` mais próximo do arquivo alterado pode acrescentar regras específicas e tem precedência no seu diretório.

## 1. Fonte de verdade do Acesso Verificado

Antes de qualquer trabalho relacionado ao Acesso Verificado ou à Rede Confia, leia nesta ordem:

1. `docs/product/verified-access/README.md`
2. `docs/product/verified-access/DECISIONS.md`
3. `docs/product/verified-access/ROADMAP.md`
4. o plano da fase atual em `docs/product/verified-access/phases/`
5. `docs/product/verified-access/execution/CURRENT_TASK.md`
6. `docs/product/verified-access/SPECIFICATION.md`
7. `docs/product/verified-access/SECURITY_AND_PRIVACY.md`
8. `docs/product/verified-access/INTEGRATIONS.md`

Em caso de conflito:

```text
DECISIONS.md
    > CURRENT_TASK.md
    > plano da fase atual
    > SPECIFICATION.md
    > documentos de referência/históricos
```

Os documentos versionados substituem cópias externas, prompts antigos e resumos de conversas.

## 2. Contrato de execução

Antes de editar:

- confirme repositório, branch, worktree, base SHA e `git status`;
- execute `git fetch origin --prune`;
- leia todos os `AGENTS.md` aplicáveis;
- preserve alterações locais preexistentes;
- apresente arquivos previstos, migrations, testes, riscos e diferenças de arquitetura;
- execute somente a tarefa autorizada em `CURRENT_TASK.md`.

Não execute sem autorização explícita:

- `git reset`, `git restore`, `git clean` ou `git stash` sobre trabalho de terceiros;
- rebase ou force-push;
- merge;
- migration remota;
- habilitação de feature;
- deploy manual;
- mudança de fase.

## 3. Banco e Supabase

- Postgres/Supabase é a fonte de verdade do backend.
- Invariantes críticas devem ser garantidas no banco quando possível.
- Não edite migration aplicada remotamente.
- `db push --dry-run` não substitui execução real em banco descartável.
- Toda migration precisa de testes, rollback, reaplicação e lint.
- Nunca use dados pessoais reais em testes.
- Preserve `condominium_id` nas entidades locais.
- Tabelas centrais da Rede Confia não pertencem a um tenant e não podem ser expostas diretamente aos usuários dos condomínios.

## 4. Segurança e privacidade

- PII não pode aparecer em logs, traces, outbox, auditoria, URLs ou mensagens de erro.
- Não armazene CPF, documento, telefone, nome, filiação ou nascimento em texto aberto quando o modelo exigir ciphertext.
- Não use hash sem segredo para CPF ou identificadores de baixo espaço de busca.
- Não armazene selfie, template facial ou embedding facial localmente.
- Não implemente reconhecimento facial 1:N ou galeria facial global.
- `LOCAL_DENIED` nunca cria automaticamente `NETWORK_SIGNAL`.
- Não existe `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` ou blacklist permanente.
- Homonímia, falha técnica, provider indisponível ou resultado inconclusivo nunca equivalem a antecedente.
- Decisões de alto impacto exigem revisão, motivo, auditoria, expiração e contestação.

## 5. Autorização

- RLS habilitada em toda tabela nova.
- Postura default-deny.
- Revogue privilégios preexistentes antes de conceder a matriz mínima.
- Não conceda acesso direto a `PUBLIC`, `anon` ou `authenticated` sem requisito e teste explícitos.
- Funções `security definer` exigem justificativa, `search_path` fixo e grants mínimos.
- Revisão sensível depende de identidade estável, RBAC específico e autenticação reforçada.

## 6. Testes e CI

Cobrir, conforme aplicável:

- schema e constraints;
- tenant isolation e IDOR;
- grants e RLS com papéis reais;
- casos positivos e negativos;
- não propagação de decisões locais;
- ausência de PII;
- rollback e reaplicação;
- db lint;
- admin lint/build.

Diagnósticos de CI devem ser sanitizados. Não publique chaves locais ou remotas em artifacts.

## 7. Aplicações

Ao alterar `apps/admin-web`, leia também `apps/admin-web/AGENTS.md` e a documentação local da versão instalada do Next.js.

Ao iniciar trabalho no app Expo, siga o `AGENTS.md` do repositório do aplicativo e a documentação da versão instalada do Expo.

## 8. Relatório final

Sempre informe:

- branch, base e SHAs;
- arquivos alterados;
- migrations;
- testes realmente executados;
- CI e links;
- diferenças entre plano e implementação;
- blockers;
- confirmação de nenhuma migration remota e nenhuma feature habilitada quando esses gates estiverem fechados.
