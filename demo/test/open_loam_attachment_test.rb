require "test_helper"

# Attachments: ActiveStorage files hanging off a tenant-scoped record.
#
# Read OpenLoam::Attachable before extending this: blobs themselves live in global
# ActiveStorage tables that OpenLoam does not scope. What is scoped is the record —
# so reaching a file means first reaching the record that owns it, which is
# where the policy applies.
class OpenLoamAttachmentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-files")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-files")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")

    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
    end
  end

  test "a file can be attached to a record and read back" do
    with_tenant(@warsaw, actor: @anna) do
      @excavator.files.attach(io: StringIO.new("service manual"), filename: "manual.txt", content_type: "text/plain")

      assert @excavator.files.attached?
      assert_equal [ "manual.txt" ], @excavator.files.map { |file| file.filename.to_s }
      assert_equal "service manual", @excavator.files.first.download
    end
  end

  test "several files can hang off one record, and one can be removed" do
    with_tenant(@warsaw, actor: @anna) do
      @excavator.files.attach(io: StringIO.new("one"), filename: "a.txt", content_type: "text/plain")
      @excavator.files.attach(io: StringIO.new("two"), filename: "b.txt", content_type: "text/plain")
      assert_equal 2, @excavator.files.count

      @excavator.files.first.purge

      assert_equal [ "b.txt" ], @excavator.reload.files.map { |file| file.filename.to_s }
    end
  end

  test "files are reached through the record, so another tenant cannot get to them" do
    with_tenant(@warsaw, actor: @anna) do
      @excavator.files.attach(io: StringIO.new("service manual"), filename: "manual.txt", content_type: "text/plain")
    end

    with_tenant(@krakow) do
      assert_equal 0, Equipment.count, "the owning record is not visible here, so neither are its files"
      assert_raises(ActiveRecord::RecordNotFound) { Equipment.find(@excavator.id) }
    end
  end

  test "attachments survive a reload and are listed per record" do
    other_id = with_tenant(@warsaw, actor: @anna) do
      @excavator.files.attach(io: StringIO.new("service manual"), filename: "manual.txt", content_type: "text/plain")
      Equipment.create!(name: "Mixer", daily_rate: 120, status: "available").id
    end

    with_tenant(@warsaw, actor: @anna) do
      assert_equal 1, Equipment.find(@excavator.id).files.count
      assert_equal 0, Equipment.find(other_id).files.count
    end
  end
end
