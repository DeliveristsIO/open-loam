---
title: Encryption at Rest
description: Per-tenant AES-256-GCM field encryption, the blind index for searchable fields, and key scoping.
nav_order: 4
---

# Encryption at rest


Sensitive columns (SSN, tax id, email) are encrypted at rest, per tenant, so a
DB dump leaks nothing and one tenant's key never decrypts another's. Generate
them — `bin/rails g open_loam:entity Patient name:string ssn:string email:string
--encrypt ssn --encrypt-searchable email` — or declare on the model:

```ruby
include OpenLoam::Encryptable
encrypts :ssn                      # encrypted, not searchable
encrypts :email, searchable: true  # + a blind index for exact-match lookup
```

Read/write is transparent (`patient.ssn` decrypts on read); a searchable field
is found by `Patient.find_by_email(value)`, which matches the per-tenant blind
index — never a LIKE. Rules: a field is NEVER both `encrypts` and `searchable_by`
(ciphertext cannot be LIKE-searched — it raises at load); reading or writing an
encrypted field with no tenant in context raises `MissingTenantError`; the audit
trail records an encrypted change as `[encrypted]`, never the value. Set
`OPEN_LOAM_MASTER_KEY` (see the initializer) — encryption raises without it. GDPR
export / key rotation: `bin/rails open_loam:encryption:decrypt_dump[Model,tenant_id]`
/ `open_loam:encryption:rotate[Model,tenant_id]`.


## Ciphertext binding (AAD, v2 format)

Each encrypted value is bound to WHERE it lives — its (tenant/owner scope, table,
column) — via AES-GCM Additional Authenticated Data. New writes use the `v2:`
format (AAD-bound); reads reconstruct the same AAD, so a ciphertext moved to a
different column, table, or tenant fails the auth tag (`DecryptionError`) instead
of decrypting. Legacy `v1:` blobs carry no AAD and stay readable (backward
compatible); `bin/rails open_loam:encryption:rotate[Model,tenant]` re-encrypts them to
v2. The AAD is authenticated, never secret — it only pins location. Record-swap
within one tenant+table+column is a documented residual (the id isn't known at
INSERT time to bind without an ugly post-insert double-write).
