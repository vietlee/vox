class AddDescriptionToVoteOptions < ActiveRecord::Migration[7.2]
  def change
    add_column :vote_options, :description, :text
  end
end
