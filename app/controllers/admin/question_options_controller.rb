class Admin::QuestionOptionsController < Admin::BaseController
  before_action :set_question

  def create
    @option = @question.question_options.build(option_params)
    @option.position = @question.question_options.count
    if @option.save
      render json: { id: @option.id, success: true }
    else
      render json: { errors: @option.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @option = @question.question_options.find(params[:id])
    @option.update(option_params)
    render json: { success: true }
  end

  def destroy
    @option = @question.question_options.find(params[:id])
    @option.destroy
    head :ok
  end

  private

  def set_question
    survey = current_workspace.surveys.find(params[:survey_id])
    @question = survey.questions.find(params[:question_id])
  end

  def option_params
    params.require(:question_option).permit(:label, :image, :position, :score)
  end
end
