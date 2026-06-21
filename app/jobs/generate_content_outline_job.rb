class GenerateContentOutlineJob < ApplicationJob
  queue_as :default

  def perform(outline_id)
    outline = ContentOutline.find_by(id: outline_id)
    return unless outline&.pending?

    ContentOutlineGenerator.call(outline)
  rescue => e
    outline&.update(status: :failed)
    Rails.logger.error "[GenerateContentOutlineJob] #{outline_id}: #{e.message}"
  end
end
