# Changelog

Notable changes to OpenLoam. This project follows [semantic versioning](https://semver.org),
with the caveat that 0.x releases may break the public surface; the
[backward-compatibility contract](BACKWARD_COMPATIBILITY.md) names what is
frozen and what is not.

## Unreleased

### Security

A full-repo audit found 16 issues; all are fixed here. Every fix ships with a
regression test that reproduces the original exploit. **Anyone running 0.2.0 or
earlier should upgrade**, and the migration notes below are not optional — three
of these change stored data.

Reported through [private vulnerability reporting](SECURITY.md) from now on.

**Cross-tenant account takeover through SSO (critical).** `SsoProvider#domain`
is typed by a tenant manager and `User` is global, so any tenant could register
a domain it did not own, point a provider at its own IdP, assert a verified
email on that domain, and be handed the matching account — then select any
tenant that user belonged to. A provider now does nothing until an operator
confirms ownership out of band (`rake open_loam:sso:verify_domain`): home-realm
discovery skips unverified providers, and `Sso.provision` refuses to link an
existing account through one. Editing `domain` revokes the confirmation.
**Every existing provider must be verified or SSO stops resolving for it.**

**The MFA lockout was fully bypassable.** `AuthThrottle.clear` deleted every
attempt kind, and a successful password login called it — so an attacker holding
the password could reset the TOTP counter before each guess and brute-force a
6-digit code without limit. `clear` now takes `kind:` and each factor clears only
its own.

**`readable:` field rules were ignored on most read paths.** The JSON API, the
generated admin index/show/form, the shared custom-fields partial, the CSV
export's custom-field columns, the history screen and the edit-conflict diff all
served values the policy restricted. All of them now apply the check. Sorting by
an unreadable column is refused too, in the admin and over MCP — ordering leaks
a ranking even when values are hidden. Export and import also stopped falling
back to the base `OpenLoam::Policy` for a model with no policy class, which
failed open.

**API tokens were stored in plaintext.** Only a SHA-256 digest is persisted now;
the value is shown once at creation. `authenticate` also re-checks the
membership, so removing someone from a tenant ends their machine access to it,
and managers can revoke another member's token — previously nobody could.

**SSRF through tenant-supplied URLs.** Webhook endpoints and the SSO issuer are
both fetched by the server and neither was validated, so either could be aimed
at `169.254.169.254`, loopback or a private range. New `OpenLoam::OutboundUrl`
validates shape at save and resolves-and-pins the address at fetch time, so DNS
rebinding cannot swap the target after the check. The SSO issuer additionally
requires `https` — the `client_secret` travels over it.

**Inbound webhook replay.** The HMAC covers the body, but the dedupe key
preferred an unsigned delivery-id header — so one captured delivery could be
replayed with a fresh header value and re-publish its event without limit.
`external_id` is now the body hash, which is the only signed material.

**A staged change was applied without checks.** `PendingAction#execute_change!`
resolved its target with a bare `constantize` and mass-assigned the stored
changeset, so a host staging a non-tenant-scoped target turned approval into a
cross-tenant `update!` on arbitrary columns. The target must now be a
`TenantRecord`, and both halves of the approver's policy apply: the action
(`create?`/`update?`/`destroy?`) and the fields the changeset writes. A policy
narrower than "any manager" — `destroy?` restricted to an owner, say — was
previously bypassed by staging the change and having a manager approve it.

**`security.mfa_required_roles` was advisory.** Login redirected to enrollment
and nothing checked again, so any other admin URL walked past it. Now enforced
on every request.

**Master-key rotation was impossible**, despite being documented and pointed at
for key compromise: swapping the key made every read fail before it could be
rewritten. Set `OPEN_LOAM_PREVIOUS_MASTER_KEY` to the outgoing key and
`open_loam:encryption:rotate` now works.

**The blind-index key was scoped to the tenant only**, unlike the ciphertext
AAD, so one value hashed alike across every searchable encrypted column — a dump
correlated rows across tables, and writing one such field was an equality oracle
against columns you could not read. The key now binds table and column.

**The uploaded import CSV** was passed as an ActiveJob argument and was not in
`filter_parameters`, so every row sat in the clear in the queue backend and the
request log — including columns headed for encrypted fields. It goes to blob
storage now, and the job purges it.

**Brakeman never scanned the gem** — only `demo/`, leaving the framework's own
`app/` and `lib/` unanalyzed. CI now passes `--add-engines-path`, which
immediately surfaced four warnings, all fixed. CI's `GITHUB_TOKEN` is read-only,
`.gitignore` matches key material anywhere, and the repository has secret
scanning, push protection and private vulnerability reporting enabled.

#### Migration

- `open_loam_api_tokens`: add `token_digest`, backfill `sha256(token)` per row,
  drop `token`. Tokens in use keep working. See the demo's
  `hash_open_loam_api_tokens`.
- `open_loam_sso_providers`: add `domain_verified_at`, then run
  `rake open_loam:sso:verify_domain[<id>]` for each provider you actually own.
  Until you do, SSO will not resolve for it.
- Searchable encrypted fields: re-index by running
  `rake open_loam:encryption:rotate[Model,tenant_id]` for each model that has
  one. The blind-index derivation changed, so existing `<field>_hash` values no
  longer match.
- `delivery_id_header` on inbound webhook sources is gone; the column can be
  dropped.

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

- **An authorization-called guard in the generated base controllers** (L-202).
  `verify_authorized!` fails any admin or API action that finished without
  calling `authorize!`, `require_role!` or `require_permission!`. Forgetting the
  check was previously silent — the screen just rendered. Screens authorized
  structurally declare `skip_authorization! "<reason>"`, and the reason is
  required, so every exemption is a documented claim.

  It runs *after* the action, so it is a development and test guard, not a
  runtime access-control layer. It raises `OpenLoam::AuthorizationNotPerformedError`,
  deliberately not a `NotAuthorizedError` — a developer bug must not render as a
  polite 403.

  Turning it on found two generated actions that never checked `read?` while
  their `show`/`deleted` siblings did: the admin and JSON `index`. Both now
  authorize. Existing apps will see the guard fire on any action of their own
  that never authorized.

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
