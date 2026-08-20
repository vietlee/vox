class AiSurveyBuilderJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job = AiJob.find(job_id)
    job.start!

    prompt    = job.input_data["prompt"]
    language  = job.input_data["language"] || "vi"
    lang_name = language == "vi" ? "Vietnamese" : "English"
    has_files = job.input_files.attached?

    system_prompt = <<~PROMPT
      You are an expert HR survey designer with 15 years of experience.
      Generate professional, psychologically-valid surveys in #{lang_name}.
      Always return ONLY valid JSON — no markdown, no explanation, no code fences.
    PROMPT

    user_prompt = build_user_prompt(prompt, lang_name, has_files)

    svc = ClaudeService.for_feature("survey_builder")
    result_text =
      if has_files
        svc.call(
          system_prompt: system_prompt,
          messages: [{ role: "user", content: file_content_blocks(job) + [{ type: "text", text: user_prompt }] }],
          max_tokens: 6000
        )
      else
        svc.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 6000)
      end

    # Strip markdown code fences if present, then extract JSON object
    cleaned = result_text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
    json_str = cleaned.match(/\{.*\}/m)&.to_s || cleaned
    survey_data = JSON.parse(json_str)

    raise "No questions generated" if survey_data["questions"].blank?

    job.complete!(survey_data)
  rescue => e
    job.fail!(e.message)
  end

  private

  # Turns each attached file into a Claude content block (image or extracted text).
  def file_content_blocks(job)
    job.input_files.filter_map do |file|
      FileContentExtractor.to_claude_block(
        data:         file.download,
        filename:     file.filename.to_s,
        content_type: file.content_type
      )
    end
  end

  def build_user_prompt(prompt, lang_name, has_files)
    attachment_note =
      if has_files
        <<~NOTE
          The user has ATTACHED one or more images/documents above. They may contain:
          (a) an existing list of survey/quiz questions — in that case KEEP each question's
              wording and intent, only normalize its "question_type" and "options" to fit the
              survey format, and add/adjust questions per the user's request; OR
          (b) reference material/content — in that case generate suitable questions from it.
          Decide which case applies from the actual content. Always prioritise the user's request below.

        NOTE
      else
        ""
      end

    <<~PROMPT
      #{attachment_note}Create a complete, ready-to-use survey based on this objective: "#{prompt}"

      Return this exact JSON structure:
      {
        "title": "Clear, specific survey title",
        "description": "2-3 sentence description explaining the survey purpose and estimated time to complete",
        "thank_you_message": "Warm thank-you message acknowledging their participation",
        "questions": [
          {
            "title": "Question text",
            "question_type": "nps|rating|linear_scale|single_choice|multiple_choice|short_text|long_text|dropdown",
            "required": true,
            "description": "Optional clarifying instruction (or null)",
            "options": ["Option A", "Option B"],
            "settings": {}
          }
        ]
      }

      REQUIREMENTS:
      - #{has_files ? "If the attachment already contains questions, produce one JSON question per source question (keep them all); otherwise generate 10-14 questions" : "Generate 10-14 questions"} covering all important aspects of the topic
      - Use diverse question types — do not repeat the same type more than 3 times consecutively
      - Prefer 1 NPS question (overall recommendation score) when relevant to the topic
      - Include 2-3 rating questions (1-5 scale for key satisfaction dimensions) when relevant
      - Include 2-3 single_choice or multiple_choice questions with realistic answer choices
      - Include 1-2 long_text questions for open qualitative insights
      - Include 1-2 short_text questions for specific factual answers
      - Use single_choice for questions with one correct/applicable answer (radio); use multiple_choice for "select all that apply" (checkboxes)
      - For single_choice/multiple_choice/dropdown: always include "options" array with realistic choices
      - For rating/nps/linear_scale: omit "options"
      - Mark essential questions required:true, optional follow-ups required:false
      - Write all content in #{lang_name}, professional and neutral tone
      - Order logically: general → specific, demographics last
    PROMPT
  end
end
