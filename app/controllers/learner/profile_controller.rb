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
    params.require(:learner).permit(:name)
  end
end
