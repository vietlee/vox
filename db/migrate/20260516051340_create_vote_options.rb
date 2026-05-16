class CreateVoteOptions < ActiveRecord::Migration[7.2]
  def change
    create_table :vote_options do |t|
      t.references  :vote,           null: false, foreign_key: true
      t.string      :label,          null: false
      t.string      :image
      t.integer     :position,       null: false, default: 0
      t.integer     :votes_count,    default: 0
      t.timestamps
    end
  end
end
