class Learner::ProfileController < Learner::BaseController
  def show; end

  def update
    if current_learner.update(profile_params)
      redirect_to learner_profile_path, notice: "Đã cập nhật thông tin."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:learner).permit(:name, :daily_goal).tap do |p|
      p[:daily_goal] = p[:daily_goal].to_i.clamp(1, 20) if p[:daily_goal].present?
    end
  end
end
