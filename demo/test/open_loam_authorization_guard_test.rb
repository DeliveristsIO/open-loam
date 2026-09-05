require "test_helper"

# The authorization-called guard (L-202). Forgetting `authorize!` in a
# controller is otherwise silent: the screen renders and nothing says the policy
# was never consulted. `verify_authorized!` turns that omission into a loud
# failure in development and in tests.
#
# It is NOT a runtime access-control layer — it runs after the action, so a
# `destroy` that forgot to authorize has already destroyed the record. Its job
# is to fail the build, not to stop the request.
class OpenLoamAuthorizationGuardTest < ActionDispatch::IntegrationTest
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-authguard")
    @tomek = User.create!(name: "Tomek", email: "tomek@authguard.test", password: "password123")
    with_tenant(@warsaw) { OpenLoam::Membership.create!(user: @tomek, role: "manager") }
    post admin_session_path, params: { email: "tomek@authguard.test", password: "password123" }
  end

  test "an action that never authorizes raises" do
    controller = Admin::EquipmentController.new
    controller.params = ActionController::Parameters.new(action: "index")

    error = assert_raises(OpenLoam::AuthorizationNotPerformedError) do
      controller.send(:verify_authorized!)
    end
    assert_match(/finished without authorizing/, error.message)
    assert_match(/skip_authorization!/, error.message, "the message must name the escape hatch")
  end

  test "the guard is not a NotAuthorizedError, so it is never rendered as a polite 403" do
    # A developer bug must not be dressed up as a refusal — nothing rescues this.
    assert_not OpenLoam::AuthorizationNotPerformedError.ancestors.include?(OpenLoam::NotAuthorizedError)
  end

  test "authorize! satisfies the guard whether the answer is yes or no" do
    controller = Admin::EquipmentController.new
    controller.send(:authorized!)

    assert_nothing_raised { controller.send(:verify_authorized!) }
  end

  test "require_role! and require_permission! also count as authorizing" do
    # Both gate a PERSON, so both answer the question the guard asks. #export is
    # gated by require_role!(:manager) and never calls authorize!.
    get export_admin_equipment_index_path

    assert_response :success
  end

  test "a screen authorized structurally passes via a declared skip" do
    get admin_notifications_path

    assert_response :success
  end

  test "skip_authorization! refuses an empty reason" do
    assert_raises(ArgumentError) { Admin::BaseController.skip_authorization!("") }
  end

  test "an unauthenticated request redirects without tripping the guard" do
    # A halted before_action chain must not run after_action callbacks — otherwise
    # every logged-out request would raise instead of redirecting to sign-in.
    reset!
    get admin_equipment_index_path

    assert_redirected_to new_admin_session_path
  end

  test "the index screens authorize read?, like show and deleted do" do
    get admin_equipment_index_path

    assert_response :success
  end

  test "the JSON index authorizes too" do
    token = with_tenant(@warsaw) { OpenLoam::ApiToken.create!(user_id: @tomek.id, label: "test").token }
    get "/api/equipment", headers: { "Authorization" => "Bearer #{token}" }

    assert_response :success
  end
end
