class Learner::FlashcardsController < Learner::BaseController
  def image
    card = Flashcard.find(params[:id])
    deck = card.flashcard_deck

    authorized = deck.learner_id == current_learner.id ||
                 FlashcardAssignment.exists?(flashcard_deck: deck, learner: current_learner)

    unless authorized
      head :not_found and return
    end

    unless card.image_data.present?
      head :not_found and return
    end

    if card.image_data.to_s.lstrip.start_with?('<svg', '<SVG')
      expires_in 30.days, public: false
      render plain: card.image_data, content_type: "image/svg+xml"
    elsif card.image_data =~ /\Adata:(image\/[\w]+);base64,(.+)\z/m
      mime_type   = $1
      binary_data = Base64.decode64($2)
      expires_in 7.days, public: false
      send_data binary_data, type: mime_type, disposition: "inline"
    else
      head :not_found
    end
  end
end
