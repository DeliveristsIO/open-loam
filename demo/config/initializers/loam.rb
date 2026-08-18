# Loam configuration and domain event subscriptions.
#
# Subscribe to a single event or a whole domain (trailing dot = prefix):
#
#   Loam::Events.subscribe("billing.subscription.renewed") do |name, payload|
#     BillingMailer.renewal_receipt(payload[:id]).deliver_later
#   end
#
#   Loam::Events.subscribe("rental.") do |name, payload|
#     Rails.logger.info("[loam event] #{name} #{payload.inspect}")
#   end
Rails.application.config.to_prepare do
end
