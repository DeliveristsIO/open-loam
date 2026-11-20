module OpenLoam
  # Domain events, delivered over HTTP to whoever asked for them.
  #
  # One global subscriber listens to every OpenLoam event and, in the tenant the
  # event was published in, enqueues a delivery per matching active endpoint.
  # Matching happens at dispatch time rather than at subscribe time because
  # endpoints are data: a tenant can add one from the admin without a reboot.
  module Webhooks
    DEFAULT_RETRY_SCHEDULE = [ 60, 300, 1_800, 7_200, 21_600, 43_200, 86_400 ].freeze
    DISABLED_EVENT = "open_loam.webhook.endpoint_disabled".freeze
    TEST_EVENT = "open_loam.webhook.test".freeze
    EXCERPT_BYTES = 512
    TIMESTAMP_TOLERANCE = 300

    CONFIG_IVARS = %i[
      @header_prefix @user_agent @retry_schedule @disable_after_failures @delivery_retention @body_builder
      @transport @require_https @allowed_ports @encrypt_secrets @test_event_name @timeout
      @secret_rotation_grace @stuck_after
    ].freeze

    class << self
      attr_writer :header_prefix, :user_agent, :retry_schedule, :disable_after_failures, :delivery_retention,
                  :body_builder, :transport, :require_https, :allowed_ports, :encrypt_secrets, :test_event_name,
                  :timeout, :secret_rotation_grace, :stuck_after

      def header_prefix = @header_prefix || "X-OpenLoam"
      def user_agent = @user_agent || "OpenLoam-Webhooks/#{OpenLoam::VERSION}"
      def retry_schedule = @retry_schedule || DEFAULT_RETRY_SCHEDULE
      def disable_after_failures = defined?(@disable_after_failures) ? @disable_after_failures : 50
      def delivery_retention = defined?(@delivery_retention) ? @delivery_retention : 30.days
      def body_builder = @body_builder
      def transport = @transport || HttpTransport
      def require_https? = @require_https ? true : false
      def allowed_ports = @allowed_ports
      def encrypt_secrets? = @encrypt_secrets ? true : false
      def test_event_name = @test_event_name || TEST_EVENT
      def timeout = @timeout || 10
      def secret_rotation_grace = @secret_rotation_grace || 24.hours
      def stuck_after = @stuck_after || 5.minutes

      # Tests (and only tests) put the module back to its defaults.
      def reset_configuration!
        CONFIG_IVARS.each { |ivar| remove_instance_variable(ivar) if instance_variable_defined?(ivar) }
      end
    end

    # Wired once from OpenLoam::Engine. Idempotent: subscribing twice would deliver
    # every event twice.
    def self.subscribe!
      @subscription ||= Events.subscribe_all { |event_name, payload| dispatch(event_name, payload) }
    end

    # Runs inline in whatever published the event, so it stays cheap: one
    # query for the tenant's active endpoints, then the HTTP call is a job.
    def self.dispatch(event_name, payload)
      tenant = Tenant.find_by(id: payload[:tenant_id])
      return if tenant.nil?

      # Only JSON-safe primitives cross into the job — event payloads are ids
      # and scalars by convention, never records.
      deliverable = payload.transform_keys(&:to_s)

      OpenLoam.as_tenant(tenant) do
        WebhookEndpoint.active.each do |endpoint|
          next unless endpoint.matches?(event_name)

          WebhookDeliveryJob.perform_later(tenant.id, endpoint.id, event_name, deliverable)
        end
      end
    end
  end
end
