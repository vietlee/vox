class Learner::DashboardController < Learner::BaseController
  CONTINUE_LIMIT = 5

  def index
    load_assignments

    @quiz_count      = @quiz_assignments.size
    @flashcard_count = @flashcard_assignments.size
    @path_count      = @path_assignments.size

    # Prioritized "Tiếp tục học" list (chỉ việc chưa xong, sắp xếp theo độ khẩn)
    @continue     = continue_items.first(CONTINUE_LIMIT)
    @active_total = continue_items.size

    # Gamification snapshot for the hero
    gam = LearnerGamification.new(current_learner)
    @streak           = current_learner.current_streak
    @xp               = current_learner.xp
    @daily_goal       = current_learner.daily_goal
    @activities_today = gam.activities_today
    @goal_met         = gam.goal_met_today?
    @activity_details = today_activity_details
  end

  # GET /learner/library — full catalog of all assigned/created content
  def library
    load_assignments
  end

  # GET /learner/suggestion/fetch — called via AJAX after page load
  def fetch_suggestion
    sug = current_learner.learner_suggestions.active.order(created_at: :desc).first
    sug ||= LearnerSuggestionService.new(current_learner).fetch

    if sug
      render json: {
        id:            sug.id,
        kind:          sug.kind,
        icon:          sug.icon,
        title:         sug.title,
        body:          sug.body,
        action_label:  sug.action_label,
        action_url:    sug.action_url,
        prefill_topic: sug.prefill_topic
      }
    else
      render json: { none: true }
    end
  end

  def dismiss_suggestion
    sug = current_learner.learner_suggestions.find_by(id: params[:id])
    sug&.update_column(:dismissed_at, Time.current)
    render json: { ok: true }
  end

  private

  def today_activity_details
    today = Date.current.beginning_of_day
    items = []

    quizzes = current_learner.quiz_assignments.includes(:quiz_set)
                .where('completed_at >= ?', today).where.not(completed_at: nil)
    quizzes.each do |a|
      items << { icon: '📝', label: a.quiz_set.title, kind: 'quiz',
                 url: learner_quiz_assignment_path(a.token) }
    end

    flashcards = current_learner.flashcard_assignments.includes(:flashcard_deck)
                   .where('updated_at >= ?', today).where('cards_reviewed > 0')
    flashcards.each do |a|
      items << { icon: '🃏', label: a.flashcard_deck.title, kind: 'flashcard',
                 url: study_learner_flashcard_assignment_path(a.token) }
    end

    speaking = current_learner.learner_speaking_sessions
                 .where('created_at >= ?', today).where('turns > 0')
    if speaking.any?
      items << { icon: '🗣️', label: "Luyện nói · #{speaking.sum(:turns)} lượt",
                 kind: 'speaking', url: learner_speaking_path }
    end

    plan_items = LearnerStudyPlanItem
                   .joins(:learner_study_plan)
                   .where(learner_study_plans: { learner_id: current_learner.id })
                   .where(done: true).where('done_at >= ?', today)
    plan_items.each do |item|
      items << { icon: '🧠', label: item.title, kind: 'plan',
                 url: learner_study_plans_path }
    end

    # Infer AI Tutor usage from remaining activity count
    accounted = quizzes.count + flashcards.count + speaking.sum(:turns) + plan_items.count
    tutor_count = [@activities_today - accounted, 0].max
    if tutor_count > 0
      items << { icon: '💬', label: "AI Tutor · #{tutor_count} tin nhắn",
                 kind: 'tutor', url: learner_ai_tutor_path }
    end

    items
  end

  def load_assignments
    @quiz_assignments      = current_learner.quiz_assignments.includes(:quiz_set).order(created_at: :desc)
    @flashcard_assignments = current_learner.flashcard_assignments.includes(:flashcard_deck).order(created_at: :desc)
    @path_assignments      = current_learner.learning_path_assignments.includes(:learning_path).order(created_at: :desc)
  end

  # Unified list of not-completed items across quiz / flashcard / path,
  # sorted: overdue first → soonest due → most recently updated.
  def continue_items
    @continue_items ||= begin
      far = 100.years.from_now
      items = []

      @quiz_assignments.reject(&:completed?).each do |a|
        due = a.due_at
        items << {
          type: :quiz, title: a.quiz_set.title,
          url: learner_quiz_assignment_path(a.token),
          cta: a.in_progress? ? "Tiếp tục" : "Bắt đầu",
          progress: a.progress_pct, due: due,
          overdue: a.respond_to?(:overdue?) && a.overdue?,
          sort: [due && due < Time.current ? 0 : 1, (due || far).to_i, -a.updated_at.to_i]
        }
      end

      @flashcard_assignments.reject(&:completed?).each do |a|
        items << {
          type: :flashcard, title: a.flashcard_deck.title,
          url: study_learner_flashcard_assignment_path(a.token),
          cta: a.cards_reviewed.to_i > 0 ? "Tiếp tục" : "Học ngay",
          progress: a.progress_pct, due: nil, overdue: false,
          sort: [1, far.to_i, -a.updated_at.to_i]
        }
      end

      @path_assignments.reject(&:completed?).each do |a|
        due = a.due_date&.to_time
        items << {
          type: :path, title: a.learning_path.title,
          url: learner_learning_path_assignment_path(a.token),
          cta: "Tiếp tục", progress: a.progress_pct, due: a.due_date,
          overdue: due && due < Time.current,
          sort: [due && due < Time.current ? 0 : 1, (due || far).to_i, -a.updated_at.to_i]
        }
      end

      items.sort_by { |i| i[:sort] }
    end
  end
  helper_method :continue_items
end
