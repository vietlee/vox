class AiJob < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true
  has_many   :ai_analysis_results, dependent: :destroy

  enum :status, { pending: 0, running: 1, done: 2, failed: 3 }

  JOB_TYPES = %w[
    survey_builder question_checker survey_analysis feedback_analysis
    post_vote_insight content_moderation executive_report ai_chat monthly_digest
  ].freeze

  CREDIT_COSTS = {
    "survey_builder"     => 5,
    "question_checker"   => 1,
    "survey_analysis"    => 5,
    "feedback_analysis"  => 3,
    "post_vote_insight"  => 2,
    "content_moderation" => 1,
    "executive_report"   => 15,
    "ai_chat"            => 2,
    "monthly_digest"     => 10
  }.freeze

  validates :job_type, inclusion: { in: JOB_TYPES }

  def credit_cost_for_type
    CREDIT_COSTS[job_type] || 1
  end

  def start!
    update!(status: :running, started_at: Time.current)
  end

  def complete!(output)
    update!(status: :done, output_data: output, completed_at: Time.current)
    notify_completion
  end

  def fail!(error)
    update!(status: :failed, error_message: error, completed_at: Time.current)
  end

  private

  def notify_completion
    return unless user
    ActionCable.server.broadcast("user_#{user_id}", {
      type: "ai_job_done",
      job_type: job_type,
      job_id: id
    })
  end
end
