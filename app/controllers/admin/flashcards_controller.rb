class Admin::FlashcardsController < Admin::BaseController
  def image
    deck = current_workspace.flashcard_decks.find(params[:flashcard_deck_id])
    card = deck.flashcards.find(params[:id])
    return head :not_found unless card.image_data.present?

    if card.image_data.to_s.lstrip.start_with?('<svg', '<SVG')
      expires_in 30.days, public: false
      render plain: card.image_data, content_type: "image/svg+xml"
    elsif card.image_data =~ /\Adata:(image\/[\w]+);base64,(.+)\z/m
      expires_in 7.days, public: false
      send_data Base64.decode64($2), type: $1, disposition: "inline"
    else
      head :not_found
    end
  end

  def update
    deck = current_workspace.flashcard_decks.find(params[:flashcard_deck_id])
    card = deck.flashcards.find(params[:id])

    attrs = {}
    attrs[:image_data] = params[:image_data] if params[:image_data].present?
    if params[:flashcard].present?
      attrs[:front] = params[:flashcard][:front] if params[:flashcard][:front].present?
      attrs[:back]  = params[:flashcard][:back]  if params[:flashcard][:back].present?
    end

    card.update!(attrs)
    render json: { ok: true }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not found" }, status: :not_found
  end
end
