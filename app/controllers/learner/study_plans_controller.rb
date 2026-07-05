class Learner::StudyPlansController < Learner::BaseController
  GENERATE_COST = 3

  def index
    @cost  = GENERATE_COST
    @plans = current_learner.learner_study_plans.order(created_at: :desc)
  end

  def show
    @plan = current_learner.learner_study_plans.find(params[:id])
  end

  def create
    unless current_learner.credits >= GENERATE_COST
      return redirect_to learner_study_plans_path, alert: "Không đủ credit. Cần #{GENERATE_COST} credits để tạo lộ trình."
    end

    plan = StudyPlanGenerator.new(current_learner).generate!
    current_learner.deduct_credits!(GENERATE_COST)
    redirect_to learner_study_plan_path(plan)
  rescue => e
    redirect_to learner_study_plans_path, alert: "Không tạo được lộ trình: #{e.message}"
  end

  def toggle_item
    @plan = current_learner.learner_study_plans.find(params[:id])
    item  = @plan.items.find(params[:item_id])
    now_done = !item.done
    item.update!(done: now_done, done_at: now_done ? Time.current : nil)

    if now_done
      LearnerGamification.record!(current_learner, :plan_item)
    end

    # Complete the plan when all items are done
    if @plan.items.where(done: false).none? && @plan.active?
      @plan.update!(status: :completed)
      LearnerGamification.record!(current_learner, :study_plan_done, count_activity: false)
    elsif @plan.completed? && @plan.items.where(done: false).any?
      @plan.update!(status: :active)
    end

    render json: {
      done: item.done, progress: @plan.progress_pct,
      plan_completed: @plan.completed?
    }
  end
end
