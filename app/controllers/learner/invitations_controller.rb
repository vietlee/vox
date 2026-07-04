class Learner::InvitationsController < ApplicationController
  layout "learner"
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  def accept
    @learner = Learner.find_by(invite_token: params[:token])
    if @learner.nil?
      redirect_to new_learner_session_path, alert: "Link không hợp lệ hoặc đã hết hạn."
    elsif @learner.password_set?
      redirect_to new_learner_session_path, notice: "Tài khoản đã được thiết lập. Vui lòng đăng nhập."
    end
    # render accept.html.erb (set-password form)
  end

  def update
    @learner = Learner.find_by(invite_token: params[:token])
    return redirect_to new_learner_session_path, alert: "Link không hợp lệ." unless @learner

    if @learner.update(password: params[:password], password_confirmation: params[:password_confirmation], password_set: true, invite_token: nil)
      @learner.confirm unless @learner.confirmed?
      sign_in(:learner, @learner)
      redirect_to learner_root_path, notice: "Chào mừng #{@learner.name}! Tài khoản của bạn đã sẵn sàng."
    else
      render :accept, status: :unprocessable_entity
    end
  end
end
