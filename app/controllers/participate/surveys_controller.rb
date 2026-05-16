class Participate::SurveysController < Participate::BaseController
  before_action :set_survey

  def show
    @questions = @survey.questions.includes(:question_options)
    unless @survey.accepting_responses?
      render :closed and return
    end
    @response = @survey.responses.build
  end

  def submit
    unless @survey.accepting_responses?
      redirect_to participate_survey_path(@survey.slug), alert: "Survey is closed."
      return
    end

    @response = @survey.responses.build(
      workspace: @survey.workspace,
      respondent_token: respondent_token,
      respondent_email: params[:response][:respondent_email],
      source: params[:source] || "link"
    )

    if @response.save
      save_answers(@response)
      @response.complete!
      render :thank_you
    else
      @questions = @survey.questions.includes(:question_options)
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_survey
    @survey = Survey.find_by!(slug: params[:slug])
    @workspace = @survey.workspace
  end

  def save_answers(response)
    @survey.questions.each do |question|
      answer_data = params.dig(:answers, question.id.to_s) || {}
      answer = response.answers.build(question: question)

      case question.question_type.to_sym
      when :short_text, :long_text
        answer.text_value = answer_data[:text]
      when :multiple_choice, :dropdown
        answer.option_ids = [answer_data[:option_id]].compact
      when :checkbox
        answer.option_ids = Array(answer_data[:option_ids])
      when :rating, :linear_scale, :nps
        answer.numeric_value = answer_data[:value].to_f
      when :matrix
        answer.matrix_values = answer_data[:matrix] || {}
      when :date_time
        answer.date_value = answer_data[:date]
      end
      answer.save!
    end
  end
end
