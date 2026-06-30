class Admin::LearningPathAssignmentsController < Admin::BaseController
  before_action :set_assignment

  def show
    @items = @assignment.learning_path.learning_path_items.includes(:quiz_set, :flashcard_deck).order(:position)
    @progresses = @assignment.learning_item_progresses.index_by(&:learning_path_item_id)
  end

  def update_progress
    item = @assignment.learning_path.learning_path_items.find(params[:item_id])
    progress = @assignment.learning_item_progresses.find_or_initialize_by(learning_path_item: item)
    progress.update!(status: params[:status], completed_at: params[:status].to_s == "completed" ? Time.current : nil)
    @assignment.reload
    pct  = @assignment.progress_pct
    done = @assignment.learning_item_progresses.completed.count
    @assignment.update!(status: :completed) if pct == 100 && @assignment.active?
    render json: { pct: pct, done_count: done }
  end

  def ai_evaluate
    items = @assignment.learning_path.learning_path_items.order(:position)
    done  = @assignment.learning_item_progresses.select(&:completed?).count
    pct   = @assignment.progress_pct

    return render json: { error: "Học viên chưa hoàn thành lộ trình (#{pct}%)." }, status: :unprocessable_entity if pct < 100

    item_details = items.map.with_index(1) do |it, i|
      prog = @assignment.learning_item_progresses.find { |p| p.learning_path_item_id == it.id }
      status = prog&.completed? ? "✓ Hoàn thành" : "✗ Chưa xong"
      "#{i}. #{it.title} (#{it.item_type}) — #{status}"
    end.join("\n")

    prompt = <<~PROMPT
      Bạn là chuyên gia đánh giá học tập cá nhân.

      **Học viên:** #{@assignment.assignee.name.presence || @assignment.assignee.email}
      **Lộ trình:** #{@assignment.learning_path.title}
      **Tiến độ:** #{done}/#{items.count} bài (#{pct}%)
      **Hạn nộp:** #{@assignment.due_date&.strftime("%d/%m/%Y") || "Không có"}

      **Chi tiết từng bài:**
      #{item_details}

      Hãy viết nhận xét cá nhân cho học viên này bằng tiếng Việt theo 3 phần:

      ## Kết quả học tập
      Đánh giá tổng quan quá trình hoàn thành lộ trình của học viên.

      ## Điểm nổi bật
      Những điểm tích cực trong quá trình học, những bài đã hoàn thành tốt.

      ## Hướng phát triển tiếp theo
      2-3 gợi ý cụ thể để học viên tiếp tục phát triển sau khi hoàn thành lộ trình này.

      Viết thân thiện, khích lệ, cá nhân hóa với tên học viên. Bằng tiếng Việt. Không dùng LaTeX.
    PROMPT

    return unless require_credits!(2)
    svc    = ClaudeService.for_feature("learning_path_eval", timeout: 120)
    result = svc.call(system_prompt: "Bạn là chuyên gia đánh giá học tập. Viết nhận xét cá nhân, thân thiện bằng tiếng Việt, dùng markdown.", user_prompt: prompt, max_tokens: 900)
    html   = markdown_to_html(result)
    current_workspace.credit_subscription.deduct_credits!(2)
    @assignment.update_columns(ai_feedback: html, ai_feedback_at: Time.current)
    render json: { html: html }
  end

  def destroy
    @assignment.destroy
    redirect_to learning_path_path(@assignment.learning_path), notice: "Đã hủy giao."
  end

  private

  def set_assignment
    @assignment = LearningPathAssignment.joins(:learning_path)
                    .where(learning_paths: { workspace: current_workspace })
                    .find(params[:id])
    authorize_assignment!
  end

  def authorize_assignment!
    return if current_workspace_admin? || @assignment.assignee == current_user
    redirect_to dashboard_path, alert: "Không có quyền."
  end
end
