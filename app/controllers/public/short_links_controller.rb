class Public::ShortLinksController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    sl = ShortLink.find_by(code: params[:code])
    if sl
      sl.increment_clicks!
      redirect_to sl.target_url, allow_other_host: true, status: :moved_permanently
    else
      render plain: "Link not found", status: :not_found
    end
  end
end
