module Loam
  # A note by one person, on one record, in one tenant. Polymorphic, so any
  # entity that `include Loam::Commentable` gets a discussion for free.
  #
  # Not audited on purpose: the comment IS the activity record. A
  # Loam::AuditRecord saying "someone created a comment" beside a comment
  # saying what they wrote is the same fact stored twice.
  #
  # Evented on purpose, in Loam's own domain ("loam.comment.created"), because
  # a new comment is exactly the kind of thing an app wants to react to —
  # notify the watchers, ping a webhook — without every app inventing its own
  # event name for it.
  class Comment < Loam::TenantRecord
    include Loam::Eventful

    self.table_name = "loam_comments"

    event_domain :loam
    event_entity :comment # not "loam_comment", which the namespace would give

    belongs_to :commentable, polymorphic: true
    belongs_to :author, class_name: "User"

    validates :body, presence: true

    scope :oldest_first, -> { order(:created_at) }
  end
end
