# CURRENT TASK — NO ACTIVE IMPLEMENTATION

## Estado

Fase 1B concluída nesta branch e em revisão no draft PR:

```text
https://github.com/luisbizzan/confia-interfone-digital/pull/3
```

Não reexecutar a Fase 1B a partir deste arquivo.

## Escopo Fechado

A Fase 1B implementou a fundação inerte da Rede Confia:

- migrations locais;
- sete tabelas centrais;
- feature flags de rede desligadas;
- RLS default-deny;
- revogação de grants;
- constraints e triggers estruturais;
- pgTAP e integração;
- rollback e reaplicação;
- CI GitHub Actions.

## Próxima Fase

A Fase 1C não está autorizada.

Aguardar:

- merge da Fase 1B;
- confirmação pós-merge;
- novo contrato versionado em `CURRENT_TASK.md`.

## Restrições Permanecem

- Não executar migrations remotas.
- Não habilitar feature flags.
- Não alterar `persons`.
- Não alterar o app Expo.
- Não implementar Fase 1C ou 1D sem novo contrato.
- Não criar API, RPC, provider, UI ou operação de rede a partir deste estado.
