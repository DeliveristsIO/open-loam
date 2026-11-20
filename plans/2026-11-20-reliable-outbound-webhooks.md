# Reliable outbound webhooks (OpenLoam 0.4.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use spark:subagent-driven-development (recommended) or spark:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn OpenLoam's fire-and-forget outbound webhooks into an at-least-once transport with a delivery ledger, response-aware retries, endpoint health, a timestamped signature and host hooks, without breaking any frozen 0.3.0 contract.

**Architecture:** `OpenLoam::Webhooks.dispatch` (already subscribed to every event) writes one `open_loam_webhook_deliveries` row per matching active endpoint in the publisher's transaction and enqueues `OpenLoam::WebhookDeliveryJob` after commit. The job claims the row, builds the body (default frozen shape or a host `body_builder`), POSTs through `OpenLoam::Webhooks::HttpTransport` (pinned IP via `OutboundUrl`), and moves the row by response code. `OpenLoam::WebhookSweepJob` re-enqueues lost/stuck rows and prunes old ones.

**Tech Stack:** Ruby ≥ 3.2, Rails ≥ 7.1 (demo on edge), ActiveJob, Net::HTTP, OpenSSL, minitest, SQLite (demo).

**Consumer:** ChatlyBot (`../chatlybot/chatlybot`, spec `docs/spark/specs/2026-11-20-crm-integrations-design.md` §3.1, plan `docs/spark/plans/2026-11-20-crm-webhooks-a1.md`). `daily-champ` and `agenty-rails` get the reliability fix for free.

## Global Constraints

- Frozen surfaces stay byte-identical (`BACKWARD_COMPATIBILITY.md` §2, §6): `X-OpenLoam-Signature: sha256=<hex HMAC-SHA256(secret, exact_body)>` with the pinned vector `sha256=d42927434049e0b8c73ce887062238cc1c6bb6644bfe66e66d8dd0f30b85679e` for `("s3cr3t", '{"a":1}')`; default body `{ "event", "payload", "tenant_id" }`; pattern rule "trailing dot = domain prefix, else exact".
- `WebhookDeliveryJob.body_for` and `WebhookDeliveryJob.signature` keep their signatures.
- Jobs inherit `ActiveJob::Base`, never the host's `ApplicationJob`.
- Retry state lives in the ROW, never in ActiveJob `retry_on` (same rule as `DurableEvents`).
- No `.unscoped` outside gem code; the one new cross-tenant read (`Webhooks.tenant_ids_needing_sweep`) returns tenant ids only and is listed as a blessed lookup.
- Every new behaviour gets a demo test; a template change is mirrored in the demo's generated copy (CONTRIBUTING.md).
- Both suites green: `rake test` (root) and `cd demo && bin/rails test`.
- Defaults keep 0.3.0 behaviour visible to receivers except: retries now happen, and extra `X-OpenLoam-*` headers are sent. Nothing a receiver relied on disappears.
- Commit after each task, conventional commit style used in this repo (`feat(webhooks): ...`, `fix(ssrf): ...`).

## Before you start

```bash
cd /home/gs/code/deliverists.io/open-loam
git checkout main && git pull --ff-only     # 0.3.0 is the base
git checkout -b feat/reliable-webhooks
cd demo && bundle install && bin/rails db:prepare && bin/rails test test/open_loam_webhook_test.rb
```
Expected: the 8 existing webhook tests pass.

## File structure

| File | Responsibility |
|---|---|
| `lib/open_loam/outbound_url.rb` (modify) | IPv4-mapped/compat IPv6 normalisation, NAT64 range, optional `ports:` |
| `lib/open_loam/webhooks.rb` (rewrite) | configuration, dispatch, enqueue-after-commit, deliver state machine, signatures, sweep/prune |
| `lib/open_loam/webhooks/http_transport.rb` (create) | the only code that opens a socket; bounded excerpt, no redirects |
| `app/models/open_loam/webhook_endpoint.rb` (modify) | patterns, metadata, secret encryption/rotation, health |
| `app/models/open_loam/webhook_delivery.rb` (create) | ledger row, scopes |
| `app/jobs/open_loam/webhook_delivery_job.rb` (modify) | `(tenant_id, delivery_id)` + legacy 4-arg form |
| `app/jobs/open_loam/webhook_sweep_job.rb` (create) | fan-out over tenants, per-tenant sweep |
| `lib/open_loam/engine.rb` (modify) | register the sweep with `OpenLoam::Scheduler` |
| `lib/open_loam.rb` (modify) | require the transport |
| `lib/generators/open_loam/install/templates/migrations/create_open_loam_webhook_endpoints.rb` (modify) | new columns for fresh installs |
| `lib/generators/open_loam/install/templates/migrations/create_open_loam_webhook_deliveries.rb` (create) | ledger table for fresh installs |
| `lib/generators/open_loam/install/install_generator.rb` (modify) | emit the new template |
| `lib/generators/open_loam/install/templates/admin/webhook_endpoints_index.html.erb` + demo copy (modify) | stop printing the secret, document V2 |
| `demo/db/migrate/20261120090000_add_open_loam_webhook_reliability.rb` (create) | upgrade path existing apps copy |
| `demo/test/open_loam_webhook_test.rb` (rewrite), `demo/test/open_loam_webhook_delivery_test.rb`, `demo/test/open_loam_webhook_endpoint_test.rb`, `demo/test/open_loam_webhook_sweep_test.rb`, `demo/test/open_loam_outbound_url_mapped_test.rb` (create) | tests |
| `docs/_agents/webhooks.md` (create), `BACKWARD_COMPATIBILITY.md`, `CHANGELOG.md`, `lib/open_loam/version.rb`, `ROADMAP.md` (modify) | contract + release notes |

---

### Task 1: SSRF — IPv4-mapped IPv6 and port allowlist in `OutboundUrl`

`BLOCKED` has no `::ffff:0:0/96`, and `IPAddr#include?` never matches across families, so `http://[::ffff:127.0.0.1]/` and `http://[::ffff:169.254.169.254]/` pass today and the job connects to loopback/metadata.

**Files:**
- Modify: `lib/open_loam/outbound_url.rb`
- Test: `demo/test/open_loam_outbound_url_mapped_test.rb`

**Interfaces:**
- Produces: `OpenLoam::OutboundUrl.validate!(url, require_https: false, ports: nil)`, `.resolve!(url, require_https: false, ports: nil)` → `[URI, String]`. `ports: nil` means any port (0.3.0 behaviour).

- [ ] **Step 1: Write the failing test**

```ruby
# demo/test/open_loam_outbound_url_mapped_test.rb
require "test_helper"

class OpenLoamOutboundUrlMappedTest < ActiveSupport::TestCase
  def blocked(url, **options)
    assert_raises(OpenLoam::OutboundUrl::BlockedError) { OpenLoam::OutboundUrl.validate!(url, **options) }
  end

  test "IPv4-mapped and IPv4-compatible IPv6 literals are checked as IPv4" do
    %w[
      http://[::ffff:127.0.0.1]/
      http://[::ffff:169.254.169.254]/latest/meta-data/
      http://[::ffff:10.0.0.1]/
      http://[::ffff:7f00:1]/
      http://[::127.0.0.1]/
    ].each { |url| blocked(url) }
  end

  test "NAT64 addresses are refused" do
    blocked("http://[64:ff9b::a9fe:a9fe]/")
  end

  test "a mapped public address is still allowed" do
    assert OpenLoam::OutboundUrl.validate!("http://[::ffff:93.184.216.34]/")
  end

  test "resolve! refuses a hostname that resolves to a mapped loopback address" do
    Resolv.stub(:getaddresses, [ "::ffff:127.0.0.1" ]) do
      assert_raises(OpenLoam::OutboundUrl::BlockedError) { OpenLoam::OutboundUrl.resolve!("https://rebind.example/") }
    end
  end

  test "ports: restricts the port when given and is ignored when nil" do
    error = blocked("https://example.com:8443/hook", ports: [ 443 ])
    assert_match(/port 8443/, error.message)
    assert OpenLoam::OutboundUrl.validate!("https://example.com/hook", ports: [ 443 ])
    assert OpenLoam::OutboundUrl.validate!("https://example.com:8443/hook")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd demo && bin/rails test test/open_loam_outbound_url_mapped_test.rb`
Expected: FAIL — the mapped literals do not raise, and `ports:` is an unknown keyword.

- [ ] **Step 3: Implement**

In `lib/open_loam/outbound_url.rb`:

1. Add `"64:ff9b::/96"` to the end of the `BLOCKED` list (NAT64 reaches IPv4 space through a gateway).
2. Replace `validate!`, `resolve!`, `parse!` and `blocked?` and add `normalize`:

```ruby
    def validate!(url, require_https: false, ports: nil)
      uri = parse!(url, require_https: require_https, ports: ports)
      if literal_address(uri.host) && blocked?(uri.host)
        raise BlockedError, "#{uri.host} is not a public address"
      end

      uri
    end

    def resolve!(url, require_https: false, ports: nil)
      uri = validate!(url, require_https: require_https, ports: ports)
      [ uri, address_for!(uri.host) ]
    end

    def parse!(url, require_https: false, ports: nil)
      uri = begin
        URI.parse(url.to_s)
      rescue URI::InvalidURIError => error
        raise BlockedError, "not a valid URL: #{error.message}"
      end

      raise BlockedError, "#{uri.scheme.inspect} is not an allowed scheme" unless SCHEMES.include?(uri.scheme)
      raise BlockedError, "https is required" if require_https && uri.scheme != "https"
      raise BlockedError, "no host in #{url.inspect}" if uri.host.blank?
      raise BlockedError, "credentials in the URL are not allowed" if uri.userinfo.present?
      raise BlockedError, "port #{uri.port} is not allowed" if ports && !Array(ports).include?(uri.port)

      uri
    end

    def blocked?(address)
      ip = normalize(IPAddr.new(address.to_s))
      BLOCKED.any? { |range| range.family == ip.family && range.include?(ip) }
    rescue IPAddr::Error
      true # unparseable is not provably public
    end

    # ::ffff:a.b.c.d (mapped) and ::a.b.c.d (compatible) reach the IPv4 host,
    # so they are judged by the IPv4 ranges. IPAddr never matches across
    # families, which is exactly how "[::ffff:127.0.0.1]" slipped through.
    def normalize(ip)
      return ip unless ip.ipv6?

      value = ip.to_i
      high = value >> 32
      return IPAddr.new(value & 0xffff_ffff, Socket::AF_INET) if high == 0xffff || (high.zero? && value > 1)

      ip
    end
```

`URI.parse` returns the host of `http://[::ffff:127.0.0.1]/` with brackets; `literal_address` uses `IPAddr.new(host)` which accepts the bracketed form. Add `require "socket"` at the top next to `require "ipaddr"`.

- [ ] **Step 4: Run the new and the existing SSRF tests**

Run: `cd demo && bin/rails test test/open_loam_outbound_url_mapped_test.rb test/open_loam_outbound_url_test.rb`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add lib/open_loam/outbound_url.rb demo/test/open_loam_outbound_url_mapped_test.rb
git commit -m "fix(ssrf): judge IPv4-mapped IPv6 by the IPv4 ranges, block NAT64, allow a port allowlist"
```

---

### Task 2: Schema, `WebhookDelivery`, and the endpoint model (patterns, metadata, secrets, health)

**Files:**
- Modify: `lib/generators/open_loam/install/templates/migrations/create_open_loam_webhook_endpoints.rb`
- Create: `lib/generators/open_loam/install/templates/migrations/create_open_loam_webhook_deliveries.rb`
- Modify: `lib/generators/open_loam/install/install_generator.rb` (after the `create_open_loam_inbound_webhooks.rb` line)
- Create: `demo/db/migrate/20261120090000_add_open_loam_webhook_reliability.rb`
- Create: `app/models/open_loam/webhook_delivery.rb`
- Modify: `app/models/open_loam/webhook_endpoint.rb`
- Create (minimal, filled in Task 3): `lib/open_loam/webhooks.rb` configuration readers used by the model
- Test: `demo/test/open_loam_webhook_endpoint_test.rb`

**Interfaces:**
- Produces (model): `WebhookEndpoint#patterns → Array<String>`, `#matches?(event_name)`, `#secret`, `#secret=`, `#previous_secret`, `#signing_secrets(now = Time.current) → Array<String>`, `#rotate_secret!(now: Time.current) → String`, `#record_success!(at = Time.current)`, `#record_failure!(at = Time.current)`, `#disable!(reason)`, `#enable!`, `#settings → Hash` (metadata with string keys), `.generate_secret → String`, `has_many :deliveries`.
- Produces (model): `WebhookDelivery` with `STATUSES = %w[pending sending succeeded failed cancelled]`, `FINAL_STATUSES = %w[succeeded failed cancelled]`, scopes `due(now)`, `overdue(now)`, `stuck(now)`, `prunable(now, retention)`, `recent_first`, `#payload_hash`, `#final?`, `delivery_id` auto `"whd_<24 hex>"`.
- Produces (config, in `OpenLoam::Webhooks`): `encrypt_secrets?`, `secret_rotation_grace`, `disable_after_failures`, `stuck_after`, constant `DISABLED_EVENT = "open_loam.webhook.endpoint_disabled"`.

- [ ] **Step 1: Migrations**

Template for fresh installs — replace the body of `create_open_loam_webhook_endpoints.rb`:

```erb
class CreateOpenLoamWebhookEndpoints < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_webhook_endpoints<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :url, null: false
      t.string :event_pattern                  # single pattern (0.3.0); nil when event_patterns is used
      t.json :event_patterns, null: false, default: []
      t.text :secret, null: false              # plaintext hex, or "v2:..." when encrypt_secrets is on
      t.text :previous_secret
      t.datetime :previous_secret_expires_at
      t.boolean :active, null: false, default: true
      t.string :description
      t.json :metadata, null: false, default: {}  # host-owned settings; OpenLoam never reads it
      t.string :disabled_reason
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.timestamps
    end
    add_index :open_loam_webhook_endpoints, %i[tenant_id active]
  end
end
```

Create `create_open_loam_webhook_deliveries.rb`:

```erb
class CreateOpenLoamWebhookDeliveries < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_webhook_deliveries<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.references :endpoint, null: false, foreign_key: { to_table: :open_loam_webhook_endpoints, on_delete: :cascade }<%= open_loam_type_option %>
      t.string :event_id, null: false          # one per published event, shared by its endpoints
      t.string :delivery_id, null: false       # one per (event, endpoint), sent as a header
      t.string :event_name, null: false
      t.json :payload, null: false             # the event payload (ids and scalars)
      t.string :status, null: false, default: "pending" # pending | sending | succeeded | failed | cancelled
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :sending_at
      t.integer :last_response_code
      t.string :last_error
      t.integer :last_duration_ms
      t.string :response_excerpt, limit: 512
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :open_loam_webhook_deliveries, %i[endpoint_id event_id], unique: true
    add_index :open_loam_webhook_deliveries, :delivery_id, unique: true
    add_index :open_loam_webhook_deliveries, %i[tenant_id status next_attempt_at]
    add_index :open_loam_webhook_deliveries, %i[endpoint_id created_at]
  end
end
```

In `install_generator.rb`, directly after the `create_open_loam_inbound_webhooks.rb` line add:

```ruby
        migration_template "migrations/create_open_loam_webhook_deliveries.rb", "db/migrate/create_open_loam_webhook_deliveries.rb"
```

Demo upgrade migration (this is the file existing apps copy; CHANGELOG points to it):

```ruby
# demo/db/migrate/20261120090000_add_open_loam_webhook_reliability.rb
# 0.4.0: delivery ledger + endpoint health. Existing endpoints keep their single
# event_pattern and plaintext secret; both stay readable.
class AddOpenLoamWebhookReliability < ActiveRecord::Migration[8.2]
  def up
    change_column_null :open_loam_webhook_endpoints, :event_pattern, true
    change_column :open_loam_webhook_endpoints, :secret, :text, null: false
    add_column :open_loam_webhook_endpoints, :event_patterns, :json, null: false, default: []
    add_column :open_loam_webhook_endpoints, :previous_secret, :text
    add_column :open_loam_webhook_endpoints, :previous_secret_expires_at, :datetime
    add_column :open_loam_webhook_endpoints, :description, :string
    add_column :open_loam_webhook_endpoints, :metadata, :json, null: false, default: {}
    add_column :open_loam_webhook_endpoints, :disabled_reason, :string
    add_column :open_loam_webhook_endpoints, :consecutive_failures, :integer, null: false, default: 0
    add_column :open_loam_webhook_endpoints, :last_success_at, :datetime
    add_column :open_loam_webhook_endpoints, :last_failure_at, :datetime

    create_table :open_loam_webhook_deliveries do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.references :endpoint, null: false, foreign_key: { to_table: :open_loam_webhook_endpoints, on_delete: :cascade }
      t.string :event_id, null: false
      t.string :delivery_id, null: false
      t.string :event_name, null: false
      t.json :payload, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :sending_at
      t.integer :last_response_code
      t.string :last_error
      t.integer :last_duration_ms
      t.string :response_excerpt, limit: 512
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :open_loam_webhook_deliveries, %i[endpoint_id event_id], unique: true
    add_index :open_loam_webhook_deliveries, :delivery_id, unique: true
    add_index :open_loam_webhook_deliveries, %i[tenant_id status next_attempt_at]
    add_index :open_loam_webhook_deliveries, %i[endpoint_id created_at]
  end

  def down
    drop_table :open_loam_webhook_deliveries
    %i[event_patterns previous_secret previous_secret_expires_at description metadata disabled_reason
       consecutive_failures last_success_at last_failure_at].each do |column|
      remove_column :open_loam_webhook_endpoints, column
    end
    change_column :open_loam_webhook_endpoints, :secret, :string, null: false
    change_column_null :open_loam_webhook_endpoints, :event_pattern, false
  end
end
```

Run: `cd demo && bin/rails db:migrate && git diff --stat db/schema.rb`
Expected: schema gains the table and columns.

- [ ] **Step 2: Write the failing model test**

```ruby
# demo/test/open_loam_webhook_endpoint_test.rb
require "test_helper"

class OpenLoamWebhookEndpointTest < ActiveSupport::TestCase
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Gdansk", slug: "gdansk-hooks")
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  def endpoint(**attrs)
    OpenLoam::WebhookEndpoint.create!({ url: "https://example.test/hook", event_pattern: "rental." }.merge(attrs))
  end

  test "event_patterns lets one endpoint follow several events; event_pattern still works alone" do
    with_tenant(@tenant) do
      many = endpoint(event_pattern: nil, event_patterns: %w[rental.equipment.created billing.])
      assert many.matches?("rental.equipment.created")
      assert many.matches?("billing.penalty.due")
      refute many.matches?("rental.equipment.updated")

      single = endpoint
      assert_equal [ "rental." ], single.patterns
      refute OpenLoam::WebhookEndpoint.new(url: "https://example.test/x", event_pattern: nil, event_patterns: []).valid?
    end
  end

  test "secrets are stored in plaintext by default and sealed when encrypt_secrets is on" do
    with_tenant(@tenant) do
      plain = endpoint
      assert_match(/\A\h{64}\z/, plain.read_attribute(:secret))

      OpenLoam::Webhooks.encrypt_secrets = true
      sealed = endpoint
      assert sealed.read_attribute(:secret).start_with?("v2:")
      assert_match(/\A\h{64}\z/, sealed.reload.secret)
      assert_match(/\A\h{64}\z/, plain.reload.secret, "a plaintext row stays readable after switching encryption on")
    end
  end

  test "rotation keeps the old secret valid for the grace period" do
    with_tenant(@tenant) do
      hook = endpoint
      old = hook.secret
      now = Time.current
      new_secret = hook.rotate_secret!(now: now)

      assert_not_equal old, new_secret
      assert_equal [ new_secret, old ], hook.signing_secrets(now + 1.hour)
      assert_equal [ new_secret ], hook.signing_secrets(now + 25.hours)
    end
  end

  test "consecutive failures disable the endpoint once and publish an event; a success resets the count" do
    OpenLoam::Webhooks.disable_after_failures = 3
    events = []
    subscription = OpenLoam::Events.subscribe("open_loam.webhook.") { |name, payload| events << [ name, payload ] }

    with_tenant(@tenant) do
      hook = endpoint
      2.times { hook.record_failure! }
      hook.record_success!
      assert_equal 0, hook.reload.consecutive_failures

      3.times { hook.record_failure! }
      hook.reload
      refute hook.active?
      assert_equal "consecutive_failures", hook.disabled_reason
      hook.record_failure!
      assert_equal 1, events.count { |name, _| name == "open_loam.webhook.endpoint_disabled" }
      assert_equal hook.id, events.last.last[:endpoint_id]

      hook.enable!
      assert hook.reload.active?
      assert_nil hook.disabled_reason
      assert_equal 0, hook.consecutive_failures
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  test "a delivery gets a public delivery id and is removed with its endpoint" do
    with_tenant(@tenant) do
      hook = endpoint
      delivery = hook.deliveries.create!(event_id: SecureRandom.uuid, event_name: "rental.equipment.created", payload: { "id" => 1 })
      assert_match(/\Awhd_\h{24}\z/, delivery.delivery_id)
      assert_equal "pending", delivery.status
      assert_equal({ "id" => 1 }, delivery.payload_hash)

      hook.destroy!
      assert_not OpenLoam::WebhookDelivery.exists?(delivery.id)
    end
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd demo && bin/rails test test/open_loam_webhook_endpoint_test.rb`
Expected: FAIL — `NoMethodError` for `reset_configuration!`, `patterns`, `deliveries`.

- [ ] **Step 4: Implement**

Add the configuration half of `lib/open_loam/webhooks.rb` now (Task 3 adds the rest of the module; keep `subscribe!`/`dispatch` from 0.3.0 untouched in this task):

```ruby
module OpenLoam
  module Webhooks
    DEFAULT_RETRY_SCHEDULE = [ 60, 300, 1_800, 7_200, 21_600, 43_200, 86_400 ].freeze
    DISABLED_EVENT = "open_loam.webhook.endpoint_disabled".freeze
    TEST_EVENT = "open_loam.webhook.test".freeze
    EXCERPT_BYTES = 512
    TIMESTAMP_TOLERANCE = 300

    CONFIG_IVARS = %i[
      @header_prefix @user_agent @retry_schedule @disable_after_failures @delivery_retention @body_builder
      @transport @require_https @allowed_ports @encrypt_secrets @test_event_name @timeout
      @secret_rotation_grace @stuck_after
    ].freeze

    class << self
      attr_writer :header_prefix, :user_agent, :retry_schedule, :disable_after_failures, :delivery_retention,
                  :body_builder, :transport, :require_https, :allowed_ports, :encrypt_secrets, :test_event_name,
                  :timeout, :secret_rotation_grace, :stuck_after

      def header_prefix = @header_prefix || "X-OpenLoam"
      def user_agent = @user_agent || "OpenLoam-Webhooks/#{OpenLoam::VERSION}"
      def retry_schedule = @retry_schedule || DEFAULT_RETRY_SCHEDULE
      def disable_after_failures = defined?(@disable_after_failures) ? @disable_after_failures : 50
      def delivery_retention = defined?(@delivery_retention) ? @delivery_retention : 30.days
      def body_builder = @body_builder
      def transport = @transport || HttpTransport
      def require_https? = @require_https ? true : false
      def allowed_ports = @allowed_ports
      def encrypt_secrets? = @encrypt_secrets ? true : false
      def test_event_name = @test_event_name || TEST_EVENT
      def timeout = @timeout || 10
      def secret_rotation_grace = @secret_rotation_grace || 24.hours
      def stuck_after = @stuck_after || 5.minutes

      # Tests (and only tests) put the module back to its defaults.
      def reset_configuration!
        CONFIG_IVARS.each { |ivar| remove_instance_variable(ivar) if instance_variable_defined?(ivar) }
      end
    end
  end
end
```

(`HttpTransport` is referenced lazily inside the method body, so it may be defined in Task 3.)

`app/models/open_loam/webhook_delivery.rb`:

```ruby
module OpenLoam
  # One event on its way to one endpoint. The ROW is the record of intent: it is
  # written in the publishing transaction, the job only accelerates it, and the
  # sweep finishes whatever a lost job left behind.
  #
  # pending -> sending -> succeeded | failed | (pending again, with next_attempt_at)
  # pending -> cancelled (endpoint switched off, or the host's body builder skipped it)
  class WebhookDelivery < OpenLoam::TenantRecord
    self.table_name = "open_loam_webhook_deliveries"

    STATUSES = %w[pending sending succeeded failed cancelled].freeze
    FINAL_STATUSES = %w[succeeded failed cancelled].freeze

    belongs_to :endpoint, class_name: "OpenLoam::WebhookEndpoint", inverse_of: :deliveries

    validates :event_id, :event_name, :delivery_id, presence: true
    validates :status, inclusion: { in: STATUSES }

    before_validation on: :create do
      self.delivery_id ||= "whd_#{SecureRandom.hex(12)}"
    end

    scope :due, ->(now = Time.current) { where(status: "pending").where("next_attempt_at IS NULL OR next_attempt_at <= ?", now) }
    # Pending rows the job should already have taken: never attempted for a
    # minute, or past their backoff. Fresh rows are left to their own job.
    scope :overdue, ->(now = Time.current) {
      where(status: "pending").where("(next_attempt_at IS NULL AND created_at <= ?) OR next_attempt_at <= ?", now - 60, now)
    }
    scope :stuck, ->(now = Time.current) { where(status: "sending").where("sending_at < ?", now - OpenLoam::Webhooks.stuck_after) }
    scope :prunable, ->(now, retention) { where(status: FINAL_STATUSES).where("updated_at < ?", now - retention) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    def payload_hash
      value = self[:payload]
      value.is_a?(String) ? JSON.parse(value) : (value || {})
    end

    def final? = FINAL_STATUSES.include?(status)
  end
end
```

Replace `app/models/open_loam/webhook_endpoint.rb`:

```ruby
module OpenLoam
  # Where one tenant wants its domain events delivered. A pattern uses the rule
  # shared with OpenLoam::Events.subscribe: a trailing dot is a domain prefix
  # ("rental."), anything else is an exact event name. `event_pattern` is the
  # 0.3.0 single pattern; `event_patterns` holds several.
  #
  # The secret signs every delivery. With OpenLoam::Webhooks.encrypt_secrets on,
  # it is sealed with the tenant's key (OpenLoam::Encryption, "v2:..."); rows
  # written before that stay readable as plaintext.
  #
  # `metadata` belongs to the host app (e.g. which fields a receiver may see);
  # OpenLoam stores it and never reads it.
  class WebhookEndpoint < OpenLoam::TenantRecord
    self.table_name = "open_loam_webhook_endpoints"

    SEALED_PREFIXES = %w[v1: v2:].freeze

    has_many :deliveries, class_name: "OpenLoam::WebhookDelivery", foreign_key: :endpoint_id,
                          inverse_of: :endpoint, dependent: :delete_all

    validates :url, presence: true
    validate :at_least_one_pattern
    # The server fetches this URL, so a tenant must not aim it at an address only
    # the server can reach. Shape is checked at save; the delivery re-checks with
    # DNS, because DNS moves.
    validate :url_is_reachable_from_outside, if: -> { url.present? }

    scope :active, -> { where(active: true) }

    before_validation on: :create do
      self.secret = self.class.generate_secret if read_attribute(:secret).blank?
    end

    def self.generate_secret = SecureRandom.hex(32)

    def patterns
      list = Array(self[:event_patterns]).map(&:to_s).reject(&:empty?)
      list.empty? ? [ event_pattern.to_s ].reject(&:empty?) : list
    end

    def matches?(event_name)
      patterns.any? { |pattern| OpenLoam::Events.pattern_matches?(pattern, event_name) }
    end

    def settings
      value = self[:metadata]
      value = JSON.parse(value) if value.is_a?(String)
      (value || {}).to_h.stringify_keys
    end

    def secret = unseal(read_attribute(:secret), "secret")
    def secret=(value)
      write_attribute(:secret, seal(value, "secret"))
    end

    def previous_secret = unseal(read_attribute(:previous_secret), "previous_secret")
    def previous_secret=(value)
      write_attribute(:previous_secret, seal(value, "previous_secret"))
    end

    # The secrets a delivery is signed with right now: the current one, plus the
    # previous one while its grace period runs, so receivers can switch over.
    def signing_secrets(now = Time.current)
      keep_previous = previous_secret_expires_at && previous_secret_expires_at > now
      [ secret, (previous_secret if keep_previous) ].compact
    end

    def rotate_secret!(now: Time.current)
      new_secret = self.class.generate_secret
      update!(previous_secret: secret, previous_secret_expires_at: now + OpenLoam::Webhooks.secret_rotation_grace,
              secret: new_secret)
      new_secret
    end

    def record_success!(at = Time.current)
      update_columns(consecutive_failures: 0, last_success_at: at, updated_at: at)
    end

    # SQL increment, so two failing deliveries at once still count twice.
    def record_failure!(at = Time.current)
      self.class.where(id: id).update_all([ "consecutive_failures = consecutive_failures + 1, last_failure_at = ?, updated_at = ?", at, at ])
      reload
      limit = OpenLoam::Webhooks.disable_after_failures
      disable!("consecutive_failures") if limit && consecutive_failures >= limit
    end

    # Idempotent: only the switch from on to off publishes the event.
    def disable!(reason)
      return unless active?

      update_columns(active: false, disabled_reason: reason.to_s, updated_at: Time.current)
      OpenLoam::Events.publish(OpenLoam::Webhooks::DISABLED_EVENT, { endpoint_id: id, reason: reason.to_s })
    end

    def enable!
      update!(active: true, disabled_reason: nil, consecutive_failures: 0)
    end

    private

    def at_least_one_pattern
      errors.add(:event_pattern, :blank) if patterns.empty?
    end

    def url_is_reachable_from_outside
      OpenLoam::OutboundUrl.validate!(url, require_https: OpenLoam::Webhooks.require_https?,
                                           ports: OpenLoam::Webhooks.allowed_ports)
    rescue OpenLoam::OutboundUrl::BlockedError => error
      errors.add(:url, error.message)
    end

    def key_scope = "tenant/#{tenant_id || OpenLoam.tenant!.id}"

    def seal(value, column)
      return value if value.nil? || !OpenLoam::Webhooks.encrypt_secrets?

      OpenLoam::Encryption.encrypt_scoped(value, key_scope,
                                          aad: OpenLoam::Encryption.aad(key_scope, self.class.table_name, column))
    end

    # A hex secret never contains ":", so anything without a version tag is a
    # plaintext row from before encryption was switched on.
    def unseal(stored, column)
      return stored if stored.nil? || SEALED_PREFIXES.none? { |prefix| stored.start_with?(prefix) }

      OpenLoam::Encryption.decrypt_scoped(stored, key_scope,
                                          aad: OpenLoam::Encryption.aad(key_scope, self.class.table_name, column))
    end
  end
end
```

The demo initializer already sets `OpenLoam::Encryption.master_key`, so the encryption test runs.

- [ ] **Step 5: Run the model test and the old webhook test**

Run: `cd demo && bin/rails test test/open_loam_webhook_endpoint_test.rb test/open_loam_webhook_test.rb`
Expected: PASS (the old dispatch path is unchanged so far).

- [ ] **Step 6: Generator harness**

Run (repo root): `rake test`
Expected: PASS — the generated app migrates with the new endpoint template and the deliveries template.

- [ ] **Step 7: Commit**

```bash
git add lib/generators app/models/open_loam lib/open_loam/webhooks.rb demo/db demo/test/open_loam_webhook_endpoint_test.rb
git commit -m "feat(webhooks): delivery ledger table, several patterns, host metadata, sealed and rotatable secrets, endpoint health"
```

---

### Task 3: Delivery state machine, signatures and the HTTP transport

**Files:**
- Modify: `lib/open_loam/webhooks.rb` (add the delivery half)
- Create: `lib/open_loam/webhooks/http_transport.rb`
- Modify: `lib/open_loam.rb` (require the transport right after `require "open_loam/webhooks"`)
- Test: `demo/test/open_loam_webhook_delivery_test.rb`

**Interfaces:**
- Consumes: Task 2 models and config.
- Produces: `OpenLoam::Webhooks::Response = Struct.new(:code, :headers, :excerpt, :duration_ms, keyword_init: true)`; `OpenLoam::Webhooks::SkipDelivery < OpenLoam::Error`; `Webhooks.deliver(delivery, now: Time.current)`; `Webhooks.body_for(endpoint, delivery) → String`; `Webhooks.headers_for(endpoint, delivery, body, now) → Hash`; `Webhooks.signature_v2(secrets, body, timestamp) → String`; `Webhooks.verify_v2(header, body, secret, now: Time.current, tolerance: 300) → Boolean`; `HttpTransport.post(url, body:, headers:, timeout:) → Response`. A host `body_builder` is any object with `#call(endpoint:, delivery:) → Hash` and may raise `SkipDelivery`. A `transport` is any object with `#post(url, body:, headers:, timeout:) → Response`.

- [ ] **Step 1: Write the failing test**

```ruby
# demo/test/open_loam_webhook_delivery_test.rb
require "test_helper"

class OpenLoamWebhookDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Stands in for the network: records every request, answers from a script.
  class ScriptedTransport
    attr_reader :requests

    def initialize(*answers)
      @answers = answers
      @requests = []
    end

    def post(url, body:, headers:, timeout:)
      @requests << { url: url, body: body, headers: headers, timeout: timeout }
      answer = @answers.shift || 200
      raise answer if answer.is_a?(Exception)

      code, retry_after = Array(answer)
      OpenLoam::Webhooks::Response.new(code: code, headers: { "retry-after" => retry_after }, excerpt: "body #{code}", duration_ms: 7)
    end
  end

  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Lodz", slug: "lodz-hooks")
    @now = Time.zone.parse("2026-11-20 10:00:00")
    with_tenant(@tenant) do
      @endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      @delivery = @endpoint.deliveries.create!(event_id: "evt-1", event_name: "rental.equipment.created", payload: { "id" => 7 })
    end
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  def deliver(*answers, now: @now)
    transport = ScriptedTransport.new(*answers)
    OpenLoam::Webhooks.transport = transport
    with_tenant(@tenant) { OpenLoam::Webhooks.deliver(@delivery.reload, now: now) }
    @delivery.reload
    transport
  end

  test "a 2xx marks the delivery succeeded and the endpoint healthy" do
    transport = deliver(204)
    assert_equal "succeeded", @delivery.status
    assert_equal 1, @delivery.attempts
    assert_equal 204, @delivery.last_response_code
    assert_equal 7, @delivery.last_duration_ms
    assert_equal @now, @delivery.delivered_at
    assert_equal @now, @endpoint.reload.last_success_at
    assert_equal 1, transport.requests.size
  end

  test "the default body and the v1 signature are the frozen 0.3.0 shapes" do
    request = deliver(200).requests.first
    expected = OpenLoam::WebhookDeliveryJob.body_for("rental.equipment.created", { "id" => 7 }, @tenant.id)
    assert_equal expected, request[:body]
    assert_equal OpenLoam::WebhookDeliveryJob.signature(@endpoint.secret, expected), request[:headers]["X-OpenLoam-Signature"]
  end

  test "headers carry event, ids, timestamp and a verifiable v2 signature" do
    request = deliver(200).requests.first
    headers = request[:headers]
    body = request[:body]
    assert_equal "rental.equipment.created", headers["X-OpenLoam-Event"]
    assert_equal "evt-1", headers["X-OpenLoam-Event-Id"]
    assert_equal @delivery.delivery_id, headers["X-OpenLoam-Delivery"]
    assert_equal @now.to_i.to_s, headers["X-OpenLoam-Timestamp"]
    assert OpenLoam::Webhooks.verify_v2(headers["X-OpenLoam-Signature-V2"], body, @endpoint.secret, now: @now)
    refute OpenLoam::Webhooks.verify_v2(headers["X-OpenLoam-Signature-V2"], body, @endpoint.secret, now: @now + 301)
    refute OpenLoam::Webhooks.verify_v2(headers["X-OpenLoam-Signature-V2"], body + " ", @endpoint.secret, now: @now)
  end

  test "the v2 signature is pinned by a fixed vector and lists every signing secret" do
    assert_equal "t=1700000000,v1=8dbbbbf4523b10bbb793e74d854144c45acccc2d233667b1c06b805b6ded8a84",
                 OpenLoam::Webhooks.signature_v2([ "s3cr3t" ], '{"a":1}', 1_700_000_000)
    assert_equal "t=1700000000,v1=8dbbbbf4523b10bbb793e74d854144c45acccc2d233667b1c06b805b6ded8a84," \
                 "v1=5bed6ff4fdaa1f7539be4b82f6c76ce254e00e815b22b0dc8132056e0392cbcf",
                 OpenLoam::Webhooks.signature_v2(%w[s3cr3t old], '{"a":1}', 1_700_000_000)
  end

  test "the header prefix and user agent are configurable" do
    OpenLoam::Webhooks.header_prefix = "X-Acme"
    OpenLoam::Webhooks.user_agent = "Acme-Webhooks/1"
    headers = deliver(200).requests.first[:headers]
    assert headers.key?("X-Acme-Signature-V2")
    refute headers.key?("X-OpenLoam-Signature-V2")
    assert_equal "Acme-Webhooks/1", headers["User-Agent"]
  end

  test "a host body builder shapes the body per endpoint, and SkipDelivery cancels" do
    OpenLoam::Webhooks.body_builder = ->(endpoint:, delivery:) { { "type" => delivery.event_name, "url" => endpoint.url } }
    assert_equal({ "type" => "rental.equipment.created", "url" => "https://example.test/hook" },
                 JSON.parse(deliver(200).requests.first[:body]))

    with_tenant(@tenant) { @delivery.update!(status: "pending") }
    OpenLoam::Webhooks.body_builder = ->(**) { raise OpenLoam::Webhooks::SkipDelivery, "record erased" }
    transport = deliver(200)
    assert_equal "cancelled", @delivery.status
    assert_empty transport.requests
  end

  test "5xx, 408, 429 and network errors are retried on the schedule; Retry-After wins, capped at an hour" do
    deliver(503)
    assert_equal "pending", @delivery.status
    assert_in_delta 60, @delivery.next_attempt_at - @now, 6.1
    assert_equal "HTTP 503", @delivery.last_error

    second_try = @delivery.next_attempt_at
    deliver([ 429, "120" ], now: second_try)
    assert_equal 2, @delivery.attempts
    assert_equal second_try + 120, @delivery.next_attempt_at

    deliver(Errno::ECONNREFUSED.new, now: @delivery.next_attempt_at)
    assert_equal "pending", @delivery.status
    assert_match(/ECONNREFUSED/, @delivery.last_error)
  end

  test "after the last scheduled retry the delivery fails" do
    OpenLoam::Webhooks.retry_schedule = [ 60 ]
    deliver(500)
    deliver(500, now: @delivery.next_attempt_at)
    assert_equal "failed", @delivery.status
    assert_equal 2, @delivery.attempts
  end

  test "410 fails and disables the endpoint; other 4xx and 3xx fail without retry" do
    deliver(410)
    assert_equal "failed", @delivery.status
    refute @endpoint.reload.active?
    assert_equal "gone", @endpoint.disabled_reason

    with_tenant(@tenant) do
      @endpoint.enable!
      @delivery.update!(status: "pending", next_attempt_at: nil)
    end
    deliver(302)
    assert_equal "failed", @delivery.status
    assert_equal 1, @endpoint.reload.consecutive_failures
  end

  test "an inactive endpoint cancels the delivery without a request" do
    with_tenant(@tenant) { @endpoint.update!(active: false) }
    transport = deliver(200)
    assert_equal "cancelled", @delivery.status
    assert_empty transport.requests
  end

  test "a delivery that is not due, or already claimed, is not sent twice" do
    with_tenant(@tenant) { @delivery.update!(next_attempt_at: @now + 10) }
    assert_empty deliver(200).requests

    with_tenant(@tenant) { @delivery.update!(status: "succeeded") }
    assert_empty deliver(200).requests
  end

  test "a URL that now resolves inside the perimeter fails and disables the endpoint" do
    OpenLoam::Webhooks.transport = Class.new do
      def self.post(*, **) = raise(OpenLoam::OutboundUrl::BlockedError, "10.0.0.1 is not public")
    end
    with_tenant(@tenant) { OpenLoam::Webhooks.deliver(@delivery.reload, now: @now) }
    assert_equal "failed", @delivery.reload.status
    assert_equal "blocked_url", @endpoint.reload.disabled_reason
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd demo && bin/rails test test/open_loam_webhook_delivery_test.rb`
Expected: FAIL — `uninitialized constant OpenLoam::Webhooks::Response`.

- [ ] **Step 3: Implement the transport**

```ruby
# lib/open_loam/webhooks/http_transport.rb
require "net/http"

module OpenLoam
  module Webhooks
    # The only code that opens a socket for a webhook. Connects to the address
    # OutboundUrl just vetted (no DNS rebinding window), never follows a
    # redirect (a 3xx is the answer), and reads at most EXCERPT_BYTES of the
    # response so a hostile receiver cannot make us buffer a large body.
    module HttpTransport
      class ExcerptComplete < StandardError; end

      module_function

      def post(url, body:, headers:, timeout:)
        uri, address = OpenLoam::OutboundUrl.resolve!(url, require_https: Webhooks.require_https?,
                                                           ports: Webhooks.allowed_ports)
        http = Net::HTTP.new(uri.host, uri.port)
        http.ipaddr = address
        http.use_ssl = uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.write_timeout = timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |name, value| request[name] = value }
        request.body = body

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        code = nil
        retry_after = nil
        excerpt = +""
        begin
          http.start do |connection|
            connection.request(request) do |response|
              code = response.code.to_i
              retry_after = response["retry-after"]
              response.read_body do |chunk|
                excerpt << chunk
                raise ExcerptComplete if excerpt.bytesize >= EXCERPT_BYTES
              end
            end
          end
        rescue ExcerptComplete
          # Enough of the body; the connection is closed by http.start's ensure.
        end

        Response.new(code: code, headers: { "retry-after" => retry_after },
                     excerpt: excerpt.byteslice(0, EXCERPT_BYTES).to_s.scrub,
                     duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      end
    end
  end
end
```

In `lib/open_loam.rb` add `require "open_loam/webhooks/http_transport"` directly after `require "open_loam/webhooks"`.

- [ ] **Step 4: Implement the delivery half of `OpenLoam::Webhooks`**

Add inside `module Webhooks` (above `class << self`):

```ruby
    Response = Struct.new(:code, :headers, :excerpt, :duration_ms, keyword_init: true)

    # Raised by a host body builder to drop one delivery on purpose (the record
    # it describes is gone, the receiver may not see this event). The row is
    # cancelled, not failed, and the endpoint's health is untouched.
    class SkipDelivery < OpenLoam::Error; end

    RETRYABLE_CODES = [ 408, 429 ].freeze
    MAX_RETRY_AFTER = 3_600
```

Add these methods inside `class << self` (below the configuration readers):

```ruby
      # One attempt for one row, inside the row's tenant. Safe to call twice:
      # only the caller that flips pending -> sending sends.
      def deliver(delivery, now: Time.current)
        return unless claim(delivery, now)

        delivery.reload
        endpoint = delivery.endpoint
        unless endpoint&.active?
          delivery.update!(status: "cancelled", sending_at: nil, last_error: "endpoint inactive")
          return
        end

        body = body_for(endpoint, delivery)
        response = transport.post(endpoint.url, body: body, headers: headers_for(endpoint, delivery, body, now), timeout: timeout)
        record_response(delivery, endpoint, response, now)
      rescue SkipDelivery => error
        delivery.update!(status: "cancelled", sending_at: nil, last_error: short(error.message))
      rescue OpenLoam::OutboundUrl::BlockedError => error
        delivery.update!(status: "failed", sending_at: nil, last_error: short("blocked: #{error.message}"))
        endpoint&.disable!("blocked_url")
      rescue StandardError => error
        retry_later(delivery, endpoint, now, error: short("#{error.class}: #{error.message}"))
      end

      def body_for(endpoint, delivery)
        if body_builder
          JSON.generate(body_builder.call(endpoint: endpoint, delivery: delivery))
        else
          OpenLoam::WebhookDeliveryJob.body_for(delivery.event_name, delivery.payload_hash, delivery.tenant_id)
        end
      end

      def headers_for(endpoint, delivery, body, now)
        timestamp = now.to_i
        prefix = header_prefix
        {
          "Content-Type" => "application/json",
          "User-Agent" => user_agent,
          "#{prefix}-Event" => delivery.event_name,
          "#{prefix}-Event-Id" => delivery.event_id,
          "#{prefix}-Delivery" => delivery.delivery_id,
          "#{prefix}-Timestamp" => timestamp.to_s,
          "#{prefix}-Signature" => OpenLoam::WebhookDeliveryJob.signature(endpoint.secret, body),
          "#{prefix}-Signature-V2" => signature_v2(endpoint.signing_secrets(now), body, timestamp)
        }
      end

      # "t=<unix>,v1=<hex>[,v1=<hex>]" — HMAC-SHA256 of "<t>.<body>" under each
      # signing secret. The timestamp is inside the MAC, so a captured request
      # cannot be replayed after the receiver's tolerance window.
      def signature_v2(secrets, body, timestamp)
        macs = Array(secrets).map { |secret| "v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, "#{timestamp}.#{body}")}" }
        ([ "t=#{timestamp}" ] + macs).join(",")
      end

      # Reference verifier (docs and tests): constant-time compare, bounded clock skew.
      def verify_v2(header, body, secret, now: Time.current, tolerance: TIMESTAMP_TOLERANCE)
        parts = header.to_s.split(",").map { |part| part.split("=", 2) }
        timestamp = parts.find { |key, _| key == "t" }&.last.to_i
        return false if timestamp.zero? || (now.to_i - timestamp).abs > tolerance

        expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "#{timestamp}.#{body}")
        parts.any? { |key, value| key == "v1" && value && ActiveSupport::SecurityUtils.secure_compare(value, expected) }
      end

      private

      def claim(delivery, now)
        OpenLoam::WebhookDelivery.where(id: delivery.id, status: "pending")
                                 .where("next_attempt_at IS NULL OR next_attempt_at <= ?", now)
                                 .update_all([ "status = 'sending', sending_at = ?, attempts = attempts + 1, updated_at = ?", now, now ]) == 1
      end

      def record_response(delivery, endpoint, response, now)
        attrs = { last_response_code: response.code, last_duration_ms: response.duration_ms,
                  response_excerpt: response.excerpt, sending_at: nil }
        case response.code
        when 200..299
          delivery.update!(attrs.merge(status: "succeeded", delivered_at: now, last_error: nil, next_attempt_at: nil))
          endpoint.record_success!(now)
        when 410
          delivery.update!(attrs.merge(status: "failed", last_error: "HTTP 410"))
          endpoint.disable!("gone")
        when *RETRYABLE_CODES, 500..599
          delivery.assign_attributes(attrs)
          retry_later(delivery, endpoint, now, error: "HTTP #{response.code}", retry_after: retry_after_seconds(response))
        else
          delivery.update!(attrs.merge(status: "failed", last_error: "HTTP #{response.code}"))
          endpoint.record_failure!(now)
        end
      end

      def retry_later(delivery, endpoint, now, error:, retry_after: nil)
        endpoint&.record_failure!(now)
        delay = retry_schedule[delivery.attempts - 1]
        if delay.nil?
          delivery.update!(status: "failed", sending_at: nil, last_error: error)
          return
        end

        wait = retry_after || (delay * (0.9 + (rand * 0.2))).round
        delivery.update!(status: "pending", sending_at: nil, last_error: error, next_attempt_at: now + wait)
        OpenLoam::WebhookDeliveryJob.set(wait: wait).perform_later(delivery.tenant_id, delivery.id)
      end

      def retry_after_seconds(response)
        value = response.headers.to_h["retry-after"].to_s
        return nil unless value.match?(/\A\d+\z/)

        value.to_i.clamp(1, MAX_RETRY_AFTER)
      end

      def short(message) = message.to_s.truncate(255)
```

`private` inside `class << self` makes these singleton methods private; keep `subscribe!`, `dispatch`, `deliver`, `body_for`, `headers_for`, `signature_v2`, `verify_v2` above it. Add `require "json"`, `require "openssl"` and `require "securerandom"` at the top of the file.

- [ ] **Step 5: Run the delivery tests**

Run: `cd demo && bin/rails test test/open_loam_webhook_delivery_test.rb test/open_loam_webhook_endpoint_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/open_loam/webhooks.rb lib/open_loam/webhooks/http_transport.rb lib/open_loam.rb demo/test/open_loam_webhook_delivery_test.rb
git commit -m "feat(webhooks): response-aware retries, timestamped v2 signature, host body builder, bounded transport"
```

---

### Task 4: Dispatch into the ledger, enqueue after commit, the new job signature

**Files:**
- Modify: `lib/open_loam/webhooks.rb` (`dispatch`, `enqueue`, `send_test!`, `redeliver!`)
- Modify: `app/jobs/open_loam/webhook_delivery_job.rb`
- Rewrite: `demo/test/open_loam_webhook_test.rb`

**Interfaces:**
- Consumes: `Webhooks.deliver` (Task 3).
- Produces: `Webhooks.dispatch(event_name, payload)` (unchanged signature; now writes rows), `Webhooks.send_test!(endpoint) → WebhookDelivery`, `Webhooks.redeliver!(delivery) → WebhookDelivery`, `WebhookDeliveryJob.perform(tenant_id, delivery_id)`; the legacy `perform(tenant_id, endpoint_id, event_name, payload)` still works for jobs enqueued by 0.3.0.

- [ ] **Step 1: Rewrite the dispatch test file (keeps every frozen-contract test)**

```ruby
# demo/test/open_loam_webhook_test.rb
require "test_helper"

# Webhooks: a tenant declares where its events go; every matching event becomes
# a ledger row in the publishing transaction and a job after commit. Nothing
# here touches the network.
class OpenLoamWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-hooks")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-hooks")
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  test "a trailing dot matches a whole domain, anything else is one exact event" do
    with_tenant(@warsaw) do
      domain = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      exact = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/one", event_pattern: "rental.equipment.created")

      assert domain.matches?("rental.equipment.created")
      assert domain.matches?("rental.damage_report.submit")
      refute domain.matches?("billing.penalty.due")
      assert exact.matches?("rental.equipment.created")
      refute exact.matches?("rental.equipment.updated")
    end
  end

  test "an endpoint is created with a signing secret and active by default" do
    with_tenant(@warsaw) do
      endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      assert endpoint.active?
      assert endpoint.secret.present?
      refute OpenLoam::WebhookEndpoint.new(url: "not-a-url", event_pattern: "rental.").valid?
    end
  end

  test "a domain event writes one ledger row per matching active endpoint and enqueues its job" do
    with_tenant(@warsaw) do
      matching = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      OpenLoam::WebhookEndpoint.create!(url: "https://example.test/billing", event_pattern: "billing.")
      OpenLoam::WebhookEndpoint.create!(url: "https://example.test/off", event_pattern: "rental.", active: false)

      assert_enqueued_jobs 1, only: OpenLoam::WebhookDeliveryJob do
        Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      end

      delivery = OpenLoam::WebhookDelivery.sole
      assert_equal matching.id, delivery.endpoint_id
      assert_equal "rental.equipment.created", delivery.event_name
      assert_equal "Equipment", delivery.payload_hash["type"]
      assert_equal [ @warsaw.id, delivery.id ], enqueued_jobs.last[:args]
    end
  end

  test "endpoints that receive the same event share its event id" do
    with_tenant(@warsaw) do
      2.times { |i| OpenLoam::WebhookEndpoint.create!(url: "https://example.test/#{i}", event_pattern: "rental.") }
      Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      assert_equal 1, OpenLoam::WebhookDelivery.distinct.count(:event_id)
      assert_equal 2, OpenLoam::WebhookDelivery.distinct.count(:delivery_id)
    end
  end

  test "a rolled-back transaction leaves no row and no job" do
    with_tenant(@warsaw) do
      OpenLoam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      assert_no_enqueued_jobs only: OpenLoam::WebhookDeliveryJob do
        ActiveRecord::Base.transaction do
          OpenLoam::Events.publish("rental.equipment.inspected", { id: 1 })
          raise ActiveRecord::Rollback
        end
      end
      assert_equal 0, OpenLoam::WebhookDelivery.count
    end
  end

  test "another tenant's endpoints never see this tenant's events" do
    with_tenant(@krakow) { OpenLoam::WebhookEndpoint.create!(url: "https://example.test/krakow", event_pattern: "rental.") }
    with_tenant(@warsaw) do
      assert_no_enqueued_jobs only: OpenLoam::WebhookDeliveryJob do
        Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      end
    end
  end

  test "the delivery body carries event, payload and tenant" do
    body = OpenLoam::WebhookDeliveryJob.body_for("rental.equipment.created", { "id" => 7 }, 3)
    assert_equal({ "event" => "rental.equipment.created", "payload" => { "id" => 7 }, "tenant_id" => 3 }, JSON.parse(body))
  end

  test "the signature is HMAC-SHA256 of the exact body under the endpoint's secret" do
    # A fixed vector: if the algorithm, the digest encoding or the header format
    # ever changes, every receiver in the world breaks — so pin it.
    assert_equal "sha256=d42927434049e0b8c73ce887062238cc1c6bb6644bfe66e66d8dd0f30b85679e",
                 OpenLoam::WebhookDeliveryJob.signature("s3cr3t", '{"a":1}')
  end

  test "the job delivers a ledger row through the configured transport" do
    sent = []
    OpenLoam::Webhooks.transport = Class.new do
      define_singleton_method(:post) do |url, body:, headers:, timeout:|
        sent << [ url, JSON.parse(body) ]
        OpenLoam::Webhooks::Response.new(code: 200, headers: {}, excerpt: "", duration_ms: 1)
      end
    end
    delivery = with_tenant(@warsaw) do
      endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      endpoint.deliveries.create!(event_id: "e1", event_name: "rental.equipment.created", payload: { "id" => 7 })
    end

    OpenLoam::WebhookDeliveryJob.perform_now(@warsaw.id, delivery.id)

    assert_equal [ [ "https://example.test/hook", { "event" => "rental.equipment.created", "payload" => { "id" => 7 }, "tenant_id" => @warsaw.id } ] ], sent
    with_tenant(@warsaw) { assert_equal "succeeded", delivery.reload.status }
  end

  test "a job enqueued by 0.3.0 (endpoint id, event, payload) still delivers once" do
    OpenLoam::Webhooks.transport = Class.new do
      def self.post(*, **) = OpenLoam::Webhooks::Response.new(code: 200, headers: {}, excerpt: "", duration_ms: 1)
    end
    endpoint_id = with_tenant(@warsaw) { OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.").id }

    OpenLoam::WebhookDeliveryJob.perform_now(@warsaw.id, endpoint_id, "rental.equipment.created", { "id" => 8 })

    with_tenant(@warsaw) do
      delivery = OpenLoam::WebhookDelivery.sole
      assert_equal "succeeded", delivery.status
      assert_equal({ "id" => 8 }, delivery.payload_hash)
    end
  end

  test "a delivery for a tenant that no longer exists is dropped" do
    assert_nothing_raised { OpenLoam::WebhookDeliveryJob.perform_now(0, 0) }
    assert_nothing_raised { OpenLoam::WebhookDeliveryJob.perform_now(0, 0, "rental.equipment.created", { "id" => 7 }) }
  end

  test "send_test! and redeliver! create or reset a row and enqueue it" do
    OpenLoam::Webhooks.test_event_name = "acme.webhook.test"
    with_tenant(@warsaw) do
      endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      test_delivery = nil
      assert_enqueued_with(job: OpenLoam::WebhookDeliveryJob) { test_delivery = OpenLoam::Webhooks.send_test!(endpoint) }
      assert_equal "acme.webhook.test", test_delivery.event_name
      assert_equal true, test_delivery.payload_hash["test"]

      test_delivery.update!(status: "failed", attempts: 3, next_attempt_at: 1.hour.from_now)
      assert_enqueued_with(job: OpenLoam::WebhookDeliveryJob, args: [ @warsaw.id, test_delivery.id ]) do
        OpenLoam::Webhooks.redeliver!(test_delivery)
      end
      assert_equal "pending", test_delivery.reload.status
      assert_nil test_delivery.next_attempt_at
    end
  end
end
```

- [ ] **Step 2: Run it to verify the new tests fail**

Run: `cd demo && bin/rails test test/open_loam_webhook_test.rb`
Expected: FAIL — no `WebhookDelivery` rows are written; `send_test!` undefined.

- [ ] **Step 3: Implement dispatch, enqueue, test send, redeliver**

Replace `dispatch` in `lib/open_loam/webhooks.rb` and add the helpers (public, above `private`):

```ruby
      # Runs inline in whatever published the event, inside its transaction when
      # there is one: the ledger rows commit or roll back with the change itself,
      # and the jobs are enqueued only after that commit.
      def dispatch(event_name, payload)
        tenant = OpenLoam::Tenant.find_by(id: payload[:tenant_id])
        return if tenant.nil?

        deliverable = payload.transform_keys(&:to_s)
        event_id = SecureRandom.uuid

        OpenLoam.as_tenant(tenant) do
          OpenLoam::WebhookEndpoint.active.each do |endpoint|
            next unless endpoint.matches?(event_name)

            enqueue(endpoint.deliveries.create!(event_id: event_id, event_name: event_name.to_s, payload: deliverable))
          end
        end
      end

      def send_test!(endpoint)
        delivery = endpoint.deliveries.create!(event_id: SecureRandom.uuid, event_name: test_event_name,
                                               payload: { "test" => true, "tenant_id" => endpoint.tenant_id })
        enqueue(delivery)
        delivery
      end

      def redeliver!(delivery)
        delivery.update!(status: "pending", next_attempt_at: nil, sending_at: nil)
        enqueue(delivery)
        delivery
      end

      def enqueue(delivery)
        tenant_id = delivery.tenant_id
        delivery_id = delivery.id
        after_commit { OpenLoam::WebhookDeliveryJob.perform_later(tenant_id, delivery_id) }
      end

      # Rails >= 7.2 defers to the outermost commit (and runs at once when no
      # transaction is open). On 7.1 the job may start before the row is visible;
      # it then finds nothing and the sweep picks the row up.
      def after_commit(&block)
        if ActiveRecord.respond_to?(:after_all_transactions_commit)
          ActiveRecord.after_all_transactions_commit(&block)
        else
          block.call
        end
      end
```

Replace `app/jobs/open_loam/webhook_delivery_job.rb`:

```ruby
require "net/http"
require "openssl"

module OpenLoam
  # Runs one attempt for one ledger row (OpenLoam::WebhookDelivery). Inherits
  # ActiveJob::Base rather than the host's ApplicationJob, and keeps no retry
  # state: OpenLoam::Webhooks.deliver moves the row and schedules the next try.
  #
  # The 4-argument form is what 0.3.0 enqueued (endpoint id, event, payload); a
  # job still in the queue at upgrade time becomes a ledger row and is delivered.
  class WebhookDeliveryJob < ActiveJob::Base
    queue_as :default

    # Frozen (BACKWARD_COMPATIBILITY.md §6): the default body and the v1 signature.
    def self.body_for(event_name, payload, tenant_id)
      JSON.generate(event: event_name, payload: payload, tenant_id: tenant_id)
    end

    def self.signature(secret, body)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, body)}"
    end

    def perform(tenant_id, delivery_id, legacy_event_name = nil, legacy_payload = nil)
      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      OpenLoam.as_tenant(tenant) do
        delivery =
          if legacy_event_name
            endpoint = OpenLoam::WebhookEndpoint.find_by(id: delivery_id)
            next if endpoint.nil? || !endpoint.active?

            endpoint.deliveries.create!(event_id: SecureRandom.uuid, event_name: legacy_event_name.to_s,
                                        payload: legacy_payload || {})
          else
            OpenLoam::WebhookDelivery.find_by(id: delivery_id)
          end
        # Not visible yet (the creating transaction has not committed) or gone:
        # the sweep covers the first case.
        next if delivery.nil?

        OpenLoam::Webhooks.deliver(delivery)
      end
    end
  end
end
```

- [ ] **Step 4: Run all webhook tests**

Run: `cd demo && bin/rails test test/open_loam_webhook_test.rb test/open_loam_webhook_delivery_test.rb test/open_loam_webhook_endpoint_test.rb`
Expected: PASS.

- [ ] **Step 5: Run the full demo suite (other features publish events)**

Run: `cd demo && bin/rails test`
Expected: PASS. If a test elsewhere asserted the old 4-argument job args, update it to `[tenant_id, delivery_id]`.

- [ ] **Step 6: Commit**

```bash
git add lib/open_loam/webhooks.rb app/jobs/open_loam/webhook_delivery_job.rb demo/test/open_loam_webhook_test.rb
git commit -m "feat(webhooks): write a ledger row per delivery in the publishing transaction, enqueue after commit"
```

---

### Task 5: Sweep, prune and the blessed cross-tenant lookup

**Files:**
- Modify: `lib/open_loam/webhooks.rb` (`sweep`, `tenant_ids_needing_sweep`)
- Create: `app/jobs/open_loam/webhook_sweep_job.rb`
- Modify: `lib/open_loam/engine.rb` (register with the scheduler)
- Test: `demo/test/open_loam_webhook_sweep_test.rb`

**Interfaces:**
- Produces: `Webhooks.sweep(now: Time.current) → Integer` (rows re-enqueued, inside a tenant), `Webhooks.tenant_ids_needing_sweep(now: Time.current) → Array<id>` (cross-tenant, ids only), `WebhookSweepJob.perform(tenant_id: nil)`: with no tenant it fans out one job per tenant that needs a sweep. Scheduler key `"open_loam_webhook_sweep"`, `interval:60`, scope tenant. Hosts that do not tick `OpenLoam::Scheduler` schedule `OpenLoam::WebhookSweepJob` themselves (ChatlyBot: `config/recurring.yml`).

- [ ] **Step 1: Write the failing test**

```ruby
# demo/test/open_loam_webhook_sweep_test.rb
require "test_helper"

class OpenLoamWebhookSweepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @now = Time.zone.parse("2026-11-20 12:00:00")
    @tenant = OpenLoam::Tenant.create!(name: "Branch Poznan", slug: "poznan-hooks")
    @quiet = OpenLoam::Tenant.create!(name: "Branch Opole", slug: "opole-hooks")
    with_tenant(@tenant) do
      @endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
    end
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  def row(**attrs)
    with_tenant(@tenant) do
      @endpoint.deliveries.create!({ event_id: SecureRandom.uuid, event_name: "rental.equipment.created", payload: {} }.merge(attrs))
    end
  end

  test "lost, overdue and stuck rows are re-enqueued; fresh and future rows are left alone" do
    lost = row(created_at: @now - 5.minutes)
    overdue = row(next_attempt_at: @now - 1.second, attempts: 2)
    stuck = row(status: "sending", sending_at: @now - 10.minutes, attempts: 1)
    fresh = row(created_at: @now - 10.seconds)
    future = row(next_attempt_at: @now + 1.hour, attempts: 1)

    enqueued = with_tenant(@tenant) { OpenLoam::Webhooks.sweep(now: @now) }

    assert_equal 3, enqueued
    ids = enqueued_jobs.select { |job| job[:job] == OpenLoam::WebhookDeliveryJob }.map { |job| job[:args].last }
    assert_equal [ lost.id, overdue.id, stuck.id ].sort, ids.sort
    with_tenant(@tenant) { assert_equal "pending", stuck.reload.status }
    refute_includes ids, fresh.id
    refute_includes ids, future.id
  end

  test "final rows older than the retention are pruned" do
    old = row(status: "succeeded", updated_at: @now - 31.days)
    recent = row(status: "failed", updated_at: @now - 1.day)
    with_tenant(@tenant) do
      OpenLoam::Webhooks.sweep(now: @now)
      refute OpenLoam::WebhookDelivery.exists?(old.id)
      assert OpenLoam::WebhookDelivery.exists?(recent.id)
    end
  end

  test "the fan-out job only visits tenants with work" do
    row(created_at: @now - 5.minutes)
    travel_to(@now) do
      assert_equal [ @tenant.id ], OpenLoam::Webhooks.tenant_ids_needing_sweep
      assert_enqueued_with(job: OpenLoam::WebhookSweepJob, args: [ { tenant_id: @tenant.id } ]) do
        OpenLoam::WebhookSweepJob.perform_now
      end
    end
  end

  test "the sweep is registered with the scheduler" do
    assert(OpenLoam::Scheduler.registered.any? { |entry| entry[:key] == "open_loam_webhook_sweep" })
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd demo && bin/rails test test/open_loam_webhook_sweep_test.rb`
Expected: FAIL — `undefined method 'sweep'`.

- [ ] **Step 3: Implement**

Add to the public part of `class << self` in `lib/open_loam/webhooks.rb`:

```ruby
      # Inside one tenant: stuck rows go back to pending (at-least-once — the
      # receiver dedupes by event id), every overdue row gets a job, and final
      # rows past the retention are deleted. Returns the number re-enqueued.
      def sweep(now: Time.current, limit: 500)
        OpenLoam::WebhookDelivery.stuck(now).update_all(status: "pending", sending_at: nil, next_attempt_at: now, updated_at: now)

        tenant_id = OpenLoam.tenant!.id
        ids = OpenLoam::WebhookDelivery.overdue(now).order(:id).limit(limit).pluck(:id)
        ids.each { |id| OpenLoam::WebhookDeliveryJob.perform_later(tenant_id, id) }

        OpenLoam::WebhookDelivery.prunable(now, delivery_retention).delete_all if delivery_retention
        ids.size
      end

      # Blessed cross-tenant lookup (BACKWARD_COMPATIBILITY.md §1), the webhook
      # twin of the scheduler's due-job claim: tenant ids only, never rows.
      def tenant_ids_needing_sweep(now: Time.current)
        all = OpenLoam::WebhookDelivery.unscoped
        work = all.overdue(now).or(all.stuck(now))
        work = work.or(all.prunable(now, delivery_retention)) if delivery_retention
        work.distinct.pluck(:tenant_id)
      end
```

Add the constant at module level, next to `DISABLED_EVENT`:

```ruby
    SWEEP_KEY = "open_loam_webhook_sweep".freeze
```

`app/jobs/open_loam/webhook_sweep_job.rb`:

```ruby
module OpenLoam
  # Finishes what a lost job left behind and prunes the ledger.
  #
  # With a tenant (how OpenLoam::Scheduler runs it): sweeps that tenant.
  # Without one (how a host's own cron runs it, e.g. Solid Queue recurring):
  # enqueues one tenant-scoped sweep per tenant that has work.
  class WebhookSweepJob < ActiveJob::Base
    queue_as :default

    def perform(tenant_id: nil)
      if tenant_id.nil?
        OpenLoam::Webhooks.tenant_ids_needing_sweep.each { |id| self.class.perform_later(tenant_id: id) }
        return
      end

      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      OpenLoam.as_tenant(tenant) { OpenLoam::Webhooks.sweep }
    end
  end
end
```

In `lib/open_loam/engine.rb`, inside `config.after_initialize`, after the event-log prune registration:

```ruby
      # Webhook ledger sweep: lost/stuck deliveries and retention, every minute.
      OpenLoam::Scheduler.register(
        key: OpenLoam::Webhooks::SWEEP_KEY, name: "Webhook delivery sweep",
        job_class: "OpenLoam::WebhookSweepJob", schedule: "interval:60", scope: "tenant"
      )
```

- [ ] **Step 4: Run the sweep tests and the scheduler tests**

Run: `cd demo && bin/rails test test/open_loam_webhook_sweep_test.rb test/open_loam_scheduled_job_test.rb`
Expected: PASS. If a scheduler test counts registered defaults, raise its expected count by one.

- [ ] **Step 5: Guardrail check**

Run: `cd demo && bin/rails test test/open_loam_guardrails_test.rb`
Expected: PASS (the `.unscoped` lives in gem code, not the demo's `app/`).

- [ ] **Step 6: Commit**

```bash
git add lib/open_loam/webhooks.rb app/jobs/open_loam/webhook_sweep_job.rb lib/open_loam/engine.rb demo/test/open_loam_webhook_sweep_test.rb
git commit -m "feat(webhooks): sweep lost and stuck deliveries, prune the ledger, fan out across tenants"
```

---

### Task 6: Admin template, docs, contract, changelog, version

**Files:**
- Modify: `lib/generators/open_loam/install/templates/admin/webhook_endpoints_index.html.erb` and `demo/app/views/admin/webhook_endpoints/index.html.erb` (identical change)
- Create: `docs/_agents/webhooks.md`
- Modify: `BACKWARD_COMPATIBILITY.md`, `CHANGELOG.md`, `ROADMAP.md`, `lib/open_loam/version.rb`

- [ ] **Step 1: Admin index stops printing the secret**

In both index templates, replace the secret cell `<td><code><%%= record.secret %></code></td>` (demo: `<%= record.secret %>`) with a status cell:

```erb
        <td><%%= record.active? ? "active" : "disabled (#{record.disabled_reason})" %></td>
```

(demo copy without the extra `%`), rename the matching `<th>` from `Secret` to `Status`, and replace the closing paragraph with:

```erb
<p>Each delivery is signed twice: <code>X-OpenLoam-Signature: sha256=HMAC-SHA256(secret, body)</code> (kept for
existing receivers) and <code>X-OpenLoam-Signature-V2: t=&lt;unix&gt;,v1=HMAC-SHA256(secret, "&lt;t&gt;.&lt;body&gt;")</code>,
which new receivers should verify. Read the secret with <code>OpenLoam::WebhookEndpoint#secret</code> in a console;
it is not shown here.</p>
```

Run: `rake test` (root) and `cd demo && bin/rails test test/controllers`
Expected: PASS.

- [ ] **Step 2: `docs/_agents/webhooks.md`**

```markdown
---
title: Outbound webhooks
description: "Ledger, retries, signatures and host hooks for OpenLoam's outbound webhooks."
nav_order: 3
---

# Outbound webhooks

Every OpenLoam event is offered to the tenant's active `OpenLoam::WebhookEndpoint`s.
A matching endpoint gets one `OpenLoam::WebhookDelivery` row, written in the
publishing transaction; `OpenLoam::WebhookDeliveryJob` is enqueued after commit.

## Guarantee

At-least-once, unordered. Receivers dedupe by the `-Event-Id` header (shared by
every endpoint and every retry of one event). The body may be rebuilt on a retry,
so it can reflect newer data than the first attempt.

## Lifecycle

`pending -> sending -> succeeded | failed`, back to `pending` with
`next_attempt_at` for a retry, `cancelled` when the endpoint is off or the body
builder raises `OpenLoam::Webhooks::SkipDelivery`.

| Answer | Outcome |
|---|---|
| 2xx | succeeded; endpoint `consecutive_failures` reset |
| 408, 429, 5xx, network error, timeout | retried on `retry_schedule` (default 1m, 5m, 30m, 2h, 6h, 12h, 24h, ±10% jitter); `Retry-After` seconds win, capped at 1h |
| 410 | failed; endpoint disabled (`gone`) |
| other 1xx/3xx/4xx | failed, no retry (redirects are never followed) |
| URL now resolves inside the perimeter | failed; endpoint disabled (`blocked_url`) |

`disable_after_failures` (default 50) failed attempts in a row disable the endpoint
and publish `open_loam.webhook.endpoint_disabled` (`endpoint_id`, `reason`).
`WebhookEndpoint#enable!` switches it back on.

## Headers

`<prefix>` is `X-OpenLoam` unless `OpenLoam::Webhooks.header_prefix` is set.

| Header | Value |
|---|---|
| `<prefix>-Event` | event name |
| `<prefix>-Event-Id` | UUID per event |
| `<prefix>-Delivery` | `whd_...` per (event, endpoint) |
| `<prefix>-Timestamp` | Unix seconds of this attempt |
| `<prefix>-Signature` | `sha256=HMAC-SHA256(secret, body)` — frozen 0.3.0 format |
| `<prefix>-Signature-V2` | `t=<ts>,v1=HMAC-SHA256(secret, "<ts>.<body>")`, one `v1=` per signing secret during rotation |

Verify V2: split on `,`, reject when `|now - t| > 300`, compare each `v1` in constant
time. `OpenLoam::Webhooks.verify_v2(header, body, secret)` is the reference.

## Host configuration

```ruby
OpenLoam::Webhooks.header_prefix = "X-Acme"
OpenLoam::Webhooks.user_agent = "Acme-Webhooks/1.0"
OpenLoam::Webhooks.require_https = true
OpenLoam::Webhooks.allowed_ports = [ 443 ]
OpenLoam::Webhooks.encrypt_secrets = true        # needs OpenLoam::Encryption.master_key
OpenLoam::Webhooks.test_event_name = "acme.webhook.test"
OpenLoam::Webhooks.delivery_retention = 30.days  # nil keeps rows forever
OpenLoam::Webhooks.body_builder = Acme::WebhookBody # #call(endpoint:, delivery:) -> Hash
```

Endpoints follow one pattern (`event_pattern`) or several (`event_patterns`), and
carry a host-owned `metadata` json (`#settings`). `send_test!(endpoint)`,
`redeliver!(delivery)` and `endpoint.rotate_secret!` (old secret valid for
`secret_rotation_grace`, default 24h) are the operator actions.

## Sweep

`OpenLoam::WebhookSweepJob` is registered with the scheduler (every 60 s, per
tenant). An app that does not tick `OpenLoam::Scheduler` runs
`OpenLoam::WebhookSweepJob.perform_later` (no arguments) from its own cron every
minute; it fans out to tenants with work.
```

- [ ] **Step 3: `BACKWARD_COMPATIBILITY.md`**

In §1 add `Webhooks.tenant_ids_needing_sweep` to the list of blessed cross-tenant lookups. In §6 add rows:

```markdown
| Outbound signature v2 | `<prefix>-Signature-V2: t=<unix>,v1=<hex>` where hex = `HMAC-SHA256(secret, "<t>.<exact_body>")`, one `v1=` per signing secret. **Pinned by a fixed test vector** (`t=1700000000`, secret `s3cr3t`, body `{"a":1}`). |
| Outbound delivery guarantee | At-least-once, unordered; `<prefix>-Event-Id` is stable across endpoints and retries. |
| Outbound header prefix | `X-OpenLoam` by default; `OpenLoam::Webhooks.header_prefix` renames every header including the v1 signature. |
```

- [ ] **Step 4: `CHANGELOG.md`** — add under `## Unreleased`, then rename it `## 0.4.0 — <release date>` at release:

```markdown
### Fixed

- **Outbound webhooks dropped data on any receiver error.** The response code
  was never read, so a 500 or a timeout lost the event. Deliveries are now rows
  (`open_loam_webhook_deliveries`) retried by response code.
- **SSRF through IPv4-mapped IPv6 literals** (`http://[::ffff:127.0.0.1]/`,
  `[::ffff:169.254.169.254]`). `OutboundUrl` judges mapped and compatible
  addresses by the IPv4 ranges and blocks NAT64 (`64:ff9b::/96`).

### Added

- Webhook delivery ledger, retry schedule, `Retry-After`, auto-disable after
  `disable_after_failures`, `open_loam.webhook.endpoint_disabled` event, sweep job,
  retention prune, `send_test!`, `redeliver!`.
- `<prefix>-Signature-V2` (timestamped) plus `-Event-Id`, `-Delivery`,
  `-Timestamp` headers; configurable prefix and user agent.
- Secret rotation with a grace period; optional sealing of secrets
  (`encrypt_secrets`).
- `event_patterns` (several per endpoint), `metadata` and `description` on
  endpoints; host `body_builder` and `SkipDelivery`.
- `OutboundUrl` `ports:` allowlist; `require_https`/`allowed_ports` for webhooks.

#### Migration

Copy `demo/db/migrate/20261120090000_add_open_loam_webhook_reliability.rb`.
Existing endpoints keep working unchanged (single pattern, plaintext secret).
Jobs enqueued by 0.3.0 are still accepted. Apps that do not tick
`OpenLoam::Scheduler` must schedule `OpenLoam::WebhookSweepJob` every minute.
The admin endpoints index no longer prints the secret; re-copy it if you
generated it.
```

- [ ] **Step 5: version and roadmap**

`lib/open_loam/version.rb`: `VERSION = "0.4.0"`. In `ROADMAP.md`, add a shipped line: `- ~~Reliable outbound webhooks~~ — ✅ ledger, retries, v2 signature (0.4.0). See docs/_agents/webhooks.md.`

- [ ] **Step 6: Both suites**

Run: `rake test` then `cd demo && bin/rails test`
Expected: PASS, both.

- [ ] **Step 7: Commit**

```bash
git add lib/generators/open_loam/install/templates/admin/webhook_endpoints_index.html.erb demo/app/views/admin/webhook_endpoints/index.html.erb docs/_agents/webhooks.md BACKWARD_COMPATIBILITY.md CHANGELOG.md ROADMAP.md lib/open_loam/version.rb
git commit -m "docs(webhooks): delivery contract, v2 signature, upgrade notes; chore(release): 0.4.0"
```

---

### Task 7 (owner action): release

Only after review approval and with the owner's go-ahead:

```bash
git checkout main && git merge --no-ff feat/reliable-webhooks
git tag v0.4.0 && git push origin main v0.4.0
gem build open-loam.gemspec && gem push open-loam-0.4.0.gem
```

Then ChatlyBot's plan (`chatlybot/docs/spark/plans/2026-11-20-crm-webhooks-a1.md`) starts with the pin bump.

## Self-review notes

- Spec §3.1 coverage: ledger (T2/T4), retries + Retry-After (T3), auto-disable + event (T2/T3), v2 signature + rotation (T2/T3), secret sealing (T2), patterns + metadata (T2), body builder (T3), SSRF fix + https/ports (T1/T3), sweep + retention (T5), docs/contract (T6).
- Not in this release (by decision): per-endpoint concurrency limit, delivery UI in the generated admin.
- Names used across tasks: `Webhooks.deliver`, `Webhooks.enqueue`, `Webhooks.sweep`, `Webhooks.tenant_ids_needing_sweep`, `Webhooks::SWEEP_KEY`, `Webhooks::Response`, `Webhooks::SkipDelivery`, `WebhookEndpoint#signing_secrets/#record_success!/#record_failure!/#disable!/#enable!/#settings/#patterns`, `WebhookDelivery` scopes `overdue/stuck/prunable/due/recent_first`.
