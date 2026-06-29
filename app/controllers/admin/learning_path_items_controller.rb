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
      Viết nội dung bài học cho chủ đề: "#{item.title}"
      Thuộc lộ trình: #{@path.title} (lĩnh vực: #{subject})
      Thời lượng học: ~#{item.estimated_minutes} phút

      Yêu cầu định dạng:
      - Viết bằng tiếng Việt tự nhiên, không dùng tiêu đề lặp lại tên bài ở đầu
      - Bắt đầu thẳng vào nội dung (không mở đầu bằng "Trong bài này..." hay tiêu đề ## lại)
      - Dùng Markdown: heading ### cho từng phần, bullet - cho danh sách, **bold** cho điểm quan trọng
      - Cấu trúc: lý thuyết chính → ví dụ thực tế → điểm cần nhớ
      - Không lời chào, không giải thích thêm, chỉ nội dung bài học
    PROMPT

    svc = ClaudeService.new(model: ClaudeService::HAIKU_MODEL)
    content = svc.call(system_prompt: "Bạn là chuyên gia viết tài liệu học tập. Viết nội dung súc tích, tự nhiên, đúng trọng tâm.", user_prompt: prompt, max_tokens: 1500)
    current_workspace.credit_subscription&.deduct_credits!(2)
    html = ApplicationHelper::MARKDOWN.render(content)
    render json: { content: content, html: html }
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def set_path
    @path = current_workspace.learning_paths.find(params[:learning_path_id])
  end

  def item_params
    params.require(:learning_path_item).permit(:title, :content, :item_type, :estimated_minutes, :quiz_set_id, :flashcard_deck_id)
  end
end
