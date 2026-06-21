class Admin::ContentOutlinesController < Admin::BaseController
  before_action :set_outline, only: [:show, :destroy, :regenerate]

  def index
    @outlines = current_workspace.content_outlines.includes(:created_by).order(created_at: :desc)
  end

  def new
    @outline = ContentOutline.new
  end

  def create
    @outline = current_workspace.content_outlines.new(outline_params.merge(created_by: current_user, status: :pending))
    @outline.save!
    GenerateContentOutlineJob.perform_later(@outline.id)
    redirect_to content_outline_path(@outline)
  rescue => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def show; end

  def regenerate
    @outline.update!(status: :pending, content: nil)
    GenerateContentOutlineJob.perform_later(@outline.id)
    redirect_to content_outline_path(@outline)
  end

  def destroy
    @outline.destroy
    redirect_to content_outlines_path, notice: "Đã xóa."
  end

  private

  def set_outline
    @outline = current_workspace.content_outlines.find(params[:id])
  end

  def outline_params
    params.require(:content_outline).permit(:title, :subject, :output_type, :prompt_input)
  end

end
