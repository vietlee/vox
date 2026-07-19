class Api::Learner::V1::LearningPathAssignmentsController < Api::Learner::V1::BaseController
  before_action :set_assignment

  def show
    path      = @assignment.learning_path
    items     = path.learning_path_items.order(:position)
    progresses = @assignment.learning_item_progresses.index_by(&:learning_path_item_id)

    render json: {
      assignment: {
        token: @assignment.token,
        status: @assignment.status,
        progress_pct: @assignment.progress_pct,
        due_date: @assignment.due_date,
        completed_at: @assignment.completed_at
      },
      path: { title: path.title },
      items: items.map { |item|
        prog = progresses[item.id]
        {
          id: item.id,
          title: item.title,
          kind: item.item_type,
          position: item.position,
          completed: prog&.completed? || false
        }
      }
    }
  end

  def complete_item
    item     = @assignment.learning_path.learning_path_items.find(params[:item_id])
    progress = @assignment.learning_item_progresses.find_or_initialize_by(learning_path_item: item)
    progress.update!(completed: true, completed_at: Time.current)

    total = @assignment.learning_path.learning_path_items.count
    done  = @assignment.learning_item_progresses.where(completed: true).count

    if done >= total
      @assignment.completed!
      @assignment.update!(completed_at: Time.current)
    end

    render json: {
      ok: true,
      progress_pct: @assignment.progress_pct,
      completed: @assignment.completed?
    }
  end

  private

  def set_assignment
    @assignment = current_learner.learning_path_assignments.find_by!(token: params[:token])
  end
end
