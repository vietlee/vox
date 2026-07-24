# Builds a self-study quiz for a learner from a title + free-form request + optional files.
class LearnerQuizGenerator
  COST = 4

  def initialize(learner, title:, prompt:, count:, include_essay: false, time_limit: nil, files: [], attachments: [])
    @learner       = learner
    @title         = title.to_s.strip
    @prompt        = prompt.to_s.strip
    @count         = count.to_i.clamp(3, 30)
    @include_essay = include_essay
    @time_limit    = time_limit.to_i
    @files         = Array(files)
    @attachments   = Array(attachments)
  end

  def generate!
    parts = build_content_parts
    raw   = call_ai(parts)
    data  = parse(raw)
    questions = Array(data["questions"]).first(@count)
    raise "AI không tạo được câu hỏi hợp lệ." if questions.empty?

    quiz = nil
    assignment = nil
    ActiveRecord::Base.transaction do
      quiz = QuizSet.create!(
        learner_id:         @learner.id,
        title:              @title.presence || "Bài kiểm tra của tôi",
        description:        @prompt.truncate(500),
        status:             :published,
        source_type:        :ai_generated,
        result_mode:        :result_immediate,
        show_answers:       true,
        allow_retake:       true,
        passing_score:      50,
        passing_score_type: "percent",
        time_limit_minutes: (@time_limit.positive? ? @time_limit : nil)
      )

      questions.each_with_index do |q, i|
        essay = q["type"].to_s == "essay"
        qq = quiz.quiz_questions.create!(
          question_text: q["question"].to_s.strip,
          question_type: essay ? :essay : :multiple_choice,
          explanation:   q["explanation"].to_s,
          essay_rubric:  q["rubric"].to_s,
          points:        (q["points"].presence || (essay ? 3 : 1)).to_i.clamp(1, 10),
          position:      i
        )
        next if essay
        Array(q["options"]).each_with_index do |opt, oi|
          qq.quiz_options.create!(
            option_text: opt["text"].to_s,
            is_correct:  [true, "true", 1, "1"].include?(opt["correct"]),
            position:    oi
          )
        end
      end

      assignment = build_assignment(quiz)
      @learner.deduct_credits!(COST)
    end

    { quiz: quiz, assignment: assignment }
  end

  private

  def build_assignment(quiz)
    QuizAssignment.create!(
      quiz_set:       quiz,
      learner:        @learner,
      assigned_by_id: nil,
      status:         :pending,
      token:          SecureRandom.urlsafe_base64(20)
    )
  end

  def build_content_parts
    parts = []
    instruction = <<~P
      Tạo một bài kiểm tra gồm #{@count} câu hỏi.
      Tiêu đề: "#{@title}".
      Yêu cầu của người học: #{@prompt.presence || "(không có, hãy bám theo tiêu đề)"}.
      #{@include_essay ? "Bao gồm 1-2 câu tự luận (essay) có kèm rubric chấm điểm; còn lại là trắc nghiệm." : "Tất cả là câu hỏi trắc nghiệm nhiều lựa chọn."}
      Trả về DUY NHẤT JSON hợp lệ theo cấu trúc:
      {"questions":[
        {"type":"multiple_choice","question":"...","options":[{"text":"...","correct":true},{"text":"...","correct":false}],"explanation":"...","points":1},
        {"type":"essay","question":"...","rubric":"tiêu chí chấm","points":3}
      ]}
      - Câu trắc nghiệm có 4 lựa chọn, chỉ 1 đáp án đúng (correct:true).
      - Viết bằng tiếng Việt trừ khi tài liệu/chủ đề bằng ngôn ngữ khác.
      - explanation giải thích ngắn gọn đáp án đúng.
    P
    parts << { type: "text", text: instruction }

    # Legacy: ActionDispatch uploaded files
    @files.each do |f|
      next unless f.respond_to?(:content_type)
      if f.content_type.to_s.start_with?("image/")
        data = Base64.strict_encode64(f.read)
        parts << { type: "image", source: { type: "base64", media_type: f.content_type, data: data } }
      else
        text = f.read.force_encoding("UTF-8").scrub.truncate(15_000)
        parts << { type: "text", text: "Tài liệu tham khảo (#{f.original_filename}):\n#{text}" }
      end
    end
    # Structured attachments from mobile app (base64-encoded)
    @attachments.each do |a|
      mime     = (a[:mime] || a["mime"]).to_s
      data     = (a[:data] || a["data"]).to_s
      filename = (a[:filename] || a["filename"] || "file").to_s
      next if data.blank?
      if mime.start_with?("image/")
        parts << { type: "image", source: { type: "base64", media_type: mime, data: data } }
      elsif mime == "application/pdf"
        parts << { type: "document", source: { type: "base64", media_type: "application/pdf", data: data } }
      else
        text = Base64.decode64(data).force_encoding("UTF-8").scrub.truncate(15_000)
        parts << { type: "text", text: "Tài liệu tham khảo (#{filename}):\n#{text}" }
      end
    end
    parts
  end

  def call_ai(parts)
    svc = ClaudeService.for_feature("quiz_generate", timeout: 90)
    svc.call(
      system_prompt: "Bạn là chuyên gia ra đề kiểm tra. Chỉ trả về JSON hợp lệ, không giải thích thêm.",
      messages: [{ role: "user", content: parts }],
      max_tokens: 6000
    )
  end

  def parse(raw)
    m = raw.match(/\{[\s\S]*\}/)
    m ? JSON.parse(m[0]) : {}
  rescue JSON::ParserError
    {}
  end
end
