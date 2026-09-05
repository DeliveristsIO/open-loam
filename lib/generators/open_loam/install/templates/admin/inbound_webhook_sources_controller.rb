module Admin
  # Manage the external systems allowed to POST webhooks into this tenant
  # (OpenLoam::InboundWebhookSource) — manager-only. Create a source (token + secret
  # are generated), copy the receive URL and secret to the sender, rotate either,
  # toggle active, and see the most recent received deliveries.
  class InboundWebhookSourcesController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_source, only: %i[destroy rotate_secret rotate_token toggle]

    def index
      @sources = OpenLoam::InboundWebhookSource.order(:name)
      @recent = OpenLoam::InboundWebhookDelivery.order(received_at: :desc).limit(20)
    end

    def new
      @source = OpenLoam::InboundWebhookSource.new(event_name: "inbound.webhook.received")
    end

    def create
      @source = OpenLoam::InboundWebhookSource.new(source_params)
      if @source.save
        redirect_to admin_inbound_webhook_sources_path, notice: "Source created. Copy the secret now — it signs every call."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      @source.destroy!
      redirect_to admin_inbound_webhook_sources_path, notice: "Source deleted."
    end

    def rotate_secret
      @source.rotate_secret!
      redirect_to admin_inbound_webhook_sources_path, notice: "Secret rotated — update the sender."
    end

    def rotate_token
      @source.rotate_token!
      redirect_to admin_inbound_webhook_sources_path, notice: "Token rotated — update the sender's URL."
    end

    def toggle
      @source.update!(active: !@source.active?)
      redirect_to admin_inbound_webhook_sources_path, notice: "Source #{@source.active? ? 'enabled' : 'disabled'}."
    end

    private

    def set_source
      @source = OpenLoam::InboundWebhookSource.find(params[:id])
    end

    def source_params
      params.require(:inbound_webhook_source).permit(
        :name, :event_name, :signature_header,
        :timestamp_header, :timestamp_tolerance
      )
    end
  end
end
