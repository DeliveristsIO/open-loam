require "test_helper"

# Loam::Import (mapping engine) + Loam::Export (policy/encryption-aware CSV).
class LoamImportTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-imp")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-imp")
    @mgr = User.create!(name: "M", email: "m@example.test", password: "password")
    @emp = User.create!(name: "E", email: "e@example.test", password: "password")
    [ @warsaw, @krakow ].each do |t|
      with_tenant(t) do
        Loam::Membership.create!(user: @mgr, role: "manager")
        Loam::Membership.create!(user: @emp, role: "employee")
      end
    end
  end

  test "import creates new rows and updates existing by a match key" do
    with_tenant(@warsaw, actor: @mgr) do
      Equipment.create!(name: "Drill A", daily_rate: 10, status: "available")
      csv = "Name,Rate,Status\nDrill A,25,rented\nDrill B,15,available\n"
      mapping = { "Name" => "name", "Rate" => "daily_rate", "Status" => "status" }

      result = Loam::Import.run(csv, model: Equipment, mapping: mapping, actor: @mgr, match_key: "name")

      assert_equal 1, result.created
      assert_equal 1, result.updated
      assert_equal 0, result.failed
      assert_equal 25.0, Equipment.find_by(name: "Drill A").daily_rate
      assert Equipment.exists?(name: "Drill B")
    end
  end

  test "a row that fails validation is logged and skipped; the rest import" do
    with_tenant(@warsaw, actor: @mgr) do
      # DamageReport.state has an inclusion validation (its workflow states).
      csv = "Desc,State\ngood,open\nbad,NOPE\nalso good,open\n"
      mapping = { "Desc" => "description", "State" => "state" }

      result = Loam::Import.run(csv, model: DamageReport, mapping: mapping, actor: @mgr)

      assert_equal 2, result.created
      assert_equal 1, result.failed
      assert_equal 3, result.errors.first["row"], "the bad row's number is recorded"
      assert_match(/State|state/, result.errors.first["message"])
    end
  end

  test "a dry run validates but commits nothing" do
    with_tenant(@warsaw, actor: @mgr) do
      result = Loam::Import.run("Name,Status\nGhost,available\n", model: Equipment,
                                mapping: { "Name" => "name", "Status" => "status" }, actor: @mgr, dry_run: true)

      assert_equal 1, result.created, "reports what WOULD be created"
      refute Equipment.exists?(name: "Ghost"), "but nothing was saved"
    end
  end

  test "the error file lists the failed rows with reasons" do
    with_tenant(@warsaw, actor: @mgr) do
      csv = "Desc,State\nbad,NOPE\n"
      result = Loam::Import.run(csv, model: DamageReport, mapping: { "Desc" => "description", "State" => "state" }, actor: @mgr, dry_run: true)
      error_csv = Loam::Import.error_csv(result, %w[Desc State])

      assert_match "_error", error_csv.lines.first
      assert_match "bad", error_csv
    end
  end

  test "a mapping to tenant_id or a non-permitted field is refused" do
    with_tenant(@warsaw, actor: @mgr) do
      assert_raises(Loam::Error) do
        Loam::Import.run("X\n1\n", model: Equipment, mapping: { "X" => "tenant_id" }, actor: @mgr)
      end
      assert_raises(Loam::Error) do
        Loam::Import.run("X\n1\n", model: Equipment, mapping: { "X" => "made_up_field" }, actor: @mgr)
      end
    end
  end

  test "the import target must be a Loam entity, never an arbitrary class" do
    %w[User Kernel String].each do |bad|
      assert_raises(Loam::Error) { Loam::Import.allowed_model(bad) }
    end
    assert_equal Equipment, Loam::Import.allowed_model("Equipment")
  end

  test "update-by-key can only ever match a record in the CURRENT tenant" do
    with_tenant(@krakow, actor: @mgr) { Equipment.create!(name: "Shared", daily_rate: 1, status: "available") }
    with_tenant(@warsaw, actor: @mgr) do
      # Same name exists in Krakow; importing here must CREATE, not reach across.
      result = Loam::Import.run("Name,Status\nShared,rented\n", model: Equipment,
                                mapping: { "Name" => "name", "Status" => "status" }, actor: @mgr, match_key: "name")
      assert_equal 1, result.created
      assert_equal 0, result.updated
      assert_equal 1, Equipment.where(name: "Shared").count, "one Warsaw row"
    end
  end

  test "import advances a ProgressJob per row" do
    with_tenant(@warsaw, actor: @mgr) do
      progress = Loam::Progress.start(name: "Import", total: 2)
      Loam::Import.run("Name,Status\nA,available\nB,available\n", model: Equipment,
                       mapping: { "Name" => "name", "Status" => "status" }, actor: @mgr, progress: progress)
      assert_equal 2, progress.reload.completed
    end
  end

  test "malformed CSV is a clean error, not a crash" do
    with_tenant(@warsaw, actor: @mgr) do
      assert_raises(Loam::Error) do
        Loam::Import.run("a,b\n\"unterminated", model: Equipment, mapping: { "a" => "name" }, actor: @mgr)
      end
    end
  end

  # --- export ---

  test "export is encryption-aware: an encrypted field is redacted, its blind index omitted" do
    with_tenant(@warsaw, actor: @emp) do
      Customer.create!(name: "Acme", email: "orders@acme.test", tax_id: "PL5260001")

      csv = Loam::Export.csv(Customer.where(name: "Acme"), actor: @emp)

      refute_match "PL5260001", csv, "encrypted tax_id is never exported in the clear"
      refute_match "orders@acme.test", csv, "encrypted email is never exported in the clear"
      refute_match "email_hash", csv, "the blind-index column is not exported"
      assert_match "[encrypted]", csv, "encrypted columns are redacted"
      assert_match "Acme", csv, "non-encrypted columns export normally"
    end
  end

  test "export is tenant-scoped and matches the given relation" do
    with_tenant(@warsaw, actor: @mgr) { Equipment.create!(name: "WarsawRig", daily_rate: 5, status: "available") }
    with_tenant(@krakow, actor: @mgr) { Equipment.create!(name: "KrakowRig", daily_rate: 5, status: "available") }

    csv = with_tenant(@warsaw, actor: @mgr) { Loam::Export.csv(Equipment.all, actor: @mgr) }
    assert_match "WarsawRig", csv
    refute_match "KrakowRig", csv
  end

  test "Policy#readable? gates export columns by role" do
    with_tenant(@warsaw, actor: @emp) do
      policy = EquipmentPolicy.new(@emp, Equipment.new)
      assert policy.readable?(:name), "no rule means any member may read"
    end
  end
end
