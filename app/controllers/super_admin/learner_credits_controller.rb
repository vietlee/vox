class SuperAdmin::LearnerCreditsController < SuperAdmin::BaseController
  before_action :set_learner

  def edit; end

  def update
    credits     = params[:learner][:credits].to_i.clamp(0, 100_000)
    max_credits = params[:learner][:max_credits].to_i.clamp(0, 100_000)
    if @learner.update(credits: credits, max_credits: max_credits)
      redirect_to super_admin_subscriptions_path, notice: "Đã cập nhật credit cho học viên."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_learner
    @learner = Learner.find(params[:id])
  end
end
