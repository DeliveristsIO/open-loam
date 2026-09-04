module Admin
  # Configure this tenant's SSO (OIDC) provider — manager-only, since it governs
  # who can sign in and at what role. Tenant-scoped by Loam::SsoProvider's default
  # scope, so a manager only ever sees and edits their own tenant's connection.
  # The client_secret is WRITE-ONLY: it is encrypted at rest and never rendered
  # back, so editing without retyping it leaves the stored secret untouched.
  class SsoProvidersController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_provider, only: %i[edit update destroy]

    rescue_from JSON::ParserError do |error|
      flash.now[:alert] = "The group→role map must be valid JSON: #{error.message}"
      @provider ||= Loam::SsoProvider.new
      render(@provider.persisted? ? :edit : :new, status: :unprocessable_entity)
    end

    def index
      @providers = Loam::SsoProvider.order(:domain)
    end

    def new
      @provider = Loam::SsoProvider.new(protocol: "oidc", active: true, jit_role: "employee")
    end

    def create
      @provider = Loam::SsoProvider.new(provider_params)
      if @provider.save
        redirect_to admin_sso_providers_path, notice: "SSO provider created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @provider.update(provider_params)
        redirect_to admin_sso_providers_path, notice: "SSO provider updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @provider.destroy!
      redirect_to admin_sso_providers_path, notice: "SSO provider deleted."
    end

    private

    def set_provider
      @provider = Loam::SsoProvider.find(params[:id])
    end

    def provider_params
      permitted = params.require(:sso_provider).permit(:name, :protocol, :issuer, :client_id, :domain, :jit_role, :active)
      # Write-only: only assign the secret when a new value was typed, so a blank
      # field on edit keeps the encrypted one already stored.
      secret = params[:sso_provider][:client_secret]
      permitted[:client_secret] = secret if secret.present?
      permitted[:group_role_map] = JSON.parse(params[:sso_provider][:group_role_map].presence || "{}")
      permitted
    end
  end
end
