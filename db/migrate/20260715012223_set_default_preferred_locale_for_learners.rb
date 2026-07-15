class SetDefaultPreferredLocaleForLearners < ActiveRecord::Migration[7.2]
  def up
    # Backfill existing learners who never explicitly chose a locale
    execute "UPDATE learners SET preferred_locale = 'vi' WHERE preferred_locale IS NULL"
    # Ensure future new learners also default to Vietnamese
    change_column_default :learners, :preferred_locale, from: nil, to: "vi"
  end

  def down
    change_column_default :learners, :preferred_locale, from: "vi", to: nil
  end
end
