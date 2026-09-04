require "test_helper"

# L-501: the reference CRM slice (Company + Lead) exercises the SAME OpenLoam
# primitives as the rental domain — tenant isolation, a role-gated workflow, an
# event that becomes a notification, and field-level policy — proving OpenLoam is
# domain-agnostic. Built with the real `open_loam:entity` generator, then a workflow
# and a policy rule added.
class CrmPipelineTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Warsaw", slug: "warsaw-crm")
    @krakow = OpenLoam::Tenant.create!(name: "Krakow", slug: "krakow-crm")
    @manager = User.create!(name: "Mgr", email: "mgr-crm@example.test", password: "password")
    @rep = User.create!(name: "Rep", email: "rep-crm@example.test", password: "password")
    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @rep, role: "employee")
    end
  end

  test "a lead moves through the pipeline; closing it is manager-only" do
    with_tenant(@warsaw, actor: @rep) do
      company = Company.create!(name: "Acme", industry: "construction", tier: "gold")
      lead = Lead.create!(company: company, source: "referral", value: 25_000, state: "new")

      lead.qualify!  # any member may advance
      assert_equal "qualified", lead.reload.state

      # An employee may not CLOSE the deal.
      assert_raises(OpenLoam::NotAuthorizedError) { lead.win! }
      assert_equal "qualified", lead.reload.state
    end
  end

  test "a manager winning a lead notifies the branch's managers" do
    lead_id = with_tenant(@warsaw, actor: @rep) do
      Lead.create!(source: "web", value: 5_000, state: "new").tap(&:qualify!).id
    end

    with_tenant(@warsaw, actor: @manager) do
      Lead.find(lead_id).win!
      assert_equal "won", Lead.find(lead_id).reload.state
      assert OpenLoam::Notification.where(user_id: @manager.id).where("title LIKE ?", "Lead%won").exists?,
             "the manager got a 'Lead won' notification"
    end
  end

  test "the deal value is writable only by a manager (field-level policy)" do
    with_tenant(@warsaw) do
      lead = Lead.create!(source: "web", value: 1000, state: "new")
      assert LeadPolicy.new(@manager, lead).writable?(:value)
      refute LeadPolicy.new(@rep, lead).writable?(:value)
    end
  end

  test "leads are tenant-isolated like everything else" do
    with_tenant(@warsaw, actor: @manager) { Lead.create!(source: "a", value: 1, state: "new") }
    with_tenant(@krakow) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      assert_equal 0, Lead.count, "a Warsaw lead is invisible in Krakow"
    end
  end
end
