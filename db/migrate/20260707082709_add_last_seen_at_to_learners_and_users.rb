class AddLastSeenAtToLearnersAndUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :learners, :last_seen_at, :datetime
    add_column :users,    :last_seen_at, :datetime
    add_index  :learners, :last_seen_at
    add_index  :users,    :last_seen_at
  end
end
