class Admin::FlashcardsController < Admin::BaseController
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
