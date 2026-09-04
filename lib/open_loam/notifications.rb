module Loam
  # The one way to tell someone something inside the app.
  #
  #   Loam::Notifications.notify(user, title: "Order approved", source: order)
  #   Loam::Notifications.notify_role(:manager, title: "New damage report")
  #
  # Records land in the CURRENT tenant (Loam::Notification is tenant-scoped),
  # so a notification can never be delivered across a tenant boundary.
  #
  # The intended pattern is event -> notification: subscribe to a domain event
  # in config/initializers/loam.rb and notify from there, instead of scattering
  # delivery calls through models and controllers.
  module Notifications
    # Returns the created notifications. Accepts one user or many; `source` is
    # any record the message is about, stored as type + id.
    def self.notify(recipients, title:, body: nil, source: nil)
      Array(recipients).map do |user|
        Notification.create!(
          user: user,
          title: title,
          body: body,
          source_type: source&.class&.name,
          source_id: source&.id
        )
      end
    end

    # Everyone holding `role` in the current tenant. Memberships are
    # tenant-scoped, so this cannot reach into another tenant's staff.
    def self.notify_role(role, title:, body: nil, source: nil)
      recipients = Membership.where(role: role.to_s).includes(:user).map(&:user)

      notify(recipients, title: title, body: body, source: source)
    end
  end
end
