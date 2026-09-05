require "test_helper"

# SSO (OpenLoam::Sso): OIDC sign-in with home-realm discovery, JIT provisioning, and
# account linking. Everything runs through the injected FakeProvider (the demo
# default), so NO test touches the network — OpenLoam::Sso::OidcProvider is never
# constructed here.
class OpenLoamSsoProvisioningTest < ActiveSupport::TestCase
  setup do
    OpenLoam::Sso::FakeProvider.reset!
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sso")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-sso")

    @provider = with_tenant(@warsaw) do
      OpenLoam::SsoProvider.create!(name: "Warsaw IdP", protocol: "oidc", issuer: "https://idp.warsaw.example",
                                client_id: "cid", client_secret: "s3cr3t", domain: "warsaw-corp.example",
                                domain_verified_at: Time.current, jit_role: "employee", group_role_map: { "managers" => "manager" })
    end
  end

  teardown { OpenLoam::Sso::FakeProvider.reset! }

  test "home-realm discovery resolves the provider by email domain, cross-tenant" do
    found = OpenLoam::Sso.provider_for(email: "Alice@Warsaw-Corp.Example")
    assert_equal @provider.id, found.id
    assert_equal @warsaw.id, found.tenant_id
    assert_nil OpenLoam::Sso.provider_for(email: "bob@unknown.example"), "no provider for an unknown domain"
    assert_nil OpenLoam::Sso.provider_for(email: "no-domain")
  end

  test "the client secret is encrypted at rest, not stored as plaintext" do
    raw = OpenLoam::SsoProvider.connection.select_value(
      "SELECT client_secret FROM open_loam_sso_providers WHERE id = #{@provider.id}"
    )
    refute_includes raw.to_s, "s3cr3t", "the raw column must be ciphertext"
    assert_equal "s3cr3t", with_tenant(@warsaw) { OpenLoam::SsoProvider.find(@provider.id).client_secret }, "and decrypts in its tenant"
  end

  test "the audit trail never records the client secret in the clear" do
    with_tenant(@warsaw) do
      @provider.update!(client_secret: "rotated-secret")
      audits = OpenLoam::AuditRecord.where(auditable_type: "OpenLoam::SsoProvider", auditable_id: @provider.id)

      refute_includes audits.map { |a| a.changeset.to_json }.join, "rotated-secret", "the secret must never reach the audit trail"
      changed = audits.last.changeset
      assert_equal "[encrypted]", changed["client_secret"] if changed.key?("client_secret")
    end
  end

  test "a verified claim JIT-creates a user with a membership at the mapped role" do
    with_tenant(@warsaw) do
      claims = OpenLoam::Sso::Claims.new(sub: "idp|1", email: "nowak@warsaw-corp.example", email_verified: true, name: "Nowak", groups: [ "managers" ])
      user = OpenLoam::Sso.provision(@provider, claims)

      assert_equal "nowak@warsaw-corp.example", user.email
      assert_equal "manager", OpenLoam::Membership.find_by(user_id: user.id).role, "the IdP group mapped to a role"
      assert OpenLoam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "idp|1")
    end
  end

  test "JIT falls back to the provider's default role when no group matches" do
    with_tenant(@warsaw) do
      claims = OpenLoam::Sso::Claims.new(sub: "idp|2", email: "kowalski@warsaw-corp.example", email_verified: true, name: "K", groups: [ "randoms" ])
      user = OpenLoam::Sso.provision(@provider, claims)
      assert_equal "employee", OpenLoam::Membership.find_by(user_id: user.id).role
    end
  end

  test "a verified claim links to an existing user by email (no duplicate)" do
    existing = User.create!(name: "Existing", email: "existing@warsaw-corp.example", password: "password")
    with_tenant(@warsaw) do
      claims = OpenLoam::Sso::Claims.new(sub: "idp|3", email: "existing@warsaw-corp.example", email_verified: true, name: "Existing", groups: [])
      user = OpenLoam::Sso.provision(@provider, claims)

      assert_equal existing.id, user.id, "linked, not duplicated"
      assert OpenLoam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "idp|3")
    end
  end

  test "resolution is by sub first, so it survives an email change at the IdP" do
    with_tenant(@warsaw) do
      first = OpenLoam::Sso.provision(@provider, OpenLoam::Sso::Claims.new(sub: "idp|4", email: "old@warsaw-corp.example", email_verified: true, name: "N", groups: []))
      again = OpenLoam::Sso.provision(@provider, OpenLoam::Sso::Claims.new(sub: "idp|4", email: "new@warsaw-corp.example", email_verified: true, name: "N", groups: []))
      assert_equal first.id, again.id, "same sub -> same user, even with a new email"
      assert_equal 1, OpenLoam::SsoIdentity.where(sso_provider_id: @provider.id, sub: "idp|4").count
    end
  end

  test "a verified claim on a domain the provider does NOT own is refused (cross-domain takeover)" do
    victim = User.create!(name: "Victim", email: "victim@other.example", password: "password")
    with_tenant(@warsaw) do
      # The provider owns warsaw-corp.example; a claim for another domain must not link.
      claims = OpenLoam::Sso::Claims.new(sub: "attacker", email: "victim@other.example", email_verified: true, name: "V", groups: [])

      assert_raises(OpenLoam::Sso::DomainMismatchError) { OpenLoam::Sso.provision(@provider, claims) }
      refute OpenLoam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "attacker"), "nothing was linked"
    end
    assert_equal 1, User.where(email: "victim@other.example").count, "the victim account is untouched, no duplicate"
    assert victim.reload.authenticate("password"), "the victim's credential is unchanged"
  end

  test "SSO re-maps the role on every login, so an IdP role change takes effect" do
    with_tenant(@warsaw) do
      OpenLoam::Sso.provision(@provider, OpenLoam::Sso::Claims.new(sub: "idp|r", email: "r@warsaw-corp.example", email_verified: true, name: "R", groups: [ "managers" ]))
      user = User.find_by(email: "r@warsaw-corp.example")
      assert_equal "manager", OpenLoam::Membership.find_by(user_id: user.id).role, "first login: the group mapped to manager"

      # The IdP later drops them from the managers group.
      OpenLoam::Sso.provision(@provider, OpenLoam::Sso::Claims.new(sub: "idp|r", email: "r@warsaw-corp.example", email_verified: true, name: "R", groups: []))
      assert_equal "employee", OpenLoam::Membership.find_by(user_id: user.id).role, "next login downgrades to the default role"
    end
  end

  test "an UNVERIFIED email is refused — no link, no takeover, no account" do
    User.create!(name: "Victim", email: "victim@warsaw-corp.example", password: "password")
    with_tenant(@warsaw) do
      claims = OpenLoam::Sso::Claims.new(sub: "attacker", email: "victim@warsaw-corp.example", email_verified: false, name: "A", groups: [])

      assert_raises(OpenLoam::Sso::UnverifiedEmailError) { OpenLoam::Sso.provision(@provider, claims) }
      refute OpenLoam::SsoIdentity.exists?(sso_provider_id: @provider.id, sub: "attacker"), "no identity was linked"
    end
  end

  # `domain` is typed by a tenant manager and `User` is global, so before
  # verification existed any tenant could register a domain it did not own and
  # have SSO hand it the matching accounts.
  class UnverifiedDomainTest < ActiveSupport::TestCase
    setup do
      OpenLoam::Sso::FakeProvider.reset!
      @attacker = OpenLoam::Tenant.create!(name: "Attacker Ltd", slug: "attacker-sso")
      @squatter = with_tenant(@attacker) do
        OpenLoam::SsoProvider.create!(name: "Attacker IdP", protocol: "oidc", client_id: "c",
                                      domain: "victimcorp.example", jit_role: "manager")
      end
    end

    teardown { OpenLoam::Sso::FakeProvider.reset! }

    test "an unverified provider cannot adopt an existing account" do
      victim = User.create!(name: "CEO", email: "ceo@victimcorp.example", password: "password")
      home = OpenLoam::Tenant.create!(name: "Victim Corp", slug: "victim-sso")
      with_tenant(home) { OpenLoam::Membership.create!(user: victim, role: "manager") }

      with_tenant(@attacker) do
        claims = OpenLoam::Sso::Claims.new(sub: "attacker|1", email: "ceo@victimcorp.example",
                                           email_verified: true, name: "CEO", groups: [])
        assert_raises(OpenLoam::Sso::UnverifiedDomainError) { OpenLoam::Sso.provision(@squatter, claims) }

        assert_empty OpenLoam::Membership.where(user_id: victim.id), "no membership in the attacker's tenant"
      end
      assert_equal [ home.id ], OpenLoam::Membership.tenants_for(victim).pluck(:id), "the victim's tenants are unchanged"
      assert_empty OpenLoam::SsoIdentity.unscoped.where(sub: "attacker|1")
    end

    test "an unverified provider is invisible to home-realm discovery" do
      assert_nil OpenLoam::Sso.provider_for(email: "anyone@victimcorp.example"),
                 "an unproven domain claim must not capture sign-ins"

      with_tenant(@attacker) { @squatter.verify_domain! }
      assert_equal @squatter.id, OpenLoam::Sso.provider_for(email: "anyone@victimcorp.example").id
    end

    test "an unverified provider may still create a new user in its own tenant" do
      with_tenant(@attacker) do
        claims = OpenLoam::Sso::Claims.new(sub: "attacker|2", email: "staff@victimcorp.example",
                                           email_verified: true, name: "Staff", groups: [])
        user = OpenLoam::Sso.provision(@squatter, claims)

        assert_equal "staff@victimcorp.example", user.email
        assert_equal [ @attacker.id ], OpenLoam::Membership.tenants_for(user).pluck(:id)
      end
    end

    test "editing the domain revokes verification" do
      with_tenant(@attacker) do
        @squatter.verify_domain!
        @squatter.update!(domain: "otherco.example")
        assert_not @squatter.reload.domain_verified?, "an approved domain cannot be repointed at an unapproved one"
      end
      assert_nil OpenLoam::Sso.provider_for(email: "someone@otherco.example")
    end
  end

  test "domain uniqueness is enforced across tenants (HRD must be unambiguous)" do
    conflict = with_tenant(@krakow) do
      OpenLoam::SsoProvider.new(name: "Krakow IdP", protocol: "oidc", client_id: "c", domain: "warsaw-corp.example", jit_role: "employee")
    end
    refute conflict.valid?, "the same domain cannot own two providers"
    assert conflict.errors[:domain].any?
  end
end

# The end-to-end web flow through the SessionsController, driven by the offline
# FakeProvider: sign-in email -> HRD redirect -> callback -> session.
class OpenLoamSsoFlowTest < ActionDispatch::IntegrationTest
  setup do
    OpenLoam::Sso::FakeProvider.reset!
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sso-flow")
    with_tenant(@warsaw) do
      OpenLoam::SsoProvider.create!(name: "Warsaw IdP", protocol: "oidc", issuer: "https://idp.warsaw.example",
                                client_id: "cid", client_secret: "s3cr3t", domain: "warsaw-corp.example",
                                domain_verified_at: Time.current, jit_role: "employee")
    end
  end

  teardown { OpenLoam::Sso::FakeProvider.reset! }

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
    assert_equal "employee", with_tenant(@warsaw) { OpenLoam::Membership.find_by(user_id: user.id).role }
    assert_equal [ @warsaw.id ], OpenLoam::Membership.tenants_for(user).pluck(:id), "membership only in the IdP's tenant, not elsewhere"
  end

  test "an SSO user who also runs app-side MFA must still pass the second factor" do
    existing = User.create!(name: "Existing", email: "existing@warsaw-corp.example", password: "password")
    secret = OpenLoam::Totp.generate_secret
    travel_to(61.seconds.ago) do
      OpenLoam::MfaCredential.new(user: existing).activate_with!(secret, OpenLoam::Totp.code_at(secret, Time.now.to_i / 30))
    end

    sign_in_via_sso("existing@warsaw-corp.example")
    assert_redirected_to mfa_challenge_admin_session_path
    assert session[:mfa_pending], "SSO does not waive MFA"
    assert_nil session[:tenant_id], "not signed in until the second factor checks out"

    post mfa_verify_admin_session_path, params: { code: OpenLoam::Totp.code_at(secret, Time.now.to_i / 30) }

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
    OpenLoam::Sso::FakeProvider.force_email_verified = false
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
