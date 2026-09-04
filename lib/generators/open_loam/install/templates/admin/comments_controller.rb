module Admin
  # One controller for every commentable entity, because a comment form is the
  # same form whatever it is attached to.
  #
  # Create only: comments are a record of what was said, so there is no edit
  # and no delete here.
  class CommentsController < BaseController
    def create
      record = commentable

      # Commenting is open to any member — and membership is already proven:
      # BaseController refuses the request otherwise. The policy check is the
      # record's own, so an entity that hides itself from a role hides its
      # discussion too.
      authorize!(policy_for(record), :read?)

      comment = record.loam_comments.new(body: params[:body], author: current_actor)
      flash[:alert] = comment.errors.full_messages.to_sentence unless comment.save

      redirect_back fallback_location: [ :admin, record ]
    end

    private

    # The type arrives from the browser, so it is never constantized blindly.
    # `safe_constantize` returns nil for anything that is not a real constant,
    # and the class then has to prove it is a Loam entity that opted into
    # comments — the allowlist is the contract, not a hand-kept list of names.
    def commentable
      klass = params[:commentable_type].to_s.safe_constantize

      unless klass.is_a?(Class) && klass < Loam::TenantRecord && klass.include?(Loam::Commentable)
        raise Loam::NotAuthorizedError, "#{params[:commentable_type].inspect} is not a commentable Loam entity"
      end

      klass.find(params[:commentable_id])
    end
  end
end
