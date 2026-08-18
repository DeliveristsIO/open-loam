module Loam
  # Discussion on a record:
  #
  #   equipment.comment!("Hydraulics serviced")   # as Loam.actor
  #   equipment.loam_comments.oldest_first
  #
  # Included by every generated entity. Comments are tenant-scoped like their
  # subject, so a discussion can never be read from another tenant.
  module Commentable
    extend ActiveSupport::Concern

    included do
      has_many :loam_comments, as: :commentable, class_name: "Loam::Comment", dependent: :destroy
    end

    # Author defaults to whoever is acting — the same person the audit trail
    # and the event payload would name.
    def comment!(body, author: Loam::Current.actor)
      loam_comments.create!(body: body, author: author)
    end
  end
end
