Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Custom error pages (used by config.exceptions_app = routes)
  match "/404", to: "errors#not_found",    via: :all
  match "/422", to: "errors#unprocessable", via: :all
  match "/500", to: "errors#server_error", via: :all

  # Public landing page
  root to: "pages#home"
  get "home", to: "pages#home", as: :home_page

  # Public template library
  resources :templates, only: [:index, :show] do
    member do
      post :use  # direct button click from template card/show page
      get  :use  # GET redirect after login/signup (pending_template_id flow)
    end
  end

  # Devise auth
  devise_for :users, controllers: {
    sessions:           "auth/sessions",
    registrations:      "auth/registrations",
    passwords:          "auth/passwords",
    omniauth_callbacks: "auth/omniauth_callbacks"
  }

  # SSO workspace setup (after OAuth, new user needs to create workspace)
  resource :sso_workspace, only: [:new, :create], controller: "auth/sso_workspaces"

  # QR code scan redirect + image
  get "/qr/:token",       to: "qr_codes#scan",  as: :qr_scan
  get "/qr/:token/image", to: "qr_codes#image", as: :qr_image

  # PayOS webhook (no CSRF)
  post "webhooks/payos" => "webhooks/payos#receive", as: :payos_webhook

  # Short links
  get  "/l/:code", to: "public/short_links#show", as: :short_link

  # Public report share (no login required)
  get  "/r/:token",             to: "public/reports#show",        as: :public_report
  get  "/r/:token/preview_pdf",  to: "public/reports#preview_pdf",  as: :public_report_preview_pdf
  get  "/r/:token/preview_html", to: "public/reports#preview_html", as: :public_report_preview_html
  get  "/ai-r/:token",          to: "public/ai_reports#show",     as: :public_ai_report

  # Public participation (End User — no login required)
  get  "/s/:slug",              to: "participate/surveys#show",    as: :participate_survey
  post "/s/:slug/submit",       to: "participate/surveys#submit",  as: :submit_survey
  get  "/s/:slug/done",         to: "participate/surveys#done",    as: :survey_done
  get  "/s/:slug/edit/:token",  to: "participate/surveys#edit_response", as: :edit_survey_response
  get  "/v/:slug",              to: "participate/votes#show",        as: :participate_vote
  post "/v/:slug/submit",       to: "participate/votes#submit",      as: :submit_vote
  get  "/v/:slug/results",      to: "participate/votes#results",     as: :vote_results
  get  "/v/:slug/present",      to: "participate/votes#present",     as: :vote_presenter
  post "/v/:slug/check_voted",  to: "participate/votes#check_voted", as: :check_voted
  get  "/f/:slug",         to: "participate/feedbacks#show",  as: :participate_feedback
  post "/f/:slug/submit",  to: "participate/feedbacks#submit", as: :submit_feedback
  post "/f/:slug/upvote",  to: "participate/feedbacks#upvote", as: :upvote_feedback
  post "/f/:slug/reply",   to: "participate/feedbacks#reply",  as: :reply_feedback
  get  "/f/:slug/list",           to: "participate/feedbacks#list",           as: :list_feedbacks
  get  "/f/:slug/verify_pending", to: "participate/feedbacks#verify_pending", as: :verify_pending_feedbacks
  post "/f/:slug/voice",          to: "participate/feedbacks#voice_transcribe", as: :feedback_voice_transcribe

  # Dynamic Forms — public participation
  get  "/forms/:slug",        to: "participate/dynamic_forms#show",   as: :participate_dynamic_form
  post "/forms/:slug/submit", to: "participate/dynamic_forms#submit",  as: :submit_dynamic_form

  # Participant — history of their votes/surveys/feedback
  namespace :my do
    resources :participations, only: [:index]
  end

  # Super Admin
  namespace :super_admin do
    root to: "dashboard#index"
    resources :workspaces do
      member do
        patch :activate
        patch :suspend
        patch :reset_admin_password
      end
    end
    resources :subscriptions, only: [:index, :show, :edit, :update]
    resources :plan_configs, only: [:index, :edit, :update]
    resources :addon_configs
    resources :broadcasts, only: [:index, :new, :create]
    resource  :ai_model_configs, only: [:show, :update], path: "ai_models"
  end

  # Authenticated workspace admin/supporter area
  scope module: "admin" do
    get "dashboard", to: "dashboard#index", as: :dashboard
    post "switch_workspace/:workspace_id", to: "workspace_switcher#switch", as: :switch_workspace
    resources :workspaces, only: [:new, :create], path: "new_workspace"

    resources :surveys do
      member do
        patch :publish
        patch :close
        patch :reopen
        patch :archive
        get   :results
        get   :html_report
        post  :pdf_report
        get   :preview_html_report
        get   :preview_html_ai_report
        post  :preview_pdf_report
        post  :generate_report_token
        delete :revoke_report_token
        post  :save_report_layout
        post  :build_report_structure
        delete :reset_report_structure
        get   :export
        get    :export_report
        get    :view_ai_report
        post   :save_ai_report_layout
        post   :generate_ai_report_token
        delete :revoke_ai_report_token
        delete :delete_report
        post   :ai_analyze
        post   :ai_report
        post   :ai_suggest_prompt
        get   :share
        post  :clone
      end
      resources :questions, only: [:create, :update, :destroy] do
        collection { patch :reorder }
        resources :question_options, only: [:create, :update, :destroy]
      end
    end

    # AI endpoints
    post "ai/generate_survey",  to: "ai#generate_survey",  as: :ai_generate_survey
    post "ai/check_question",   to: "ai#check_question",   as: :ai_check_question
    post "ai/analyze",          to: "ai#analyze_survey",   as: :ai_analyze
    post "ai/generate_report",  to: "ai#generate_report",  as: :ai_generate_report
    get  "ai/chat",             to: "ai#chat_page",        as: :ai_chat_page
    post "ai/chat",             to: "ai#chat",             as: :ai_chat
    get  "ai/job_status/:id",   to: "ai#job_status",       as: :ai_job_status

    # Text-to-Speech (ElevenLabs)
    get  "tts",          to: "tts#index",    as: :tts
    get  "tts/voices",   to: "tts#voices",   as: :tts_voices
    post "tts/generate", to: "tts#generate", as: :tts_generate

    # Speech-to-Text / Transcription (ElevenLabs Scribe v2)
    get  "stt",                  to: "stt#index",            as: :stt
    post "stt/transcribe",       to: "stt#transcribe",       as: :stt_transcribe
    post "stt/transcribe_url",   to: "stt#transcribe_url",   as: :stt_transcribe_url
    post "stt/transcribe_chunk", to: "stt#transcribe_chunk", as: :stt_transcribe_chunk
    post   "stt/summarize",        to: "stt#summarize",        as: :stt_summarize
    post   "stt/translate",        to: "stt#translate",        as: :stt_translate
    get    "stt/history",          to: "stt#history",          as: :stt_history
    post   "stt/save_mic",         to: "stt#save_mic",         as: :stt_save_mic
    delete "stt/history/:id",      to: "stt#destroy_history",  as: :stt_destroy_history

    resources :votes do
      member do
        patch :open
        patch :close
        get   :results
        get   :export
        get   :present
        get   :share
      end
      resources :vote_options, only: [:create, :update, :destroy], shallow: true do
        collection { patch :reorder }
        member do
          patch  :update_image
          delete :destroy_image
        end
      end
    end

    resources :action_items, only: [:create, :update, :destroy]

    resources :feedback_boards do
      member do
        patch :close
        patch :reopen
        get   :export
        post  :ai_summarize
      end
      resources :feedbacks, only: [:index, :show, :update, :destroy] do
        collection do
          post :bulk_action
        end
        member do
          patch :approve
          patch :hide
          patch :unhide
          patch :pin
          patch :unpin
          patch :update_admin_status
          patch :mark_safe
        end
      end
    end

    resources :dynamic_forms do
      member do
        patch :publish
        patch :close
        patch :reopen
        get   :submissions
        get   :export_csv
        get   :show_submission
        patch :update_submission_status
        patch :update_submission_assignee
        patch :update_submission_data
        delete :destroy_submission
        delete :bulk_destroy_submissions
      end
    end

    resource  :profile, only: [:show, :update]
    resource  :workspace_settings, only: [:show, :update, :destroy], path: "settings"
    resources :members, only: [:index, :new, :create, :destroy] do
      member do
        patch :toggle_status
        post  :reset_password
      end
    end

    resource :subscription, only: [:show, :update] do
      get  :billing
      post :upgrade
      post :cancel
      get  :invoices
      post :checkout
      post :checkout_addon
      get  :payment_return
      get  :payment_cancel
      get  :payment_status
    end

    resources :notifications, only: [:index] do
      collection { patch :mark_all_read }
      member     { patch :mark_read }
    end

    get "audit_log", to: "audit_logs#index", as: :audit_log

    resources :quiz_sets do
      member do
        patch :publish
        patch :unpublish
        get   :results
        post  :ai_generate
        get   :ai_generate_status
        post  :send_result_email
        get   :attempt_detail
        post  :ai_evaluate_attempt
        post  :ai_evaluate_results
        patch :update_ai_evaluation
        post  :send_ai_evaluation_email
        post  :ai_grade_essay         # chấm tự luận
      end
      resources :quiz_questions, only: [:create, :update, :destroy] do
        collection { post :reorder }
        resources :quiz_options, only: [:create, :update, :destroy]
      end
    end

    # Module 1: Tạo nội dung AI
    resources :content_outlines, only: [:index, :new, :create, :show, :destroy] do
      member do
        post :regenerate
        post :ai_edit
        get  :status
        patch :update_slides
      end
    end

    # Module 2 + 3: Lộ trình học
    resources :learning_paths do
      member do
        patch :publish
        post  :ai_generate
        get   :ai_status
        post  :assign
      end
      resources :learning_path_items, only: [:create, :update, :destroy] do
        collection { patch :reorder }
      end
    end
    resources :learning_path_assignments, only: [:show, :destroy] do
      member { patch :update_progress }
    end

    # Module 3: Flashcards
    resources :flashcard_decks do
      member do
        post :ai_generate
        get  :ai_status
        get  :study
        post :review
      end
      resources :flashcards, only: [:update]
    end

    # Module 3: Tóm tắt tài liệu
    resources :document_summaries, only: [:index, :new, :create, :show, :destroy] do
      member { get :ai_status }
    end

    # Module 3: AI Tutor & Writing
    get  "ai/tutor",   to: "ai#tutor_page",  as: :ai_tutor_page
    post "ai/tutor",   to: "ai#tutor",       as: :ai_tutor
    post "ai/writing", to: "ai#writing",     as: :ai_writing
  end

  # Public quiz routes (học sinh làm bài)
  scope "/q" do
    get  ":token",            to: "quiz#show",   as: :quiz
    post ":token/start",      to: "quiz#start",  as: :start_quiz
    get  ":token/take",       to: "quiz#take",   as: :take_quiz
    post ":token/submit",     to: "quiz#submit",     as: :submit_quiz
    post ":token/save_answer", to: "quiz#save_answer", as: :save_quiz_answer
    post ":token/send_result", to: "quiz#send_result", as: :send_quiz_result
    get  "result/:result_token", to: "quiz#public_result", as: :quiz_public_result
  end

  # Catch-all: phải đặt cuối cùng — bắt mọi URL không khớp
  # Loại trừ /rails/... để ActiveStorage & các engine nội bộ hoạt động đúng
  match "*unmatched_path", to: "errors#not_found", via: :all,
        constraints: ->(req) { !req.path.start_with?("/rails/") }
end
