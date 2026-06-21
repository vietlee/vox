class Admin::QuizOptionsController < Admin::BaseController
  before_action :set_context

  def create
    @option = @question.quiz_options.build(option_params)
    @option.position = @question.quiz_options.count
    if @option.save
      render json: { success: true, id: @option.id }
    else
      render json: { error: @option.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  def update
    if params[:quiz_option][:is_correct] == "true" && !@question.allow_multiple
      @question.quiz_options.update_all(is_correct: false)
    end
    if @option.update(option_params)
      render json: { success: true }
    else
      render json: { error: @option.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  def destroy
    @option.destroy
    render json: { success: true }
  end

  private

  def set_context
    quiz_set  = current_workspace.quiz_sets.find(params[:quiz_set_id])
    @question = quiz_set.quiz_questions.find(params[:quiz_question_id])
    @option   = @question.quiz_options.find(params[:id]) if params[:id]
  end

  def option_params
    params.require(:quiz_option).permit(:option_text, :is_correct, :position)
  end
end
