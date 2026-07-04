class Admin::LearningPathsController < Admin::BaseController
  before_action :set_path, only: [:show, :edit, :update, :destroy, :publish, :ai_generate, :ai_status, :assign, :progress, :ai_evaluate_progress]

  def index
    @learning_paths = current_workspace.learning_paths.includes(:created_by, :learning_path_items, :learning_path_assignments).order(created_at: :desc)
    # Assignments cho current_user — từ mọi workspace (kể cả workspace đã rời)
    @my_assignments = LearningPathAssignment
                        .where(assignee: current_user)
                        .joins(:learning_path)
                        .includes(:learning_path)
                        .order(created_at: :desc)
  end

  def new
    @learning_path = LearningPath.new
  end

  def create
    @learning_path = current_workspace.learning_paths.new(path_params.merge(created_by: current_user))
    if @learning_path.save
      redirect_to learning_path_path(@learning_path), notice: "Đã tạo lộ trình."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @items = @learning_path.learning_path_items.includes(:quiz_set, :flashcard_deck).order(:position)
    @assignments = @learning_path.learning_path_assignments.includes(:assignee, :learning_item_progresses, learning_path: :learning_path_items)
    @my_assignment = @assignments.find_by(assignee: current_user)
    @workspace_members = accessible_workspace_members
    @quiz_sets = current_workspace.quiz_sets.published.order(:title)
    @flashcard_decks = current_workspace.flashcard_decks.order(:title)
  end

  def edit; end

  def update
    if @learning_path.update(path_params)
      redirect_to learning_path_path(@learning_path), notice: "Đã cập nhật."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @learning_path.destroy
    redirect_to learning_paths_path, notice: "Đã xóa."
  end

  def publish
    @learning_path.update!(status: :published)
    redirect_to learning_path_path(@learning_path), notice: "Đã phát hành."
  end

  def ai_status
    if @learning_path.ai_generating?
      render json: { pending: true }
    else
      render json: { success: true, redirect: learning_path_path(@learning_path) }
    end
  end

  def ai_generate
    require_credits!(5)
    prompt = params[:prompt].to_s.strip

    @learning_path.update!(ai_generating: true)
    GenerateLearningPathJob.perform_later(@learning_path.id, prompt)
    redirect_to learning_path_path(@learning_path), notice: "AI đang tạo lộ trình, vui lòng chờ..."
  rescue => e
    @learning_path.update(ai_generating: false)
    redirect_to learning_path_path(@learning_path), alert: "Lỗi: #{e.message.truncate(100)}"
  end

  def progress
    @items = @learning_path.learning_path_items.order(:position)
    @assignments = @learning_path.learning_path_assignments
                     .includes(:assignee, :learning_item_progresses, learning_path: :learning_path_items)
                     .order(created_at: :desc)
  end

  def ai_evaluate_progress
    assignments = @learning_path.learning_path_assignments
                    .includes(:assignee, :learning_item_progresses)
    items = @learning_path.learning_path_items.order(:position)

    total    = assignments.count
    not_done = assignments.count { |a| a.progress_pct < 100 }

    return render json: { error: "Còn #{not_done} học viên chưa hoàn thành." }, status: :unprocessable_entity if not_done > 0
    return render json: { error: "Chưa có học viên nào." }, status: :unprocessable_entity if total == 0

    avg_pct = (assignments.sum(&:progress_pct) / total.to_f).round

    student_summaries = assignments.map do |a|
      done = a.learning_item_progresses.select(&:completed?).count
      "- #{a.assignee.name.presence || a.assignee.email}: #{done}/#{items.count} bài (#{a.progress_pct}%)"
    end.join("\n")

    prompt = <<~PROMPT
      Bạn là chuyên gia phân tích kết quả học tập.

      **Lộ trình học:** #{@learning_path.title}
      **Mô tả:** #{@learning_path.description.presence || "Không có"}
      **Tổng số bài:** #{items.count}
      **Số học viên:** #{total} — tất cả đã hoàn thành
      **Tiến độ trung bình:** #{avg_pct}%

      **Kết quả từng học viên:**
      #{student_summaries}

      Hãy viết đánh giá tổng quan bằng tiếng Việt theo 4 phần:

      ## Tổng quan kết quả
      Đánh giá chung về hiệu quả của lộ trình học, mức độ hoàn thành của nhóm.

      ## Điểm tích cực
      Những gì đã diễn ra tốt — tỷ lệ hoàn thành, sự tham gia, v.v.

      ## Điểm cần cải thiện
      Những hạn chế, học viên nào có thể gặp khó khăn, bài nào cần xem xét lại.

      ## Đề xuất tiếp theo
      3-4 hành động cụ thể để cải thiện lộ trình hoặc hỗ trợ học viên tốt hơn.

      Viết súc tích, khách quan, bằng tiếng Việt. Không dùng LaTeX.
    PROMPT

    return unless require_credits!(3)
    svc    = ClaudeService.for_feature("learning_path_eval", timeout: 120)
    result = svc.call(system_prompt: "Bạn là chuyên gia phân tích kết quả học tập. Trả lời bằng tiếng Việt, dùng markdown.", user_prompt: prompt, max_tokens: 1200)
    html   = markdown_to_html(result)
    workspace_billing_subscription&.deduct_credits!(3)
    render json: { html: html }
  end

  def assign
    due_date = params[:due_date].presence
    assigned = 0

    # Luồng 1: chọn từ danh sách thành viên
    Array(params[:user_ids]).map(&:to_i).uniq.each do |uid|
      user = accessible_workspace_members.find { |m| m.id == uid }
      next unless user
      assigned += 1 if assign_to_user(user, due_date, new_account: false)
    end

    # Luồng 2: nhập email tự do
    if params[:invite_emails].present?
      params[:invite_emails].split(",").map(&:strip).reject(&:blank?).each do |email|
        next unless email.match?(URI::MailTo::EMAIL_REGEXP)
        new_account = false
        user = User.find_by(email: email.downcase)
        unless user
          password = Devise.friendly_token.first(10)
          user = User.create!(
            email: email.downcase,
            name:  email.split("@").first.humanize,
            password: password,
            password_confirmation: password,
            confirmed_at: Time.current
          )
          new_account = true
          user.instance_variable_set(:@plain_password, password)
        end
        assigned += 1 if assign_to_user(user, due_date, new_account: new_account)
      end
    end

    redirect_to learning_path_path(@learning_path), notice: "Đã giao cho #{assigned} người."
  end

  private

  def set_path
    @learning_path = current_workspace.learning_paths.find(params[:id])
  end

  def path_params
    params.require(:learning_path).permit(:title, :description, :subject)
  end

  def assign_to_user(user, due_date, new_account: false)
    asgn = LearningPathAssignment.find_or_create_by!(learning_path: @learning_path, assignee: user) do |a|
      a.assigned_by = current_user
      a.due_date    = due_date
      a.status      = :active
    end
    Notification.notify(
      user:  user,
      type:  "learning_path_assigned",
      title: "Bạn được giao lộ trình: #{@learning_path.title}",
      body:  due_date ? "Hạn hoàn thành: #{Date.parse(due_date).strftime('%d/%m/%Y')}" : nil,
      resource: asgn
    ) rescue nil
    NotificationMailer.learning_path_assigned(asgn, new_account: new_account).deliver_later rescue nil
    true
  rescue => e
    Rails.logger.error "[assign_to_user] #{e.message}"
    false
  end

  def accessible_workspace_members
    @_members ||= begin
      owner = current_workspace.owner
      members = current_workspace.workspace_memberships.active.includes(:user).map(&:user)
      ([owner] + members).compact.uniq(&:id)
    end
  end
end
