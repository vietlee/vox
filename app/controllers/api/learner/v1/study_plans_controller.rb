class Api::Learner::V1::StudyPlansController < Api::Learner::V1::BaseController
  GENERATE_COST = 3

  def index
    plans = current_learner.learner_study_plans.includes(:items).order(created_at: :desc)
    render json: plans.map { |plan|
      {
        id: plan.id,
        title: plan.title,
        status: plan.status,
        progress_pct: plan.progress_pct,
        created_at: plan.created_at,
        items: plan.items.map { |item|
          { id: item.id, title: item.title, done: item.done,
            done_at: item.done_at, position: item.position }
        }
      }
    }
  end

  def create
    unless current_learner.credits >= GENERATE_COST
      return render json: { error: "Không đủ credit. Cần #{GENERATE_COST} credits." },
                    status: :payment_required
    end

    plan = StudyPlanGenerator.new(current_learner, extra: params[:focus]).generate!
    current_learner.deduct_credits!(GENERATE_COST)

    render json: {
      id: plan.id,
      title: plan.title,
      status: plan.status,
      progress_pct: plan.progress_pct,
      created_at: plan.created_at,
      credits_remaining: current_learner.reload.credits,
      items: plan.items.map { |item|
        { id: item.id, title: item.title, done: item.done,
          done_at: item.done_at, position: item.position }
      }
    }
  rescue => e
    render json: { error: "Không tạo được lộ trình: #{e.message}" }, status: :unprocessable_entity
  end

  def destroy
    plan = current_learner.learner_study_plans.find(params[:id])
    plan.destroy!
    render json: { ok: true }
  end

  def toggle_item
    plan = current_learner.learner_study_plans.find(params[:id])
    item = plan.items.find(params[:item_id])
    now_done = !item.done
    item.update!(done: now_done, done_at: now_done ? Time.current : nil)

    if now_done
      LearnerGamification.record!(current_learner, :plan_item)
    end

    if plan.items.where(done: false).none? && plan.active?
      plan.update!(status: :completed)
      LearnerGamification.record!(current_learner, :study_plan_done, count_activity: false)
    elsif plan.completed? && plan.items.where(done: false).any?
      plan.update!(status: :active)
    end

    render json: {
      done: item.done, progress: plan.progress_pct, plan_completed: plan.completed?
    }
  end
end
