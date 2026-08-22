module Admin
  # Durable event deliveries (Loam::EventDelivery) — the dead-letter view.
  # Manager-only. Lists deliveries parked as `dead` (handler removed, or retries
  # exhausted) and lets an operator requeue one after fixing the handler. Pending
  # deliveries drain on their own; a small sample is shown for visibility.
  class EventDeliveriesController < BaseController
    before_action { require_role!(:manager) }

    def index
      @dead = Loam::EventDelivery.dead.order(updated_at: :desc).limit(200)
      @pending = Loam::EventDelivery.pending.order(Arel.sql("next_attempt_at IS NULL DESC, next_attempt_at ASC")).limit(50)
    end

    # Re-arm one delivery: back to pending with a clean slate, and nudge a job.
    # The sweep would eventually pick it up anyway; this is the "try now" button.
    def redeliver
      delivery = Loam::EventDelivery.find(params[:id])
      delivery.update!(status: "pending", attempts: 0, next_attempt_at: nil, last_error: nil)
      Loam::EventDeliveryJob.perform_later(delivery.tenant_id, delivery.id)
      redirect_to admin_event_deliveries_path, notice: "Delivery requeued."
    end
  end
end
