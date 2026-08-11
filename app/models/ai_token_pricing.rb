# Converts real Claude token usage into AI credits for conversational features
# (AI Chat, AI Tutor) on BOTH the teacher web app and the learner mobile app.
#
# Replaces the old flat "N credits per session" model: a turn now costs credits
# proportional to how much the model actually processed + produced this turn.
# With prompt caching on the system prompt + conversation prefix, the re-sent
# history bills as cache reads and is excluded from `input_tokens`, so a turn's
# billable tokens ≈ the NEW question + the answer — i.e. its real length.
module AiTokenPricing
  # Billable (input + output) tokens covered by one credit. Tuned so a typical
  # tutoring exchange (~short question + a paragraph answer) costs ~1 credit,
  # while a long answer or a document/image turn scales up fairly. At Sonnet
  # rates this keeps every turn comfortably profitable vs. the 1.000đ/credit
  # sale price (see the credit-economics analysis).
  TOKENS_PER_CREDIT = 1_500

  # Every real turn costs at least this many credits, so a one-word exchange
  # still carries a token (and we never serve AI for free).
  MIN_CREDITS_PER_TURN = 1

  # Credits to charge for one turn given the API-reported usage. Cache-read
  # tokens are intentionally NOT passed in — only fresh input + output count.
  def self.credits_for(input_tokens:, output_tokens:)
    total = input_tokens.to_i + output_tokens.to_i
    return 0 if total <= 0
    [(total.to_f / TOKENS_PER_CREDIT).ceil, MIN_CREDITS_PER_TURN].max
  end
end
