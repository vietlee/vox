class DailyChallengeService
  def initialize(learner)
    @learner = learner
  end

  def generate(count = 5)
    questions = []
    questions += from_quiz_assignments(count * 2)
    questions += from_flashcards(count * 2) if questions.size < count

    # Dedupe by question text (ids aren't assigned yet — deduping by q["id"] here
    # collapsed everything to ONE question because every id was nil), then pick `count`.
    questions = questions.uniq { |q| q["text"] }.sample(count)
    questions.each_with_index { |q, i| q["id"] = i + 1 }
    questions
  end

  private

  def from_quiz_assignments(limit)
    quiz_set_ids = @learner.quiz_assignments.pluck(:quiz_set_id)
    return [] if quiz_set_ids.empty?

    # Get random MC question IDs first (avoids DISTINCT + ORDER BY RANDOM() conflict in PG)
    ids = QuizQuestion
      .joins(:quiz_options)
      .where(quiz_set_id: quiz_set_ids, question_type: 0)
      .pluck(:id)
      .uniq
      .sample(limit)

    return [] if ids.empty?

    QuizQuestion.includes(:quiz_options).where(id: ids)
      .map { |q| format_quiz_question(q) }
      .compact
  end

  def from_flashcards(limit)
    deck_ids = @learner.flashcard_assignments.pluck(:flashcard_deck_id)
    deck_ids += FlashcardDeck.where(learner_id: @learner.id).pluck(:id)
    return [] if deck_ids.empty?

    Flashcard
      .where(flashcard_deck_id: deck_ids.uniq)
      .order("RANDOM()")
      .limit(limit)
      .map { |c| format_flashcard_question(c) }
  end

  def format_quiz_question(question)
    opts = question.quiz_options.sort_by(&:position)
    return nil if opts.size < 2

    correct_idx = opts.index(&:is_correct)
    return nil unless correct_idx

    {
      "text"          => question.question_text,
      "options"       => opts.map(&:option_text),
      "correct_index" => correct_idx,
      "source"        => "quiz"
    }
  end

  def format_flashcard_question(card)
    correct = card.back
    distractors = Flashcard
      .where(flashcard_deck_id: card.flashcard_deck_id)
      .where.not(id: card.id)
      .order("RANDOM()")
      .limit(3)
      .pluck(:back)

    options = ([correct] + distractors).first(4)
    return nil if options.size < 2

    options.shuffle!
    correct_idx = options.index(correct)

    {
      "text"          => "\"#{card.front}\" nghĩa là gì?",
      "options"       => options,
      "correct_index" => correct_idx,
      "source"        => "flashcard"
    }
  end
end
