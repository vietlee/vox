class ApplicationJob < ActiveJob::Base
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3
end
