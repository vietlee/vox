class UpdatePlanConfigsToNewPricing < ActiveRecord::Migration[7.2]
  def up
    # FREE: 5 surveys/votes, 30 credits, unlock ai_survey_builder + ai_analysis + ai_chat
    if (free = PlanConfig.find_by(plan_key: "free"))
      free.update!(
        limits: { max_surveys: 5, max_votes: 5, max_feedbacks: 10, max_supporters: 0, max_ai_credits: 30 },
        features: free.features.merge(
          "ai_survey_builder"   => true,
          "ai_analysis"         => true,
          "ai_executive_report" => false,
          "ai_chat"             => true,
          "ai_moderation"       => false
        )
      )
    end

    # PRO: 190,000₫, 50 limits, 300 credits, enable ai_chat
    if (pro = PlanConfig.find_by(plan_key: "pro"))
      pro.update!(
        price_vnd: 190_000,
        limits: { max_surveys: 50, max_votes: 50, max_feedbacks: 50, max_supporters: 10, max_ai_credits: 300 },
        features: pro.features.merge(
          "ai_survey_builder"   => true,
          "ai_analysis"         => true,
          "ai_executive_report" => true,
          "ai_chat"             => true,
          "ai_moderation"       => true
        )
      )
    end

    # ENTERPRISE: 390,000₫, 1000 credits (unlimited surveys/votes/feedbacks/supporters)
    if (ent = PlanConfig.find_by(plan_key: "enterprise"))
      ent.update!(
        price_vnd: 390_000,
        limits: { max_surveys: nil, max_votes: nil, max_feedbacks: nil, max_supporters: nil, max_ai_credits: 1000 },
        features: ent.features.merge(
          "ai_survey_builder"   => true,
          "ai_analysis"         => true,
          "ai_executive_report" => true,
          "ai_chat"             => true,
          "ai_moderation"       => true
        )
      )
    end
  end

  def down
    if (free = PlanConfig.find_by(plan_key: "free"))
      free.update!(
        limits: { max_surveys: 3, max_votes: 3, max_feedbacks: 10, max_supporters: 0, max_ai_credits: 0 },
        features: free.features.merge("ai_survey_builder" => false, "ai_analysis" => false, "ai_chat" => false)
      )
    end
    if (pro = PlanConfig.find_by(plan_key: "pro"))
      pro.update!(
        price_vnd: 1_000_000,
        limits: { max_surveys: nil, max_votes: nil, max_feedbacks: nil, max_supporters: 10, max_ai_credits: 500 },
        features: pro.features.merge("ai_chat" => false)
      )
    end
    if (ent = PlanConfig.find_by(plan_key: "enterprise"))
      ent.update!(price_vnd: 0, limits: ent.limits.merge("max_ai_credits" => nil))
    end
  end
end
