# Encryption at rest


Sensitive columns (SSN, tax id, email) are encrypted at rest, per tenant, so a
DB dump leaks nothing and one tenant's key never decrypts another's. Generate
them — `bin/rails g loam:entity Patient name:string ssn:string email:string
--encrypt ssn --encrypt-searchable email` — or declare on the model:

```ruby
include Loam::Encryptable
encrypts :ssn                      # encrypted, not searchable
encrypts :email, searchable: true  # + a blind index for exact-match lookup
```

Read/write is transparent (`patient.ssn` decrypts on read); a searchable field
is found by `Patient.find_by_email(value)`, which matches the per-tenant blind
index — never a LIKE. Rules: a field is NEVER both `encrypts` and `searchable_by`
(ciphertext cannot be LIKE-searched — it raises at load); reading or writing an
encrypted field with no tenant in context raises `MissingTenantError`; the audit
trail records an encrypted change as `[encrypted]`, never the value. Set
`LOAM_MASTER_KEY` (see the initializer) — encryption raises without it. GDPR
export / key rotation: `bin/rails loam:encryption:decrypt_dump[Model,tenant_id]`
/ `loam:encryption:rotate[Model,tenant_id]`.

