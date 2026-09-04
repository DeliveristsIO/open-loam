# Contributing to Loam

Loam is a foundation other people (and their AI agents) build businesses on, so
the bar is consistency over cleverness: there should be **one obvious way** to
do each thing, and a change is good when it makes that one way clearer. This
guide is short on purpose.

## Repository layout

```
lib/loam/               the gem: tenancy, policy, audit, events, custom fields,
                        workflow, notifications, webhooks, comments, search, ...
app/models/loam/        engine models (Tenant, Membership, AuditRecord, ...)
lib/generators/loam/    install + entity generators — the one interface
test/                   generator harness (builds real Rails apps in tmp)
demo/                   equipment-rental app built with the generators
ai/                     golden-tasks benchmark + recorded runs
docs/                   guides, agent deep-dives, ADRs (Jekyll site source)
```

## Getting set up

Requires Ruby ≥ 3.2 and a recent Rails (CI runs against released Rails; the demo
tracks edge). No database server needed — everything runs on SQLite.

```bash
git clone git@github.com:DeliveristsIO/open-loam.git
cd open-loam

# the gem's generator harness (builds throwaway Rails apps and exercises them)
gem install rails rake minitest
rake test

# the demo app
cd demo && bundle install && bin/rails db:migrate db:seed && bin/rails test
```

## The two test suites — both must stay green

1. **`rake test`** at the repo root — the generator harness. It generates a
   fresh Rails app in a temp dir, runs `loam:install` + `loam:entity`, and
   asserts the generated app's own suite passes. If you touch anything under
   `lib/generators/` or the templates, run this.
2. **`cd demo && bin/rails test`** — the demo app, which uses the generators the
   way a real project does. If you touch `lib/loam/` behavior, run this.

A change to a generator template also has to be reflected in the demo's already
-generated copy (the demo doesn't re-run generators). The harness will catch a
broken template; a stale demo copy it won't — sync it yourself.

## Invariants you must not break

These are the promises the whole project rests on. They're enforced by
`test/loam_guardrails_test.rb` in every generated app, so breaking one shows up
as a failing test, not a review comment:

- **Every business model inherits `Loam::TenantRecord`.** Never
  `ApplicationRecord` for tenant data.
- **Never `.unscoped` on a tenant-scoped model** in app code. The only blessed
  cross-tenant lookups live in gem code (`Loam::ApiToken.authenticate`,
  `Loam::Membership.tenants_for`) and are commented as such.
- **Never rescue `Loam::MissingTenantError`** — it means a missing
  `Loam.as_tenant` context upstream; fix that instead.
- **Every controller action checks a policy; forms use
  `policy.permitted_fields`** — no hand-rolled `params.permit` lists.
- **Event names are `domain.thing.happened`** (three+ dot-separated segments).
- **`AGENTS.md` stays under 32 KB** — a guardrail test enforces it, because
  agent harnesses silently truncate an oversized instruction file.

## Adding a capability

Prefer extending the generators over one-off code, because the generator output
*is* the product — it's what an agent and a reviewer read. A new pillar usually
means: a concern in `lib/loam/`, wiring in the `install`/`entity` generator
templates, the demo synced, tests in both suites, and a row in the generated
`AGENTS.md` (mind the byte budget). Keep every file under 500 lines and match
the surrounding comment style: comments state a constraint the code can't show,
not narration.

## For AI agents

If you are an agent working in a Loam **app**, your contract is that app's
`AGENTS.md` — follow it exactly; the guardrail tests are the referee. If you are
changing the **framework** (this repo), this file is your contract, and the
golden-tasks benchmark in `ai/` is how the framework's agent-legibility is
measured — a change that makes those tasks harder or less safe is a regression.

## Commits and pull requests

- Conventional-commit subjects (`feat:`, `fix:`, `docs:`, `chore:`), imperative
  mood, the *why* in the body when it isn't obvious.
- One logical change per commit; keep the diff small enough to review in
  minutes — the same standard the framework asks of an agent's output.
- Both suites green and no new guardrail violation before you open a PR. CI runs
  both on every push.
- New behavior comes with tests. A bug fix comes with the regression test that
  would have caught it.

## Releasing

Releases are published by tag, from CI, using RubyGems trusted publishing —
GitHub's OIDC token is exchanged for short-lived credentials, so no API key
exists on anyone's machine or in repo secrets.

```bash
# 1. bump lib/loam/version.rb and add the release to CHANGELOG.md
# 2. commit, then:
git tag -a v0.2.0 -m "Loam 0.2.0"
git push --follow-tags
```

`.github/workflows/release.yml` then re-runs the harness against the tagged
commit and publishes. It re-runs deliberately: `ci.yml` only covers pushes to
`main`, a tag can point at any commit, and a published gem version can never be
re-pushed.

The `release` environment gates the publish, so any approval rule configured on
it applies. The trusted publisher itself is registered at rubygems.org against
this repository, `release.yml`, and that environment.

Don't run `gem push` by hand — it would publish a version that never went
through the gate.

## License

By contributing you agree your contributions are licensed under the project's
[MIT license](LICENSE).
