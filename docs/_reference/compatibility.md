---
title: Backward compatibility
description: What surfaces of OpenLoam are frozen — the promise OpenLoam makes about not breaking your app.
nav_order: 3
permalink: /reference/compatibility/
---

# Backward compatibility

OpenLoam is pre-1.0 and marked a prototype, but it already keeps a written
inventory of its **frozen public surfaces** — the things an app or an agent
builds against that OpenLoam promises not to break without a major-version bump
and a migration path. Everything not on that list is an internal detail and
may change in a minor release.

The full contract lives at
[`BACKWARD_COMPATIBILITY.md`](https://github.com/DeliveristsIO/open-loam/blob/main/BACKWARD_COMPATIBILITY.md)
in the repo root. It covers, section by section: tenancy (`OpenLoam::TenantRecord`,
`OpenLoam.tenant!`, `OpenLoam.as_tenant`), domain events (naming, publish/subscribe
signatures), the generators as the one interface, authorization (`OpenLoam::Policy`),
encryption at rest (the `v1:`/`v2:` ciphertext format), inbound/outbound
webhooks, the JSON API, custom fields, audit & undo, and a set of other keyed
surfaces (overrides, feature flags, and similar registries) — plus what
"frozen" actually means (shape is stable; adding an optional parameter or a
new value to an open set is fine, renaming or tightening semantics is not) and
the process for changing a frozen contract when it's unavoidable.

## Related pages

- [Configuration]({% link _reference/configuration.md %})
- [Pillar implementation reference]({% link _reference/pillars.md %})
