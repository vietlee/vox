class Learner::MyFlashcardsController < Learner::BaseController
  GENERATE_COST = 3
  IMAGE_COST    = 5

  def index
    @decks = FlashcardDeck.where(learner_id: current_learner.id).order(created_at: :desc)
  end

  def new
    @cost = GENERATE_COST
  end

  def show
    @deck       = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    @assignment = FlashcardAssignment.find_by(flashcard_deck: @deck, learner: current_learner)
    @image_cost = IMAGE_COST
  end

  # Generate AI illustrations for every card in the deck (5 credits)
  def generate_images
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    return render json: { error: "Không có thẻ nào." }, status: :unprocessable_entity if deck.flashcards.empty?
    # If already generating: just hand back the poll URL so the client can resume polling
    if deck.image_generating?
      return render json: { pending: true, poll_url: learner_image_status_my_flashcard_path(deck) }
    end
    unless current_learner.credits >= IMAGE_COST
      return render json: { error: "Không đủ credit. Cần #{IMAGE_COST} credits để tạo ảnh." }, status: :payment_required
    end

    deck.update!(image_generating: true)
    GenerateFlashcardImagesJob.perform_later(deck.id, nil)
    render json: { pending: true, poll_url: learner_image_status_my_flashcard_path(deck) }
  rescue => e
    deck&.update(image_generating: false)
    render json: { error: e.message.truncate(120) }, status: :unprocessable_entity
  end

  def image_status
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    if deck.image_generating?
      render json: { pending: true }
    else
      render json: { done: true, credits_remaining: current_learner.reload.credits }
    end
  end

  def destroy
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    deck.destroy!
    render json: { ok: true }
  end

  def generate
    unless current_learner.credits >= GENERATE_COST
      return render json: { error: "Không đủ credits. Cần #{GENERATE_COST} credits để tạo bộ flashcard." }, status: :payment_required
    end

    topic      = params[:topic].to_s.strip
    card_count = params[:card_count].to_i.clamp(5, 30)
    language   = params[:language].to_s.presence || "vi"

    return render json: { error: "Vui lòng nhập chủ đề." } if topic.blank?

    lang_instruction = language == "en" ? "Reply entirely in English." : "Trả lời bằng tiếng Việt."

    svc = ClaudeService.for_feature("ai_tutor", timeout: 60)
    raw = svc.call(
      system_prompt: "Bạn là chuyên gia tạo flashcard học tập. Chỉ trả về JSON hợp lệ, không giải thích thêm. #{lang_instruction}",
      messages: [{
        role: "user",
        content: <<~PROMPT
          Tạo #{card_count} flashcards cho chủ đề: "#{topic}".

          Hướng dẫn định dạng mặt trước/mặt sau (chọn phù hợp nhất với topic):

          1. Nếu người dùng yêu cầu rõ format "front: X, back: Y" trong topic, làm đúng theo đó.

          2. Nếu topic là TỪ VỰNG / VOCABULARY tiếng Anh (e.g. IELTS vocab, English words, từ vựng tiếng Anh):
             - Front: từ tiếng Anh + phiên âm IPA ngắn gọn, ví dụ: "commute /kəˈmjuːt/"
             - Back: nghĩa tiếng Việt + 1 ví dụ câu ngắn sử dụng từ đó

          3. Nếu topic là kiến thức học thuật (toán, lý, hóa, lịch sử, văn học...):
             - Front: câu hỏi hoặc khái niệm cốt lõi, ngắn gọn (tối đa 15 từ)
             - Back: đáp án/giải thích súc tích (1–3 câu, tối đa 60 từ)

          4. Đa dạng nội dung: định nghĩa, ví dụ, so sánh, câu hỏi ứng dụng.

          Trả về JSON theo đúng format này, không có text nào khác:
          {"title":"<tiêu đề ngắn gọn cho bộ thẻ>","cards":[{"front":"...","back":"..."}]}
        PROMPT
      }],
      max_tokens: 4000
    )

    parsed    = extract_json(raw)
    title     = parsed["title"].presence || topic.truncate(100)
    cards_arr = parsed["cards"] || []

    return render json: { error: "AI không trả về dữ liệu hợp lệ, vui lòng thử lại." } if cards_arr.empty?

    deck       = nil
    assignment = nil

    ActiveRecord::Base.transaction do
      deck = FlashcardDeck.create!(
        learner_id:    current_learner.id,
        title:         title,
        subject:       topic.truncate(100),
        ai_generated:  true,
        card_count:    0
      )

      cards_arr.each_with_index do |c, i|
        next if c["front"].blank? || c["back"].blank?
        deck.flashcards.create!(
          front:    c["front"].to_s.truncate(300),
          back:     c["back"].to_s.truncate(600),
          position: i
        )
      end

      count = deck.flashcards.count
      deck.update_column(:card_count, count)

      assignment = FlashcardAssignment.create!(
        flashcard_deck: deck,
        learner:        current_learner,
        assigned_by_id: nil,
        status:         :pending,
        token:          SecureRandom.urlsafe_base64(20)
      )

      current_learner.deduct_credits!(GENERATE_COST)
    end

    render json: {
      redirect_url:    learner_my_flashcard_path(deck.id),
      deck_id:         deck.id,
      title:           deck.title,
      card_count:      deck.card_count,
      credits_remaining: current_learner.reload.credits
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def extract_json(raw)
    raw.scan(/\{[\s\S]*?\}/).each do |candidate|
      parsed = JSON.parse(candidate)
      return parsed if parsed["cards"].is_a?(Array)
    rescue JSON::ParserError
      next
    end

    # Try broader match
    if (m = raw.match(/\{[\s\S]*"cards"[\s\S]*\}/))
      JSON.parse(m[0]) rescue {}
    else
      {}
    end
  end
end
