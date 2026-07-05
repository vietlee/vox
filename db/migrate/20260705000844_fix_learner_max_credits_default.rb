class FixLearnerMaxCreditsDefault < ActiveRecord::Migration[7.2]
  MONTHLY_FREE = 50

  def up
    change_column_default :learners, :max_credits, from: 100, to: MONTHLY_FREE
    Learner.where(max_credits: 100).update_all(max_credits: MONTHLY_FREE)
  end

  def down
    change_column_default :learners, :max_credits, from: MONTHLY_FREE, to: 100
  end
end
