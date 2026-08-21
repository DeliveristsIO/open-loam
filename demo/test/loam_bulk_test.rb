require "test_helper"

# Loam::Bulk: datatable bulk actions — policy-checked per record, tenant-scoped.
class LoamBulkTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-bulk")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-bulk")
    @mgr = User.create!(name: "M", email: "m@example.test", password: "password")
    [ @warsaw, @krakow ].each { |t| with_tenant(t) { Loam::Membership.create!(user: @mgr, role: "manager") } }
  end

  test "bulk soft-delete removes only the selected records" do
    with_tenant(@warsaw, actor: @mgr) do
      a = Equipment.create!(name: "A", daily_rate: 1, status: "available")
      b = Equipment.create!(name: "B", daily_rate: 1, status: "available")
      keep = Equipment.create!(name: "Keep", daily_rate: 1, status: "available")

      count = Loam::Bulk.soft_delete(Equipment, [ a.id, b.id ])

      assert_equal 2, count
      assert_equal [ keep.id ], Equipment.pluck(:id), "only the unselected survives"
      assert_equal 2, Equipment.only_deleted.count
    end
  end

  test "bulk set-field updates the selected, respecting the permit list" do
    with_tenant(@warsaw, actor: @mgr) do
      a = Equipment.create!(name: "A", daily_rate: 1, status: "available")
      b = Equipment.create!(name: "B", daily_rate: 1, status: "available")

      count = Loam::Bulk.set_field(Equipment, [ a.id, b.id ], field: "status", value: "retired")
      assert_equal 2, count
      assert_equal %w[retired retired], Equipment.where(id: [ a.id, b.id ]).pluck(:status)

      # A plumbing/non-column field is refused (no write, zero affected).
      assert_equal 0, Loam::Bulk.set_field(Equipment, [ a.id ], field: "tenant_id", value: 999)
      assert_equal @warsaw.id, a.reload.tenant_id
    end
  end

  test "a forged cross-tenant id is never touched (resolved through the tenant scope)" do
    krakow_rig = with_tenant(@krakow, actor: @mgr) { Equipment.create!(name: "KrakowRig", daily_rate: 1, status: "available") }

    with_tenant(@warsaw, actor: @mgr) do
      count = Loam::Bulk.soft_delete(Equipment, [ krakow_rig.id ])
      assert_equal 0, count, "a Krakow id is simply not in the Warsaw scope"
    end
    assert_equal false, with_tenant(@krakow, actor: @mgr) { krakow_rig.reload.deleted? }, "the Krakow record is untouched"
  end

  test "bulk export-selected produces a CSV of only the selected, tenant-scoped rows" do
    with_tenant(@warsaw, actor: @mgr) do
      a = Equipment.create!(name: "Alpha", daily_rate: 1, status: "available")
      Equipment.create!(name: "Beta", daily_rate: 1, status: "available")

      csv = Loam::Export.csv(Loam::Bulk.selected(Equipment, [ a.id ]), actor: @mgr)
      assert_match "Alpha", csv
      refute_match "Beta", csv
    end
  end
end

# The datatable bulk bar + export/import links through the Equipment controller.
class AdminEquipmentBulkTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-eq-bulk")
    @mgr = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    with_tenant(@tenant) { Loam::Membership.create!(user: @mgr, role: "manager") }
    post admin_session_path, params: { email: "anna@example.test", password: "password" }
  end

  test "the manager index shows the export/import links and the bulk bar" do
    with_tenant(@tenant) { Equipment.create!(name: "Rig", daily_rate: 1, status: "available") }
    get admin_equipment_index_path

    assert_response :success
    assert_select "a", text: "Export CSV"
    assert_select "a", text: "Import CSV"
    assert_select "input.bulk-select"
  end

  test "export returns a CSV attachment" do
    with_tenant(@tenant) { Equipment.create!(name: "Rig", daily_rate: 1, status: "available") }
    get export_admin_equipment_index_path

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "Rig", response.body
  end

  test "the bulk endpoint soft-deletes the selected rows" do
    rig = with_tenant(@tenant) { Equipment.create!(name: "Rig", daily_rate: 1, status: "available") }

    post bulk_admin_equipment_index_path, params: { bulk_action: "soft_delete", ids: [ rig.id ] }

    assert_redirected_to admin_equipment_index_path
    assert with_tenant(@tenant) { rig.reload.deleted? }
  end

  test "an import runs in the background as a job" do
    file = Rack::Test::UploadedFile.new(StringIO.new("Name,Status\nImported,available\n"), "text/csv", original_filename: "e.csv")

    # Preview parses and shows the mapping.
    post preview_admin_imports_path, params: { entity_type: "Equipment", file: file }
    assert_response :success
    assert_select "select"

    # Running enqueues the background ImportJob.
    assert_enqueued_with(job: ImportJob) do
      post admin_imports_path, params: { entity_type: "Equipment", csv: "Name,Status\nImported,available\n",
                                         mapping: { "Name" => "name", "Status" => "status" }, commit: "Import" }
    end
  end
end
