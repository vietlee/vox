class AddCreatedCountsToWorkspaces < ActiveRecord::Migration[7.2]
  def up
    add_column :workspaces, :surveys_created_count,   :integer, default: 0, null: false
    add_column :workspaces, :votes_created_count,     :integer, default: 0, null: false
    add_column :workspaces, :feedbacks_created_count, :integer, default: 0, null: false

    # Back-fill existing workspaces with current record counts
    Workspace.find_each do |ws|
      ws.update_columns(
        surveys_created_count:   ws.surveys.count,
        votes_created_count:     ws.votes.count,
        feedbacks_created_count: ws.feedback_boards.count
      )
    end
  end

  def down
    remove_column :workspaces, :surveys_created_count
    remove_column :workspaces, :votes_created_count
    remove_column :workspaces, :feedbacks_created_count
  end
end
