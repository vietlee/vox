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

  private

  def set_path
    @path = current_workspace.learning_paths.find(params[:learning_path_id])
  end

  def item_params
    params.require(:learning_path_item).permit(:title, :content, :item_type, :estimated_minutes, :quiz_set_id)
  end
end
