class Admin::QuizQuestionsController < Admin::BaseController
  before_action :set_quiz_set
  before_action :set_question, only: [:update, :destroy]

  def create
    @question = @quiz_set.quiz_questions.build(question_params)
    @question.position = @quiz_set.quiz_questions.count
    if @question.save
      if @question.true_false?
        @question.quiz_options.create!([
          { option_text: "Đúng", is_correct: true,  position: 0 },
          { option_text: "Sai",  is_correct: false, position: 1 }
        ])
      elsif params[:options].present?
        params[:options].each_with_index do |opt, i|
          @question.quiz_options.create!(
            option_text: opt[:text].to_s.strip,
            is_correct:  opt[:correct].in?([true, "true"]),
            position:    i
          )
        end
      end
      render json: {
        success: true,
        id:            @question.id,
        question_text: @question.question_text,
        question_type: @question.question_type,
        allow_multiple: @question.allow_multiple,
        explanation:   @question.explanation,
        points:        @question.points,
        essay_rubric:  @question.essay_rubric,
        options: @question.quiz_options.map { |o| { id: o.id, text: o.option_text, correct: o.is_correct } }
      }
    else
      render json: { error: @question.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  def update
    if @question.update(question_params)
      render json: { success: true }
    else
      render json: { error: @question.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  def destroy
    @question.destroy
    render json: { success: true }
  end

  def reorder
    ids = params[:ids] || []
    ids.each_with_index { |id, idx| @quiz_set.quiz_questions.where(id: id).update_all(position: idx) }
    render json: { success: true }
  end

  private

  def set_quiz_set
    @quiz_set = current_workspace.quiz_sets.find(params[:quiz_set_id])
  end

  def set_question
    @question = @quiz_set.quiz_questions.find(params[:id])
  end

  def question_params
    params.require(:quiz_question).permit(:question_text, :question_type, :explanation, :points, :allow_multiple, :essay_rubric)
  end
end
