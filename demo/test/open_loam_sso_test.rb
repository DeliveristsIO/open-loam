require "test_helper"

# SSO (Loam::Sso): OIDC sign-in with home-realm discovery, JIT provisioning, and
# account linking. Everything runs through the injected FakeProvider (the demo
# default), so NO test touches the network — Loam::Sso::OidcProvider is never
# constructed here.
class LoamSsoProvisioningTest < ActiveSupport::TestCase
  setup do
    Loam::Sso::FakeProvider.reset!
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sso")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-sso")

    @provider = with_tenant(@warsaw) do
      Loam::SsoProvider.create!(name: "Warsaw IdP", protocol: "oidc", issuer: "https://idp.warsaw.example",
                                client_id: "cid", client_secret: "s3cr3t", domain: "warsaw-corp.example",
                                jit_role: "employee", group_role_map: { "managers" => "manager" })
    end
  end

  teardown { Loam::Sso::FakeProvider.reset! }

  test "home-realm discovery resolves the provider by email domain, cross-tenant" do
    found = Loam::Sso.provider_for(email: "Alice@Warsaw-Corp.Example")
    assert_equal @provider.id, found.id
    assert_equal @warsaw.id, found.tenant_id
    assert_nil Loam::Sso.provider_for(email: "bob@unknown.example"), "no provider for an unknown domain"
    assert_nil Loam::Sso.provider_for(email: "no-domain")
  end

  test "the client secret is encrypted at rest, not stored as plaintext" do
    raw = Loam::SsoProvider.connection.select_value(
      "SELECT client_secret FROM loam_sso_providers WHERE id = #{@provider.id}"
    )
    refute_includes raw.to_s, "s3cr3t", "the raw column must be ciphertext"
    assert_equal "s3cr3t", with_tenant(@warsaw) { Loam::SsoProvider.find(@provider.id).client_secret }, "and decrypts in its tenant"
  end

  test "the audit trail never records the client secret in the clear" do
    with_tenant(@warsaw) do
      @provider.update!(client_secret: "rotated-secret")
      audits = Loam::AuditRecord.where(auditable_type: "Loam::SsoProvider", auditable_id: @provider.id)

      refute_includes audits.map { |a| a.changeset.to_json }.join, "rotated-secret", "the secret must never reach the audit trail"
      changed = audits.last.changeset
      assert_equal "[encrypted]", changed["client_secret"] if changed.key?("client_secret")
    end
  end

  test "a verified claim JIT-creates a user with a membership at the mapped role" do
    with_tenant(@warsaw) do
      claims = Loam::Sso::Claims.new(sub: "idp|1", email: "nowak@warsaw-corp.example", email_verified: true, name: "Nowak", groups: [ "managers" ])
      user = Loam::Sso.provision(@provider, claims)

      assert_equal "nowak@warsaw-corp.example", user.email
      assert_equal "manager", Loam::Membership.find_by(user_id: user.id).role, "the IdP group mapped to a role"
      assert Loam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "idp|1")
    end
  end

  test "JIT falls back to the provider's default role when no group matches" do
    with_tenant(@warsaw) do
      claims = Loam::Sso::Claims.new(sub: "idp|2", email: "kowalski@warsaw-corp.example", email_verified: true, name: "K", groups: [ "randoms" ])
      user = Loam::Sso.provision(@provider, claims)
      assert_equal "employee", Loam::Membership.find_by(user_id: user.id).role
    end
  end

  test "a verified claim links to an existing user by email (no duplicate)" do
    existing = User.create!(name: "Existing", email: "existing@warsaw-corp.example", password: "password")
    with_tenant(@warsaw) do
      claims = Loam::Sso::Claims.new(sub: "idp|3", email: "existing@warsaw-corp.example", email_verified: true, name: "Existing", groups: [])
      user = Loam::Sso.provision(@provider, claims)

      assert_equal existing.id, user.id, "linked, not duplicated"
      assert Loam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "idp|3")
    end
  end

  test "resolution is by sub first, so it survives an email change at the IdP" do
    with_tenant(@warsaw) do
      first = Loam::Sso.provision(@provider, Loam::Sso::Claims.new(sub: "idp|4", email: "old@warsaw-corp.example", email_verified: true, name: "N", groups: []))
      again = Loam::Sso.provision(@provider, Loam::Sso::Claims.new(sub: "idp|4", email: "new@warsaw-corp.example", email_verified: true, name: "N", groups: []))
      assert_equal first.id, again.id, "same sub -> same user, even with a new email"
      assert_equal 1, Loam::SsoIdentity.where(sso_provider_id: @provider.id, sub: "idp|4").count
    end
  end

  test "a verified claim on a domain the provider does NOT own is refused (cross-domain takeover)" do
    victim = User.create!(name: "Victim", email: "victim@other.example", password: "password")
    with_tenant(@warsaw) do
      # The provider owns warsaw-corp.example; a claim for another domain must not link.
      claims = Loam::Sso::Claims.new(sub: "attacker", email: "victim@other.example", email_verified: true, name: "V", groups: [])

      assert_raises(Loam::Sso::DomainMismatchError) { Loam::Sso.provision(@provider, claims) }
      refute Loam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "attacker"), "nothing was linked"
    end
    assert_equal 1, User.where(email: "victim@other.example").count, "the victim account is untouched, no duplicate"
    assert victim.reload.authenticate("password"), "the victim's credential is unchanged"
  end

  test "SSO re-maps the role on every login, so an IdP role change takes effect" do
    with_tenant(@warsaw) do
      Loam::Sso.provision(@provider, Loam::Sso::Claims.new(sub: "idp|r", email: "r@warsaw-corp.example", email_verified: true, name: "R", groups: [ "managers" ]))
      user = User.find_by(email: "r@warsaw-corp.example")
      assert_equal "manager", Loam::Membership.find_by(user_id: user.id).role, "first login: the group mapped to manager"

      # The IdP later drops them from the managers group.
      Loam::Sso.provision(@provider, Loam::Sso::Claims.new(sub: "idp|r", email: "r@warsaw-corp.example", email_verified: true, name: "R", groups: []))
      assert_equal "employee", Loam::Membership.find_by(user_id: user.id).role, "next login downgrades to the default role"
    end
  end

  test "an UNVERIFIED email is refused — no link, no takeover, no account" do
    User.create!(name: "Victim", email: "victim@warsaw-corp.example", password: "password")
    with_tenant(@warsaw) do
      claims = Loam::Sso::Claims.new(sub: "attacker", email: "victim@warsaw-corp.example", email_verified: false, name: "A", groups: [])

      assert_raises(Loam::Sso::UnverifiedEmailError) { Loam::Sso.provision(@provider, claims) }
      refute Loam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "attacker"), "no identity was linked"
    end
  end

  test "domain uniqueness is enforced across tenants (HRD must be unambiguous)" do
    conflict = with_tenant(@krakow) do
      Loam::SsoProvider.new(name: "Krakow IdP", protocol: "oidc", client_id: "c", domain: "warsaw-corp.example", jit_role: "employee")
    end
    refute conflict.valid?, "the same domain cannot own two providers"
    assert conflict.errors[:domain].any?
  end
end

# The end-to-end web flow through the SessionsController, driven by the offline
# FakeProvider: sign-in email -> HRD redirect -> callback -> session.
class LoamSsoFlowTest < ActionDispatch::IntegrationTest
  setup do
    Loam::Sso::FakeProvider.reset!
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sso-flow")
    with_tenant(@warsaw) do
      Loam::SsoProvider.create!(name: "Warsaw IdP", protocol: "oidc", issuer: "https://idp.warsaw.example",
                                client_id: "cid", client_secret: "s3cr3t", domain: "warsaw-corp.example", jit_role: "employee")
    end
  end

  teardown { Loam::Sso::FakeProvider.reset! }

  def sign_in_via_sso(email)
    post sso_start_admin_session_path, params: { email: email }
    assert_response :redirect
    follow_redirect!  # the FakeProvider authorization_url points back at our callback
  end

  test "SSO signs in and JIT-provisions a new user into the IdP's tenant" do
    sign_in_via_sso("nowak@warsaw-corp.example")

    assert_redirected_to admin_root_path
    user = User.find_by(email: "nowak@warsaw-corp.example")
    assert user, "the user was JIT-created"
    assert_equal user.id, session[:user_id]
    assert_equal @warsaw.id, session[:tenant_id], "landed in the IdP's tenant"
    assert_equal "employee", with_tenant(@warsaw) { Loam::Membership.find_by(user_id: user.id).role }
    assert_equal [ @warsaw.id ], Loam::Membership.tenants_for(user).pluck(:id), "membership only in the IdP's tenant, not elsewhere"
  end

  test "an SSO user who also runs app-side MFA must still pass the second factor" do
    existing = User.create!(name: "Existing", email: "existing@warsaw-corp.example", password: "password")
    secret = Loam::Totp.generate_secret
    travel_to(61.seconds.ago) do
      Loam::MfaCredential.new(user: existing).activate_with!(secret, Loam::Totp.code_at(secret, Time.now.to_i / 30))
    end

    sign_in_via_sso("existing@warsaw-corp.example")
    assert_redirected_to mfa_challenge_admin_session_path
    assert session[:mfa_pending], "SSO does not waive MFA"
    assert_nil session[:tenant_id], "not signed in until the second factor checks out"

    post mfa_verify_admin_session_path, params: { code: Loam::Totp.code_at(secret, Time.now.to_i / 30) }

    assert_redirected_to admin_root_path
    assert_equal existing.id, session[:user_id], "linked to the existing account"
    assert_equal @warsaw.id, session[:tenant_id], "the IdP-tenant preference survived the MFA step"
    assert_equal 1, User.where(email: "existing@warsaw-corp.example").count, "no duplicate user"
  end

  test "an unmatched email domain falls back to password login" do
    post sso_start_admin_session_path, params: { email: "someone@nowhere.example" }
    assert_redirected_to new_admin_session_path(email: "someone@nowhere.example")
    assert_nil session[:user_id]
  end

  test "an unverified email from the IdP is refused (no session)" do
    Loam::Sso::FakeProvider.force_email_verified = false
    User.create!(name: "Victim", email: "victim@warsaw-corp.example", password: "password")

    sign_in_via_sso("victim@warsaw-corp.example")

    assert_redirected_to new_admin_session_path
    assert_nil session[:user_id], "no session was established for an unverified email"
  end

  test "a callback with a bad state is rejected (CSRF)" do
    get sso_callback_admin_session_path, params: { code: "x", state: "forged" }

    assert_redirected_to new_admin_session_path
    assert_nil session[:user_id]
  end
end
