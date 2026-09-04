require "test_helper"

# OpenLoam::AuthThrottle: rate-limit + lockout on failed auth. No sleeps — travel_to
# drives the window.
class OpenLoamAuthThrottleTest < ActiveSupport::TestCase
  setup { OpenLoam::AuthAttempt.delete_all }

  test "an identifier locks after max failures within the window" do
    OpenLoam::AuthThrottle.max_attempts.times { OpenLoam::AuthThrottle.record_failure("alice@x.test", kind: "password") }
    assert OpenLoam::AuthThrottle.locked?("alice@x.test")
    refute OpenLoam::AuthThrottle.locked?("bob@x.test"), "per-identifier — bob is unaffected"
  end

  test "a success clears the counter" do
    3.times { OpenLoam::AuthThrottle.record_failure("alice@x.test", kind: "password") }
    OpenLoam::AuthThrottle.clear("alice@x.test")
    assert_equal 0, OpenLoam::AuthThrottle.recent_failures("alice@x.test")
    refute OpenLoam::AuthThrottle.locked?("alice@x.test")
  end

  test "the window expires — failures age out and the lock lifts" do
    OpenLoam::AuthThrottle.max_attempts.times { OpenLoam::AuthThrottle.record_failure("alice@x.test", kind: "password") }
    assert OpenLoam::AuthThrottle.locked?("alice@x.test")

    travel_to((OpenLoam::AuthThrottle.window + 1.minute).from_now) do
      refute OpenLoam::AuthThrottle.locked?("alice@x.test"), "past the window, the lock is gone"
    end
  end

  test "the identifier is normalized (case/whitespace insensitive)" do
    OpenLoam::AuthThrottle.max_attempts.times { OpenLoam::AuthThrottle.record_failure("  Alice@X.test ", kind: "password") }
    assert OpenLoam::AuthThrottle.locked?("alice@x.test")
  end

  test "remaining_lockout reports seconds until unlock" do
    OpenLoam::AuthThrottle.record_failure("alice@x.test", kind: "password")
    assert_operator OpenLoam::AuthThrottle.remaining_lockout("alice@x.test"), :>, 0
    assert_equal 0, OpenLoam::AuthThrottle.remaining_lockout("nobody@x.test")
  end
end

# Through the controllers — password lockout, TOTP lockout, and enumeration safety.
class AuthThrottleFlowTest < ActionDispatch::IntegrationTest
  setup do
    OpenLoam::AuthAttempt.delete_all
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-throttle")
    @user = User.create!(name: "Anna", email: "anna@example.test", password: "password123")
    with_tenant(@tenant) { OpenLoam::Membership.create!(user: @user, role: "manager") }
  end

  def lock(email)
    OpenLoam::AuthThrottle.max_attempts.times { OpenLoam::AuthThrottle.record_failure(email, kind: "password") }
  end

  test "a locked identifier is refused even with the RIGHT password" do
    lock("anna@example.test")

    post admin_session_path, params: { email: "anna@example.test", password: "password123" }

    assert_response :too_many_requests
    assert_match(/too many attempts/i, response.body)
    assert_nil session[:user_id], "no session despite the correct password"
  end

  test "a failed login records an attempt; a success clears the counter" do
    post admin_session_path, params: { email: "anna@example.test", password: "wrong" }
    assert_response :unauthorized
    assert_equal 1, OpenLoam::AuthAttempt.where(identifier: "anna@example.test").count

    post admin_session_path, params: { email: "anna@example.test", password: "password123" }
    assert_response :redirect
    assert_equal 0, OpenLoam::AuthAttempt.where(identifier: "anna@example.test").count, "success cleared the counter"
  end

  test "ENUMERATION safety: a locked known and a locked unknown identifier respond identically" do
    lock("anna@example.test")     # exists
    lock("ghost@example.test")    # does not exist

    # Strip the echoed submitted email (the attacker's OWN input, not an oracle)
    # before comparing — everything else must be identical.
    scrub = ->(body) { body.gsub(/value="[^"]*@example\.test"/, 'value="X"') }

    post admin_session_path, params: { email: "anna@example.test", password: "password123" }
    known_status, known_body = response.status, scrub.call(response.body)

    post admin_session_path, params: { email: "ghost@example.test", password: "whatever" }
    unknown_status, unknown_body = response.status, scrub.call(response.body)

    assert_equal 429, known_status
    assert_equal known_status, unknown_status, "same status — no existence oracle"
    assert_equal known_body, unknown_body, "same page — a lockout can't reveal which emails exist"
    assert_match(/too many attempts/i, known_body)
  end

  test "TOTP is throttled: after max wrong codes the right code is refused until unlock" do
    secret = OpenLoam::Totp.generate_secret
    travel_to(61.seconds.ago) { OpenLoam::MfaCredential.new(user: @user).activate_with!(secret, OpenLoam::Totp.code_at(secret, Time.now.to_i / 30)) }

    # Password step (clean), lands on the MFA challenge.
    post admin_session_path, params: { email: "anna@example.test", password: "password123" }
    assert_redirected_to mfa_challenge_admin_session_path

    OpenLoam::AuthThrottle.max_attempts.times { post mfa_verify_admin_session_path, params: { code: "000000" } }

    # Even the correct code is now refused.
    post mfa_verify_admin_session_path, params: { code: OpenLoam::Totp.code_at(secret, Time.now.to_i / 30) }
    assert_response :too_many_requests
    assert_nil session[:tenant_id], "still not signed in"
  end
end
