class Api::Learner::V1::MyFlashcardsController < Api::Learner::V1::BaseController
  GENERATE_COST = 3
  IMAGE_COST    = 5

  def index
    decks = FlashcardDeck.where(learner_id: current_learner.id).order(created_at: :desc)
    assignments = current_learner.flashcard_assignments
                    .where(flashcard_deck_id: decks.map(&:id))
                    .index_by(&:flashcard_deck_id)

    render json: decks.map { |deck|
      a = assignments[deck.id]
      {
        id: deck.id,
        title: deck.title,
        subject: deck.subject,
        card_count: deck.card_count,
        ai_generated: deck.ai_generated,
        image_generating: deck.image_generating,
        assignment_token: a&.token
      }
    }
  end

  def generate
    unless current_learner.credits >= GENERATE_COST
      return render json: { error: "Không đủ credits. Cần #{GENERATE_COST} credits để tạo bộ flashcard." },
                    status: :payment_required
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
             - Back: nghĩa tiếng Việt, Ví dụ: [câu ví dụ tiếng Anh]. ([nghĩa câu đó bằng tiếng Việt].)

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
        learner_id:   current_learner.id,
        title:        title,
        subject:      topic.truncate(100),
        ai_generated: true,
        card_count:   0
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
      deck_id:           deck.id,
      title:             deck.title,
      card_count:        deck.card_count,
      assignment_token:  assignment.token,
      credits_remaining: current_learner.reload.credits
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    deck       = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    assignment = current_learner.flashcard_assignments.find_by(flashcard_deck_id: deck.id)
    cards      = deck.flashcards.order(:position, :id)
    render json: {
      id:               deck.id,
      title:            deck.title,
      subject:          deck.subject,
      card_count:       deck.card_count,
      assignment_token: assignment&.token,
      cards:            cards.map { |c| { id: c.id, front: c.front, back: c.back, position: c.position } }
    }
  end

  def create_card
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    card = deck.flashcards.create!(
      front:    params[:front].to_s.strip.truncate(300),
      back:     params[:back].to_s.strip.truncate(600),
      position: deck.flashcards.count
    )
    deck.update_column(:card_count, deck.flashcards.count)
    render json: { id: card.id, front: card.front, back: card.back, position: card.position }
  end

  def update_card
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    card = deck.flashcards.find(params[:card_id])
    card.update!(
      front: params[:front].to_s.strip.truncate(300),
      back:  params[:back].to_s.strip.truncate(600)
    )
    render json: { id: card.id, front: card.front, back: card.back, position: card.position }
  end

  def destroy_card
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    card = deck.flashcards.find(params[:card_id])
    card.destroy!
    deck.update_column(:card_count, deck.flashcards.count)
    render json: { ok: true }
  end

  def destroy
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    deck.destroy!
    render json: { ok: true }
  end

  def generate_images
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    return render json: { error: "Không có thẻ nào." }, status: :unprocessable_entity if deck.flashcards.empty?

    if deck.image_generating?
      return render json: { pending: true }
    end

    unless current_learner.credits >= IMAGE_COST
      return render json: { error: "Không đủ credit. Cần #{IMAGE_COST} credits để tạo ảnh." },
                    status: :payment_required
    end

    deck.update!(image_generating: true)
    GenerateFlashcardImagesJob.perform_later(deck.id, nil)
    render json: { pending: true }
  rescue => e
    deck&.update(image_generating: false)
    render json: { error: e.message.truncate(120) }, status: :unprocessable_entity
  end

  def image_status
    deck = FlashcardDeck.find_by!(id: params[:id], learner_id: current_learner.id)
    if deck.image_generating?
      done  = deck.flashcards.where.not(image_data: [nil, ""]).count
      total = deck.flashcards.count
      render json: { pending: true, done: done, total: total }
    else
      render json: { pending: false, done: deck.flashcards.where.not(image_data: [nil, ""]).count,
                     total: deck.flashcards.count }
    end
  end

  private

  def extract_json(raw)
    raw.scan(/\{[\s\S]*?\}/).each do |candidate|
      parsed = JSON.parse(candidate)
      return parsed if parsed["cards"].is_a?(Array)
    rescue JSON::ParserError
      next
    end

    if (m = raw.match(/\{[\s\S]*"cards"[\s\S]*\}/))
      JSON.parse(m[0]) rescue {}
    else
      {}
    end
  end
end
