class AddHistoryToLearnerSpeakingSessions < ActiveRecord::Migration[7.2]
  def change
    add_column :learner_speaking_sessions, :history, :jsonb
  end
end
