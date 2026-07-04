class GenerateQuizQuestionsJob < ApplicationJob
  queue_as :default

  def perform(quiz_set_id, job_content, questions_count, custom_prompt)
    quiz_set = QuizSet.find_by(id: quiz_set_id)
    return unless quiz_set

    content = resolve_content(job_content)
    if content.blank?
      quiz_set.update(ai_generating: false, ai_failed: true)
      Rails.logger.error "[GenerateQuizQuestionsJob] #{quiz_set_id}: file upload expired or unreadable"
      return
    end

    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    if content.is_a?(Hash) && content[:image_base64]
      messages = [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: content[:mime_type], data: content[:image_base64] } },
          { type: "text", text: build_prompt(questions_count, custom_prompt) }
        ]
      }]
      raw = svc.call(system_prompt: SYSTEM_PROMPT, messages: messages, max_tokens: 8000)
    else
      user_prompt = "#{build_prompt(questions_count, custom_prompt)}\n\n---\n#{content.to_s.truncate(22000)}"
      raw = svc.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt, max_tokens: 8000)
    end

    questions = parse_ai_response(raw)
    raise "No questions found in AI response" if questions.blank?

    ActiveRecord::Base.transaction do
      quiz_set.workspace.credit_subscription&.deduct_credits!(5)
      quiz_set.update!(source_type: :ai_generated, ai_generating: false, ai_failed: false)
      questions.each_with_index do |q, idx|
        question = quiz_set.quiz_questions.create!(
          question_text: q[:question],
          question_type: :multiple_choice,
          explanation:   q[:explanation],
          position:      quiz_set.quiz_questions.count + idx
        )
        (q[:options] || []).each_with_index do |opt, oi|
          question.quiz_options.create!(option_text: opt[:text], is_correct: opt[:correct], position: oi)
        end
      end
    end
  rescue => e
    quiz_set&.update(ai_generating: false, ai_failed: true)
    Rails.logger.error "[GenerateQuizQuestionsJob] #{quiz_set_id}: #{e.message}"
  ensure
    # Clean up temp file
    tmp = job_content.is_a?(Hash) ? (job_content["tmp_file"] || job_content[:tmp_file]) : nil
    File.delete(tmp) rescue nil if tmp
  end

  private

  SYSTEM_PROMPT = "You are a quiz generator. Respond with ONLY valid JSON, no markdown, no code fences, no explanation."

  def resolve_content(job_content)
    return job_content unless job_content.is_a?(Hash)

    # Support both string and symbol keys (ActiveJob may convert either way)
    path = job_content["tmp_file"] || job_content[:tmp_file]
    return job_content unless path  # hash without tmp_file = image data already resolved

    unless File.exist?(path)
      Rails.logger.error "[GenerateQuizQuestionsJob] tmp file missing: #{path}"
      return nil
    end

    raw = File.read(path)
    JSON.parse(raw, symbolize_names: true)
  rescue JSON::ParserError => e
    Rails.logger.error "[GenerateQuizQuestionsJob] tmp file JSON parse error: #{e.message}"
    nil
  end

  def parse_ai_response(raw)
    return nil if raw.blank?

    # Strip markdown code fences: ```json ... ``` or ``` ... ```
    cleaned = raw
      .gsub(/\A\s*```(?:json)?\s*/i, '')
      .gsub(/\s*```\s*\z/, '')
      .strip

    # Extract first JSON object or array
    json_str = extract_json(cleaned) || extract_json(raw)
    return nil if json_str.blank?

    # Parse — retry with LaTeX-escaped backslashes if first attempt fails
    parsed = begin
      JSON.parse(json_str, symbolize_names: true)
    rescue JSON::ParserError
      JSON.parse(sanitize_backslashes(json_str), symbolize_names: true) rescue nil
    end

    return nil unless parsed
    parsed.is_a?(Array) ? parsed : parsed[:questions]
  end

  def extract_json(str)
    # Try to extract outermost { } first, then [ ]
    [/\{[\s\S]*\}/, /\[[\s\S]*\]/].each do |pattern|
      m = str.match(pattern)
      next unless m
      candidate = m[0]
      # Validate it's parseable before returning
      JSON.parse(candidate) rescue next
      return candidate
    end
    nil
  end

  def sanitize_backslashes(str)
    str.gsub(/\\(?!["\\\/bfnrt]|u[0-9a-fA-F]{4})/, '\\\\')
  end

  def build_prompt(count, custom_prompt)
    count_instruction = count.nil? \
      ? "Extract ALL multiple-choice questions found in the provided content (there may be multiple documents/sections). Do not invent new ones — extract every question present across all documents." \
      : "Generate exactly #{count} multiple-choice questions based on the content."
    user_instruction = custom_prompt.present? ? "\n\nAdditional instructions: #{custom_prompt}" : ""
    <<~PROMPT
      #{count_instruction}#{user_instruction}

      Return ONLY this JSON (no other text, no markdown):
      {"questions":[{"question":"...","options":[{"text":"...","correct":true},{"text":"...","correct":false},{"text":"...","correct":false},{"text":"...","correct":false}],"explanation":"..."}]}
    PROMPT
  end
end
