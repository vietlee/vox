class AiModelConfig < ApplicationRecord
  validates :feature_key, presence: true, uniqueness: true
  validates :model_id,    presence: true, inclusion: { in: -> (_) { AVAILABLE_MODELS.map { |m| m[:id] } } }

  AVAILABLE_MODELS = [
    { id: "claude-opus-4-8",           name: "Claude Opus 4.8",     tier: :opus,   desc: "Mạnh nhất hiện tại. Phù hợp tác vụ phức tạp và phân tích chuyên sâu." },
    { id: "claude-opus-4-5",           name: "Claude Opus 4.5",     tier: :opus,   desc: "Chất lượng cao, phù hợp phân tích chuyên sâu. Tốn nhiều credit hơn." },
    { id: "claude-sonnet-4-6",         name: "Claude Sonnet 4.6",   tier: :sonnet, desc: "Cân bằng tốt giữa chất lượng và tốc độ. Khuyến nghị cho hầu hết tính năng.", recommended: true },
    { id: "claude-sonnet-4-5",         name: "Claude Sonnet 4.5",   tier: :sonnet, desc: "Phiên bản Sonnet trước. Ổn định, phù hợp nếu cần tương thích ngược." },
    { id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5",    tier: :haiku,  desc: "Nhanh nhất, tiết kiệm credit nhất. Phù hợp tác vụ đơn giản, tự động hóa." },
  ].freeze

  FEATURES = {
    "quiz_generate"       => { label: "Quiz — Tạo bộ đề từ tài liệu",       default: "claude-sonnet-4-6",         credit_note: "5 credits/lần" },
    "quiz_eval_student"   => { label: "Quiz — Nhận xét AI từng học viên",    default: "claude-sonnet-4-6",         credit_note: "2 credits/lần" },
    "quiz_eval_class"     => { label: "Quiz — Phân tích AI toàn bộ kết quả", default: "claude-sonnet-4-6",         credit_note: "3 credits/lần" },
    "ai_chat"             => { label: "AI Chat workspace",                    default: "claude-sonnet-4-6",         credit_note: "1 credit/tin nhắn" },
    "survey_analysis"     => { label: "Khảo sát — Phân tích sâu (Opus)",     default: "claude-opus-4-5",           credit_note: "10 credits/lần" },
    "survey_builder"      => { label: "Khảo sát — Tạo khảo sát bằng AI",    default: "claude-sonnet-4-6",         credit_note: "3 credits/lần" },
    "survey_report"       => { label: "Khảo sát — Tạo báo cáo AI",           default: "claude-sonnet-4-6",         credit_note: "5 credits/lần" },
    "feedback_analysis"   => { label: "Góp ý — Phân tích AI",                default: "claude-sonnet-4-6",         credit_note: "5 credits/lần" },
    "vote_insight"        => { label: "Bình chọn — AI Insight",              default: "claude-haiku-4-5-20251001", credit_note: "1 credit/lần" },
    "moderation"          => { label: "Kiểm duyệt nội dung tự động",         default: "claude-haiku-4-5-20251001", credit_note: "tự động" },
    "stt_enhance"         => { label: "STT — Cải thiện văn bản",             default: "claude-haiku-4-5-20251001", credit_note: "1 credit/lần" },
  }.freeze

  CACHE_KEY = "ai_model_configs_v1"

  def self.model_for(feature_key)
    all_configs[feature_key.to_s] || FEATURES.dig(feature_key.to_s, :default) || ClaudeService::SONNET_MODEL
  end

  def self.all_configs
    Rails.cache.fetch(CACHE_KEY, expires_in: 5.minutes) do
      where(feature_key: FEATURES.keys).pluck(:feature_key, :model_id).to_h
    end
  end

  def self.invalidate_cache!
    Rails.cache.delete(CACHE_KEY)
  end
end
