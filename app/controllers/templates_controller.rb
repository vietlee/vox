class TemplatesController < ApplicationController
  skip_before_action :authenticate_user!
  layout "public"

  def index
    @templates = SurveyTemplate.active.ordered
    @type      = params[:type].presence
    @category  = params[:category].presence

    @templates = @templates.where(template_type: @type)     if @type.present?
    @templates = @templates.where(category: @category)       if @category.present?

    @categories  = SurveyTemplate::CATEGORIES
    @types       = SurveyTemplate::TYPES
    @total_count = SurveyTemplate.active.count
  end

  def show
    @template = SurveyTemplate.active.find(params[:id])
  end

  def use
    @template = SurveyTemplate.active.find(params[:id])

    unless user_signed_in?
      # Store with timestamp so it expires if user doesn't complete sign-up quickly
      session[:pending_template] = { id: @template.id, at: Time.current.to_i }
      redirect_to new_user_registration_path and return
    end

    resource = create_from_template(@template)
    @template.increment!(:use_count)

    notice = I18n.locale == :vi ?
      "Đã tạo từ mẫu \"#{@template.title}\" — hãy tuỳ chỉnh rồi phát hành!" :
      "Created from template \"#{@template.title}\" — customize and publish!"

    case @template.template_type
    when "survey"   then redirect_to edit_survey_path(resource),         notice: notice
    when "vote"     then redirect_to edit_vote_path(resource),           notice: notice
    when "feedback" then redirect_to edit_feedback_board_path(resource), notice: notice
    end
  end

  private

  def create_from_template(template)
    workspace = current_user.workspace
    s = template.structure

    case template.template_type
    when "survey"
      survey = workspace.surveys.create!(
        user:        current_user,
        title:       s["title"] || template.title,
        description: s["description"],
        status:      :draft
      )
      (s["questions"] || []).each_with_index do |q, idx|
        question = survey.questions.create!(
          title:         q["title"],
          question_type: q["question_type"],
          required:      q["required"] || false,
          position:      idx,
          settings:      q["settings"] || {}
        )
        (q["options"] || []).each_with_index do |opt, oidx|
          question.question_options.create!(label: opt, position: oidx)
        end
      end
      survey

    when "vote"
      vote = workspace.votes.create!(
        user:        current_user,
        title:       s["title"] || template.title,
        description: s["description"],
        vote_type:   s["vote_type"] || "single_choice",
        status:      :draft
      )
      (s["options"] || []).each_with_index do |opt, idx|
        vote.vote_options.create!(label: opt, position: idx)
      end
      vote

    when "feedback"
      workspace.feedback_boards.create!(
        user:        current_user,
        title:       s["title"] || template.title,
        description: s["description"],
        status:      :draft
      )
    end
  end
end
