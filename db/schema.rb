# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_07_14_163752) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "action_items", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "feedback_board_id", null: false
    t.string "title"
    t.text "description"
    t.integer "priority"
    t.integer "status"
    t.integer "assignee_id"
    t.integer "ai_analysis_result_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feedback_board_id"], name: "index_action_items_on_feedback_board_id"
    t.index ["workspace_id"], name: "index_action_items_on_workspace_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addon_configs", force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.string "addon_type", default: "resource_pack", null: false
    t.integer "price_cents", default: 0, null: false
    t.integer "surveys_bonus", default: 0
    t.integer "votes_bonus", default: 0
    t.integer "feedbacks_bonus", default: 0
    t.integer "ai_credits_bonus", default: 0
    t.boolean "active", default: true, null: false
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ai_analysis_results", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "ai_job_id", null: false
    t.string "result_type", null: false
    t.string "resource_type"
    t.integer "resource_id"
    t.jsonb "output", default: {}, null: false
    t.integer "credits_cost", default: 0
    t.integer "response_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_job_id"], name: "index_ai_analysis_results_on_ai_job_id"
    t.index ["resource_type", "resource_id"], name: "index_ai_analysis_results_on_resource_type_and_resource_id"
    t.index ["result_type"], name: "index_ai_analysis_results_on_result_type"
    t.index ["workspace_id"], name: "index_ai_analysis_results_on_workspace_id"
  end

  create_table "ai_jobs", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "user_id"
    t.string "job_type", null: false
    t.integer "status", default: 0, null: false
    t.string "resource_type"
    t.integer "resource_id"
    t.jsonb "input_data", default: {}
    t.jsonb "output_data", default: {}
    t.integer "credits_cost", default: 0
    t.string "model_used"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_type"], name: "index_ai_jobs_on_job_type"
    t.index ["resource_type", "resource_id"], name: "index_ai_jobs_on_resource_type_and_resource_id"
    t.index ["status"], name: "index_ai_jobs_on_status"
    t.index ["user_id"], name: "index_ai_jobs_on_user_id"
    t.index ["workspace_id"], name: "index_ai_jobs_on_workspace_id"
  end

  create_table "ai_model_configs", force: :cascade do |t|
    t.string "feature_key", null: false
    t.string "model_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_key"], name: "index_ai_model_configs_on_feature_key", unique: true
  end

  create_table "answers", force: :cascade do |t|
    t.bigint "response_id", null: false
    t.bigint "question_id", null: false
    t.text "text_value"
    t.jsonb "option_ids", default: []
    t.jsonb "matrix_values", default: {}
    t.float "numeric_value"
    t.date "date_value"
    t.string "file_attachment"
    t.integer "score", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_answers_on_question_id"
    t.index ["response_id"], name: "index_answers_on_response_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "workspace_id"
    t.bigint "user_id"
    t.string "action", null: false
    t.string "resource_type"
    t.integer "resource_id"
    t.jsonb "changes_data", default: {}
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "resource_label"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
    t.index ["workspace_id"], name: "index_audit_logs_on_workspace_id"
  end

  create_table "content_outlines", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "created_by_id", null: false
    t.string "title", null: false
    t.string "subject"
    t.string "output_type"
    t.text "prompt_input"
    t.text "content"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "slide_json"
    t.string "share_token"
    t.text "source_document_text"
    t.index ["created_by_id"], name: "index_content_outlines_on_created_by_id"
    t.index ["workspace_id"], name: "index_content_outlines_on_workspace_id"
  end

  create_table "document_summaries", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "created_by_id", null: false
    t.string "title"
    t.string "source_type"
    t.string "source_filename"
    t.text "source_text"
    t.text "summary"
    t.text "key_points"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_document_summaries_on_created_by_id"
    t.index ["workspace_id"], name: "index_document_summaries_on_workspace_id"
  end

  create_table "dynamic_form_assignments", force: :cascade do |t|
    t.bigint "dynamic_form_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dynamic_form_id", "user_id"], name: "index_dynamic_form_assignments_on_dynamic_form_id_and_user_id", unique: true
    t.index ["dynamic_form_id"], name: "index_dynamic_form_assignments_on_dynamic_form_id"
    t.index ["user_id"], name: "index_dynamic_form_assignments_on_user_id"
  end

  create_table "dynamic_form_fields", force: :cascade do |t|
    t.bigint "dynamic_form_id", null: false
    t.string "label", null: false
    t.string "field_key", null: false
    t.string "field_type", default: "text", null: false
    t.string "placeholder"
    t.text "hint"
    t.boolean "required", default: false, null: false
    t.jsonb "options", default: [], null: false
    t.integer "min_length"
    t.integer "max_length"
    t.string "min_value"
    t.string "max_value"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "accept"
    t.integer "max_size_mb"
    t.boolean "multiple", default: false, null: false
    t.jsonb "conditional_logic", default: {}, null: false
    t.boolean "admin_only", default: false, null: false
    t.boolean "admin_editable", default: false, null: false
    t.index ["dynamic_form_id"], name: "index_dynamic_form_fields_on_dynamic_form_id"
  end

  create_table "dynamic_form_submissions", force: :cascade do |t|
    t.bigint "dynamic_form_id", null: false
    t.jsonb "data", default: {}, null: false
    t.string "respondent_token"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.integer "assignee_id"
    t.string "custom_status"
    t.index ["assignee_id"], name: "index_dynamic_form_submissions_on_assignee_id"
    t.index ["dynamic_form_id"], name: "index_dynamic_form_submissions_on_dynamic_form_id"
    t.index ["status"], name: "index_dynamic_form_submissions_on_status"
  end

  create_table "dynamic_forms", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.integer "submissions_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "settings", default: {}, null: false
    t.index ["slug"], name: "index_dynamic_forms_on_slug", unique: true
    t.index ["user_id"], name: "index_dynamic_forms_on_user_id"
    t.index ["workspace_id", "slug"], name: "index_dynamic_forms_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_dynamic_forms_on_workspace_id"
  end

  create_table "feedback_boards", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.integer "identity_mode", default: 0, null: false
    t.boolean "auto_moderation", default: true
    t.boolean "manual_approval", default: false
    t.boolean "allow_replies", default: true
    t.boolean "allow_upvotes", default: true
    t.string "slug"
    t.jsonb "tags", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "allow_voice_input", default: false, null: false
    t.index ["slug"], name: "index_feedback_boards_on_slug", unique: true
    t.index ["status"], name: "index_feedback_boards_on_status"
    t.index ["user_id"], name: "index_feedback_boards_on_user_id"
    t.index ["workspace_id"], name: "index_feedback_boards_on_workspace_id"
  end

  create_table "feedback_replies", force: :cascade do |t|
    t.bigint "feedback_id", null: false
    t.string "author_name"
    t.boolean "anonymous", default: true
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feedback_id"], name: "index_feedback_replies_on_feedback_id"
  end

  create_table "feedback_upvotes", force: :cascade do |t|
    t.bigint "feedback_id", null: false
    t.string "voter_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feedback_id", "voter_token"], name: "index_feedback_upvotes_on_feedback_id_and_voter_token", unique: true
    t.index ["feedback_id"], name: "index_feedback_upvotes_on_feedback_id"
  end

  create_table "feedbacks", force: :cascade do |t|
    t.bigint "feedback_board_id", null: false
    t.bigint "workspace_id", null: false
    t.text "content", null: false
    t.string "author_name"
    t.string "author_email"
    t.boolean "anonymous", default: true
    t.string "image_attachment"
    t.integer "status", default: 0, null: false
    t.integer "admin_status", default: 0, null: false
    t.integer "upvotes_count", default: 0
    t.boolean "pinned", default: false
    t.text "admin_reply"
    t.datetime "admin_replied_at"
    t.integer "moderation_status", default: 0
    t.float "priority_score"
    t.string "cluster_label"
    t.text "moderation_reason"
    t.jsonb "ai_analysis", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feedback_board_id"], name: "index_feedbacks_on_feedback_board_id"
    t.index ["moderation_status"], name: "index_feedbacks_on_moderation_status"
    t.index ["pinned"], name: "index_feedbacks_on_pinned"
    t.index ["status"], name: "index_feedbacks_on_status"
    t.index ["workspace_id"], name: "index_feedbacks_on_workspace_id"
  end

  create_table "flashcard_assignments", force: :cascade do |t|
    t.bigint "flashcard_deck_id", null: false
    t.bigint "learner_id", null: false
    t.bigint "assigned_by_id"
    t.string "token", null: false
    t.integer "status", default: 0, null: false
    t.datetime "due_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "cards_reviewed", default: 0, null: false
    t.index ["flashcard_deck_id", "learner_id"], name: "idx_on_flashcard_deck_id_learner_id_acaee1ea5f", unique: true
    t.index ["flashcard_deck_id"], name: "index_flashcard_assignments_on_flashcard_deck_id"
    t.index ["learner_id"], name: "index_flashcard_assignments_on_learner_id"
    t.index ["token"], name: "index_flashcard_assignments_on_token", unique: true
  end

  create_table "flashcard_decks", force: :cascade do |t|
    t.bigint "workspace_id"
    t.bigint "created_by_id"
    t.string "title", null: false
    t.string "subject"
    t.boolean "ai_generated", default: false
    t.integer "card_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ai_generating", default: false
    t.boolean "image_generating", default: false
    t.bigint "learner_id"
    t.index ["created_by_id"], name: "index_flashcard_decks_on_created_by_id"
    t.index ["learner_id"], name: "index_flashcard_decks_on_learner_id"
    t.index ["workspace_id"], name: "index_flashcard_decks_on_workspace_id"
  end

  create_table "flashcard_reviews", force: :cascade do |t|
    t.bigint "flashcard_id", null: false
    t.bigint "user_id"
    t.integer "rating", default: 0
    t.integer "interval_days", default: 1
    t.float "ease_factor", default: 2.5
    t.datetime "next_review_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "learner_id"
    t.index ["flashcard_id", "learner_id"], name: "index_fc_reviews_on_flashcard_and_learner", unique: true, where: "(learner_id IS NOT NULL)"
    t.index ["flashcard_id", "user_id"], name: "index_flashcard_reviews_on_flashcard_id_and_user_id", unique: true
    t.index ["flashcard_id"], name: "index_flashcard_reviews_on_flashcard_id"
    t.index ["learner_id", "next_review_at"], name: "index_fc_reviews_on_learner_and_next_review"
    t.index ["user_id", "next_review_at"], name: "index_flashcard_reviews_on_user_id_and_next_review_at"
    t.index ["user_id"], name: "index_flashcard_reviews_on_user_id"
  end

  create_table "flashcards", force: :cascade do |t|
    t.bigint "flashcard_deck_id", null: false
    t.text "front", null: false
    t.text "back", null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "image_data"
    t.index ["flashcard_deck_id"], name: "index_flashcards_on_flashcard_deck_id"
  end

  create_table "learner_badges", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.string "key", null: false
    t.datetime "earned_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id", "key"], name: "index_learner_badges_on_learner_id_and_key", unique: true
    t.index ["learner_id"], name: "index_learner_badges_on_learner_id"
  end

  create_table "learner_daily_challenges", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.date "challenge_date", null: false
    t.jsonb "questions", default: []
    t.jsonb "submitted_answers", default: {}
    t.integer "score", default: 0
    t.integer "total", default: 5
    t.boolean "completed", default: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id", "challenge_date"], name: "idx_on_learner_id_challenge_date_8742452dc7", unique: true
    t.index ["learner_id"], name: "index_learner_daily_challenges_on_learner_id"
  end

  create_table "learner_daily_stats", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.date "day", null: false
    t.integer "xp", default: 0, null: false
    t.integer "activities", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id", "day"], name: "index_learner_daily_stats_on_learner_id_and_day", unique: true
  end

  create_table "learner_folder_members", force: :cascade do |t|
    t.bigint "learner_folder_id", null: false
    t.bigint "learner_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_folder_id", "learner_id"], name: "idx_learner_folder_members_unique", unique: true
    t.index ["learner_folder_id"], name: "index_learner_folder_members_on_learner_folder_id"
    t.index ["learner_id"], name: "index_learner_folder_members_on_learner_id"
  end

  create_table "learner_folders", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "created_by_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_learner_folders_on_created_by_id"
    t.index ["workspace_id"], name: "index_learner_folders_on_workspace_id"
  end

  create_table "learner_notifications", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.string "title", null: false
    t.text "body"
    t.string "notification_type", default: "general", null: false
    t.boolean "read", default: false, null: false
    t.string "action_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id", "read"], name: "index_learner_notifications_on_learner_id_and_read"
    t.index ["learner_id"], name: "index_learner_notifications_on_learner_id"
  end

  create_table "learner_payments", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.integer "amount_cents"
    t.string "currency"
    t.integer "status"
    t.string "gateway"
    t.bigint "payos_order_code"
    t.string "payment_link_id"
    t.string "invoice_number"
    t.integer "credits_amount"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id"], name: "index_learner_payments_on_learner_id"
  end

  create_table "learner_push_subscriptions", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.text "endpoint", null: false
    t.string "p256dh_key"
    t.string "auth_key"
    t.string "reminder_hour", default: "20"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_learner_push_subscriptions_on_endpoint", unique: true
    t.index ["learner_id"], name: "index_learner_push_subscriptions_on_learner_id"
  end

  create_table "learner_saved_links", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.text "url", null: false
    t.string "title"
    t.text "description"
    t.string "thumbnail"
    t.string "favicon"
    t.string "category", default: "learning", null: false
    t.string "link_type", default: "generic", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id", "position"], name: "index_learner_saved_links_on_learner_id_and_position"
    t.index ["learner_id"], name: "index_learner_saved_links_on_learner_id"
  end

  create_table "learner_speaking_sessions", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.string "language", default: "en"
    t.string "scenario"
    t.integer "turns", default: 0, null: false
    t.integer "score"
    t.text "feedback"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "history"
    t.index ["learner_id"], name: "index_learner_speaking_sessions_on_learner_id"
  end

  create_table "learner_study_plan_items", force: :cascade do |t|
    t.bigint "learner_study_plan_id", null: false
    t.integer "position", default: 0
    t.string "kind"
    t.string "title", null: false
    t.text "description"
    t.string "topic"
    t.string "action_url"
    t.boolean "done", default: false, null: false
    t.datetime "done_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_study_plan_id"], name: "index_learner_study_plan_items_on_learner_study_plan_id"
  end

  create_table "learner_study_plans", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.string "title", null: false
    t.text "focus"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id"], name: "index_learner_study_plans_on_learner_id"
  end

  create_table "learner_suggestions", force: :cascade do |t|
    t.bigint "learner_id", null: false
    t.string "kind"
    t.string "title", null: false
    t.text "body", null: false
    t.string "action_label"
    t.string "action_url"
    t.string "prefill_topic"
    t.datetime "dismissed_at"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id"], name: "index_learner_suggestions_on_learner_id"
  end

  create_table "learners", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "name", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "credits", default: 50, null: false
    t.string "invite_token"
    t.datetime "invite_sent_at"
    t.boolean "password_set", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "ai_analysis_html"
    t.datetime "ai_analyzed_at"
    t.integer "max_credits", default: 50, null: false
    t.integer "xp", default: 0, null: false
    t.integer "current_streak", default: 0, null: false
    t.integer "longest_streak", default: 0, null: false
    t.date "last_active_on"
    t.integer "daily_goal", default: 3, null: false
    t.datetime "last_seen_at"
    t.string "preferred_locale"
    t.index ["confirmation_token"], name: "index_learners_on_confirmation_token", unique: true
    t.index ["email"], name: "index_learners_on_email", unique: true
    t.index ["invite_token"], name: "index_learners_on_invite_token", unique: true
    t.index ["last_seen_at"], name: "index_learners_on_last_seen_at"
    t.index ["reset_password_token"], name: "index_learners_on_reset_password_token", unique: true
  end

  create_table "learning_item_progresses", force: :cascade do |t|
    t.bigint "learning_path_assignment_id", null: false
    t.bigint "learning_path_item_id", null: false
    t.integer "status", default: 0
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learning_path_assignment_id"], name: "index_learning_item_progresses_on_learning_path_assignment_id"
    t.index ["learning_path_item_id"], name: "index_learning_item_progresses_on_learning_path_item_id"
  end

  create_table "learning_path_assignments", force: :cascade do |t|
    t.bigint "learning_path_id", null: false
    t.bigint "assigned_by_id", null: false
    t.bigint "assignee_id"
    t.date "due_date"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "ai_feedback"
    t.datetime "ai_feedback_at"
    t.bigint "learner_id"
    t.string "token"
    t.datetime "completed_at"
    t.index ["assigned_by_id"], name: "index_learning_path_assignments_on_assigned_by_id"
    t.index ["assignee_id"], name: "index_learning_path_assignments_on_assignee_id"
    t.index ["learner_id"], name: "index_learning_path_assignments_on_learner_id"
    t.index ["learning_path_id", "assignee_id"], name: "idx_on_learning_path_id_assignee_id_44b44d6f23", unique: true
    t.index ["learning_path_id"], name: "index_learning_path_assignments_on_learning_path_id"
    t.index ["token"], name: "index_learning_path_assignments_on_token", unique: true
  end

  create_table "learning_path_items", force: :cascade do |t|
    t.bigint "learning_path_id", null: false
    t.integer "item_type", null: false
    t.bigint "quiz_set_id"
    t.string "title", null: false
    t.text "content"
    t.integer "position", default: 0
    t.integer "estimated_minutes", default: 15
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "flashcard_deck_id"
    t.index ["learning_path_id", "position"], name: "index_learning_path_items_on_learning_path_id_and_position"
    t.index ["learning_path_id"], name: "index_learning_path_items_on_learning_path_id"
  end

  create_table "learning_paths", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "created_by_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "subject"
    t.integer "status", default: 0
    t.boolean "ai_generated", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ai_generating", default: false
    t.index ["created_by_id"], name: "index_learning_paths_on_created_by_id"
    t.index ["workspace_id"], name: "index_learning_paths_on_workspace_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "user_id", null: false
    t.string "notification_type", null: false
    t.string "title", null: false
    t.text "body"
    t.boolean "read", default: false
    t.string "resource_type"
    t.integer "resource_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["user_id", "read"], name: "index_notifications_on_user_id_and_read"
    t.index ["user_id"], name: "index_notifications_on_user_id"
    t.index ["workspace_id"], name: "index_notifications_on_workspace_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "subscription_id", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "VND"
    t.integer "status", default: 0, null: false
    t.string "gateway", null: false
    t.string "gateway_transaction_id"
    t.string "invoice_number"
    t.jsonb "gateway_response", default: {}
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "payos_order_code"
    t.string "payment_link_id"
    t.bigint "addon_config_id"
    t.index ["addon_config_id"], name: "index_payments_on_addon_config_id"
    t.index ["gateway"], name: "index_payments_on_gateway"
    t.index ["payos_order_code"], name: "index_payments_on_payos_order_code", unique: true, where: "(payos_order_code IS NOT NULL)"
    t.index ["status"], name: "index_payments_on_status"
    t.index ["subscription_id"], name: "index_payments_on_subscription_id"
    t.index ["workspace_id"], name: "index_payments_on_workspace_id"
  end

  create_table "plan_configs", force: :cascade do |t|
    t.string "plan_key", null: false
    t.string "display_name", null: false
    t.integer "price_vnd", default: 0, null: false
    t.string "billing_cycle", default: "month"
    t.jsonb "limits", default: {}, null: false
    t.jsonb "features", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "monthly_free_credits", default: 100, null: false
    t.index ["plan_key"], name: "index_plan_configs_on_plan_key", unique: true
  end

  create_table "qr_codes", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "resource_type", null: false
    t.integer "resource_id", null: false
    t.string "token", null: false
    t.string "foreground_color", default: "#000000"
    t.string "background_color", default: "#FFFFFF"
    t.boolean "show_logo", default: false
    t.integer "scan_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_type", "resource_id"], name: "index_qr_codes_on_resource_type_and_resource_id", unique: true
    t.index ["token"], name: "index_qr_codes_on_token", unique: true
    t.index ["workspace_id"], name: "index_qr_codes_on_workspace_id"
  end

  create_table "question_options", force: :cascade do |t|
    t.bigint "question_id", null: false
    t.string "label", null: false
    t.string "image"
    t.integer "position", default: 0, null: false
    t.integer "score", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_question_options_on_question_id"
  end

  create_table "questions", force: :cascade do |t|
    t.bigint "survey_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "image"
    t.integer "question_type", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.integer "section", default: 0
    t.boolean "required", default: false
    t.jsonb "settings", default: {}
    t.jsonb "conditional_logic", default: {}
    t.integer "score_weight", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["survey_id", "position"], name: "index_questions_on_survey_id_and_position"
    t.index ["survey_id"], name: "index_questions_on_survey_id"
  end

  create_table "quiz_assignments", force: :cascade do |t|
    t.bigint "quiz_set_id", null: false
    t.bigint "learner_id", null: false
    t.bigint "assigned_by_id"
    t.string "token", null: false
    t.integer "status", default: 0, null: false
    t.datetime "due_at"
    t.text "message"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_id"], name: "index_quiz_assignments_on_learner_id"
    t.index ["quiz_set_id", "learner_id"], name: "index_quiz_assignments_on_quiz_set_id_and_learner_id", unique: true
    t.index ["quiz_set_id"], name: "index_quiz_assignments_on_quiz_set_id"
    t.index ["token"], name: "index_quiz_assignments_on_token", unique: true
  end

  create_table "quiz_attempt_answers", force: :cascade do |t|
    t.bigint "quiz_attempt_id", null: false
    t.bigint "quiz_question_id", null: false
    t.bigint "quiz_option_id"
    t.text "text_answer"
    t.boolean "is_correct", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "essay_text"
    t.integer "ai_grade"
    t.text "ai_feedback"
    t.datetime "ai_graded_at"
    t.index ["quiz_attempt_id"], name: "index_quiz_attempt_answers_on_quiz_attempt_id"
    t.index ["quiz_option_id"], name: "index_quiz_attempt_answers_on_quiz_option_id"
    t.index ["quiz_question_id"], name: "index_quiz_attempt_answers_on_quiz_question_id"
  end

  create_table "quiz_attempts", force: :cascade do |t|
    t.bigint "quiz_set_id", null: false
    t.string "participant_name", null: false
    t.string "participant_email", null: false
    t.integer "score", default: 0, null: false
    t.integer "total_questions", default: 0, null: false
    t.integer "total_points", default: 0, null: false
    t.integer "earned_points", default: 0, null: false
    t.datetime "submitted_at"
    t.integer "time_spent_seconds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "started_at"
    t.string "result_token"
    t.text "ai_evaluation"
    t.datetime "ai_evaluated_at"
    t.index ["quiz_set_id", "participant_email"], name: "index_quiz_attempts_on_quiz_set_id_and_participant_email"
    t.index ["quiz_set_id"], name: "index_quiz_attempts_on_quiz_set_id"
    t.index ["result_token"], name: "index_quiz_attempts_on_result_token", unique: true
  end

  create_table "quiz_options", force: :cascade do |t|
    t.bigint "quiz_question_id", null: false
    t.text "option_text", null: false
    t.boolean "is_correct", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["quiz_question_id"], name: "index_quiz_options_on_quiz_question_id"
  end

  create_table "quiz_questions", force: :cascade do |t|
    t.bigint "quiz_set_id", null: false
    t.text "question_text", null: false
    t.integer "question_type", default: 0, null: false
    t.text "explanation"
    t.integer "position", default: 0, null: false
    t.decimal "points", precision: 5, scale: 1, default: "1.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "allow_multiple", default: false, null: false
    t.text "essay_rubric"
    t.index ["quiz_set_id", "position"], name: "index_quiz_questions_on_quiz_set_id_and_position"
    t.index ["quiz_set_id"], name: "index_quiz_questions_on_quiz_set_id"
  end

  create_table "quiz_sets", force: :cascade do |t|
    t.bigint "workspace_id"
    t.bigint "user_id"
    t.string "title", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.integer "source_type", default: 0, null: false
    t.string "share_token", null: false
    t.boolean "allow_retake", default: true, null: false
    t.boolean "show_answers", default: true, null: false
    t.integer "time_limit_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "result_mode", default: 0, null: false
    t.integer "passing_score", default: 80, null: false
    t.text "ai_class_evaluation"
    t.datetime "ai_class_evaluated_at"
    t.boolean "ai_generating", default: false
    t.boolean "ai_failed", default: false, null: false
    t.integer "total_score"
    t.string "passing_score_type", default: "percent", null: false
    t.bigint "learner_id"
    t.index ["learner_id"], name: "index_quiz_sets_on_learner_id"
    t.index ["share_token"], name: "index_quiz_sets_on_share_token", unique: true
    t.index ["user_id"], name: "index_quiz_sets_on_user_id"
    t.index ["workspace_id", "status"], name: "index_quiz_sets_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_quiz_sets_on_workspace_id"
  end

  create_table "responses", force: :cascade do |t|
    t.bigint "survey_id", null: false
    t.bigint "workspace_id", null: false
    t.string "respondent_email"
    t.string "respondent_token"
    t.integer "status", default: 0
    t.datetime "completed_at"
    t.integer "completion_time_seconds"
    t.float "quality_score"
    t.boolean "excluded", default: false
    t.string "source", default: "link"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "respondent_ip"
    t.string "edit_token"
    t.index ["edit_token"], name: "index_responses_on_edit_token", unique: true
    t.index ["respondent_email"], name: "index_responses_on_respondent_email"
    t.index ["status"], name: "index_responses_on_status"
    t.index ["survey_id", "respondent_ip"], name: "index_responses_on_survey_id_and_respondent_ip"
    t.index ["survey_id"], name: "index_responses_on_survey_id"
    t.index ["user_id"], name: "index_responses_on_user_id"
    t.index ["workspace_id"], name: "index_responses_on_workspace_id"
  end

  create_table "short_links", force: :cascade do |t|
    t.string "code", null: false
    t.string "target_url", null: false
    t.bigint "workspace_id"
    t.integer "clicks_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_short_links_on_code", unique: true
    t.index ["target_url"], name: "index_short_links_on_target_url"
    t.index ["workspace_id"], name: "index_short_links_on_workspace_id"
  end

  create_table "stt_transcripts", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "title", default: "Untitled", null: false
    t.text "transcript_text", default: "", null: false
    t.string "language_code"
    t.float "duration_secs", default: 0.0, null: false
    t.integer "credits_used", default: 1, null: false
    t.string "source", default: "file", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "speaker_segments"
    t.index ["workspace_id", "created_at"], name: "index_stt_transcripts_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_stt_transcripts_on_workspace_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.integer "plan", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "auto_renew", default: true
    t.integer "credit_balance", default: 0
    t.integer "credit_used", default: 0
    t.integer "max_surveys", default: 3
    t.integer "max_votes", default: 3
    t.integer "max_feedbacks", default: 10
    t.integer "max_supporters", default: 0
    t.integer "max_ai_credits", default: 0
    t.integer "price_cents", default: 0
    t.string "currency", default: "VND"
    t.string "billing_cycle", default: "monthly"
    t.jsonb "features", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_dynamic_forms"
    t.bigint "user_id"
    t.index ["plan"], name: "index_subscriptions_on_plan"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.index ["workspace_id"], name: "index_subscriptions_on_workspace_id"
  end

  create_table "survey_templates", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.string "category", default: "general", null: false
    t.string "template_type", default: "survey", null: false
    t.string "icon", default: "📋"
    t.string "color", default: "#4F46E5"
    t.integer "estimated_minutes", default: 3
    t.integer "use_count", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.jsonb "structure", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_survey_templates_on_active"
    t.index ["position"], name: "index_survey_templates_on_position"
    t.index ["template_type"], name: "index_survey_templates_on_template_type"
  end

  create_table "surveys", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "banner_image"
    t.integer "status", default: 0, null: false
    t.integer "identity_mode", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.integer "max_responses"
    t.integer "max_per_user", default: 1
    t.boolean "show_progress", default: true
    t.boolean "show_results", default: false
    t.boolean "allow_edit", default: false
    t.string "thank_you_message"
    t.string "redirect_url"
    t.boolean "scoring_enabled", default: false
    t.string "slug"
    t.integer "response_count", default: 0
    t.jsonb "settings", default: {}
    t.boolean "ai_generated", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "login_providers", default: "both"
    t.index ["slug"], name: "index_surveys_on_slug", unique: true
    t.index ["status"], name: "index_surveys_on_status"
    t.index ["user_id"], name: "index_surveys_on_user_id"
    t.index ["workspace_id"], name: "index_surveys_on_workspace_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "workspace_id"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", default: "", null: false
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "avatar"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.boolean "must_change_password", default: false
    t.string "otp_secret"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login", default: false
    t.string "otp_backup_codes", array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "uid"
    t.datetime "last_seen_at"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email"
    t.index ["last_seen_at"], name: "index_users_on_last_seen_at"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["workspace_id", "email"], name: "index_users_on_workspace_id_and_email", unique: true
    t.index ["workspace_id"], name: "index_users_on_workspace_id"
  end

  create_table "vote_options", force: :cascade do |t|
    t.bigint "vote_id", null: false
    t.string "label", null: false
    t.string "image"
    t.integer "position", default: 0, null: false
    t.integer "votes_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.index ["vote_id"], name: "index_vote_options_on_vote_id"
  end

  create_table "vote_responses", force: :cascade do |t|
    t.bigint "vote_id", null: false
    t.bigint "workspace_id", null: false
    t.string "respondent_token"
    t.string "respondent_email"
    t.jsonb "selected_option_ids", default: []
    t.text "text_value"
    t.jsonb "ranking_order", default: []
    t.integer "upvote_target_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "fingerprint"
    t.index ["user_id"], name: "index_vote_responses_on_user_id"
    t.index ["vote_id", "fingerprint"], name: "index_vote_responses_on_vote_and_fingerprint"
    t.index ["vote_id"], name: "index_vote_responses_on_vote_id"
    t.index ["workspace_id"], name: "index_vote_responses_on_workspace_id"
  end

  create_table "votes", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.integer "vote_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "identity_mode", default: 0, null: false
    t.integer "countdown_seconds"
    t.boolean "show_results_live", default: true
    t.boolean "allow_multiple_votes", default: false
    t.string "slug"
    t.integer "participant_count", default: 0
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "opened_at"
    t.boolean "login_required", default: false, null: false
    t.string "login_providers", default: "both"
    t.index ["slug"], name: "index_votes_on_slug", unique: true
    t.index ["status"], name: "index_votes_on_status"
    t.index ["user_id"], name: "index_votes_on_user_id"
    t.index ["workspace_id"], name: "index_votes_on_workspace_id"
  end

  create_table "workspace_memberships", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "user_id", null: false
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_workspace_memberships_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_workspace_memberships_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_workspace_memberships_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "logo"
    t.string "brand_color", default: "#6366F1"
    t.string "favicon"
    t.string "language", default: "vi"
    t.string "timezone", default: "Asia/Ho_Chi_Minh"
    t.integer "status", default: 0, null: false
    t.string "custom_domain"
    t.jsonb "email_template_config", default: {}
    t.boolean "force_2fa", default: false
    t.integer "session_timeout_days", default: 60
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "surveys_created_count", default: 0, null: false
    t.integer "votes_created_count", default: 0, null: false
    t.integer "feedbacks_created_count", default: 0, null: false
    t.datetime "counts_reset_at"
    t.boolean "notify_on_new_feedback", default: false, null: false
    t.boolean "notify_on_new_response", default: false, null: false
    t.integer "dynamic_forms_created_count", default: 0, null: false
    t.bigint "owner_id"
    t.index ["owner_id"], name: "index_workspaces_on_owner_id"
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
    t.index ["status"], name: "index_workspaces_on_status"
  end

  add_foreign_key "action_items", "feedback_boards"
  add_foreign_key "action_items", "workspaces"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_analysis_results", "ai_jobs"
  add_foreign_key "ai_analysis_results", "workspaces"
  add_foreign_key "ai_jobs", "users"
  add_foreign_key "ai_jobs", "workspaces"
  add_foreign_key "answers", "questions"
  add_foreign_key "answers", "responses"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "audit_logs", "workspaces"
  add_foreign_key "content_outlines", "users", column: "created_by_id"
  add_foreign_key "content_outlines", "workspaces"
  add_foreign_key "document_summaries", "users", column: "created_by_id"
  add_foreign_key "document_summaries", "workspaces"
  add_foreign_key "dynamic_form_assignments", "dynamic_forms"
  add_foreign_key "dynamic_form_assignments", "users"
  add_foreign_key "dynamic_form_fields", "dynamic_forms"
  add_foreign_key "dynamic_form_submissions", "dynamic_forms"
  add_foreign_key "dynamic_forms", "users"
  add_foreign_key "dynamic_forms", "workspaces"
  add_foreign_key "feedback_boards", "users"
  add_foreign_key "feedback_boards", "workspaces"
  add_foreign_key "feedback_replies", "feedbacks"
  add_foreign_key "feedback_upvotes", "feedbacks"
  add_foreign_key "feedbacks", "feedback_boards"
  add_foreign_key "feedbacks", "workspaces"
  add_foreign_key "flashcard_assignments", "flashcard_decks"
  add_foreign_key "flashcard_assignments", "learners"
  add_foreign_key "flashcard_decks", "users", column: "created_by_id"
  add_foreign_key "flashcard_decks", "workspaces"
  add_foreign_key "flashcard_reviews", "flashcards"
  add_foreign_key "flashcard_reviews", "users"
  add_foreign_key "flashcards", "flashcard_decks"
  add_foreign_key "learner_badges", "learners"
  add_foreign_key "learner_daily_challenges", "learners"
  add_foreign_key "learner_folder_members", "learner_folders"
  add_foreign_key "learner_folder_members", "learners"
  add_foreign_key "learner_folders", "users", column: "created_by_id"
  add_foreign_key "learner_folders", "workspaces"
  add_foreign_key "learner_notifications", "learners"
  add_foreign_key "learner_payments", "learners"
  add_foreign_key "learner_push_subscriptions", "learners"
  add_foreign_key "learner_saved_links", "learners"
  add_foreign_key "learning_item_progresses", "learning_path_assignments"
  add_foreign_key "learning_item_progresses", "learning_path_items"
  add_foreign_key "learning_path_assignments", "learning_paths"
  add_foreign_key "learning_path_assignments", "users", column: "assigned_by_id"
  add_foreign_key "learning_path_assignments", "users", column: "assignee_id"
  add_foreign_key "learning_path_items", "learning_paths"
  add_foreign_key "learning_paths", "users", column: "created_by_id"
  add_foreign_key "learning_paths", "workspaces"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "workspaces"
  add_foreign_key "payments", "subscriptions"
  add_foreign_key "payments", "workspaces"
  add_foreign_key "qr_codes", "workspaces"
  add_foreign_key "question_options", "questions"
  add_foreign_key "questions", "surveys"
  add_foreign_key "quiz_assignments", "learners"
  add_foreign_key "quiz_assignments", "quiz_sets"
  add_foreign_key "quiz_attempt_answers", "quiz_attempts"
  add_foreign_key "quiz_attempt_answers", "quiz_options"
  add_foreign_key "quiz_attempt_answers", "quiz_questions"
  add_foreign_key "quiz_attempts", "quiz_sets"
  add_foreign_key "quiz_options", "quiz_questions"
  add_foreign_key "quiz_questions", "quiz_sets"
  add_foreign_key "quiz_sets", "users"
  add_foreign_key "quiz_sets", "workspaces"
  add_foreign_key "responses", "surveys"
  add_foreign_key "responses", "users", on_delete: :nullify
  add_foreign_key "responses", "workspaces"
  add_foreign_key "short_links", "workspaces"
  add_foreign_key "stt_transcripts", "workspaces"
  add_foreign_key "subscriptions", "workspaces"
  add_foreign_key "surveys", "users"
  add_foreign_key "surveys", "workspaces"
  add_foreign_key "users", "workspaces"
  add_foreign_key "vote_options", "votes"
  add_foreign_key "vote_responses", "users", on_delete: :nullify
  add_foreign_key "vote_responses", "votes"
  add_foreign_key "vote_responses", "workspaces"
  add_foreign_key "votes", "users"
  add_foreign_key "votes", "workspaces"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
end
