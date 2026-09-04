require "test_helper"

# OpenLoam::SoftDeletable on a real entity: destroying hides a record instead of
# erasing it, restore brings it back, and the recycle bin stays tenant-scoped.
class OpenLoamSoftDeleteTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-softdelete")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-softdelete")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")

    with_tenant(@warsaw) { OpenLoam::Membership.create!(user: @anna, role: "manager") }
    with_tenant(@krakow) { OpenLoam::Membership.create!(user: @anna, role: "manager") }
  end

  test "soft_delete hides a record from the default scope but keeps the row" do
    with_tenant(@warsaw, actor: @anna) do
      excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")

      excavator.soft_delete

      assert excavator.deleted?
      assert_equal 0, Equipment.count, "a soft-deleted record is gone from ordinary queries"
      assert_equal 1, Equipment.with_deleted.count, "but the row still exists"
      assert_raises(ActiveRecord::RecordNotFound) { Equipment.find(excavator.id) }
    end
  end

  test "restore brings a soft-deleted record back into the default scope" do
    with_tenant(@warsaw, actor: @anna) do
      excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      excavator.soft_delete

      excavator.restore

      refute excavator.deleted?
      assert_equal 1, Equipment.count
      assert_equal excavator.id, Equipment.find(excavator.id).id
    end
  end

  test "only_deleted lists exactly the deleted records" do
    with_tenant(@warsaw, actor: @anna) do
      kept = Equipment.create!(name: "Crane", daily_rate: 1200, status: "available")
      gone = Equipment.create!(name: "Drill", daily_rate: 40, status: "available")
      gone.soft_delete

      assert_equal [ gone.id ], Equipment.only_deleted.pluck(:id)
      assert_equal [ kept.id ], Equipment.pluck(:id)
    end
  end

  # The invariant that matters most: with_deleted lifts the deleted_at filter
  # but NOT the tenant filter, so the recycle bin can never leak across tenants.
  test "with_deleted stays tenant-scoped — a deleted Warsaw record is invisible from Krakow" do
    warsaw_id = with_tenant(@warsaw, actor: @anna) do
      excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      excavator.soft_delete
      excavator.id
    end

    with_tenant(@krakow, actor: @anna) do
      assert_equal 0, Equipment.with_deleted.count,
        "with_deleted must keep the tenant scope, or it leaks another tenant's rows"
      assert_equal 0, Equipment.only_deleted.count
      assert_raises(ActiveRecord::RecordNotFound) { Equipment.with_deleted.find(warsaw_id) }
    end
  end

  test "a soft-delete is audited as its own action, with the deleted_at change" do
    with_tenant(@warsaw, actor: @anna) do
      excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      excavator.soft_delete

      audit = OpenLoam::AuditRecord.find_by(auditable_type: "Equipment", auditable_id: excavator.id, action: "soft_delete")
      assert audit, "a soft-delete must leave a soft_delete audit record, not an update"
      assert_equal @anna.id, audit.actor_id
      assert audit.changeset.key?("deleted_at")
      assert_equal 0, OpenLoam::AuditRecord.where(auditable_id: excavator.id, action: "update").count,
        "the soft-delete must NOT also be recorded as an ordinary update"
    end
  end

  test "restore is audited as its own action" do
    with_tenant(@warsaw, actor: @anna) do
      excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      excavator.soft_delete
      excavator.restore

      assert OpenLoam::AuditRecord.exists?(auditable_type: "Equipment", auditable_id: excavator.id, action: "restore")
    end
  end

  test "soft_delete and restore are idempotent — no duplicate audit on a repeat" do
    with_tenant(@warsaw, actor: @anna) do
      excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")

      excavator.soft_delete
      excavator.soft_delete

      assert_equal 1, OpenLoam::AuditRecord.where(auditable_id: excavator.id, action: "soft_delete").count,
        "re-deleting an already-deleted record must not write a second audit record"
    end
  end

  test "hard destroy still erases the row and is audited as a destroy" do
    with_tenant(@warsaw, actor: @anna) do
      excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")

      excavator.destroy!

      assert_equal 0, Equipment.with_deleted.count, "destroy really removes the row"
      assert OpenLoam::AuditRecord.exists?(auditable_type: "Equipment", auditable_id: excavator.id, action: "destroy")
    end
  end
end

# The admin recycle-bin flow end to end: the delete button soft-deletes, the
# deleted screen renders, and Restore brings the record back.
class AdminSoftDeleteFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-softdelete-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")

    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
    end

    post admin_session_path, params: { email: "anna@example.test", password: "password" }
  end

  test "the delete button soft-deletes, and Restore brings the record back" do
    delete polymorphic_path([:admin, @excavator])
    assert_response :redirect

    with_tenant(@tenant) do
      assert_equal 0, Equipment.count, "the admin delete must soft-delete, not leave the record listed"
      assert Equipment.with_deleted.find(@excavator.id).deleted?
    end

    get polymorphic_path([:deleted, :admin, Equipment])
    assert_response :success
    assert_match "Excavator", response.body, "the deleted record shows in the recycle bin"

    patch polymorphic_path([:restore, :admin, @excavator])
    assert_response :redirect

    with_tenant(@tenant) do
      assert_equal 1, Equipment.count, "Restore must return the record to the default scope"
      refute Equipment.find(@excavator.id).deleted?
    end
  end
end
