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
    assert raw.start_with?("v2:"), "stored as v2 (AAD-bound) versioned ciphertext"
    refute_includes raw, secret, "the base32 secret must not appear in the column"
  end

  # THE critical property: MFA is per-user, so a secret enrolled while acting in
  # one tenant must verify while acting in another — and at login, with none.
  test "MFA enrolled in one tenant verifies in another tenant and with no tenant" do
    secret = with_tenant(@warsaw) { enroll(@user).totp_secret }

    with_tenant(@krakow) do
      code = Loam::Totp.code_at(secret, Time.now.to_i / 30)
      assert Loam::MfaCredential.active_for(@user).verify_totp(code), "verifies in a different tenant"
    end

    # Replay protection consumed that step, so use the next window's code — the
    # property under test (verifies with no tenant, at login time) is unchanged.
    travel 30.seconds do
      Loam::Current.reset
      code = Loam::Totp.code_at(secret, Time.now.to_i / 30)
      assert Loam::MfaCredential.active_for(@user).verify_totp(code), "verifies with no tenant (login time)"
    end
  end

  test "a credential is not active until a live code confirms enrollment" do
    secret = Loam::Totp.generate_secret
    credential = Loam::MfaCredential.new(user: @user)
    assert_nil Loam::MfaCredential.active_for(@user), "an unsaved/pending enrollment does not gate login"

    refute credential.activate_with!(secret, "000000"), "a wrong code does not activate"
    assert_nil Loam::MfaCredential.active_for(@user)

    codes = credential.activate_with!(secret, Loam::Totp.code_at(secret, Time.now.to_i / 30))
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

  # Regression (recovery-code race): a stale in-memory copy cannot re-consume a
  # code already spent, because with_lock reloads and re-checks under the lock.
  test "a recovery code cannot be consumed twice, even from a stale instance" do
    credential = enroll(@user)
    code = @recovery_codes.first
    stale = Loam::MfaCredential.find(credential.id) # loaded BEFORE the first consume

    assert credential.consume_recovery_code(code), "valid the first time"
    refute stale.consume_recovery_code(code), "the stale copy must re-check under the lock and refuse"
  end

  # Regression (TOTP replay): a captured code cannot be reused within its window;
  # the next step's code still works.
  test "a TOTP code cannot be replayed within its validity window" do
    credential = enroll(@user)
    code = Loam::Totp.code_at(credential.totp_secret, Time.now.to_i / 30)

    assert credential.verify_totp(code), "accepted once"
    refute credential.reload.verify_totp(code), "the same code is a replay and is rejected"

    travel 30.seconds do
      next_code = Loam::Totp.code_at(credential.totp_secret, Time.now.to_i / 30)
      assert credential.reload.verify_totp(next_code), "a later step's code is not over-rejected"
    end
  end

  private

  # Enroll + activate, capturing the recovery codes. Enrollment happens ~2 steps
  # in the past so codes computed at the real "now" are fresh (not replay-rejected
  # against the step recorded at activation).
  def enroll(user)
    secret = Loam::Totp.generate_secret
    credential = Loam::MfaCredential.new(user: user)
    travel_to(61.seconds.ago) do
      @recovery_codes = credential.activate_with!(secret, Loam::Totp.code_at(secret, Time.now.to_i / 30))
    end
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

  # Regression (HIGH — MFA re-enrollment downgrade): a GET to the enroll page
  # (reachable cross-site) must NOT mutate an active credential. Before the fix,
  # GET /admin/mfa/new called start_enrollment! and wiped the active secret,
  # silently downgrading the next login to password-only.
  test "a GET to the enroll page cannot disable active MFA" do
    secret = enroll(@anna)
    raw_before = raw_secret_of(@anna)

    log_in_with_mfa(secret)

    get new_admin_mfa_path
    assert_response :success

    assert_equal raw_before, raw_secret_of(@anna), "the active secret's ciphertext must be byte-identical after a GET"
    assert Loam::MfaCredential.active_for(@anna), "MFA is still active — not downgraded to password-only"
  end

  test "replacing an active credential needs step-up and leaves it untouched until confirmed" do
    secret = enroll(@anna)
    log_in_with_mfa(secret)
    raw_before = raw_secret_of(@anna)

    travel 6.minutes do # sudo has gone stale
      post admin_mfa_path, params: { code: "000000" } # attempt to activate a new secret
      assert_redirected_to new_admin_sudo_path, "replacing active MFA is step-up gated"
      assert_equal raw_before, raw_secret_of(@anna), "the old secret is untouched"
      assert Loam::MfaCredential.active_for(@anna)
    end
  end

  # Regression (sudo burns a recovery code): step-up takes a TOTP code, never a
  # single-use recovery code — those are for login only and must not be spent.
  test "step-up does not accept or consume a recovery code" do
    secret = Loam::Totp.generate_secret
    recovery_code = nil
    travel_to(61.seconds.ago) do
      recovery_code = Loam::MfaCredential.new(user: @anna).activate_with!(secret, Loam::Totp.code_at(secret, Time.now.to_i / 30)).first
    end
    log_in_with_mfa(secret)

    travel 6.minutes do
      token = with_tenant(@tenant) { Loam::ApiToken.create!(user: @anna, label: "x") }
      delete admin_api_token_path(token)
      assert_redirected_to new_admin_sudo_path

      post admin_sudo_path, params: { code: recovery_code }
      assert_response :unauthorized, "a recovery code must not satisfy step-up"
      assert_equal Loam::MfaCredential::RECOVERY_CODE_COUNT,
                   Loam::MfaCredential.active_for(@anna).unused_recovery_code_count, "and it must not be burned"
      assert Loam::MfaCredential.active_for(@anna).consume_recovery_code(recovery_code), "it still works at login"
    end
  end

  private

  def raw_secret_of(user)
    Loam::MfaCredential.connection.select_value("SELECT totp_secret FROM loam_mfa_credentials WHERE user_id = #{user.id}")
  end

  def log_in_with_mfa(secret)
    post admin_session_path, params: { email: @anna.email, password: "password" }
    post mfa_verify_admin_session_path, params: { code: Loam::Totp.code_at(secret, Time.now.to_i / 30) }
  end

  # Enroll ~2 steps in the past so a code computed at the real "now" (during the
  # login/sudo requests) is fresh, not a replay of the activation step.
  def enroll(user)
    secret = Loam::Totp.generate_secret
    travel_to(61.seconds.ago) do
      Loam::MfaCredential.new(user: user).activate_with!(secret, Loam::Totp.code_at(secret, Time.now.to_i / 30))
    end
    secret
  end
end
