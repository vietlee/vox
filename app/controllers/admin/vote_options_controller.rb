class Admin::VoteOptionsController < Admin::BaseController
  before_action :require_admin!
  before_action :set_vote, only: [:create]
  before_action :set_option, only: [:update, :destroy, :update_image, :destroy_image]

  def create
    return head :forbidden if @vote.active?

    @option = @vote.vote_options.build(
      label:       params[:label].to_s.strip,
      description: params[:description].to_s.strip.presence,
      position:    @vote.vote_options.maximum(:position).to_i + 1
    )

    if @option.label.present? && @option.save
      render json: { id: @option.id, label: @option.label, description: @option.description.to_s, position: @option.position }
    else
      render json: { error: "Không hợp lệ" }, status: :unprocessable_entity
    end
  end

  def update
    return head :forbidden if @option.vote.active?

    attrs = {}
    attrs[:label]       = params[:label].to_s.strip        if params.key?(:label)
    attrs[:description] = params[:description].to_s.strip  if params.key?(:description)
    return render json: { error: "Label required" }, status: :unprocessable_entity if attrs[:label] == ""
    if attrs.any? && @option.update(attrs)
      render json: { id: @option.id, label: @option.label, description: @option.description.to_s }
    else
      render json: { error: "Không hợp lệ" }, status: :unprocessable_entity
    end
  end

  def destroy
    return head :forbidden if @option.vote.active?
    @option.destroy
    head :no_content
  end

  def update_image
    return head :forbidden if @option.vote.active?
    return render json: { error: "No image" }, status: :unprocessable_entity unless params[:image].present?
    @option.image.attach(params[:image])
    render json: { url: rails_blob_path(@option.image, only_path: true) }
  end

  def destroy_image
    return head :forbidden if @option.vote.active?
    @option.image.purge
    head :no_content
  end

  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    ids.each_with_index do |id, idx|
      VoteOption.joins(:vote)
                .where(votes: { workspace_id: current_workspace.id })
                .where(id: id)
                .update_all(position: idx)
    end
    head :ok
  end

  private

  def set_vote
    @vote = current_workspace.votes.find(params[:vote_id])
  end

  def set_option
    @option = VoteOption.joins(:vote).where(votes: { workspace_id: current_workspace.id }).find(params[:id])
  end
end
