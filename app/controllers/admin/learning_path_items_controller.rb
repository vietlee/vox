class Admin::LearningPathItemsController < Admin::BaseController
  before_action :set_path

  def create
    item = @path.learning_path_items.create!(item_params.merge(position: @path.learning_path_items.count))
    render json: { id: item.id, title: item.title, item_type: item.item_type }
  end

  def update
    item = @path.learning_path_items.find(params[:id])
    item.update!(item_params)
    render json: { ok: true }
  end

  def destroy
    @path.learning_path_items.find(params[:id]).destroy
    render json: { ok: true }
  end

  def reorder
    params[:order].each_with_index { |id, i| @path.learning_path_items.find_by(id: id)&.update_columns(position: i) }
    render json: { ok: true }
  end

  def ai_content
    item = @path.learning_path_items.find(params[:id])
    return render json: { error: "Chỉ dùng cho bài học" }, status: :unprocessable_entity unless item.lesson?
    return unless require_credits!(2)

    subject = @path.subject.presence || @path.title
    prompt = <<~PROMPT
      Bạn là giáo viên chuyên nghiệp. Hãy viết nội dung bài học cho:
      - Lộ trình: #{@path.title}
      - Môn học / lĩnh vực: #{subject}
      - Tên bài: #{item.title}

      Yêu cầu:
      - Viết bằng tiếng Việt, rõ ràng, dễ hiểu
      - Độ dài phù hợp với #{item.estimated_minutes} phút học
      - Dùng định dạng Markdown (heading ##, bullet -, bold **text**)
      - Bao gồm: phần lý thuyết chính, ví dụ minh họa, điểm ghi nhớ
      - Không cần lời chào hay giải thích, chỉ trả về nội dung bài học
    PROMPT

    svc = ClaudeService.new(model: ClaudeService::HAIKU_MODEL)
    content = svc.chat([{ role: "user", content: prompt }], max_tokens: 1500)
    current_workspace.credit_subscription&.deduct_credits!(2)
    render json: { content: content }
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def set_path
    @path = current_workspace.learning_paths.find(params[:learning_path_id])
  end

  def item_params
    params.require(:learning_path_item).permit(:title, :content, :item_type, :estimated_minutes, :quiz_set_id)
  end
end
