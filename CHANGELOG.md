# Changelog

Notable changes to OpenLoam. This project follows [semantic versioning](https://semver.org),
with the caveat that 0.x releases may break the public surface; the
[backward-compatibility contract](BACKWARD_COMPATIBILITY.md) names what is
frozen and what is not.

## Unreleased

### Added

- **The event log — `OpenLoam::EventLog` + `OpenLoam::EventRecord`.** Every
  published event is captured as an append-only, tenant-scoped row, so a
  tenant's history is queryable and replayable rather than only observable live.
  `EventLog.read(name_or_prefix, since:, limit:)` and `EventLog.replay(...)` take
  the same patterns as `Events.subscribe`. `OpenLoam::DurableEvents` had made
  *delivery* durable; this closes *capture*, which its contract explicitly did
  not cover.

  Capture is on by default and captures everything except
  `OpenLoam.uncaptured_events` (default: `["open_loam.progress."]`). It runs
  inline, so a failed insert propagates into the publishing operation. Retention
  is `OpenLoam.event_log_retention` (90 days), swept per tenant by
  `OpenLoam::EventLogPruneJob`. New apps get the table from
  `rails g open_loam:install`; existing apps need the
  `create_open_loam_event_records` migration.

### Changed

- **The four "wrap a proven gem" roadmap items are resolved**, recorded in
  [ADR 0007](docs/_adr/0007-proven-gem-swaps-resolved.md). Tenancy (L-201) and
  audit (L-203) stay in-gem for good; the Pundit swap (L-202) is declined, but
  the gap it exposed — no `verify_authorized`-equivalent guard — is tracked
  separately. L-204 is the event log above. No public `OpenLoam::` contract
  changed.

## 0.2.0 — 2026-09-05

### BREAKING

- **Ruby namespace renamed `Loam` → `OpenLoam`**, and every dependent
  surface with it: the CLI (`rails g open_loam:install`,
  `rails g open_loam:entity`, `bin/rails open_loam:mcp:serve`, etc.), all
  `loam_*`-prefixed database tables and columns, `LOAM_*` env vars (now
  `OPEN_LOAM_*`), and the outbound webhook signature header
  (`X-Loam-Signature` → `X-OpenLoam-Signature`, tracked in
  [BACKWARD_COMPATIBILITY.md](BACKWARD_COMPATIBILITY.md)). The RubyGems
  package name is unaffected — it stays `open-loam`, as it already was.
- No back-compat shim is provided for any of this. Per 0.1.0/0.1.1 above, no
  production deployment exists yet, so there is nothing running against the
  old names to break in place — an app installed from an 0.1.x generator
  would need its own table/env-var renames to upgrade, which is why this
  ships as a breaking 0.x release rather than a deprecation cycle.
- One literal is deliberately **not** renamed, ever: the encryption
  key-derivation inputs in `lib/open_loam/encryption/key_provider.rb`
  (the HKDF `SALT` and `info` strings) and the AAD prefix in
  `lib/open_loam/encryption.rb#aad`. These are inputs to key/tag
  derivation, not identifiers — changing any of them would silently
  break decryption of already-encrypted data.

## 0.1.1 — 2026-09-04

No functional change. The packaged code is byte-identical to 0.1.0 — only CI
configuration moved, and workflows are not part of the gem.

This version exists to exercise the release pipeline end to end, so that the
first keyless publish is a version nothing depends on rather than one that
matters.

### Changed

- Releases are published from CI using RubyGems trusted publishing. GitHub's
  OIDC token is exchanged for short-lived credentials, so no API key is held on
  a maintainer's machine or in repository secrets, and publishing is gated on an
  approval in the `release` environment.

## 0.1.0 — 2026-09-04

First public release. OpenLoam is a working, tested prototype: the foundation and
the agent workflow are complete end to end, but no production deployment has
used it yet. Evaluate it as a prototype, not as proven infrastructure.

### The foundation

- **Multi-tenancy** — `OpenLoam::TenantRecord` scopes every query, job and event to
  the current tenant. A missing tenant context raises `OpenLoam::MissingTenantError`
  rather than silently widening a query.
- **Authorization** — roles, policies, field-level write access, and
  deny-by-default wildcard feature permissions (`equipment.*`).
- **Authentication** — password auth, MFA with step-up, rate-limiting and
  lockout, and per-tenant OIDC single sign-on with JIT provisioning.
- **Audit and history** — audit trails, record history, undo, soft deletion,
  and optimistic-locking protection against concurrent edits.
- **Encryption** — per-tenant AES-256-GCM field encryption with AAD binding,
  and blind indexes for exact-match lookup on encrypted values.
- **Business modelling** — runtime custom fields with a read-model index,
  managed dictionaries, declared workflows with role-gated approvals, saved
  views, configurable dashboards, content translations, comments and
  attachments.
- **Integration** — token-authenticated JSON APIs with generated OpenAPI 3.1
  docs, signed outbound webhooks, replay-resistant inbound webhooks, and a
  two-tier event bus (in-process subscribers plus durable, retryable delivery
  with dead-lettering).
- **Operations** — notifications, live browser updates, an atomic-claim
  scheduler, long-running task progress, and policy-aware bulk CSV
  import/export.

### For AI coding agents

- **`AGENTS.md`** — the contract, generated into the host app, telling an agent
  where code belongs and which boundaries it must preserve.
- **Generators as the interface** — `open_loam:install` and `open_loam:entity` are the
  supported way to add a feature, for humans and agents alike.
- **Structural guardrails** — tests that fail the build on a missing tenant
  scope, a stray `.unscoped`, or an oversized `AGENTS.md`.
- **A human-approval gate** — `OpenLoam::PendingActions` stages an agent-proposed
  mutation for review before it touches business data.
- **The golden-tasks benchmark** and `OpenLoam::Eval` scorer. Results, methodology
  and caveats are published at
  <https://deliveristsio.github.io/open-loam/agents/golden-tasks/>; they come
  from a single internal run and are not independently reproduced.

### Database keys

- Generators follow the host app's primary key type — `bigint`, `uuid` or
  `string` — resolved from `--primary-key-type`, then the app's own
  `config.generators` setting, then `bigint`. This covers `create_table`,
  `t.references`, and the polymorphic `*_id` columns that cannot use
  `t.references`.
- `OpenLoam::GeneratedKey` assigns a UUID before create when the key is not an
  integer, since a string primary key has no database default. Integer keys are
  still generated by the database.

### Known limitations

- No production validation. The next milestone is one measured real build, not
  more modules.
- The benchmark is internal and has been run once.
- Requires Rails 7.1 or newer and Ruby 3.2 or newer. The demo and CI run on
  SQLite; other adapters are untested.
