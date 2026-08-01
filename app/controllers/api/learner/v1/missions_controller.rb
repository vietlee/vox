class Api::Learner::V1::MissionsController < Api::Learner::V1::BaseController
  def index
    l = current_learner
    claimed = l.learner_mission_claims
                .where(period: [Date.current.to_s, "once"])
                .pluck(:mission_key, :period).to_set

    missions = MissionCatalog.all.map do |m|
      progress = MissionCatalog.progress_for(m, l)
      period   = MissionCatalog.period_for(m)
      {
        key:      m[:key],
        type:     m[:type],
        target:   m[:target],
        reward:   m[:reward],
        progress: progress,
        done:     progress >= m[:target],
        claimed:  claimed.include?([m[:key], period])
      }
    end

    render json: {
      missions:          missions,
      credits_remaining: l.credits
    }
  end

  def claim
    l       = current_learner
    mission = MissionCatalog.find(params[:key])
    return render json: { error: "Nhiệm vụ không tồn tại." }, status: :not_found unless mission

    period   = MissionCatalog.period_for(mission)
    progress = MissionCatalog.progress_for(mission, l)
    return render json: { error: "Nhiệm vụ chưa hoàn thành." }, status: :unprocessable_entity if progress < mission[:target]

    begin
      ActiveRecord::Base.transaction do
        l.learner_mission_claims.create!(
          mission_key: mission[:key], period: period,
          reward: mission[:reward], claimed_at: Time.current
        )
        l.add_credits!(mission[:reward])
      end
    rescue ActiveRecord::RecordNotUnique
      return render json: { error: "Đã nhận thưởng rồi." }, status: :unprocessable_entity
    end

    render json: {
      ok:                true,
      reward:            mission[:reward],
      credits_remaining: l.reload.credits
    }
  end
end
