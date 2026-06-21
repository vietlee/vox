class Admin::FlashcardsController < Admin::BaseController
  def update
    deck = current_workspace.flashcard_decks.find(params[:flashcard_deck_id])
    card = deck.flashcards.find(params[:id])
    card.update!(image_data: params[:image_data])
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not found" }, status: :not_found
  end
end
