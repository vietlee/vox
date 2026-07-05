class Admin::FlashcardDecksController < Admin::BaseController
  before_action :set_deck, only: [:show, :edit, :update, :destroy, :ai_generate, :ai_status, :generate_images, :image_status, :study, :review, :analytics, :assign_learner, :learner_assignments, :remove_assignment]

  def index
    @decks = current_workspace.flashcard_decks.includes(:created_by).order(created_at: :desc)
  end

  def new
    @deck = FlashcardDeck.new(title: params[:title], subject: params[:subject])
  end

  def create
    @deck = current_workspace.flashcard_decks.new(deck_params.merge(created_by: current_user))
    if @deck.save
      if (src = params[:source_text].to_s.strip).present?
        return unless require_credits!(3)
        @deck.update!(ai_generating: true)
        GenerateFlashcardsJob.perform_later(@deck.id, src.truncate(8000), 15, current_user.id)
        redirect_to flashcard_deck_path(@deck), notice: "Bộ thẻ đã tạo — AI đang sinh thẻ từ tài liệu..."
      else
        redirect_to flashcard_deck_path(@deck)
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @cards = @deck.flashcards
  end

  def edit; end

  def update
    if @deck.update(deck_params)
      redirect_to flashcard_deck_path(@deck), notice: "Đã cập nhật."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @deck.destroy
    redirect_to flashcard_decks_path, notice: "Đã xóa."
  end

  def ai_status
    if @deck.ai_generating?
      render json: { pending: true }
    elsif @deck.ai_generated? && @deck.card_count.to_i > 0
      render json: { success: true, redirect: flashcard_deck_path(@deck) }
    else
      render json: { failed: true, error: "AI gặp lỗi khi tạo thẻ. Vui lòng thử lại." }
    end
  end

  def ai_generate
    require_credits!(3)
    topic = params[:topic].to_s.strip.presence || @deck.title
    count = params[:count].to_i.clamp(5, 30)
    @deck.update!(ai_generating: true)
    GenerateFlashcardsJob.perform_later(@deck.id, topic, count, current_user.id)
    respond_to do |format|
      format.json { render json: { pending: true, poll_url: ai_status_flashcard_deck_path(@deck, format: :json), show_url: flashcard_deck_path(@deck) } }
      format.html { redirect_to flashcard_deck_path(@deck) }
    end
  rescue => e
    @deck.update(ai_generating: false)
    respond_to do |format|
      format.json { render json: { error: e.message.truncate(100) }, status: :unprocessable_entity }
      format.html { redirect_to flashcard_deck_path(@deck), alert: "Lỗi: #{e.message.truncate(100)}" }
    end
  end

  def generate_images
    return render json: { error: "Không có thẻ nào" }, status: :unprocessable_entity if @deck.flashcards.empty?
    return render json: { error: "Đang xử lý" }, status: :unprocessable_entity if @deck.image_generating?

    require_credits!(5)
    @deck.update!(image_generating: true)
    GenerateFlashcardImagesJob.perform_later(@deck.id, current_user.id)

    render json: {
      pending: true,
      poll_url: image_status_flashcard_deck_path(@deck, format: :json),
      show_url: flashcard_deck_path(@deck)
    }
  rescue => e
    @deck.update(image_generating: false)
    render json: { error: e.message.truncate(100) }, status: :unprocessable_entity
  end

  def image_status
    if @deck.image_generating?
      render json: { pending: true }
    else
      render json: { success: true, redirect: flashcard_deck_path(@deck) }
    end
  end

  def analytics
    card_ids = @deck.flashcards.pluck(:id)
    reviews  = FlashcardReview.where(flashcard_id: card_ids)

    @total_reviews   = reviews.count
    @unique_learners = reviews.distinct.count(:user_id)
    good_or_easy     = reviews.where(rating: [2, 3]).count
    @mastery_rate    = @total_reviews > 0 ? (good_or_easy.to_f / @total_reviews * 100).round : 0

    # Per-card stats
    review_counts  = reviews.group(:flashcard_id).count
    avg_eases      = reviews.group(:flashcard_id).average(:ease_factor)
    hard_counts    = reviews.where(rating: [0, 1]).group(:flashcard_id).count
    mastered_counts= reviews.where(rating: [2, 3]).group(:flashcard_id).count

    @cards_with_stats = @deck.flashcards.map do |card|
      {
        card:           card,
        review_count:   review_counts[card.id] || 0,
        avg_ease:       avg_eases[card.id]&.round(2) || 0,
        hard_count:     hard_counts[card.id] || 0,
        mastered_count: mastered_counts[card.id] || 0
      }
    end.sort_by { |s| -s[:hard_count] }

    # Daily activity — last 14 days
    daily_raw = FlashcardReview
      .where(flashcard: @deck.flashcards)
      .where(created_at: 14.days.ago..Time.current)
      .group("DATE(created_at)")
      .count
    # Build full 14-day array with zeros for missing days
    @daily_activity = (13.downto(0)).map do |n|
      date = n.days.ago.to_date
      { date: date, count: daily_raw[date.to_s] || 0 }
    end

    # Per-learner stats
    user_ids = reviews.distinct.pluck(:user_id)
    users    = User.where(id: user_ids).index_by(&:id)
    learner_totals   = reviews.group(:user_id).count
    learner_mastered = reviews.where(rating: [2, 3]).group(:user_id).count
    learner_last     = reviews.group(:user_id).maximum(:created_at)

    @learner_stats = user_ids.map do |uid|
      user = users[uid]
      next unless user
      {
        user:          user,
        total_reviews: learner_totals[uid] || 0,
        mastered:      learner_mastered[uid] || 0,
        last_reviewed: learner_last[uid]
      }
    end.compact.sort_by { |s| -s[:total_reviews] }
  end

  def study
    @cards   = @deck.flashcards.order(:position)
    @reviews = FlashcardReview.where(flashcard: @cards, user: current_user).index_by(&:flashcard_id)

    # Due cards: most overdue first
    due = @cards
            .joins(:flashcard_reviews)
            .where(flashcard_reviews: { user: current_user })
            .where("flashcard_reviews.next_review_at <= ?", Time.current)
            .order("flashcard_reviews.next_review_at ASC")

    # New cards: never reviewed, in deck order
    new_cards = @cards.where.not(id: FlashcardReview.where(user: current_user).select(:flashcard_id))

    @study_cards = (due.to_a + new_cards.to_a).first(20)

    # Pass review data to view so JS can show accurate next intervals
    @review_map = @reviews.transform_values { |r| { interval: r.interval_days, ease: r.ease_factor } }
  end

  def review
    card = @deck.flashcards.find(params[:card_id])
    rating = params[:rating].to_i.clamp(0, 3)
    rev = FlashcardReview.find_or_initialize_by(flashcard: card, user: current_user)
    ef = rev.ease_factor || 2.5
    interval = rev.interval_days || 1
    new_ef, _, new_interval = Flashcard.next_interval(rating, ef, interval)
    rev.update!(rating: rating, ease_factor: [1.3, new_ef].max, interval_days: new_interval, next_review_at: Time.current + new_interval.days)
    render json: { ok: true, next_days: new_interval }
  end

  def assign_learner
    learner_ids = Array(params[:learner_ids]).map(&:to_i).uniq
    due_at      = params[:due_at].presence

    if learner_ids.empty?
      redirect_to flashcard_deck_path(@deck), alert: "Vui lòng chọn ít nhất một learner."; return
    end

    learners = current_workspace.learner_folders.joins(:learner_folder_members).includes(learner_folder_members: :learner)
                 .flat_map(&:learners).uniq.select { |l| learner_ids.include?(l.id) }
    assigned = 0; skipped = 0

    learners.each do |learner|
      next if FlashcardAssignment.exists?(flashcard_deck: @deck, learner: learner)
      assignment = FlashcardAssignment.create!(flashcard_deck: @deck, learner: learner, assigned_by: current_user, due_at: due_at)
      url = Rails.application.routes.url_helpers.learner_flashcard_assignment_url(
        assignment, token: assignment.token,
        host: Rails.application.config.action_mailer.default_url_options[:host]
      )
      LearnerMailer.assignment_notification(learner, "Flashcard", @deck.title, url).deliver_later
      assigned += 1
    rescue => e
      skipped += 1
    end

    msg = "Đã giao cho #{assigned} learner."
    msg += " Bỏ qua #{skipped} lỗi." if skipped > 0
    redirect_to flashcard_deck_path(@deck), notice: msg
  end

  def learner_assignments
    @assignments = @deck.flashcard_assignments.includes(:learner).order(created_at: :desc)
    render json: @assignments.map { |a|
      { id: a.id, learner_id: a.learner_id, email: a.learner.email, name: a.learner.name, status: a.status, due_at: a.due_at }
    }
  end

  def remove_assignment
    assignment = @deck.flashcard_assignments.find(params[:assignment_id])
    assignment.destroy!
    render json: { ok: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_deck
    @deck = current_workspace.flashcard_decks.find(params[:id])
  end

  def deck_params
    params.require(:flashcard_deck).permit(:title, :subject)
  end
end
