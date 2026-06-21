class Admin::FlashcardDecksController < Admin::BaseController
  before_action :set_deck, only: [:show, :edit, :update, :destroy, :ai_generate, :study, :review]

  def index
    @decks = current_workspace.flashcard_decks.includes(:created_by).order(created_at: :desc)
  end

  def new; @deck = FlashcardDeck.new; end

  def create
    @deck = current_workspace.flashcard_decks.new(deck_params.merge(created_by: current_user))
    if @deck.save
      redirect_to flashcard_deck_path(@deck)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @cards = @deck.flashcards
  end

  def edit; end

  def update
    @deck.update!(deck_params)
    redirect_to flashcard_deck_path(@deck), notice: "Đã cập nhật."
  end

  def destroy
    @deck.destroy
    redirect_to flashcard_decks_path, notice: "Đã xóa."
  end

  def ai_generate
    require_credits!(3)
    topic = params[:topic].to_s.strip.presence || @deck.title
    count = (params[:count].to_i.clamp(5, 30))
    svc = ClaudeService.for_feature("quiz_generate", timeout: 120)
    raw = svc.call(
      system_prompt: "Tạo flashcard học tập. Trả về JSON hợp lệ. Ngắn gọn, dễ nhớ.",
      user_prompt: "Tạo #{count} flashcards cho chủ đề: \"#{topic}\".\nJSON: {\"cards\":[{\"front\":\"Câu hỏi/khái niệm\",\"back\":\"Định nghĩa/đáp án ngắn gọn\"},...]}\nMặt trước: câu hỏi hoặc khái niệm. Mặt sau: đáp án/giải thích ngắn (1-3 câu).",
      max_tokens: 3000
    )
    data = JSON.parse(raw.match(/\{.*\}/m)&.to_s || raw)
    cards = data["cards"] || []
    ActiveRecord::Base.transaction do
      cards.each_with_index { |c, i| @deck.flashcards.create!(front: c["front"], back: c["back"], position: @deck.flashcards.count + i) }
      @deck.update!(ai_generated: true, card_count: @deck.flashcards.count)
    end
    deduct_credits!(3)
    redirect_to flashcard_deck_path(@deck), notice: "AI đã tạo #{cards.size} thẻ."
  rescue => e
    redirect_to flashcard_deck_path(@deck), alert: "Lỗi: #{e.message.truncate(100)}"
  end

  def study
    @cards = @deck.flashcards.order(:position)
    @reviews = FlashcardReview.where(flashcard: @cards, user: current_user).index_by(&:flashcard_id)
    # Ưu tiên thẻ đến hạn ôn
    due = @cards.joins(:flashcard_reviews).where(flashcard_reviews: { user: current_user }).where("flashcard_reviews.next_review_at <= ?", Time.current)
    new_cards = @cards.where.not(id: FlashcardReview.where(user: current_user).select(:flashcard_id))
    @study_cards = (due + new_cards).first(20)
    @study_cards = @cards.first(20) if @study_cards.empty?
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

  private

  def set_deck
    @deck = current_workspace.flashcard_decks.find(params[:id])
  end

  def deck_params
    params.require(:flashcard_deck).permit(:title, :subject)
  end
end
