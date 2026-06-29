class Admin::LearningPathAssignmentsController < Admin::BaseController
  before_action :set_assignment

  def show
    @items = @assignment.learning_path.learning_path_items.includes(:quiz_set, :flashcard_deck).order(:position)
    @progresses = @assignment.learning_item_progresses.index_by(&:learning_path_item_id)
  end

  def update_progress
    item = @assignment.learning_path.learning_path_items.find(params[:item_id])
    progress = @assignment.learning_item_progresses.find_or_initialize_by(learning_path_item: item)
    progress.update!(status: params[:status], completed_at: params[:status].to_s == "completed" ? Time.current : nil)
    pct = @assignment.reload.progress_pct; done = @assignment.learning_item_progresses.completed.count; @assignment.update!(status: :completed) if pct == 100 && @assignment.active? rescue nil; render json: { pct: pct, done_count: done }
  end

  def destroy
    @assignment.destroy
    redirect_to learning_path_path(@assignment.learning_path), notice: "Đã hủy giao."
  end

  private

  def set_assignment
    @assignment = LearningPathAssignment.joins(:learning_path)
                    .where(learning_paths: { workspace: current_workspace })
                    .find(params[:id])
    authorize_assignment!
  end

  def authorize_assignment!
    return if current_workspace_admin? || @assignment.assignee == current_user
    redirect_to dashboard_path, alert: "Không có quyền."
  end
end
