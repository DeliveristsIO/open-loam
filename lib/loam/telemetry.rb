module Loam
  # A dependency-free observability seam (L-712). Wrap a unit of work in a span;
  # by default it emits an `ActiveSupport::Notifications` event
  # ("loam.span.<name>") carrying the attributes and duration, so ANY subscriber
  # — an OpenTelemetry bridge, StatsD, a log line — picks it up with no hard
  # dependency on Loam's side. An app that wants real OTLP spans replaces the
  # whole strategy:
  #
  #   Loam::Telemetry.backend = ->(name, attributes, work) do
  #     Tracer.in_span(name, attributes: attributes) { work.call }
  #   end
  #
  # Loam instruments its async/background hot paths (scheduler tick, durable
  # event delivery, inbound webhook ingest) so an operator sees them without
  # wiring anything per-call.
  module Telemetry
    module_function

    # Run `block` as a span named `name` with `attributes`. Returns the block's
    # value. A nil/absent block is a no-op that returns nil.
    def span(name, **attributes, &block)
      return block&.call unless block_given?

      if backend
        backend.call(name.to_s, attributes, block)
      else
        ActiveSupport::Notifications.instrument("loam.span.#{name}", **attributes, &block)
      end
    end

    def backend
      @backend
    end

    def backend=(callable)
      @backend = callable
    end

    def reset!
      @backend = nil
    end
  end
end
