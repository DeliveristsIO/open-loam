# Async CSV export — Vanilla Rails vs Loam

An internal, single-task A/B run comparing an established conventional Rails
baseline with an equivalent Rails + Loam baseline. Both coding-agent sessions
received the same feature prompt: add a manager-only asynchronous Customer CSV
export that preserves the active status filter, runs through Active Job, and
produces a downloadable file.

This run measures whether Loam changes the implementation surface. It does
**not** establish a correctness advantage: both implementations passed every
hidden contract assertion.

## Headline

| | Vanilla Rails + AI | Loam + AI |
|---|---:|---:|
| Hidden evaluator | PASS | PASS |
| Hidden tests / assertions | 7 / 76 | 7 / 76 |
| Full suite | 46 tests / 196 assertions | 57 tests / 293 assertions |
| Files changed | 18 | 9 |
| Insertions / deletions | +477 / -8 | +471 / -0 |
| New persistence model | `CustomerExport` | None |
| New migration | Yes | No |
| New dependency | `csv` | None |

**Correctness is a tie.** The useful signal is architectural: the Loam agent
changed half as many files and reused tenant context, authorization,
`Loam::Export`, and `Loam::ProgressJob`. The Vanilla agent had to introduce its
own export record, migration, associations, controller, job, views, and CSV
dependency.

Total insertions are almost equal, so this is not evidence of dramatically
less typing. Both agents wrote extensive tests, and the Loam agent added 77
lines of ADR/lessons documentation. The narrower Loam result is about fewer
new architectural concepts and persistence pieces, not raw line count.

## Contract exercised

The evaluator established deterministic ACME and GLOBEX tenants and checked:

1. An ACME manager can create an export.
2. An ACME member cannot create one.
3. An active-filtered export includes the active ACME customer.
4. It excludes the inactive ACME customer.
5. CSV rows contain name, email, and status.
6. ACME exports contain no GLOBEX data.
7. A GLOBEX manager can create an export.
8. GLOBEX exports contain no ACME data.
9. A manager in another tenant cannot download ACME's export.
10. Generation enqueues and executes through the real background-job path.

The two application-specific evaluators enforced the same business contract
and produced the same 7-test, 76-assertion tally.

## What each implementation built

### Vanilla Rails

The Vanilla implementation added a `CustomerExport` model and database table,
organization/user associations, a dedicated controller, an Active Job, export
index/download views, routes, and the `csv` gem. Tenant ownership and download
authorization are application code that this feature must maintain.

### Loam

The Loam implementation added an Active Job and customer-controller/view
actions, but stored export status and output in the existing tenant-scoped
`Loam::ProgressJob`. It generated content with `Loam::Export.csv`, carried
tenant and actor identifiers into the job, and relied on `TenantRecord` scoping
for export lookup. It needed no application model, schema change, association,
or dependency.

## Caveats

- This is one internal run, not an independently reproduced experiment or a
  statistically meaningful success-rate comparison.
- The protocol requested the same coding agent and model for both feature runs,
  but the harness did not record model/session metadata and therefore cannot
  verify that condition from its artifacts.
- The evaluator was committed before the feature runs, but was agent-authored
  after inspecting both baselines. It is a strong regression contract, not an
  independent third-party audit.
- Loam's entity generator already supplied a synchronous, manager-gated,
  policy-aware CSV export. The Loam task extended existing export machinery to
  an asynchronous/downloadable flow; it did not begin from zero. This is a real
  framework benefit, but also an intentional asymmetry that must be disclosed.
- Evaluator wall-clock times are test-run times, not agent implementation times,
  and are not comparable performance measurements.
- The original harness used plain `git diff`, which omitted newly created
  files. The complete patches below were regenerated with intent-to-add entries
  so new files are included.
- The harness stored a mutable absolute path to the Loam checkout rather than
  its commit SHA. The exact Loam source revision used by the run cannot be
  proven from the result artifacts alone.

## Implementation review notes

Passing the contract does not make either patch a production reference
implementation. Two storage/reliability details are visible in the artifacts:

- Both implementations persist the complete CSV in a database column. That is
  acceptable at prototype scale but should become streamed object storage for
  large exports.
- The Loam `CustomerExportJob` catches generation errors, marks its
  `Loam::ProgressJob` failed, and does not re-raise. The queue therefore sees a
  successful execution and will not apply its normal retry policy. The Vanilla
  job records failure and re-raises. A production Loam implementation should
  preserve the progress failure state and then re-raise unless a deliberate
  no-retry policy is configured.

Neither issue changes the measured PASS: retry behavior and large-export
storage were outside the frozen business contract. They are recorded so the
artifact is useful for engineering review rather than mistaken for endorsed
production code.

## Conclusion

The defensible conclusion is:

> Both agents produced correct and tenant-safe features. In this run, Loam did
> not improve the pass rate; it reduced the amount of application-specific
> architecture needed to reach the same result.

That distinction matters. This run supports Loam's composability and reduced
plumbing thesis. It should not be cited as evidence that Vanilla Rails failed,
that Loam was faster, or that Loam improved correctness in this task.

## Artifacts

- [Vanilla complete baseline-to-feature patch](artifacts/2026-08-26-async-csv-export/vanilla-full.diff)
  — SHA-256 `c1e2c1e2d0e24b380565b92c18997623b0fb874a3ac15960b7563623501dafdd`
- [Loam complete baseline-to-feature patch](artifacts/2026-08-26-async-csv-export/loam-full.diff)
  — SHA-256 `e30905931536d4fcb1cf70e60ac89aa9f6790dcb2a5cbfac2c4b7d6e2092dd03`

Both complete patches passed `git diff --check`. After the hidden evaluation,
both full application suites were rerun successfully.
