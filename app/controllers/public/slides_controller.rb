class Public::SlidesController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  layout 'public_slide'

  def show
    @outline = ContentOutline.find_by!(share_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render plain: 'Slide không tồn tại hoặc đã bị xóa.', status: :not_found
  end
end
