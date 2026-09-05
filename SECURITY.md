# Security policy

## Reporting a vulnerability

Use [private vulnerability reporting](https://github.com/DeliveristsIO/open-loam/security/advisories/new).
It is enabled on this repository, so the report stays between you and the
maintainers until a fix ships.

**Please do not open a public issue for a vulnerability.** OpenLoam is a
multi-tenancy and authorization framework — a report here is a working attack
against every app built on it.

Expect a first response within a week. There is no bounty; credit in the
advisory and the CHANGELOG if you want it.

## Scope

In scope: anything that crosses a boundary OpenLoam claims to hold — the tenant
boundary, a `OpenLoam::Policy` field rule, authentication and MFA, the
encryption at rest, the MCP tool surface, or the inbound/outbound webhook
verification.

Out of scope: the demo app's deployment posture (see below), and findings that
require an attacker to already hold operator-level access.

## Supported versions

Pre-1.0, so only the latest minor release is supported. Fixes land on `main` and
in the next release; there are no backports.

## Known, accepted

**`demo/config/master.key` is in git history and is public.** The demo exists to
be read and run locally; it holds no real data and must never be deployed. The
key is not used by the gem, which reads `OPEN_LOAM_MASTER_KEY` from the
environment. Treat every credential under `demo/` as public.

**Record-swap within one tenant, table and column.** Encrypted values are bound
to their (scope, table, column) by the AES-GCM AAD, not to the record id — the
id is unknown at INSERT time. Moving a ciphertext between two rows of the same
column in the same tenant therefore passes the auth tag. Documented in
[the encryption page](docs/_agents/encryption.md).

**Free-text search does not apply `readable:` rules.** The generated `search`
scope spans every searchable attribute regardless of the field policy, so a
role can infer a restricted string column's contents by which queries match.
Sorting and filtering are gated; search is a model-level scope with no actor in
hand, and making it role-aware is a design change rather than a patch.

**A tenant can squat an SSO domain it does not own.** `domain` carries a global
unique index, so registering one blocks the genuine owner from configuring SSO
for it — though an unverified provider can no longer *do* anything with the
claim. An operator can delete the squatting row.

## For people running OpenLoam

- Set `OPEN_LOAM_MASTER_KEY` from the environment or a secret manager. Never
  commit it. To rotate, see
  [the encryption page](docs/_agents/encryption.md).
- SSO providers do nothing until an operator confirms domain ownership
  (`rake open_loam:sso:verify_domain`). Confirm it out of band — the person who
  typed the domain is the party the check exists to constrain.
- Run `bin/brakeman` with `--add-engines-path` pointed at the gem, as CI does.
  Scanning only your own `app/` leaves the framework's code unanalyzed.
