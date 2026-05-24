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

ActiveRecord::Schema[7.2].define(version: 2026_05_24_035500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
    t.index ["workspace_id"], name: "index_audit_logs_on_workspace_id"
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
    t.index ["respondent_email"], name: "index_responses_on_respondent_email"
    t.index ["status"], name: "index_responses_on_status"
    t.index ["survey_id", "respondent_ip"], name: "index_responses_on_survey_id_and_respondent_ip"
    t.index ["survey_id"], name: "index_responses_on_survey_id"
    t.index ["user_id"], name: "index_responses_on_user_id"
    t.index ["workspace_id"], name: "index_responses_on_workspace_id"
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
    t.index ["plan"], name: "index_subscriptions_on_plan"
    t.index ["status"], name: "index_subscriptions_on_status"
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
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email"
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
    t.index ["user_id"], name: "index_vote_responses_on_user_id"
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
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
    t.index ["status"], name: "index_workspaces_on_status"
  end

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
  add_foreign_key "feedback_boards", "users"
  add_foreign_key "feedback_boards", "workspaces"
  add_foreign_key "feedback_replies", "feedbacks"
  add_foreign_key "feedback_upvotes", "feedbacks"
  add_foreign_key "feedbacks", "feedback_boards"
  add_foreign_key "feedbacks", "workspaces"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "workspaces"
  add_foreign_key "payments", "subscriptions"
  add_foreign_key "payments", "workspaces"
  add_foreign_key "qr_codes", "workspaces"
  add_foreign_key "question_options", "questions"
  add_foreign_key "questions", "surveys"
  add_foreign_key "responses", "surveys"
  add_foreign_key "responses", "users", on_delete: :nullify
  add_foreign_key "responses", "workspaces"
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
