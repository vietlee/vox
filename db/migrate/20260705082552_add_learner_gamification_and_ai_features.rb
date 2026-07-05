class AddLearnerGamificationAndAiFeatures < ActiveRecord::Migration[7.2]
  def change
    # ── Gamification: XP + streak + daily goal on learners ──
    add_column :learners, :xp,             :integer, default: 0, null: false
    add_column :learners, :current_streak, :integer, default: 0, null: false
    add_column :learners, :longest_streak, :integer, default: 0, null: false
    add_column :learners, :last_active_on, :date
    add_column :learners, :daily_goal,     :integer, default: 3, null: false

    # ── Per-day activity log (powers streak, daily goal, progress charts) ──
    create_table :learner_daily_stats do |t|
      t.bigint  :learner_id, null: false
      t.date    :day,        null: false
      t.integer :xp,         default: 0, null: false
      t.integer :activities, default: 0, null: false
      t.timestamps
    end
    add_index :learner_daily_stats, [:learner_id, :day], unique: true

    # ── AI personalized study plan ──
    create_table :learner_study_plans do |t|
      t.bigint  :learner_id, null: false
      t.string  :title,      null: false
      t.text    :focus
      t.integer :status,     default: 0, null: false  # active / completed
      t.timestamps
    end
    add_index :learner_study_plans, :learner_id

    create_table :learner_study_plan_items do |t|
      t.bigint  :learner_study_plan_id, null: false
      t.integer :position,   default: 0
      t.string  :kind                       # flashcard | quiz | tutor | read
      t.string  :title,      null: false
      t.text    :description
      t.string  :topic                      # prefill for flashcard/tutor
      t.string  :action_url
      t.boolean :done,       default: false, null: false
      t.datetime :done_at
      t.timestamps
    end
    add_index :learner_study_plan_items, :learner_study_plan_id

    # ── AI speaking practice sessions ──
    create_table :learner_speaking_sessions do |t|
      t.bigint  :learner_id, null: false
      t.string  :language,   default: "en"
      t.string  :scenario
      t.integer :turns,      default: 0, null: false
      t.integer :score                     # optional AI-graded 0-100
      t.text    :feedback
      t.timestamps
    end
    add_index :learner_speaking_sessions, :learner_id
  end
end
