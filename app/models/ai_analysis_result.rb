class AiAnalysisResult < ApplicationRecord
  belongs_to :workspace
  belongs_to :ai_job

  RESULT_TYPES = %w[
    executive_summary sentiment themes anomaly trend recommendations cross_segment
    vote_insight moderation_result executive_report
  ].freeze

  validates :result_type, inclusion: { in: RESULT_TYPES }

  def summary_text
    output["summary"] || output["text"] || ""
  end
end
