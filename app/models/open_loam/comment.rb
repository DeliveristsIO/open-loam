module OpenLoam
  # A note by one person, on one record, in one tenant. Polymorphic, so any
  # entity that `include OpenLoam::Commentable` gets a discussion for free.
  #
  # Not audited on purpose: the comment IS the activity record. A
  # OpenLoam::AuditRecord saying "someone created a comment" beside a comment
  # saying what they wrote is the same fact stored twice.
  #
  # Evented on purpose, in OpenLoam's own domain ("open_loam.comment.created"), because
  # a new comment is exactly the kind of thing an app wants to react to —
  # notify the watchers, ping a webhook — without every app inventing its own
  # event name for it.
  class Comment < OpenLoam::TenantRecord
    include OpenLoam::Eventful

    self.table_name = "open_loam_comments"

    event_domain :open_loam
    event_entity :comment # not "open_loam_comment", which the namespace would give

    belongs_to :commentable, polymorphic: true
    belongs_to :author, class_name: "User"

    validates :body, presence: true

    scope :oldest_first, -> { order(:created_at) }
  end
end
