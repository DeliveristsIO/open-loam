module Admin
  # Server-Sent Events: a per-tenant push stream (OpenLoam::EventStream) so the admin
  # updates live instead of polling. Authentication runs in the normal
  # before_action chain (set_open_loam_context) BEFORE any stream write — so an
  # unauthenticated request redirects to login the ordinary way, since no headers
  # have been committed yet. Once the loop starts writing, the response is
  # committed and there is no going back; that ordering is the whole safety of a
  # Live action.
  class EventsController < BaseController
    skip_authorization! "OpenLoam::EventStream gates every message: declared pattern, matching tenant, and audience."

    include ActionController::Live

    HEARTBEAT_SECONDS = 20

    def stream
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      handle = nil # so the ensure never raises NameError if subscribe below does
      queue = Queue.new

      # Subscribe as the FIRST thing in the begin whose ensure unsubscribes: a
      # leaked AS::Notifications subscriber would fire on every future event in
      # the process, holding this dead stream's queue forever.
      handle = OpenLoam::EventStream.broadcaster.subscribe(tenant: current_tenant, actor: current_actor) do |sse|
        queue << sse
      end

      loop do
        # A heartbeat comment both keeps the connection alive AND detects a dead
        # client: writing to a closed socket raises IOError → the loop exits →
        # ensure runs and the subscription is dropped.
        message = queue.pop(timeout: HEARTBEAT_SECONDS)
        response.stream.write(message || ": heartbeat\n\n")
      end
    rescue IOError, ActionController::Live::ClientDisconnected
      # The client went away — nothing to do but clean up in `ensure`.
    ensure
      OpenLoam::EventStream.broadcaster.unsubscribe(handle)
      response.stream.close
      OpenLoam::Current.reset
    end
  end
end
