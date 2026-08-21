require "test_helper"

# The business-rules admin screen (Admin::BusinessRulesController): manager-only
# CRUD where the condition and actions are edited as JSON. Covers the bespoke
# bits the model/engine tests don't touch — the role gate, the JSON-parse error
# path, and that the index (including the recent-runs table) actually renders.
class AdminBusinessRulesTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-rules-admin")
    @manager = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @employee = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  def sign_in(email)
    post admin_session_path, params: { email: email, password: "password" }
  end

  test "a manager sees the rules list and the recent-runs table" do
    with_tenant(@tenant) do
      rule = Loam::BusinessRule.create!(name: "Flag urgent", trigger: "rental.damage_report.submit",
                                        condition: {}, actions: [ { "type" => "notify", "role" => "manager", "title" => "x" } ])
      # A run row so the runs table (run.business_rule.name, actions_taken) renders.
      Loam::BusinessRuleRun.create!(business_rule: rule, event_name: "rental.damage_report.submit",
                                    matched: true, actions_taken: [ "notify" ])
    end
    sign_in("anna@example.test")

    get admin_business_rules_path

    assert_response :success
    assert_match "Flag urgent", response.body
    assert_match "Recent runs", response.body
    assert_match "notify", response.body
  end

  test "an employee may not manage rules" do
    sign_in("tomek@example.test")

    get admin_business_rules_path

    assert_response :forbidden
  end

  test "a manager creates a rule with JSON condition and actions" do
    sign_in("anna@example.test")

    assert_difference -> { with_tenant(@tenant) { Loam::BusinessRule.count } }, 1 do
      post admin_business_rules_path, params: { business_rule: {
        name: "Pricey", trigger: "rental.equipment.pinged", entity_type: "Equipment", priority: 5, active: "1",
        condition: '{"field":"daily_rate","op":"gt","value":500}',
        actions: '[{"type":"notify","role":"manager","title":"Pricey"}]'
      } }
    end

    assert_redirected_to admin_business_rules_path
    rule = with_tenant(@tenant) { Loam::BusinessRule.find_by(name: "Pricey") }
    assert_equal "gt", rule.condition["op"]
    assert_equal "notify", rule.actions.first["type"]
  end

  test "the edit form renders and an update persists" do
    rule = with_tenant(@tenant) do
      Loam::BusinessRule.create!(name: "Old", trigger: "rental.equipment.pinged", condition: {}, actions: [])
    end
    sign_in("anna@example.test")

    get edit_admin_business_rule_path(rule)
    assert_response :success

    patch admin_business_rule_path(rule), params: { business_rule: {
      name: "Renamed", trigger: rule.trigger, condition: "{}", actions: "[]"
    } }
    assert_redirected_to admin_business_rules_path
    assert_equal "Renamed", with_tenant(@tenant) { Loam::BusinessRule.find(rule.id).name }
  end

  test "malformed JSON re-renders the form as 422, never a 500" do
    sign_in("anna@example.test")

    assert_no_difference -> { with_tenant(@tenant) { Loam::BusinessRule.count } } do
      post admin_business_rules_path, params: { business_rule: {
        name: "Broken", trigger: "rental.equipment.pinged",
        condition: "{ not valid json",
        actions: "[]"
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/must be valid JSON/, response.body)
  end
end
