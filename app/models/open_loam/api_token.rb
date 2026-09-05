require "openssl"

module OpenLoam
  # A bearer token that lets a machine act as one user in one tenant. Same
  # rules as a human session: whatever the token's user may do in that tenant,
  # no more. Plumbing, so not audited and not evented.
  #
  # Only the SHA-256 digest is stored. The plaintext is returned once, from the
  # instance that generated it, and is unrecoverable afterwards — a dump of this
  # table is not a set of working credentials. A 24-byte random token needs no
  # slow KDF; it is not guessable the way a password is.
  class ApiToken < OpenLoam::TenantRecord
    self.table_name = "open_loam_api_tokens"

    belongs_to :user

    validates :token_digest, presence: true, uniqueness: true

    # Present only on the instance that just created it — never after a reload.
    attr_reader :token

    before_validation on: :create do
      @token ||= SecureRandom.hex(24)
      self.token_digest = self.class.digest(@token)
    end

    def self.digest(raw_token)
      OpenSSL::Digest::SHA256.hexdigest(raw_token.to_s)
    end

    # THE blessed cross-tenant lookup, and the reason it lives in the gem.
    #
    # A bearer token arrives with no tenant context — the token IS how the
    # request discovers which tenant it belongs to, so this one query must
    # bypass the tenant scope. That is exactly what host apps are forbidden to
    # do (`test/open_loam_guardrails_test.rb` fails the build on it), so the escape
    # hatch is vetted framework code here, used once, at the edge: find the
    # token, establish OpenLoam::Current, and everything downstream is ordinary
    # tenant-scoped code again.
    #
    # Returns the token, or nil for an unknown/blank one — callers render 401.
    def self.authenticate(raw_token)
      return nil if raw_token.blank?

      api_token = unscoped.find_by(token_digest: digest(raw_token))
      return nil unless api_token

      OpenLoam::Current.tenant = api_token.tenant
      OpenLoam::Current.actor = api_token.user

      # A token outlives the membership that justified it, so offboarding a user
      # from a tenant would otherwise leave their machine access intact. Checked
      # here rather than at revoke time: the membership is the authority.
      unless OpenLoam::Membership.exists?(user_id: api_token.user_id)
        OpenLoam::Current.reset
        return nil
      end

      api_token.update_column(:last_used_at, Time.current)
      api_token
    end
  end
end
