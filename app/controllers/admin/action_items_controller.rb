class Admin::ActionItemsController < Admin::BaseController
  before_action :set_action_item, only: [:update, :destroy]

  # POST /action_items  (AJAX)
  def create
    board = current_workspace.feedback_boards.find(params[:action_item][:feedback_board_id])
    item  = current_workspace.action_items.create!(
      feedback_board: board,
      title:          create_params[:title].to_s.strip.truncate(200),
      description:    create_params[:description],
      priority:       create_params[:priority].presence || :medium,
      status:         :pending
    )
    render json: { ok: true, id: item.id }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /action_items/:id  (AJAX)
  def update
    @action_item.update!(update_params)
    render json: {
      ok:       true,
      status:   @action_item.status,
      priority: @action_item.priority,
      assignee: @action_item.assignee ? { id: @action_item.assignee_id, name: @action_item.assignee.display_name } : nil
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /action_items/:id  (AJAX)
  def destroy
    @action_item.destroy!
    render json: { ok: true }
  end

  private

  def set_action_item
    @action_item = current_workspace.action_items.find(params[:id])
  end

  def update_params
    params.require(:action_item).permit(:status, :assignee_id, :priority, :title, :description)
  end

  def create_params
    params.require(:action_item).permit(:title, :description, :priority, :feedback_board_id)
  end
end
