# The Loam manifesto

**Convention is fertility.**

Every business app is a field. Most teams start by clearing rocks — auth,
tenancy, permissions, audit, an admin — before a single seed goes in. Quarters
disappear into ground-clearing that no customer will ever see.

We believe that ground should already be rich.

---

**1. Decide once, well, together.**
A hundred small architectural decisions, made consistently, are worth more than
any feature. Loam makes them — and makes them *agree with each other* — so you
never re-argue tenancy or permissions per project.

**2. Convention is what makes an agent safe.**
An AI agent is a fast, tireless junior who has never seen your codebase. It
thrives in a codebase with one obvious way to do things and dies in a snowflake.
The same conventions that make Rails pleasant for humans make it *tractable* for
agents. Loam pushes that legibility all the way up to the business domain.

**3. Guardrails, not guidelines.**
Tenancy and authorization must be structural — enforced by base classes and
default scopes — not politely suggested. A boundary an agent (or a tired human)
can forget is not a boundary. Loam's invariants fail loudly, in tests, before
they leak.

**4. Assemble, don't reinvent.**
The Rails ecosystem already solved tenancy, events, policies, auditing. Loam's
job is the *fusion* and the *opinion*, not another rewrite. Small surface, low
risk, proven parts.

**5. Grow the 20%, not the 80%.**
Your business is the 20% no framework can give you. Everything Loam does is in
service of getting you there on day one — so the first thing you plant is a
feature, and it grows.

---

**Loam** — not a market. The ground beneath one.

You don't admire loam. You plant in it.
