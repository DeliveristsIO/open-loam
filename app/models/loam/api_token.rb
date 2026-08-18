module Loam
  # A bearer token that lets a machine act as one user in one tenant. Same
  # rules as a human session: whatever the token's user may do in that tenant,
  # no more. Plumbing, so not audited and not evented.
  class ApiToken < Loam::TenantRecord
    self.table_name = "loam_api_tokens"

    belongs_to :user

    validates :token, presence: true, uniqueness: true

    before_validation on: :create do
      self.token ||= SecureRandom.hex(24)
    end

    # THE blessed cross-tenant lookup, and the reason it lives in the gem.
    #
    # A bearer token arrives with no tenant context — the token IS how the
    # request discovers which tenant it belongs to, so this one query must
    # bypass the tenant scope. That is exactly what host apps are forbidden to
    # do (`test/loam_guardrails_test.rb` fails the build on it), so the escape
    # hatch is vetted framework code here, used once, at the edge: find the
    # token, establish Loam::Current, and everything downstream is ordinary
    # tenant-scoped code again.
    #
    # Returns the token, or nil for an unknown/blank one — callers render 401.
    def self.authenticate(raw_token)
      return nil if raw_token.blank?

      api_token = unscoped.find_by(token: raw_token)
      return nil unless api_token

      Loam::Current.tenant = api_token.tenant
      Loam::Current.actor = api_token.user
      api_token.update_column(:last_used_at, Time.current)

      api_token
    end
  end
end
