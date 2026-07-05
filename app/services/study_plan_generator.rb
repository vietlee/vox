# Builds a personalized, adaptive study plan from a learner's performance data.
class StudyPlanGenerator
  include Rails.application.routes.url_helpers

  def initialize(learner, extra: nil)
    @learner = learner
    @extra   = extra.to_s.strip
  end

  def generate!
    context = build_context
    raw     = call_ai(context)
    data    = parse(raw)

    title = data["title"].presence || "Lộ trình cải thiện của bạn"
    items = Array(data["items"]).first(6)
    raise "AI không trả về lộ trình hợp lệ" if items.empty?

    plan = @learner.learner_study_plans.create!(
      title:  title.truncate(120),
      focus:  data["focus"].to_s.truncate(500),
      status: :active
    )

    items.each_with_index do |it, i|
      kind  = %w[flashcard quiz tutor read].include?(it["kind"]) ? it["kind"] : "read"
      topic = it["topic"].to_s.truncate(120)
      plan.items.create!(
        position:    i,
        kind:        kind,
        title:       it["title"].to_s.truncate(150),
        description: it["description"].to_s.truncate(400),
        topic:       topic,
        action_url:  action_url_for(kind, topic)
      )
    end

    plan
  end

  private

  def action_url_for(kind, topic)
    case kind
    when "flashcard" then "/learner/my_flashcards/new?topic=#{CGI.escape(topic)}"
    when "tutor"     then "/learner/tutor?context=#{CGI.escape(topic)}"
    else nil
    end
  end

  def build_context
    # Quiz results — scores live on QuizAttempt (matched by email), not QuizAssignment
    weak = QuizAttempt.where(participant_email: @learner.email)
                      .where.not(submitted_at: nil)
                      .includes(:quiz_set)
                      .order(:submitted_at).to_a.reverse.uniq(&:quiz_set_id).map do |a|
      next unless a.quiz_set
      "Quiz '#{a.quiz_set.title}': #{a.score_pct}%#{a.quiz_set.passing_score ? " (cần #{a.quiz_set.passing_score}%)" : ""}"
    end.compact

    fc = @learner.flashcard_assignments.includes(:flashcard_deck).map do |fa|
      next unless fa.flashcard_deck
      "Flashcard '#{fa.flashcard_deck.title}': #{fa.progress_pct}% hoàn thành"
    end.compact

    lines = []
    lines << "Kết quả quiz:\n#{weak.join("\n")}" if weak.any?
    lines << "Flashcard:\n#{fc.join("\n")}" if fc.any?
    lines.join("\n\n").presence || "Học viên chưa có nhiều dữ liệu học tập."
  end

  def call_ai(context)
    prompt = <<~P
      Bạn là cố vấn học tập AI. Dựa trên dữ liệu học tập của học viên, hãy tạo một lộ trình cải thiện gồm 4–6 bước cụ thể, có thứ tự hợp lý (ôn kiến thức yếu trước, luyện tập, kiểm tra lại).

      Mỗi bước phải có "kind" là một trong:
      - "flashcard": ôn tập bằng bộ thẻ AI về một chủ đề
      - "tutor": hỏi AI Tutor để hiểu sâu một khái niệm
      - "quiz": làm lại/luyện quiz
      - "read": đọc/tự ôn một nội dung

      Trả về DUY NHẤT JSON hợp lệ, không giải thích:
      {
        "title": "<tiêu đề lộ trình ngắn gọn>",
        "focus": "<1-2 câu tóm tắt lộ trình này tập trung vào điều gì>",
        "items": [
          {"kind":"flashcard","title":"<tên bước>","description":"<mô tả ngắn>","topic":"<chủ đề để tạo thẻ/hỏi>"}
        ]
      }
    P

    user_msg = "Dữ liệu học viên:\n#{context}"
    user_msg += "\n\nMong muốn/yêu cầu riêng của học viên (ưu tiên bám sát): #{@extra.truncate(500)}" if @extra.present?
    user_msg += "\n\nHãy tạo lộ trình bằng tiếng Việt."

    svc = ClaudeService.for_feature("ai_tutor", timeout: 45)
    svc.call(
      system_prompt: prompt,
      messages: [{ role: "user", content: user_msg }],
      max_tokens: 1500
    )
  end

  def parse(raw)
    m = raw.match(/\{[\s\S]*\}/)
    m ? JSON.parse(m[0]) : {}
  rescue JSON::ParserError
    {}
  end
end
