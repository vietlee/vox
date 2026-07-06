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
      days_str  = days_left <= 1 ? I18n.t('learner_suggestions.days_today') : I18n.t('learner_suggestions.days_remaining', n: days_left)
      {
        kind:         "deadline",
        title:        I18n.t('learner_suggestions.deadline_title'),
        body:         I18n.t('learner_suggestions.deadline_quiz_body', title: quiz.quiz_set.title, days_str: days_str),
        action_label: I18n.t('learner_suggestions.deadline_quiz_action'),
        action_url:   take_learner_quiz_assignment_path(quiz.token),
        prefill_topic: nil
      }
    else
      days_left = (path.due_date - Date.current).to_i
      days_str  = days_left <= 0 ? I18n.t('learner_suggestions.days_today') : I18n.t('learner_suggestions.days_remaining', n: days_left)
      {
        kind:         "deadline",
        title:        I18n.t('learner_suggestions.deadline_title'),
        body:         I18n.t('learner_suggestions.deadline_path_body', title: path.learning_path.title, days_str: days_str),
        action_label: I18n.t('learner_suggestions.deadline_path_action'),
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
      title:         I18n.t('learner_suggestions.low_score_title'),
      body:          I18n.t('learner_suggestions.low_score_body', pct: weak.score_pct, title: topic),
      action_label:  I18n.t('learner_suggestions.low_score_action'),
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
        title:        I18n.t('learner_suggestions.abandoned_fc_title'),
        body:         I18n.t('learner_suggestions.abandoned_fc_body', title: name, days: days),
        action_label: I18n.t('learner_suggestions.abandoned_fc_action'),
        action_url:   study_learner_flashcard_assignment_path(fc.token),
        prefill_topic: nil
      }
    elsif lp
      name = lp.learning_path.title
      days = ((Time.current - lp.updated_at) / 1.day).round
      {
        kind:         "abandoned",
        title:        I18n.t('learner_suggestions.abandoned_lp_title'),
        body:         I18n.t('learner_suggestions.abandoned_lp_body', title: name, days: days),
        action_label: I18n.t('learner_suggestions.abandoned_lp_action'),
        action_url:   learner_learning_path_assignment_path(lp.token),
        prefill_topic: nil
      }
    end
  end

  # --- Rule 4: AI trending (no data) ---
  def ai_trending_suggestion
    reply_lang = I18n.locale == :en ? "English" : "Vietnamese"
    prompt = <<~P
      You are a learning assistant. Suggest ONE trending and practical learning topic for a learner in #{Date.current.year}.
      Keep it concise and motivating. Reply in #{reply_lang}.

      Return ONLY valid JSON, no other text:
      {"topic":"<short topic name>","body":"<1-2 motivating sentences highlighting practical benefits>"}
    P

    svc  = ClaudeService.for_feature("ai_tutor", timeout: 20)
    raw  = svc.call(system_prompt: prompt, messages: [{ role: "user", content: "Suggest a topic." }], max_tokens: 150)
    data = JSON.parse(raw.match(/\{[\s\S]*\}/)[0])

    topic = data["topic"].to_s.strip
    body  = data["body"].to_s.strip
    return nil if topic.blank? || body.blank?

    {
      kind:          "ai_trending",
      title:         I18n.t('learner_suggestions.trending_title'),
      body:          body,
      action_label:  I18n.t('learner_suggestions.trending_action'),
      action_url:    "/learner/my_flashcards/new",
      prefill_topic: topic
    }
  rescue => e
    Rails.logger.warn("[LearnerSuggestionService] AI fallback failed: #{e.message}")
    {
      kind:          "ai_trending",
      title:         I18n.t('learner_suggestions.fallback_title'),
      body:          I18n.t('learner_suggestions.fallback_body'),
      action_label:  I18n.t('learner_suggestions.fallback_action'),
      action_url:    "/learner/my_flashcards/new",
      prefill_topic: nil
    }
  end

  def default_url_options
    { host: "localhost" }
  end
end
