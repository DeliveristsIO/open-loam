---
title: Architecture Decisions
permalink: /adr/
---

# Architecture Decision Records

An ADR captures **one decision**: the context, the choice, and its consequences.
They exist so a decision is made once, on purpose, and stays legible to the next
person — or the next agent — instead of being re-litigated or reverse-engineered
from the code.

## The convention

- One file per decision: `NNNN-short-kebab-title.md`, numbered in order.
- Keep it short — context, decision, consequences, and a status. A page, not an essay.
- **Status**: `Proposed` → `Accepted` → (`Superseded by NNNN` | `Deprecated`).
  A decision that changes gets a *new* ADR that supersedes the old one; the old
  file stays (history is the point), its status updated.
- Link the ADR from the code or doc it governs when it helps.

## Template

```markdown
# NNNN. <Title>

- Status: Accepted
- Date: YYYY-MM-DD

## Context
What forces are at play — the problem, the constraints, what we know.

## Decision
The choice, stated plainly.

## Consequences
What this makes easy, what it makes hard, and what it rules out. Note the
kill-criterion or revisit condition if there is one.
```

## For agents (the "specs-as-ADRs" flow)

Before a non-trivial feature, write the spec **as an ADR** — the decision and its
consequences — then implement against it. After, record what you learned in
[`ai/lessons.md`](https://github.com/DeliveristsIO/open-loam/blob/main/ai/lessons.md). The ADR is the intent; `lessons.md` is the
hindsight. Both are inputs the next agent reads.

## Index

- [0001 — Row-level tenancy]({% link _adr/0001-row-level-tenancy.md %})
- [0002 — In-gem implementations before wrapping proven gems]({% link _adr/0002-in-gem-implementations.md %})
- [0003 — A generated ERB admin, not a dependency]({% link _adr/0003-generated-erb-admin.md %})
- [0004 — A byte-budgeted AGENTS.md as the agent contract]({% link _adr/0004-agents-md-contract.md %})
- [0005 — Events as the decoupling seam; two subscriber tiers]({% link _adr/0005-event-backbone-two-tiers.md %})
- [0006 — Evaluating Avo as an alternate admin backend]({% link _adr/0006-avo-admin-evaluation.md %})
