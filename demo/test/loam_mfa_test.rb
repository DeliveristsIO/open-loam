require "test_helper"

# Loam::MfaCredential + TOTP: the second factor and its per-user key. Security
# tests — the secret must be encrypted at rest, verifiable in any tenant (and at
# login, with none), and recovery codes must be single-use.
class LoamMfaTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-mfa")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-mfa")
    @user = User.create!(name: "Zoe", email: "zoe@example.test", password: "password")
  end

  test "TOTP verification accepts a live code and rejects wrong or malformed ones" do
    secret = Loam::Totp.generate_secret
    now = Time.now.to_i

    assert Loam::Totp.verify(secret, Loam::Totp.code_at(secret, now / 30), at: now)
    assert Loam::Totp.verify(secret, Loam::Totp.code_at(secret, now / 30 + 1), at: now), "±1 step drift is allowed"
    refute Loam::Totp.verify(secret, Loam::Totp.code_at(secret, now / 30 + 2), at: now), "±2 steps is not"
    refute Loam::Totp.verify(secret, "000000", at: now)
    refute Loam::Totp.verify(secret, "abc", at: now)
  end

  test "the TOTP secret is encrypted at rest" do
    credential = enroll(@user)
    secret = credential.totp_secret

    raw = Loam::MfaCredential.connection.select_value(
      "SELECT totp_secret FROM loam_mfa_credentials WHERE id = #{credential.id}"
    )
    assert raw.start_with?("v1:"), "stored as versioned ciphertext"
    refute_includes raw, secret, "the base32 secret must not appear in the column"
  end

  # THE critical property: MFA is per-user, so a secret enrolled while acting in
  # one tenant must verify while acting in another — and at login, with none.
  test "MFA enrolled in one tenant verifies in another tenant and with no tenant" do
    secret = with_tenant(@warsaw) { enroll(@user).totp_secret }
    code = Loam::Totp.code_at(secret, Time.now.to_i / 30)

    with_tenant(@krakow) do
      assert Loam::MfaCredential.active_for(@user).verify_totp(code), "verifies in a different tenant"
    end

    Loam::Current.reset
    assert Loam::MfaCredential.active_for(@user).verify_totp(code), "verifies with no tenant (login time)"
  end

  test "a credential is not active until a live code confirms enrollment" do
    credential = Loam::MfaCredential.new(user: @user).start_enrollment!
    assert_nil Loam::MfaCredential.active_for(@user), "pending enrollment does not gate login"

    refute credential.activate!("000000"), "a wrong code does not activate"
    assert_nil Loam::MfaCredential.active_for(@user)

    codes = credential.activate!(Loam::Totp.code_at(credential.totp_secret, Time.now.to_i / 30))
    assert_equal Loam::MfaCredential::RECOVERY_CODE_COUNT, codes.size
    assert Loam::MfaCredential.active_for(@user)
  end

  test "a recovery code works exactly once" do
    credential = enroll(@user)
    code = @recovery_codes.first

    assert credential.consume_recovery_code(code), "valid the first time"
    refute credential.reload.consume_recovery_code(code), "spent thereafter"
    refute credential.consume_recovery_code("not-a-real-code")
  end

  test "assigning a secret with no user raises rather than deriving a shared key" do
    assert_raises(Loam::Encryption::Error) { Loam::MfaCredential.new.totp_secret = "x" }
  end

  private

  # Enroll + activate, capturing the recovery codes for the test.
  def enroll(user)
    credential = Loam::MfaCredential.new(user: user).start_enrollment!
    @recovery_codes = credential.activate!(Loam::Totp.code_at(credential.totp_secret, Time.now.to_i / 30))
    credential
  end
end

# The login, enrollment, and step-up flows through the admin.
class AdminMfaFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-mfa-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    with_tenant(@tenant) { Loam::Membership.create!(user: @anna, role: "manager") }
  end

  test "with MFA active, login demands a TOTP code before granting access" do
    secret = enroll(@anna)

    post admin_session_path, params: { email: @anna.email, password: "password" }
    assert_redirected_to mfa_challenge_admin_session_path, "password alone does not log in"

    post mfa_verify_admin_session_path, params: { code: "000000" }
    assert_response :unauthorized

    get admin_root_path
    assert_redirected_to new_admin_session_path, "still not in without a valid code"

    post mfa_verify_admin_session_path, params: { code: Loam::Totp.code_at(secret, Time.now.to_i / 30) }
    assert_redirected_to admin_root_path
    get admin_root_path
    assert_response :success
  end

  test "a role on security.mfa_required_roles is forced to enroll" do
    Loam::Configs.set("security.mfa_required_roles", [ "manager" ], scope: :global)

    post admin_session_path, params: { email: @anna.email, password: "password" }
    assert_redirected_to new_admin_mfa_path, "a manager without MFA must enroll first"
  end

  test "a sudo-gated action re-challenges once the login is stale, then allows it" do
    post admin_session_path, params: { email: @anna.email, password: "password" }
    token = with_tenant(@tenant) { Loam::ApiToken.create!(user: @anna, label: "scanner") }

    # Fresh from login: no re-challenge.
    delete admin_api_token_path(token)
    assert_redirected_to admin_api_tokens_path

    travel 6.minutes do
      other = with_tenant(@tenant) { Loam::ApiToken.create!(user: @anna, label: "old") }

      delete admin_api_token_path(other)
      assert_redirected_to new_admin_sudo_path, "stale auth must re-challenge before a sensitive action"
      assert with_tenant(@tenant) { Loam::ApiToken.exists?(other.id) }, "and the token is untouched"

      post admin_sudo_path, params: { password: "password" }
      delete admin_api_token_path(other)
      assert_redirected_to admin_api_tokens_path
      refute with_tenant(@tenant) { Loam::ApiToken.exists?(other.id) }, "now the delete goes through"
    end
  end

  test "step-up for an MFA user needs a TOTP code, not just a password" do
    secret = enroll(@anna)

    post admin_session_path, params: { email: @anna.email, password: "password" }
    post mfa_verify_admin_session_path, params: { code: Loam::Totp.code_at(secret, Time.now.to_i / 30) }

    travel 6.minutes do
      token = with_tenant(@tenant) { Loam::ApiToken.create!(user: @anna, label: "old") }

      delete admin_api_token_path(token)
      assert_redirected_to new_admin_sudo_path

      # A password must NOT satisfy step-up for a user who has MFA — that would
      # silently downgrade the second factor.
      post admin_sudo_path, params: { password: "password" }
      assert_response :unauthorized
      assert with_tenant(@tenant) { Loam::ApiToken.exists?(token.id) }

      # A live code does.
      post admin_sudo_path, params: { code: Loam::Totp.code_at(secret, Time.now.to_i / 30) }
      delete admin_api_token_path(token)
      assert_redirected_to admin_api_tokens_path
      refute with_tenant(@tenant) { Loam::ApiToken.exists?(token.id) }
    end
  end

  private

  def enroll(user)
    credential = Loam::MfaCredential.new(user: user).start_enrollment!
    credential.activate!(Loam::Totp.code_at(credential.totp_secret, Time.now.to_i / 30))
    credential.totp_secret
  end
end
