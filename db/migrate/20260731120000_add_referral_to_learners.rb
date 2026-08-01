class AddReferralToLearners < ActiveRecord::Migration[7.2]
  def up
    add_column :learners, :referral_code,        :string
    add_column :learners, :referred_by_id,       :bigint
    add_column :learners, :referral_rewarded_at, :datetime

    # Backfill a unique referral code for every existing learner.
    Learner.reset_column_information
    Learner.where(referral_code: nil).find_each do |l|
      code = nil
      loop do
        code = SecureRandom.alphanumeric(7).upcase
        break unless Learner.exists?(referral_code: code)
      end
      l.update_columns(referral_code: code)
    end

    add_index :learners, :referral_code,  unique: true
    add_index :learners, :referred_by_id
  end

  def down
    remove_index  :learners, :referral_code
    remove_index  :learners, :referred_by_id
    remove_column :learners, :referral_code
    remove_column :learners, :referred_by_id
    remove_column :learners, :referral_rewarded_at
  end
end
