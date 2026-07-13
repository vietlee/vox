class Learner::LearningPathAssignmentsController < Learner::BaseController
  before_action :set_assignment
  before_action :ensure_published

  def show
    @path  = @assignment.learning_path
    @items = @path.learning_path_items.includes(:quiz_set, :flashcard_deck).order(:position).to_a
    @progresses = @assignment.learning_item_progresses.index_by(&:learning_path_item_id)

    quiz_set_ids = @items.filter_map(&:quiz_set_id)
    deck_ids     = @items.filter_map(&:flashcard_deck_id)
    @qa_by_set   = current_learner.quiz_assignments.where(quiz_set_id: quiz_set_ids).index_by(&:quiz_set_id)
    @fa_by_deck  = current_learner.flashcard_assignments.where(flashcard_deck_id: deck_ids).index_by(&:flashcard_deck_id)
  end

  def complete_item
    item = @assignment.learning_path.learning_path_items.find(params[:item_id])
    progress = @assignment.learning_item_progresses.find_or_initialize_by(learning_path_item: item)
    progress.update!(completed: true, completed_at: Time.current)

    total = @assignment.learning_path.learning_path_items.count
    done  = @assignment.learning_item_progresses.where(completed: true).count

    if done >= total
      @assignment.completed!
      @assignment.update!(completed_at: Time.current)
    end

    render json: { ok: true, progress_pct: @assignment.progress_pct, completed: @assignment.completed? }
  end

  private

  def set_assignment
    @assignment = current_learner.learning_path_assignments.find_by!(token: params[:token])
  end

  def ensure_published
    unless @assignment.learning_path.published?
      redirect_to learner_root_path,
        alert: "Lộ trình học này chưa được mở. Vui lòng liên hệ admin."
    end
  end
end
