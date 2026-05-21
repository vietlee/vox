class AddLoginProvidersToSurveys < ActiveRecord::Migration[7.2]
  def change
    add_column :surveys, :login_providers, :string, default: "both"
  end
end
