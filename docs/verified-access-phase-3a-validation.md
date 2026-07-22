# Verified Access Phase 3A Validation

## Scope

Phase 3A implements only local invitations, opaque tokens, authenticated
resident operations and deterministic fake messaging. It does not implement a
public registration surface, participant creation, PII capture, a real
provider, a worker, Phase 3B or Phase 3C.

Validated technical head:
`43de21a3f4b15206565e911cc4dcf60869597538`.

## Database

Migrations applied from scratch:

- `20260721100000_verified_access_invitations.sql`;
- `20260721101000_verified_access_invitation_rpcs.sql`.

Objects added:

- `verified_access_invitations`;
- `verified_access_invitation_commands`;
- four authenticated resident RPCs;
- three internal Phase 3A helpers;
- no-login exact-signature executor role.

Both tables have RLS enabled with no policies and no direct grants to
`PUBLIC`, `anon`, `authenticated` or `service_role`. Only `authenticated`
inherits the exact RPC executor role. Helpers remain inaccessible to all
runtime roles.

The invitation stores only `v1:<sha256-hex>`. One partial unique index permits
at most one `PENDING` or `SENT` invitation per slot. Request, slot, invitation,
command and actor are tied to the same condominium. The slot remains `OPEN` and
Phase 3A creates no participant.

## Token And Messaging

The issuing Edge Function generates 32 random bytes with Web Crypto, encodes
them as unpadded base64url and sends only the versioned SHA-256 hash to the
database. The raw value exists only in the post-commit fake dispatch call.

Issue and resend return `dispatchRequired=true` only for the committed command
that generated or rotated the token. Idempotent replays return `false`, do not
dispatch again and do not expose a new token. Fake failures leave the domain
record `PENDING`; operational retry is a new resend command and rotates the
token.

The existing `MessagingProvider` remains compatible with participant-based
operations and additionally accepts the pre-participant target
`participantSlotId + invitationId` for invitation messages. No real transport,
destination or PII was introduced.

## Audit And Outbox

Issue, resend, revoke and materialized expiration write audit and outbox in the
same database transaction as the invitation change. Payloads contain only
tenant and domain identifiers, status, send count, timestamps and event code.
Raw tokens, token hashes, destination data and PII are absent. The fake runs
only after the RPC commit.

## Tests

Local tests actually executed:

- Deno format, lint and type check: success;
- Deno provider and Edge tests: 34 passed, 0 failed;
- admin-web lint: success;
- admin-web production build: success;
- `git diff --check`: success.

Docker and Supabase CLI were not exposed by the local Windows shell, so all
database execution evidence below comes from the disposable GitHub Actions
Supabase stack. No remote Supabase migration was used.

## CI Evidence

Green Phase 3A run:
<https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29871859260>.

Results:

- migrations from scratch: success;
- pgTAP: success;
- integration 1A, 1B, 1C, 2 and 3A: success;
- runtime role checks with a synthetic denied role: success;
- database lint: success;
- Phase 3A rollback: success;
- preservation of Phases 1A through 2 and `persons`: success;
- migration reapplication: success;
- post-reapplication pgTAP and integration: success;
- Edge format, lint, type check, tests and log/PII guard: success;
- admin-web lint and build: success.

Regression workflows at the same head:

- Phase 1A: `29871859501`, success;
- Phase 1B: `29871859419`, success;
- Phase 1C: `29871859388`, success;
- Phase 2: `29871859366`, success;
- Vercel preview: success.

## Corrective Cycles

The CI corrections were restricted to verified causes:

1. Run `29870602528`: PostgreSQL rejected multiple `%rowtype` records in one `INTO`; locked rows
   are now loaded separately without changing locking or authorization.
2. Run `29871011088`: the tenant-isolation fixture now expects the RPC's non-enumerating
   `INVITATION_TARGET_NOT_FOUND` code and counts the materialized expired row.
3. Run `29871296726`: the runtime ACL loop removed a record/alias collision.
4. Run `29871549672`: the synthetic denied role is temporarily granted to the
   non-superuser harness actor before `SET ROLE`, then revoked and dropped in
   the same transaction.

No correction widened grants or weakened tenant, token, audit or RLS rules.

## Rollback

`verified_access_phase_3a_rollback.sql` was executed successfully. It removes
the executor membership, RPCs, helpers, command table, invitation table and
executor role in dependency order. The cumulative Phase 1A workflow removes
Phase 3A before Phase 2, Phase 1C, Phase 1B and Phase 1A.

After rollback, the full migration chain was reapplied and pgTAP plus all
integration suites passed again.

## Safety Confirmations

- no remote migration was executed;
- `VERIFIED_ACCESS` remains disabled outside disposable test transactions;
- no feature was enabled remotely;
- `persons` and Expo were not changed;
- no participant or identity profile was created by Phase 3A;
- no PII, real destination, public endpoint, page or provider was added;
- no Phase 3B or Phase 3C implementation was started;
- no merge, mark-ready or force-push was performed;
- PR #7 remains draft.
