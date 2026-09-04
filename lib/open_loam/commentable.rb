module OpenLoam
  # Discussion on a record:
  #
  #   equipment.comment!("Hydraulics serviced")   # as OpenLoam.actor
  #   equipment.open_loam_comments.oldest_first
  #
  # Included by every generated entity. Comments are tenant-scoped like their
  # subject, so a discussion can never be read from another tenant.
  module Commentable
    extend ActiveSupport::Concern

    included do
      has_many :open_loam_comments, as: :commentable, class_name: "OpenLoam::Comment", dependent: :destroy
    end

    # Author defaults to whoever is acting — the same person the audit trail
    # and the event payload would name.
    def comment!(body, author: OpenLoam::Current.actor)
      open_loam_comments.create!(body: body, author: author)
    end
  end
end
