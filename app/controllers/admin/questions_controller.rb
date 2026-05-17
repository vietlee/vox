class Admin::QuestionsController < Admin::BaseController
  before_action :set_survey

  def create
    @question = @survey.questions.build(question_params)
    @question.position = @survey.questions.count
    if @question.save
      html = render_to_string(
        partial: "admin/surveys/question_card",
        locals: { question: @question, idx: @question.position }
      )
      render json: { id: @question.id, success: true, html: html }
    else
      render json: { errors: @question.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @question = @survey.questions.find(params[:id])
    if @question.update(question_params)
      render json: { success: true }
    else
      render json: { errors: @question.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @question = @survey.questions.find(params[:id])
    @question.destroy
    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to edit_survey_path(@survey) }
    end
  end

  def reorder
    params[:order].each_with_index do |id, idx|
      @survey.questions.find_by(id: id)&.update!(position: idx)
    end
    head :ok
  end

  private

  def set_survey
    @survey = current_workspace.surveys.find(params[:survey_id])
  end

  def question_params
    params.require(:question).permit(:title, :description, :question_type, :required, :position, :section, :score_weight, settings: {}, conditional_logic: {})
  end
end
