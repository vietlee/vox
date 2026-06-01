class Admin::FeedbacksController < Admin::BaseController
  before_action :set_board
  before_action :set_feedback, only: [:show, :update, :destroy, :approve, :hide, :unhide, :pin, :unpin, :update_admin_status, :mark_safe]

  def index
    feedbacks = @board.feedbacks.order(pinned: :desc, created_at: :desc)
    feedbacks = feedbacks.where(status: params[:status]) if params[:status].present?
    feedbacks = feedbacks.where(moderation_status: params[:moderation]) if params[:moderation].present?
    feedbacks = feedbacks.where("content ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @feedbacks = pagy(feedbacks)
    @pending_count = @board.feedbacks.where(status: :pending).count
    @flagged_count = @board.feedbacks.where(moderation_status: :flagged).count
    @ai_summary = AiAnalysisResult.where(
      workspace: current_workspace,
      resource_type: "FeedbackBoard",
      resource_id: @board.id,
      result_type: "themes"
    ).order(created_at: :desc).first
    @action_items      = @board.action_items.includes(:assignee).ordered
    @workspace_members = workspace_members_for_assignment
    @new_feedbacks_since_analysis = @ai_summary ?
      @board.feedbacks.approved.where("created_at > ?", @ai_summary.created_at).count : 0

    if params[:partial] == "action_items" && request.xhr?
      render partial: "admin/feedbacks/action_items_card",
             locals: { action_items: @action_items, workspace_members: @workspace_members, board: @board }
      return
    end
  end

  def show
  end

  def update
    @feedback.update(feedback_update_params)
    @feedback.admin_reply_image.purge if params.dig(:feedback, :remove_admin_reply_image) == '1' && @feedback.admin_reply_image.attached?
    respond_to do |format|
      format.json do
        image_url = @feedback.admin_reply_image.attached? ? url_for(@feedback.admin_reply_image) : nil
        render json: { ok: true, admin_reply: @feedback.admin_reply, image_url: image_url }
      end
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def destroy
    @feedback.destroy
    respond_to do |format|
      format.json { render json: { ok: true } }
      format.html { redirect_to feedback_board_feedbacks_path(@board) }
    end
  end

  def approve
    @feedback.update!(status: :approved)
    respond_to do |format|
      format.json { render json: { status: 'approved' } }
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def hide
    @feedback.update!(status: :hidden)
    respond_to do |format|
      format.json { render json: { status: 'hidden' } }
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def unhide
    @feedback.update!(status: :approved)
    respond_to do |format|
      format.json { render json: { status: 'approved' } }
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def pin
    @feedback.update!(pinned: true)
    respond_to do |format|
      format.json { render json: { pinned: true, order: sorted_ids } }
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def unpin
    @feedback.update!(pinned: false)
    respond_to do |format|
      format.json { render json: { pinned: false, order: sorted_ids } }
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def update_admin_status
    @feedback.update!(admin_status: params[:admin_status])
    respond_to do |format|
      format.json { render json: { ok: true } }
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def mark_safe
    @feedback.update!(moderation_status: :safe, status: :approved)
    respond_to do |format|
      format.json { render json: { ok: true } }
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
    end
  end

  def bulk_action
    ids    = Array(params[:ids]).map(&:to_i).uniq
    action = params[:bulk_action_type].to_s

    allowed = %w[approve hide reject delete]
    unless allowed.include?(action)
      render json: { error: "Invalid action" }, status: :bad_request and return
    end

    feedbacks = @board.feedbacks.where(id: ids)
    count = 0

    case action
    when "approve"
      count = feedbacks.update_all(status: :approved, moderation_status: :safe)
    when "hide"
      count = feedbacks.update_all(status: :hidden, moderation_status: :safe)
    when "reject"
      count = feedbacks.update_all(status: :rejected, moderation_status: :safe)
    when "delete"
      count = feedbacks.count
      feedbacks.destroy_all
    end

    render json: { ok: true, count: count, action: action }
  end

  private

  def set_board
    @board = current_workspace.feedback_boards.find(params[:feedback_board_id])
  end

  def workspace_members_for_assignment
    admin = current_workspace.users.where(workspace_id: current_workspace.id).where.not(role: :super_admin)
    supporters = current_workspace.workspace_memberships.active.includes(:user).map(&:user).compact
    (admin + supporters).uniq(&:id)
  end

  def set_feedback
    @feedback = @board.feedbacks.find(params[:id])
  end

  def sorted_ids
    @board.feedbacks.order(pinned: :desc, created_at: :desc).pluck(:id)
  end

  def feedback_update_params
    params.require(:feedback).permit(:admin_reply, :admin_reply_image, :admin_status, :status, :pinned)
  end
end
