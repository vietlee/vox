class AddMaxCreditsToLearners < ActiveRecord::Migration[7.2]
  def change
    add_column :learners, :max_credits, :integer, default: 100, null: false
  end
end
