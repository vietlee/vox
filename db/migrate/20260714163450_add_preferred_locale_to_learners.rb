class AddPreferredLocaleToLearners < ActiveRecord::Migration[7.2]
  def change
    add_column :learners, :preferred_locale, :string
  end
end
