class LearnerSuggestionService
  include Rails.application.routes.url_helpers
  include Rails.application.routes.mounted_helpers

  TTL_HOURS       = 24
  ABANDON_DAYS    = 3
  DEADLINE_DAYS   = 3

  def initialize(learner)
    @learner = learner
  end

  def fetch
    existing = @learner.learner_suggestions.active.order(created_at: :desc).first
    return existing if existing
    generate_and_save
  end

  private

  def generate_and_save
    attrs = deadline_suggestion ||
            low_score_suggestion ||
            abandoned_suggestion ||
            ai_trending_suggestion

    return nil unless attrs

    @learner.learner_suggestions.create!(
      attrs.merge(expires_at: TTL_HOURS.hours.from_now)
    )
  rescue => e
    Rails.logger.error("[LearnerSuggestionService] #{e.message}")
    nil
  end

  # --- Rule 1: upcoming deadline ---
  def deadline_suggestion
    quiz = @learner.quiz_assignments
                   .includes(:quiz_set)
                   .where.not(status: :completed)
                   .where("due_at BETWEEN ? AND ?", Time.current, DEADLINE_DAYS.days.from_now)
                   .order(:due_at).first

    # learning_path_assignments use a `due_date` (date) column, not `due_at`
    path = @learner.learning_path_assignments
                   .includes(:learning_path)
                   .where.not(status: :completed)
                   .where("due_date BETWEEN ? AND ?", Date.current, DEADLINE_DAYS.days.from_now.to_date)
                   .order(:due_date).first

    quiz_due = quiz&.due_at
    path_due = path&.due_date&.to_time

    return nil if quiz_due.nil? && path_due.nil?

    use_quiz = path_due.nil? || (quiz_due && quiz_due <= path_due)

    if use_quiz
      days_left = ((quiz_due - Time.current) / 1.day).ceil
      days_str  = days_left <= 1 ? "hôm nay" : "#{days_left} ngày nữa"
      {
        kind:         "deadline",
        title:        "⏰ Deadline sắp đến",
        body:         "Quiz \"#{quiz.quiz_set.title}\" cần hoàn thành #{days_str}. Đừng để deadline trôi qua!",
        action_label: "Làm quiz ngay →",
        action_url:   take_learner_quiz_assignment_path(quiz.token),
        prefill_topic: nil
      }
    else
      days_left = (path.due_date - Date.current).to_i
      days_str  = days_left <= 0 ? "hôm nay" : "#{days_left} ngày nữa"
      {
        kind:         "deadline",
        title:        "⏰ Deadline sắp đến",
        body:         "Lộ trình \"#{path.learning_path.title}\" cần hoàn thành #{days_str}. Tiếp tục ngay nào!",
        action_label: "Tiếp tục →",
        action_url:   learner_learning_path_assignment_path(path.token),
        prefill_topic: nil
      }
    end
  end

  # --- Rule 2: low quiz score ---
  def low_score_suggestion
    # Scores live on QuizAttempt (matched by email), not QuizAssignment
    weak = QuizAttempt.where(participant_email: @learner.email)
                      .where.not(submitted_at: nil)
                      .includes(:quiz_set)
                      .select { |a| a.quiz_set && !a.passed? }
                      .min_by(&:score_pct)

    return nil unless weak

    topic = weak.quiz_set.title
    {
      kind:          "low_score",
      title:         "📉 Cần cải thiện",
      body:          "Bạn đạt #{weak.score_pct}% trong quiz \"#{topic}\" — chưa đạt yêu cầu. Hãy ôn lại kiến thức bằng flashcard AI!",
      action_label:  "Tạo flashcard ôn tập →",
      action_url:    "/learner/my_flashcards/new",
      prefill_topic: topic
    }
  end

  # --- Rule 3: abandoned content ---
  def abandoned_suggestion
    cutoff = ABANDON_DAYS.days.ago

    fc = @learner.flashcard_assignments
                 .includes(:flashcard_deck)
                 .where.not(status: :completed)
                 .where("updated_at < ?", cutoff)
                 .order(:updated_at).first

    lp = @learner.learning_path_assignments
                 .includes(:learning_path)
                 .where(status: :in_progress)
                 .where("updated_at < ?", cutoff)
                 .order(:updated_at).first

    if fc
      name = fc.flashcard_deck.title
      days = ((Time.current - fc.updated_at) / 1.day).round
      {
        kind:         "abandoned",
        title:        "😴 Bạn đang bỏ quên",
        body:         "Bộ flashcard \"#{name}\" chưa được ôn trong #{days} ngày. Chỉ cần 5 phút mỗi ngày là đủ!",
        action_label: "Ôn flashcard →",
        action_url:   study_learner_flashcard_assignment_path(fc.token),
        prefill_topic: nil
      }
    elsif lp
      name = lp.learning_path.title
      days = ((Time.current - lp.updated_at) / 1.day).round
      {
        kind:         "abandoned",
        title:        "😴 Bạn đang bỏ dở",
        body:         "Lộ trình \"#{name}\" chưa được tiếp tục trong #{days} ngày. Hãy hoàn thành bước tiếp theo!",
        action_label: "Tiếp tục →",
        action_url:   learner_learning_path_assignment_path(lp.token),
        prefill_topic: nil
      }
    end
  end

  # --- Rule 4: AI trending (no data) ---
  def ai_trending_suggestion
    prompt = <<~P
      You are a learning assistant. Suggest ONE trending and practical learning topic for a Vietnamese learner in #{Date.current.year}.
      Keep it concise and motivating. Reply in Vietnamese.

      Return ONLY valid JSON, no other text:
      {"topic":"<tên chủ đề ngắn gọn>","body":"<1-2 câu gợi ý hấp dẫn, nêu lợi ích thực tế>"}
    P

    svc  = ClaudeService.for_feature("ai_tutor", timeout: 20)
    raw  = svc.call(system_prompt: prompt, messages: [{ role: "user", content: "Suggest a topic." }], max_tokens: 150)
    data = JSON.parse(raw.match(/\{[\s\S]*\}/)[0])

    topic = data["topic"].to_s.strip
    body  = data["body"].to_s.strip
    return nil if topic.blank? || body.blank?

    {
      kind:          "ai_trending",
      title:         "✨ Gợi ý cho bạn",
      body:          body,
      action_label:  "Khám phá với Flashcard →",
      action_url:    "/learner/my_flashcards/new",
      prefill_topic: topic
    }
  rescue => e
    Rails.logger.warn("[LearnerSuggestionService] AI fallback failed: #{e.message}")
    {
      kind:          "ai_trending",
      title:         "✨ Mẹo học tập",
      body:          "Thử tạo bộ flashcard về một chủ đề bạn muốn cải thiện — chỉ mất 30 giây!",
      action_label:  "Tạo flashcard →",
      action_url:    "/learner/my_flashcards/new",
      prefill_topic: nil
    }
  end

  def default_url_options
    { host: "localhost" }
  end
end
