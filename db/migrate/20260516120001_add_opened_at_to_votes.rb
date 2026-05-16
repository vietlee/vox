class AddOpenedAtToVotes < ActiveRecord::Migration[7.2]
  def change
    add_column :votes, :opened_at, :datetime
  end
end
