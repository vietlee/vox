class Api::Learner::V1::FlashcardsController < Api::Learner::V1::BaseController
  # The image is streamed as a plain, cacheable URL so the study/detail JSON no
  # longer has to embed a huge base64 blob for every card (which made those
  # screens slow to load). Authorized either by the logged-in owner or by the
  # deck's assignment token (query param) — so a cookie-less <img>/Image.network
  # fetch works and the browser/OS can cache it.
  skip_before_action :authenticate_learner!, only: [:image]
  skip_before_action :touch_last_seen!,      only: [:image]

  def image
    card = Flashcard.find_by(id: params[:id])
    return head :not_found unless card

    token = params[:token].to_s
    authorized =
      (current_learner && card.flashcard_deck.learner_id == current_learner.id) ||
      (token.present? && FlashcardAssignment.exists?(token: token, flashcard_deck_id: card.flashcard_deck_id))
    return head :forbidden unless authorized

    data = card.image_data.to_s
    return head :not_found if data.blank?

    if data.start_with?("data:")
      meta, b64 = data.split(",", 2)
      content_type = meta[/data:([^;]+)/, 1] || "image/webp"
      bytes = Base64.decode64(b64.to_s)
      bytes = ImageThumbnailer.resize(bytes, params[:w]) || bytes  # optional ?w= downscale
      response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
      send_data bytes, type: content_type, disposition: "inline"
    elsif data.start_with?("http")
      redirect_to data, allow_other_host: true
    else
      head :not_found
    end
  end
end
