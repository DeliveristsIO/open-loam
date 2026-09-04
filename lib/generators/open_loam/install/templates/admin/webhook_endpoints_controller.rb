module Admin
  # Where this tenant's events get delivered. Structural rather than
  # per-record, like field definitions, so it is gated on the manager role
  # instead of a generated entity policy.
  class WebhookEndpointsController < BaseController
    before_action { require_role!(:manager) }

    def index
      @records = OpenLoam::WebhookEndpoint.order(:event_pattern)
    end

    def new
      @record = OpenLoam::WebhookEndpoint.new(active: true)
    end

    def create
      @record = OpenLoam::WebhookEndpoint.new(permitted_params)

      if @record.save
        redirect_to admin_webhook_endpoints_path
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      OpenLoam::WebhookEndpoint.find(params[:id]).destroy!
      redirect_to admin_webhook_endpoints_path
    end

    private

    # The secret is generated, never submitted.
    def permitted_params
      params.require(:webhook_endpoint).permit(:url, :event_pattern, :active)
    end
  end
end
