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
is found by `Patient.find_by_email(value)`, which matches the blind index — never
a LIKE. That index's HMAC key is derived per **(tenant, table, column)**, like the
ciphertext AAD, so one value does not hash alike across two searchable columns: a
tenant-only key would let a dump correlate rows across tables, and would hand
anyone who can write one such field an equality oracle against columns they may
not read. Rules: a field is NEVER both `encrypts` and `searchable_by`
(ciphertext cannot be LIKE-searched — it raises at load); reading or writing an
encrypted field with no tenant in context raises `MissingTenantError`; the audit
trail records an encrypted change as `[encrypted]`, never the value. Set
`OPEN_LOAM_MASTER_KEY` (see the initializer) — encryption raises without it. GDPR
export / key rotation: `bin/rails open_loam:encryption:decrypt_dump[Model,tenant_id]`
/ `open_loam:encryption:rotate[Model,tenant_id]`.


## Rotating the master key

Set the outgoing key as `OPEN_LOAM_PREVIOUS_MASTER_KEY` and the new one as
`OPEN_LOAM_MASTER_KEY`, then run
`bin/rails open_loam:encryption:rotate[Model,tenant_id]` for each encryptable
model and tenant. Reads fall back to the previous key — GCM's auth tag makes
"wrong key" an unambiguous failure, so the fallback cannot silently mis-decrypt —
and every write uses the new key, so a row is rotated as soon as anything saves
it. Blind indexes are rebuilt in the same pass, since the HMAC key derives from
the master too.

Drop `OPEN_LOAM_PREVIOUS_MASTER_KEY` once every model has been rotated. Until
then both keys are live, and the old one still protects real data.

A KMS-backed `key_provider` manages its own key versions; the fallback is only
used when the provider implements `previous_data_key`, which the default
HKDF provider does and the base `KeyProvider` does not.

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
