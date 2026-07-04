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

    questions = if content.is_a?(Array) && content.first&.dig(:image_base64)
      # Multiple image files — call AI once per image, merge results
      extract_questions_from_images(svc, content, questions_count, custom_prompt)
    elsif content.is_a?(Hash) && content[:image_base64]
      messages = [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: content[:mime_type], data: content[:image_base64] } },
          { type: "text", text: build_prompt(questions_count, custom_prompt) }
        ]
      }]
      raw = svc.call(system_prompt: SYSTEM_PROMPT, messages: messages, max_tokens: 8000)
      parse_ai_response(raw)
    else
      extract_questions_chunked(svc, content.to_s, questions_count, custom_prompt)
    end

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

  def extract_questions_from_images(svc, images, questions_count, custom_prompt)
    all_questions = []
    images.each_with_index do |img, idx|
      img_count = if questions_count
        per = (questions_count.to_f / images.size).ceil
        idx == images.size - 1 ? questions_count - all_questions.size : per
      end
      next if img_count && img_count <= 0

      messages = [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: img[:mime_type], data: img[:image_base64] } },
          { type: "text", text: build_prompt(img_count, idx == 0 ? custom_prompt : nil) }
        ]
      }]
      raw = svc.call(system_prompt: SYSTEM_PROMPT, messages: messages, max_tokens: 8000)
      parsed = parse_ai_response(raw)
      Rails.logger.info "[GenerateQuizQuestionsJob] image #{idx}: got #{parsed&.size || 0} questions"
      all_questions.concat(parsed) if parsed.present?
    end
    questions_count ? all_questions.first(questions_count) : all_questions
  end

  CHUNK_CHAR_LIMIT = 20_000  # ~5k tokens per chunk, safe margin for 8k output

  # Split large content into chunks, run AI on each, merge all questions.
  # If questions_count is set, distribute evenly across chunks then slice.
  def extract_questions_chunked(svc, text, questions_count, custom_prompt)
    # Split by document markers first — process each doc separately for reliability
    doc_sections = split_by_documents(text)
    doc_count = doc_sections.size

    Rails.logger.info "[GenerateQuizQuestionsJob] doc_count=#{doc_count}, questions_count=#{questions_count.inspect}, total_chars=#{text.length}"

    if doc_count > 1
      all_questions = []
      doc_sections.each_with_index do |section, idx|
        doc_q_count = if questions_count
          per = (questions_count.to_f / doc_count).ceil
          idx == doc_count - 1 ? questions_count - all_questions.size : per
        end
        next if doc_q_count && doc_q_count <= 0

        # For each doc section, still chunk if very large
        chunks = split_into_chunks(section, CHUNK_CHAR_LIMIT)
        chunks.each_with_index do |chunk, cidx|
          chunk_count = doc_q_count ? (cidx == chunks.size - 1 ? doc_q_count - (all_questions.size - (idx * (questions_count.to_f / doc_count).ceil).to_i) : (doc_q_count.to_f / chunks.size).ceil.to_i) : nil
          chunk_count = nil if chunk_count && chunk_count <= 0
          next if chunk_count&.<=(0)

          user_prompt = "#{build_prompt(chunk_count || doc_q_count, idx == 0 && cidx == 0 ? custom_prompt : nil, 1)}\n\n---\n#{chunk}"
          raw = svc.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt, max_tokens: 8000)
          parsed = parse_ai_response(raw)
          Rails.logger.info "[GenerateQuizQuestionsJob] doc #{idx} chunk #{cidx}: got #{parsed&.size || 0} questions"
          all_questions.concat(parsed) if parsed.present?
        end
      end
      return questions_count ? all_questions.first(questions_count) : all_questions
    end

    # Single document — chunk by size
    chunks = split_into_chunks(text, CHUNK_CHAR_LIMIT)
    Rails.logger.info "[GenerateQuizQuestionsJob] single_doc chunks=#{chunks.size}"
    all_questions = []

    chunks.each_with_index do |chunk, idx|
      chunk_count = if questions_count
        per = (questions_count.to_f / chunks.size).ceil
        idx == chunks.size - 1 ? questions_count - all_questions.size : per
      end
      next if chunk_count && chunk_count <= 0

      user_prompt = "#{build_prompt(chunk_count, idx == 0 ? custom_prompt : nil, 1)}\n\n---\n#{chunk}"
      raw = svc.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt, max_tokens: 8000)
      parsed = parse_ai_response(raw)
      Rails.logger.info "[GenerateQuizQuestionsJob] chunk #{idx}: got #{parsed&.size || 0} questions"
      all_questions.concat(parsed) if parsed.present?
    end

    questions_count ? all_questions.first(questions_count) : all_questions
  end

  # Split combined text into per-document sections by the markers the controller embeds
  def split_by_documents(text)
    parts = text.split(/(?=--- Tài liệu \d+)/)
    sections = parts.map(&:strip).reject(&:blank?)
    sections.size > 1 ? sections : [text]
  end

  # Split on paragraph/section boundaries to avoid cutting mid-sentence
  def split_into_chunks(text, max_chars)
    return [text] if text.length <= max_chars

    chunks = []
    remaining = text
    while remaining.length > max_chars
      # Try to cut at a double newline (paragraph boundary) within the limit
      cut = remaining[0, max_chars].rindex(/\n\n|\n---/) || max_chars
      chunks << remaining[0, cut].strip
      remaining = remaining[cut..].lstrip
    end
    chunks << remaining.strip unless remaining.blank?
    chunks
  end

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

  def build_prompt(count, custom_prompt, doc_count = 1)
    if count.nil?
      doc_hint = doc_count > 1 ? "There are #{doc_count} separate documents in the content below. " : ""
      count_instruction = "#{doc_hint}Extract EVERY multiple-choice question from ALL documents/sections. Do not stop early. Do not invent new ones — only extract questions that already exist in the text."
    else
      count_instruction = "Generate exactly #{count} multiple-choice questions based on the content."
    end
    user_instruction = custom_prompt.present? ? "\n\nAdditional instructions: #{custom_prompt}" : ""
    <<~PROMPT
      #{count_instruction}#{user_instruction}

      Return ONLY this JSON (no other text, no markdown):
      {"questions":[{"question":"...","options":[{"text":"...","correct":true},{"text":"...","correct":false},{"text":"...","correct":false},{"text":"...","correct":false}],"explanation":"..."}]}
    PROMPT
  end
end
