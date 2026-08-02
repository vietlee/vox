class Api::Learner::V1::RegistrationsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace
  skip_forgery_protection

  def create
    name     = params.dig(:learner, :name).to_s.strip
    email    = params.dig(:learner, :email).to_s.strip.downcase
    password = params.dig(:learner, :password).to_s
    ref_code = params.dig(:learner, :referral_code).to_s.strip.upcase.presence

    learner = Learner.new(name: name, email: email, password: password)

    # A new record can never be its own referrer, so no self-referral check needed.
    referrer = ref_code && Learner.find_by(referral_code: ref_code)
    learner.referred_by_id = referrer.id if referrer

    if learner.save
      bonus = 0
      if referrer
        # Reward BOTH sides once, at registration.
        ActiveRecord::Base.transaction do
          referrer.add_credits!(Learner::REFERRAL_REWARD)
          learner.add_credits!(Learner::REFERRAL_REWARD)
          learner.update_column(:referral_rewarded_at, Time.current)
        end
        bonus = Learner::REFERRAL_REWARD
        notify_referrer(referrer, learner)
      end

      learner.remember_me = true
      sign_in(:learner, learner)
      learner.update_column(:last_seen_at, Time.current)

      render json: {
        learner: {
          id: learner.id, name: learner.name, email: learner.email,
          credits: learner.reload.credits, xp: learner.xp,
          current_streak: learner.current_streak, daily_goal: learner.daily_goal,
          preferred_locale: learner.preferred_locale
        },
        referral_bonus: bonus
      }
    else
      render json: { error: learner.errors.full_messages.first || "Đăng ký thất bại." },
             status: :unprocessable_entity
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def notify_referrer(referrer, new_learner)
    LearnerNotification.notify_t!(
      learner:    referrer,
      title_key:  "referral_title", title_args: { n: Learner::REFERRAL_REWARD },
      body_key:   "referral_body",  body_args:  { name: new_learner.name },
      type:       "referral"
    )
  rescue => e
    Rails.logger.warn "[Referral notify] #{e.message}"
  end
end
