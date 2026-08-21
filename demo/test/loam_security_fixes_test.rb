require "test_helper"

# Regression tests for the LATER-batch security review (2 HIGH + MEDs + LOWs).
class LoamSecurityFixesTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sec")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-sec")
    @mgr = User.create!(name: "M", email: "m@example.test", password: "password")
    @emp = User.create!(name: "E", email: "e@example.test", password: "password")
    [ @warsaw, @krakow ].each do |t|
      with_tenant(t) do
        Loam::Membership.create!(user: @mgr, role: "manager")
        Loam::Membership.create!(user: @emp, role: "employee")
      end
    end
  end

  # HIGH 2 — the workflow column may only change through a transition (model layer).
  test "a direct write to a workflow column is refused; transitions still work" do
    with_tenant(@warsaw, actor: @mgr) do
      report = DamageReport.create!(equipment_id: 1, description: "x", state: "open")

      # direct write (edit form / import) — refused
      refute report.update(state: "approved"), "a direct status write is rejected"
      assert report.errors[:state].any?
      assert_equal "open", report.reload.state

      # Bulk.set_field on the workflow column — refused (0 affected, unchanged)
      count = Loam::Bulk.set_field(DamageReport, [ report.id ], field: "state", value: "approved")
      assert_equal 0, count
      assert_equal "open", report.reload.state

      # the transition path still works
      report.submit!
      assert_equal "pending_approval", report.reload.state
      report.approve!
      assert_equal "approved", report.reload.state
    end
  end

  # MED 1 — only allowlisted job classes are schedulable.
  test "a non-allowlisted ActiveJob class cannot be scheduled" do
    saved = Loam.schedulable_jobs
    Loam.schedulable_jobs = %w[DemoScheduledJob]
    with_tenant(@warsaw) do
      bad = Loam::ScheduledJob.new(key: "purge", name: "x", job_class: "ActiveStorage::PurgeJob", schedule: "0 0 * * *")
      refute bad.valid?, "a real ActiveJob that isn't allowlisted is refused"
      assert Loam::ScheduledJob.new(key: "ok", name: "ok", job_class: "DemoScheduledJob", schedule: "0 0 * * *").valid?
    end
  ensure
    Loam.schedulable_jobs = saved
  end

  # MED 2 — a failed import row must not persist raw cell values (PII) in the result.
  test "import error rows carry only row + message, never the raw cell values" do
    with_tenant(@warsaw, actor: @mgr) do
      csv = "Desc,State\nSENSITIVE-PII,NOPE\n"  # NOPE fails the state validation
      result = Loam::Import.run(csv, model: DamageReport, mapping: { "Desc" => "description", "State" => "state" }, actor: @mgr)

      assert_equal 1, result.failed
      assert_equal %w[row message], result.errors.first.keys, "only row + message"
      refute_includes result.to_h.to_json, "SENSITIVE-PII", "the raw cell value never reaches the persisted result"
    end
  end

  # MED 3 — the translates/encrypts guard is order-independent.
  test "translates + encrypts on the same field is refused in BOTH declaration orders" do
    assert_raises(Loam::Error) do
      Class.new(Loam::TenantRecord) do
        self.table_name = "loam_translations"
        include Loam::Encryptable
        include Loam::Translatable
        translates :value
        encrypts :value          # translates-then-encrypts
      end
    end

    assert_raises(Loam::Error) do
      Class.new(Loam::TenantRecord) do
        self.table_name = "loam_translations"
        include Loam::Encryptable
        include Loam::Translatable
        encrypts :value
        translates :value        # encrypts-then-translates
      end
    end
  end

  # LOW 1 — CSV formula injection is neutralized.
  test "a formula-looking cell is neutralized in CSV export" do
    with_tenant(@warsaw, actor: @mgr) do
      Equipment.create!(name: "=HYPERLINK(\"http://evil\")", daily_rate: 1, status: "available")
      csv = Loam::Export.csv(Equipment.all, actor: @mgr)
      refute_match(/^=HYPERLINK/, csv, "a leading = is escaped")
      assert_match(/'=HYPERLINK/, csv, "prefixed with a single quote")
    end
  end

  # LOW 2 — the OpenAPI column fallback never surfaces an encrypted/_hash column.
  test "OpenApi column fallback excludes encrypted and blind-index columns" do
    # Customer has a searchable-encrypted email -> an email_hash blind-index column.
    fallback = Customer.column_names - Loam::OpenApi.plumbing(Customer) -
               Customer.loam_encrypted_attributes - Customer.loam_searchable_encrypted_attributes.map { |a| "#{a}_hash" }
    refute_includes fallback, "email_hash", "the blind index is not exposed"
    refute_includes fallback, "email", "the encrypted column is not exposed"

    # And the generated document's Customer schema never carries the hash.
    schema = Loam::OpenApi.document["components"]["schemas"]["Customer"]["properties"]
    refute schema.key?("email_hash")
  end
end

# Controller-level regressions.
class AdminSecurityFixesTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sec-adm")
    @mgr = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @emp = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @mgr, role: "manager")
      Loam::Membership.create!(user: @emp, role: "employee")
    end
  end

  def sign_in(email)
    post admin_session_path, params: { email: email, password: "password" }
  end

  # HIGH 1 — a tenant manager can't create a scope:"system" schedule.
  test "a manager's scope:system schedule is forced to tenant" do
    saved = Loam.schedulable_jobs
    Loam.schedulable_jobs = %w[DemoScheduledJob]
    sign_in("anna@example.test")

    post admin_scheduled_jobs_path, params: { scheduled_job: {
      key: "x", name: "x", job_class: "DemoScheduledJob", schedule: "0 3 * * *", scope: "system", active: "1"
    } }

    job = with_tenant(@tenant) { Loam::ScheduledJob.find_by(key: "x") }
    assert job
    assert_equal "tenant", job.scope, "scope is forced to tenant, not the submitted system"
  ensure
    Loam.schedulable_jobs = saved
  end

  # MED 4 — the bulk export branch is manager-gated.
  test "an employee cannot bulk-export" do
    rig = with_tenant(@tenant) { Equipment.create!(name: "Rig", daily_rate: 1, status: "available") }
    sign_in("tomek@example.test")

    post bulk_admin_equipment_index_path, params: { bulk_action: "export", ids: [ rig.id ] }
    assert_response :forbidden
  end

  # LOW 3 — a member can't cancel another user's job.
  test "an employee cannot cancel a job they do not own" do
    job = with_tenant(@tenant, actor: @mgr) { Loam::Progress.start(name: "mgr job", total: 5) }
    sign_in("tomek@example.test")

    post cancel_admin_progress_job_path(job)
    assert_response :forbidden
    assert_equal "running", with_tenant(@tenant) { job.reload.status }
  end
end
