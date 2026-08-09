# Single source of truth for how many AI credits each teacher-side action costs.
#
# Flat pricing: one fixed cost per action, independent of the AI model chosen.
# Both the deduction sites (controllers/jobs) AND the displayed price notes
# (AiModelConfig) read from here, so the number a teacher sees always equals
# the number they are charged.
#
# Values are the amounts historically charged, so this refactor changes *where*
# the numbers live, not what users pay.
module CreditCost
  COSTS = {
    # ── Surveys / votes / feedback (AiController, feedback, votes) ──
    survey_builder:         5,  # ai#generate_survey
    question_checker:       1,  # ai#check_question
    survey_analysis:        5,  # ai#analyze_survey
    executive_report:      15,  # ai#generate_report
    ai_chat:                2,  # ai#chat
    survey_suggest_prompt:  3,  # surveys#ai_suggest_prompt
    feedback_summarize:     3,  # feedback_boards#ai_summarize
    moderation:             1,  # AiModerationJob

    # ── Quiz ──
    quiz_generate:          5,  # quiz_sets#create/#ai_generate + GenerateQuizQuestionsJob
    quiz_eval_student:      2,  # quiz_sets#ai_evaluate_attempt
    quiz_eval_class:        3,  # quiz_sets#ai_evaluate_results
    quiz_grade_essay:       1,  # quiz_sets#ai_grade_essay

    # ── Flashcards ──
    flashcard_generate:     3,  # flashcard_decks#create/#ai_generate + GenerateFlashcardsJob
    flashcard_images:       5,  # flashcard_decks#generate_images + GenerateFlashcardImagesJob

    # ── Learning paths ──
    learning_path_generate: 5,  # learning_paths#ai_generate + GenerateLearningPathJob
    learning_path_eval:     3,  # learning_paths#ai_evaluate_progress
    lp_item_content:        2,  # learning_path_items#ai_content
    lp_item_quiz:           5,  # learning_path_items#ai_create_quiz
    lp_item_flashcard:      3,  # learning_path_items#ai_create_flashcard
    lp_assignment_eval:     2,  # learning_path_assignments#ai_evaluate

    # ── Tools ──
    document_summary:       2,  # GenerateDocumentSummaryJob
    tutor:                  1,  # ai#tutor
    tutor_voice:            1,  # ai#tutor_voice
    writing:                1,  # ai#writing
    stt_enhance:            2,  # STT post-processing (per call)
  }.freeze

  # Raises for unknown keys so a typo fails loudly instead of silently charging 0.
  def self.[](key)
    COSTS.fetch(key) { raise ArgumentError, "Unknown credit cost key: #{key.inspect}" }
  end
end
