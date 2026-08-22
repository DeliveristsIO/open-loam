# A minimal durable event subscriber for the demo (registered in
# config/initializers/loam.rb via Loam::DurableEvents.register). It just records
# what it received into a class-level sink so the admin/tests can see durable
# delivery working end to end. A real subscriber would do real work here —
# provision an account, post to a ledger, send a fulfilment request — and MUST be
# idempotent, because durable delivery is at-least-once.
class DurableEventEcho
  class << self
    def received
      @received ||= []
    end

    def reset!
      @received = []
    end

    def call(event_name, payload)
      received << { event: event_name, payload: payload }
    end
  end
end
