class AddResultTokenToQuizAttempts < ActiveRecord::Migration[7.2]
  def change
    add_column :quiz_attempts, :result_token, :string
    add_index  :quiz_attempts, :result_token, unique: true
  end
end
