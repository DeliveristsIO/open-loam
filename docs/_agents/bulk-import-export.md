---
title: Bulk Import / Export
description: Policy- and encryption-aware CSV export/import with column mapping, dry-run, and dedupe-by-key.
nav_order: 9
---

# Bulk import / export


Every entity index carries (manager-only) Export CSV, Import CSV, and a
bulk-action bar. Export (`OpenLoam::Export.csv`) is policy- and encryption-aware —
readable columns only, encrypted fields redacted. Import (`OpenLoam::Import`) maps CSV
columns to WRITABLE fields only (a mapping to `tenant_id`/a non-permitted field is
refused; the entity_type is whitelisted to a TenantRecord), with a dry-run,
update-by-key, a per-row skipped-row error file, and background progress. Bulk
actions (`OpenLoam::Bulk`: soft-delete / set-field / export-selected) are
policy-checked per record and tenant-scoped. New entities get all of this from
the generator.

