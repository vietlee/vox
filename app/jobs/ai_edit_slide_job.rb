class AiEditSlideJob < ApplicationJob
  queue_as :default

  def perform(outline_id, edit_prompt)
    outline = ContentOutline.find_by(id: outline_id)
    return unless outline&.pending?

    ContentOutlineGenerator.ai_edit(outline, edit_prompt)
  rescue => e
    outline&.update(status: :failed)
    Rails.logger.error "[AiEditSlideJob] #{outline_id}: #{e.message}"
  end
end
