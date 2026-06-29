class Admin::LearningPathsController < Admin::BaseController
  before_action :set_path, only: [:show, :edit, :update, :destroy, :publish, :ai_generate, :ai_status, :assign]

  def index
    @learning_paths = current_workspace.learning_paths.includes(:created_by, :learning_path_items).order(created_at: :desc)
    # Assignments cho current_user
    @my_assignments = LearningPathAssignment.joins(:learning_path)
                        .where(learning_paths: { workspace: current_workspace }, assignee: current_user)
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
    @items = @learning_path.learning_path_items.includes(:quiz_set).order(:position)
    @assignments = @learning_path.learning_path_assignments.includes(:assignee)
    @my_assignment = @assignments.find_by(assignee: current_user)
    @workspace_members = accessible_workspace_members
    @quiz_sets = current_workspace.quiz_sets.published.order(:title)
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
    render json: { pending: @learning_path.ai_generating? }
  end

  def ai_generate
    require_credits!(5)
    prompt = params[:prompt].to_s.strip
    return redirect_to(learning_path_path(@learning_path), alert: "Cần nhập yêu cầu.") if prompt.blank?

    @learning_path.update!(ai_generating: true)
    GenerateLearningPathJob.perform_later(@learning_path.id, prompt)
    redirect_to learning_path_path(@learning_path), notice: "AI đang tạo lộ trình, vui lòng chờ..."
  rescue => e
    @learning_path.update(ai_generating: false)
    redirect_to learning_path_path(@learning_path), alert: "Lỗi: #{e.message.truncate(100)}"
  end

  def assign
    user_ids = Array(params[:user_ids]).map(&:to_i).uniq
    due_date = params[:due_date].presence
    assigned = 0
    user_ids.each do |uid|
      user = accessible_workspace_members.find { |m| m.id == uid }
      next unless user
      LearningPathAssignment.find_or_create_by!(learning_path: @learning_path, assignee: user) do |a|
        a.assigned_by = current_user
        a.due_date = due_date
        a.status = :active
      end
      assigned += 1
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

  def accessible_workspace_members
    @_members ||= begin
      owner = current_workspace.owner
      members = current_workspace.workspace_memberships.active.includes(:user).map(&:user)
      ([owner] + members).compact.uniq(&:id)
    end
  end
end
