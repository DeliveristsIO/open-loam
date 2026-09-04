module OpenLoam
  # One in-app message for one recipient (`user`) in one tenant. The same
  # person in two tenants has two separate inboxes — like everything else in
  # OpenLoam, "your notifications" always means "in the current tenant".
  #
  # Plumbing, not business data: not audited, the same way OpenLoam::AuditRecord
  # isn't. It IS evented, though — creating one publishes "open_loam.notification.created"
  # (carrying the recipient's user_id) so OpenLoam::EventStream can push it to that
  # user's browser and the bell updates live. Created through
  # OpenLoam::Notifications.notify, read through the admin bell.
  class Notification < OpenLoam::TenantRecord
    self.table_name = "open_loam_notifications"

    belongs_to :user

    validates :title, presence: true

    scope :unread, -> { where(read_at: nil) }

    # The one signal the real-time bell listens for. Only id + recipient ride the
    # event (OpenLoam::Events also stamps tenant_id); no message content is broadcast.
    after_create_commit do
      OpenLoam::Events.publish("open_loam.notification.created", id: id, user_id: user_id)
    end

    # What the notification is about, if anything (source_type/source_id) —
    # stored rather than associated, so a notification survives its subject.

    def read? = read_at.present?

    def mark_read!
      update!(read_at: Time.current) unless read?
      self
    end
  end
end
