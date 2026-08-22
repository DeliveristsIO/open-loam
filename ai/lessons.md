# Lessons (L-708)

Hindsight an agent should read **before** implementing in this repo — real bugs
and gotchas found the hard way, each with the rule that prevents a repeat. New
lesson at the top; keep each entry to a claim + the rule.

Format: **Lesson** — what went wrong. **Rule** — what to do instead.

---

**Adding a workflow to a generated entity breaks its generated isolation test.**
`loam:entity` writes a test that creates the record with placeholder string values
(`state: "Sample state 0"`). Add `workflow :state` later and those values fail the
states-inclusion validation.
**Rule:** after `include Loam::Workflow` on a generated entity, update the
generated entity test's placeholder for the workflow column to a declared state
(or omit it so it defaults to the initial state).

**Custom fields are nested under the model's param key.**
`assign_custom_fields!` first read `params[:custom_fields]` and silently saved
nothing while the redirect still said "success". They arrive as
`params[model_param_key][:custom_fields]`.
**Rule:** read nested params with `params.dig(record.model_name.param_key, :custom_fields)`; add a test that reads the value back, not just that the request redirected.

**The workflow column must never be written directly.**
Bulk set-field, import, business-rule `set_field`, an edit form, and undo could
all set the `status`/`state` column and skip the role-gated transition — a member
could self-"approve". A model validation (`on: :update`) closes every path at once.
**Rule:** change a workflow column only through `loam_perform_transition!`. Any new
write path (undo, a rule action, an importer) must skip the workflow column — detect
it via `Model.loam_workflow&.column`.

**Encrypted fields have no plaintext in the audit.**
The audit changeset stores `"[encrypted]"` for an encrypted field, never the value.
Undo, diffs, and any "revert to old value" logic have nothing to restore.
**Rule:** anything reading a changeset must skip entries whose value is the String
`"[encrypted]"` (not a `[before, after]` pair). Never `searchable_by` / `translates`
an encrypted field either (both refuse at load — a stored token/translation would be
plaintext).

**Never `constantize` a type name straight from params or a DB row.**
Turning `params[:type]` or a stored `job_class`/`subscriber_key` into a class and
calling it is a code-execution hole.
**Rule:** `safe_constantize`, then require membership in a known set — `< Loam::TenantRecord`,
an allowlist (scheduler `job_class`), or the boot registry (durable subscribers). An
unknown value is refused/parked, never executed.

**A user-supplied ORDER BY column is SQL injection.**
The sortable index headers pass `params[:sort]` toward `ORDER BY`.
**Rule:** whitelist against `Model.column_names` and constrain the direction to
`asc`/`desc` before it reaches `reorder`. Same shape for any filter whitelist
(saved views, business-rule conditions): fields are validated, values are literals,
never `eval`/`send`.

**Durable delivery is at-least-once — handlers must be idempotent.**
A retry or the redelivery sweep can deliver the same event twice; the delivery row,
not the queue, is the source of truth.
**Rule:** a `DurableEvents` handler (and an inbound-webhook consumer) must be safe to
run twice on the same payload. Don't keep retry state in the queue (`retry_on`);
keep it in the row.

**Anonymous test classes leak into `descendants`.**
`Class.new(Loam::TenantRecord)` in a test appears in `TenantRecord.descendants`;
code that walks descendants (`OpenApi`, search) then crashed on the nameless class —
order-dependent, so green locally and red in CI.
**Rule:** when iterating `descendants`, `reject { |m| m.name.blank? }`.

**Carry the FULL filter state through pagination.**
Page 2 of a filtered/sorted admin index dropped everything but `q`, silently showing
unfiltered results.
**Rule:** build one `current_index_params` (q + perspective + custom-field filter +
sort/dir) and pass it to every pagination link, the export link, and the sort headers.

**UI strings need `t()`, entity/field names need Rails i18n.**
Baking English into a generated view (`"New equipment"`, `attribute.humanize`) makes
the app un-translatable.
**Rule:** generic chrome uses `t("loam.…")`; entity/field labels use
`Model.model_name.human` / `human_attribute_name` (localized via `activerecord.*`).
The switcher sets `I18n.locale`, not just `Loam::Current.locale`.
