class MonthlyFreeResetJob < ApplicationJob
  queue_as :default

  def perform
    reset_at = Time.current

    # Find all workspaces on the free plan
    free_workspace_ids = Subscription.active.free.pluck(:workspace_id)
    return if free_workspace_ids.empty?

    Workspace.where(id: free_workspace_ids).find_each do |workspace|
      workspace.update_columns(
        surveys_created_count:       0,
        votes_created_count:         0,
        feedbacks_created_count:     0,
        dynamic_forms_created_count: 0,
        counts_reset_at:             reset_at
      )
    end

    Rails.logger.info("[MonthlyFreeReset] Reset counts for #{free_workspace_ids.size} free workspaces at #{reset_at}")
  end
end
