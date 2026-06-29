class Admin::AiController < Admin::BaseController
  def generate_survey
    return unless require_ai_feature!(:ai_survey_builder)
    return unless require_credits!(5)

    current_workspace.credit_subscription&.deduct_credits!(5)
    job = AiJob.create!(
      workspace: current_workspace,
      user: current_user,
      job_type: "survey_builder",
      credits_cost: 5,
      input_data: { prompt: params[:prompt], language: current_workspace.language }
    )
    AiSurveyBuilderJob.perform_later(job.id)
    render json: { job_id: job.id, status: "queued" }
  end

  def check_question
    return unless require_ai_feature!(:ai_survey_builder)
    return unless require_credits!(1)

    current_workspace.credit_subscription&.deduct_credits!(1)
    job = AiJob.create!(
      workspace: current_workspace,
      user: current_user,
      job_type: "question_checker",
      credits_cost: 1,
      input_data: { question_text: params[:question_text], language: current_workspace.language }
    )
    AiQuestionCheckerJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def analyze_survey
    return unless require_ai_feature!(:ai_analysis)
    return unless require_credits!(5)

    survey = current_workspace.surveys.find(params[:survey_id])
    current_workspace.credit_subscription&.deduct_credits!(5)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "survey_analysis", resource_type: "Survey", resource_id: survey.id, credits_cost: 5)
    AiSurveyAnalysisJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def generate_report
    return unless require_ai_feature!(:ai_executive_report)
    return unless require_credits!(15)

    survey = current_workspace.surveys.find(params[:survey_id])
    current_workspace.credit_subscription&.deduct_credits!(15)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "executive_report", resource_type: "Survey", resource_id: survey.id, credits_cost: 15, input_data: { language: params[:language] || "vi" })
    AiExecutiveReportJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def chat_page
    return unless require_ai_feature!(:ai_chat)
  end

  def chat
    return unless require_ai_feature!(:ai_chat)
    return unless require_credits!(2)

    current_workspace.credit_subscription&.deduct_credits!(2)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "ai_chat", credits_cost: 2, input_data: { message: params[:message], conversation_history: params[:history] || [] })
    AiChatJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def job_status
    job = current_workspace.ai_jobs.find(params[:id])
    render json: {
      status: job.status,
      output: job.done? ? job.output_data : nil,
      error:  job.failed? ? job.error_message : nil
    }
  end

  # AI Tutor — hỏi đáp Socratic, không đưa đáp án thẳng
  def tutor_page
    @context_type = params[:context_type]   # 'learning_path_item', 'document_summary', etc.
    @context_id   = params[:context_id]
    @context_title = resolve_tutor_context
  end

  def tutor
    return unless require_credits!(1)
    message  = params[:message].to_s.strip
    history  = params[:history] || []
    context  = params[:context].to_s.strip

    system_prompt = <<~PROMPT
      Bạn là AI gia sư/trợ lý học tập. Nhiệm vụ:
      - Giúp người dùng HIỂU, không đưa đáp án thẳng ngay
      - Dẫn dắt bằng câu hỏi gợi mở, ví dụ, phân tích từng bước
      - Nếu người dùng thực sự bí và hỏi đáp án, mới giải thích đầy đủ
      - Ngôn ngữ thân thiện, khuyến khích
      #{context.present? ? "\n=== NỘI DUNG TÀI LIỆU ===\n#{context.truncate(8000)}\n=== HẾT ===" : ""}
      Trả lời bằng tiếng Việt với markdown.
    PROMPT

    messages = history.map { |h| { role: h["role"], content: h["content"] } }
    messages << { role: "user", content: message }

    current_workspace.credit_subscription&.deduct_credits!(1)
    result = ClaudeService.for_feature("ai_chat").call(system_prompt: system_prompt, messages: messages, max_tokens: 1024)
    render json: { response: result }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # AI Writing assistant — sửa lỗi và cải thiện văn bản
  def writing
    return unless require_credits!(1)
    text   = params[:text].to_s.strip
    action = params[:action_type].to_s  # 'correct', 'improve', 'summarize', 'rewrite'

    instructions = {
      "correct"   => "Sửa lỗi chính tả, ngữ pháp. Giữ nguyên ý nghĩa. Giải thích các lỗi đã sửa.",
      "improve"   => "Cải thiện văn phong, làm rõ ý hơn, chuyên nghiệp hơn. Giải thích thay đổi.",
      "summarize" => "Tóm tắt ngắn gọn, giữ ý chính.",
      "rewrite"   => "Viết lại hoàn toàn theo cách khác, giữ nguyên nội dung.",
    }
    instruction = instructions[action] || instructions["correct"]

    current_workspace.credit_subscription&.deduct_credits!(1)
    result = ClaudeService.for_feature("ai_chat").call(
      system_prompt: "Bạn là trợ lý viết văn bản chuyên nghiệp. #{instruction} Trả lời bằng tiếng Việt với markdown.",
      user_prompt: "Văn bản cần xử lý:\n\n#{text.truncate(5000)}",
      max_tokens: 2048
    )
    render json: { result: result }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def resolve_tutor_context
    case params[:context_type]
    when "learning_path_item"
      item = LearningPathItem.joins(:learning_path).where(learning_paths: { workspace: current_workspace }).find_by(id: params[:context_id])
      item&.title
    when "document_summary"
      doc = current_workspace.document_summaries.find_by(id: params[:context_id])
      doc&.title
    end
  end
end
