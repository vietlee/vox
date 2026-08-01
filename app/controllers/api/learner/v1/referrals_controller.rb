class Api::Learner::V1::ReferralsController < Api::Learner::V1::BaseController
  def show
    l = current_learner
    if l.referral_code.blank?
      l.ensure_referral_code
      l.save!
    end

    rewarded = l.referrals.where.not(referral_rewarded_at: nil).count

    render json: {
      code:           l.referral_code,
      invite_link:    referral_link(l.referral_code),
      reward:         Learner::REFERRAL_REWARD,
      invited_count:  rewarded,
      credits_earned: rewarded * Learner::REFERRAL_REWARD
    }
  end

  private

  def referral_link(code)
    host = ENV.fetch("APP_HOST", "vox.czin.net")
    "https://#{host}/invite/#{code}"
  end
end
