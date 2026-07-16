# ADR: Verified Access Network Foundation

Date: 2026-07-16

## Status

Accepted for Phase 1B implementation.

## Context

Phase 1A created tenant-local Verified Access records for requests, policies,
identity profiles, participants, outbox and audit. Phase 1B needs a central
network foundation that can later support cross-condominium identity and signal
review without enabling any network decisioning or copying civil PII into a
central table.

The repository documentation defines strict limits for this phase:

- all network features remain disabled;
- tenants cannot read or write central network tables;
- `service_role` has no direct operational write path to central network
  tables;
- central tables do not store plaintext civil PII or ciphertext copied from
  tenant records;
- phone, e-mail, name, facial and biometric data are not network identifiers;
- no SQL HMAC helper, RPC, view, Edge Function, search API or provider
  integration is introduced;
- local denials and open cases do not create network signals;
- only future, active and unexpired signals may become actionable in later
  phases.

## Decision

Create a Phase 1B database-only foundation with three disabled feature flags and
seven central tables:

1. `verified_access_network_subjects`
2. `verified_access_network_subject_identifiers`
3. `verified_access_network_subject_links`
4. `verified_access_network_security_cases`
5. `verified_access_network_signals`
6. `verified_access_network_signal_reviews`
7. `verified_access_network_appeals`

The tables are structural only. They use declarative constraints, composite FKs
to Phase 1A tenant-local tables, indexes for future review workflows, RLS
enabled with no policies, and explicit privilege revocation from `PUBLIC`,
`anon`, `authenticated` and `service_role`.

Network identifiers are HMAC values supplied by future application/provider
layers. This phase stores the resulting HMAC, key version and canonicalization
version but does not implement canonicalization or HMAC generation in SQL.

Network signals are restricted to:

- `INFORM_AUTHORIZED_REVIEWER`;
- `REVALIDATE_IDENTITY`;
- `REQUERY_OFFICIAL_SOURCE`;
- `REQUIRE_MANUAL_REVIEW`;
- `HOLD_CREDENTIAL`.

The schema intentionally excludes `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` and
`PERMANENT_BLACKLIST`.

Network signals must reference a `SUBSTANTIATED` source case for the same
network subject. This is enforced by a composite FK and by a `security invoker`
trigger that validates source status only; it does not activate signals or
propagate effects to tenant participants.

## Consequences

The central model can be tested and reviewed without enabling any tenant-facing
behavior. Future phases must add audited application services, privacy review,
feature-flag gating, operational propagation and provider integrations before
any central signal affects a tenant workflow.

Until then, Phase 1B data remains inaccessible to tenants and runtime roles by
direct table access.

## Non-Decisions

This ADR does not approve:

- network search;
- Edge Functions or RPCs;
- real HMAC or canonicalization implementation;
- background-check provider calls;
- app or admin UI changes;
- automatic denial;
- participant eligibility propagation;
- central storage of CPF, phone, e-mail, name, facial or biometric data.
