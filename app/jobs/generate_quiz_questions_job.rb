class GenerateQuizQuestionsJob < ApplicationJob
  queue_as :default

  def perform(quiz_set_id, cache_key, questions_count, custom_prompt)
    quiz_set = QuizSet.find_by(id: quiz_set_id)
    return unless quiz_set

    content = Rails.cache.read(cache_key)
    raise "Uploaded content expired. Please re-upload the file." if content.blank?

    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    if content.is_a?(Hash) && content[:image_base64]
      messages = [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: content[:mime_type], data: content[:image_base64] } },
          { type: "text", text: build_prompt(questions_count, custom_prompt) }
        ]
      }]
      raw = svc.call(system_prompt: "You are a quiz generator. Always respond with valid JSON only.", messages: messages, max_tokens: 4000)
    else
      user_prompt = "#{build_prompt(questions_count, custom_prompt)}\n\n---\n#{content.to_s.truncate(12000)}"
      raw = svc.call(system_prompt: "You are a quiz generator. Always respond with valid JSON only.", user_prompt: user_prompt, max_tokens: 4000)
    end

    json_str = raw[/\{.*\}/m] || raw[/\[.*\]/m]
    raise "AI did not return valid JSON" if json_str.nil?

    parsed    = JSON.parse(json_str, symbolize_names: true) rescue JSON.parse(sanitize_latex(json_str), symbolize_names: true)
    questions = parsed.is_a?(Array) ? parsed : parsed[:questions]
    raise "No questions found in AI response" if questions.blank?

    ActiveRecord::Base.transaction do
      quiz_set.workspace.active_subscription&.deduct_credits!(5)
      quiz_set.update!(source_type: :ai_generated, ai_generating: false)
      questions.each_with_index do |q, idx|
        question = quiz_set.quiz_questions.create!(
          question_text: q[:question],
          question_type: :multiple_choice,
          explanation:   q[:explanation],
          position:      quiz_set.quiz_questions.count + idx
        )
        q[:options].each_with_index do |opt, oi|
          question.quiz_options.create!(option_text: opt[:text], is_correct: opt[:correct], position: oi)
        end
      end
    end

    Rails.cache.delete(cache_key)
  rescue => e
    quiz_set&.update(ai_generating: false)
    Rails.logger.error "[GenerateQuizQuestionsJob] #{quiz_set_id}: #{e.message}"
  end

  private

  def build_prompt(count, custom_prompt)
    count_instruction = count.nil? \
      ? "Extract ALL multiple-choice questions found in the document." \
      : "Generate exactly #{count} multiple-choice questions."
    user_instruction = custom_prompt.present? ? "\n\nAdditional instructions:\n#{custom_prompt}" : ""
    "#{count_instruction}#{user_instruction}\n\nReturn ONLY valid JSON:\n{\"questions\":[{\"question\":\"...\",\"options\":[{\"text\":\"...\",\"correct\":true/false},...],\"explanation\":\"...\"}]}"
  end

  def sanitize_latex(str)
    str.gsub(/\\(?!["\\/bfnrt]|u[0-9a-fA-F]{4})/, '\\\\')
  end
end
