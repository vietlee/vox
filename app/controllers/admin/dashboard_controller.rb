class Admin::DashboardController < Admin::BaseController
  def index
    @workspace = current_workspace
    return redirect_to super_admin_root_path if @workspace.nil?
    @subscription = current_subscription
    ws = @workspace

    # ── Teacher KPIs ──────────────────────────────────────────────────────
    @classes_count = ws.learner_folders.count
    learner_ids = LearnerFolderMember.joins(:learner_folder)
                    .where(learner_folders: { workspace_id: ws.id })
                    .distinct.pluck(:learner_id)
    @learners_count  = learner_ids.size
    @active_learners = Learner.where(id: learner_ids)
                              .where("last_seen_at > ?", 7.days.ago).count

    @quiz_sets_count       = ws.quiz_sets.count
    @flashcard_decks_count = ws.flashcard_decks.count
    @learning_paths_count  = ws.learning_paths.count

    quiz_assign = QuizAssignment.joins(:quiz_set).where(quiz_sets: { workspace_id: ws.id }).count
    fc_assign   = FlashcardAssignment.joins(:flashcard_deck).where(flashcard_decks: { workspace_id: ws.id }).count
    lp_assign   = LearningPathAssignment.where(learning_path_id: ws.learning_paths.select(:id)).count
    @assignments_count = quiz_assign + fc_assign + lp_assign

    # ── My classes (unread class-chat per class computed in the view) ─────
    @classes = ws.learner_folders.order(:name).limit(6)

    # ── Recent learner submissions (graded quiz attempts) ─────────────────
    @recent_submissions = QuizAttempt.joins(:quiz_set)
                            .where(quiz_sets: { workspace_id: ws.id })
                            .where.not(submitted_at: nil)
                            .order(submitted_at: :desc).limit(6)

    # ── Recent content created (quiz + flashcard + learning path) ─────────
    recent = []
    ws.quiz_sets.order(created_at: :desc).limit(6).each do |q|
      recent << { type: :quiz, title: q.title, at: q.created_at, path: quiz_set_path(q) }
    end
    ws.flashcard_decks.order(created_at: :desc).limit(6).each do |d|
      recent << { type: :flashcard, title: d.title, at: d.created_at, path: flashcard_deck_path(d) }
    end
    ws.learning_paths.order(created_at: :desc).limit(6).each do |p|
      recent << { type: :path, title: p.title, at: p.created_at, path: learning_path_path(p) }
    end
    @recent_content = recent.sort_by { |c| c[:at] }.reverse.first(6)

    # ── Secondary engagement counts (small footer row) ────────────────────
    @surveys_count   = ws.surveys.count
    @votes_count     = ws.votes.count
    @feedbacks_count = Feedback.where(feedback_board_id: ws.feedback_board_ids).count
  end
end
