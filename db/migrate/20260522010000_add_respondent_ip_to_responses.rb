class AddRespondentIpToResponses < ActiveRecord::Migration[7.2]
  def change
    add_column :responses, :respondent_ip, :string
    add_index  :responses, [:survey_id, :respondent_ip]
  end
end
