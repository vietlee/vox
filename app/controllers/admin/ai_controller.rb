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
    @context_type  = params[:context_type]
    @context_id    = params[:context_id]
    @context_title = resolve_tutor_context
    @has_stt = current_workspace&.feature_subscription&.has_feature?(:stt)
    @has_tts = current_workspace&.feature_subscription&.has_feature?(:tts)
  end

  def tutor
    return unless require_credits!(1)
    message    = params[:message].to_s.strip
    history    = params[:history] || []
    voice_mode = params[:voice_mode] == 'true'

    # Resolve context content from context_type/context_id
    context_text = resolve_tutor_content(params[:context_type], params[:context_id])

    if voice_mode
      system_prompt = <<~PROMPT
        Bạn là AI Tutor giọng nói — gia sư thân thiện, trả lời ngắn gọn để đọc to.
        - Trả lời TỐI ĐA 2-3 câu, súc tích, dễ nghe
        - KHÔNG dùng markdown, bullet, bold, tiêu đề — chỉ văn xuôi thuần
        - Không dùng ký hiệu đặc biệt: *, #, **, --, []
        - Nói tự nhiên như trò chuyện, thân mật
        #{context_text.present? ? "\nTài liệu tham khảo: #{context_text.truncate(2000)}\n" : ""}
        Trả lời bằng tiếng Việt.
      PROMPT
      messages   = history.last(6).map { |h| { role: h["role"], content: h["content"] } }
      messages  << { role: "user", content: message }
      svc        = ClaudeService.new(model: ClaudeService::HAIKU_MODEL, timeout: 15)
      max_tokens = 200
    else
      system_prompt = <<~PROMPT
        Bạn là AI Tutor — gia sư cá nhân thông minh, thân thiện và kiên nhẫn.

        Phong cách trả lời:
        - Viết tự nhiên như đang trò chuyện, không dùng tiêu đề ## hay ###
        - Không dùng bảng (table) trừ khi người dùng yêu cầu so sánh rõ ràng
        - Dùng bullet gạch đầu dòng chỉ khi liệt kê từ 3 điểm trở lên
        - **Bold** chỉ cho khái niệm quan trọng, không bold cả câu
        - Câu trả lời ngắn gọn, tập trung — không liệt kê dài dòng không cần thiết
        - Khi giải thích, dùng ví dụ gần gũi, dễ hình dung

        Phương pháp dạy:
        - Ưu tiên dẫn dắt để người học tự tìm ra đáp án bằng câu hỏi gợi mở
        - Chỉ đưa đáp án trực tiếp khi người học thực sự bí hoặc yêu cầu rõ ràng
        - Khuyến khích, tạo động lực — không phán xét
        - Luôn kiểm tra xem người học đã hiểu chưa sau khi giải thích
        #{context_text.present? ? "\nNgữ cảnh tài liệu đang học:\n#{context_text.truncate(8000)}\n" : ""}
        Trả lời bằng tiếng Việt.
      PROMPT
      messages   = history.map { |h| { role: h["role"], content: h["content"] } }
      messages  << { role: "user", content: message }
      svc        = ClaudeService.for_feature("ai_chat")
      max_tokens = 1024
    end

    result = svc.call(system_prompt: system_prompt, messages: messages, max_tokens: max_tokens)
    current_workspace.credit_subscription&.deduct_credits!(1)
    render json: { response: result }
  rescue => e
    Rails.logger.error "[AI Tutor] #{e.class}: #{e.message}"
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

  # Suggest title + subject for a slide/content from document summary text
  def suggest_meta
    content = params[:content].to_s.strip.truncate(3000)
    return render json: { error: "Thiếu nội dung" }, status: :unprocessable_entity if content.blank?

    svc = ClaudeService.new(model: ClaudeService::HAIKU_MODEL, timeout: 15)
    raw = svc.call(
      system_prompt: "Bạn là trợ lý phân tích tài liệu. Chỉ trả về JSON hợp lệ, không giải thích.",
      user_prompt: <<~PROMPT,
        Dựa vào nội dung tóm tắt tài liệu sau, hãy đề xuất:
        - title: Tiêu đề ngắn gọn cho bộ slide thuyết trình (5-10 từ, tiếng Việt)
        - subject: Lĩnh vực / ngành của tài liệu (1-3 từ, VD: "Marketing", "Công nghệ", "Y tế", "Giáo dục"...)

        Nội dung tài liệu:
        #{content}

        Trả về JSON: {"title":"...","subject":"..."}
      PROMPT
      max_tokens: 150
    )
    data = JSON.parse(raw.match(/\{.*\}/m)&.to_s || "{}")
    render json: { title: data["title"].to_s, subject: data["subject"].to_s }
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
    when "learning_path"
      lp = current_workspace.learning_paths.find_by(id: params[:context_id])
      lp&.title
    end
  end

  def resolve_tutor_content(context_type, context_id)
    case context_type.to_s
    when "learning_path_item"
      item = LearningPathItem.joins(:learning_path).where(learning_paths: { workspace: current_workspace }).find_by(id: context_id)
      return nil unless item
      parts = ["Bài học: #{item.title}"]
      parts << "Nội dung:\n#{item.content}" if item.content.present?
      parts.join("\n\n")
    when "document_summary"
      doc = current_workspace.document_summaries.find_by(id: context_id)
      return nil unless doc&.done?
      parts = ["Tài liệu: #{doc.title}"]
      parts << "Tóm tắt: #{doc.summary}" if doc.summary.present?
      if doc.key_points.present?
        pts = JSON.parse(doc.key_points) rescue []
        parts << "Điểm chính:\n#{pts.map { |p| "- #{p}" }.join("\n")}" if pts.any?
      end
      if doc.source_text.present?
        parts << "Nội dung gốc tài liệu:\n#{doc.source_text.truncate(6000)}"
      end
      parts.join("\n\n")
    when "learning_path"
      lp = current_workspace.learning_paths.find_by(id: context_id)
      return nil unless lp
      items = lp.learning_path_items.order(:position).map { |i| "- #{i.title} (#{i.item_type})" }.join("\n")
      "Lộ trình: #{lp.title}\nMô tả: #{lp.description}\nCác bài học:\n#{items}"
    end
  end
end
