puts "Seeding database..."

# ─────────────────────────────────────────────────────────────────────────────
# 1. Super Admin
# ─────────────────────────────────────────────────────────────────────────────
super_admin = User.find_or_create_by(email: "quocvietlee@gmail.com") do |u|
  u.name                  = "Quoc Viet"
  u.role                  = :super_admin
  u.password              = SecureRandom.hex(12)
  u.password_confirmation = u.password
  u.confirmed_at          = Time.current
  puts "  → Super admin password (save this!): #{u.password}"
end

unless super_admin.super_admin?
  super_admin.update!(role: :super_admin)
end

puts "✓ Super Admin: #{super_admin.email}"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Plan Configs (3 gói)
# ─────────────────────────────────────────────────────────────────────────────
plans = [
  {
    plan_key:     "free",
    display_name: "Free",
    price_vnd:    0,
    billing_cycle: "month",
    limits: {
      max_surveys:    3,
      max_votes:      3,
      max_feedbacks:  10,
      max_supporters: 0,
      max_ai_credits: 0,
      max_dynamic_forms: 3
    },
    features: {
      ai_survey_builder:    false,
      ai_analysis:          false,
      ai_executive_report:  false,
      ai_chat:              false,
      ai_moderation:        false,
      custom_branding:      false,
      export:               false,
      sso:                  false
    }
  },
  {
    plan_key:     "pro",
    display_name: "Pro",
    price_vnd:    990_000,
    billing_cycle: "month",
    limits: {
      max_surveys:    nil,
      max_votes:      nil,
      max_feedbacks:  nil,
      max_supporters: 10,
      max_ai_credits: 500,
      max_dynamic_forms: 10
    },
    features: {
      ai_survey_builder:    true,
      ai_analysis:          true,
      ai_executive_report:  true,
      ai_chat:              false,
      ai_moderation:        true,
      custom_branding:      true,
      export:               true,
      sso:                  false
    }
  },
  {
    plan_key:     "enterprise",
    display_name: "Enterprise",
    price_vnd:    0,
    billing_cycle: "month",
    limits: {
      max_surveys:    nil,
      max_votes:      nil,
      max_feedbacks:  nil,
      max_supporters: nil,
      max_ai_credits: nil,
      max_dynamic_forms: nil
    },
    features: {
      ai_survey_builder:    true,
      ai_analysis:          true,
      ai_executive_report:  true,
      ai_chat:              true,
      ai_moderation:        true,
      custom_branding:      true,
      export:               true,
      sso:                  true
    }
  }
]

plans.each do |attrs|
  pc = PlanConfig.find_or_initialize_by(plan_key: attrs[:plan_key])
  pc.assign_attributes(attrs)
  pc.save!
  puts "✓ Plan: #{pc.display_name} (#{pc.price_vnd == 0 ? 'Free/Custom' : "#{pc.price_vnd.to_s.reverse.gsub(/\d{3}(?=.)/, '\0.').reverse} ₫/tháng"})"
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. Addon Configs (2 gói)
# ─────────────────────────────────────────────────────────────────────────────
addons = [
  {
    name:             "Gói AI Credits",
    description:      "Nạp thêm 100 AI credits để dùng phân tích, báo cáo và kiểm duyệt AI",
    addon_type:       "ai_credits",
    price_cents:      199_000,
    ai_credits_bonus: 100,
    surveys_bonus:    0,
    votes_bonus:      0,
    feedbacks_bonus:  0,
    sort_order:       1,
    active:           true
  },
  {
    name:             "Gói Mở Rộng Tính Năng",
    description:      "Thêm 10 khảo sát, 10 bình chọn và 100 góp ý cho workspace",
    addon_type:       "resource_pack",
    price_cents:      299_000,
    ai_credits_bonus: 0,
    surveys_bonus:    10,
    votes_bonus:      10,
    feedbacks_bonus:  100,
    sort_order:       2,
    active:           true
  }
]

addons.each do |attrs|
  ac = AddonConfig.find_or_initialize_by(name: attrs[:name])
  ac.assign_attributes(attrs)
  ac.save!
  puts "✓ Addon: #{ac.name} (#{ac.price_cents.to_s.reverse.gsub(/\d{3}(?=.)/, '\0.').reverse} ₫)"
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. Demo Workspace (development / staging only)
# ─────────────────────────────────────────────────────────────────────────────
unless Rails.env.production?
  workspace = Workspace.find_or_create_by(slug: "demo-corp") do |w|
    w.name        = "Demo Corporation"
    w.brand_color = "#6366F1"
    w.language    = "vi"
    w.timezone    = "Asia/Ho_Chi_Minh"
    w.status      = :active
  end

  workspace.subscriptions.find_or_create_by(status: :active) do |s|
    s.plan              = :pro
    s.credit_balance    = 500
    s.max_ai_credits    = 500
    s.max_dynamic_forms = 10
    s.starts_at         = Time.current
    s.ends_at           = 1.year.from_now
  end

  admin = workspace.users.find_or_create_by(email: "admin@demo.vox.vn") do |u|
    u.name                  = "HR Manager"
    u.role                  = :admin
    u.password              = "admin123"
    u.password_confirmation = "admin123"
    u.confirmed_at          = Time.current
  end

  supporter = workspace.users.find_or_create_by(email: "supporter@demo.vox.vn") do |u|
    u.name                  = "Team Lead"
    u.role                  = :supporter
    u.password              = "supporter123"
    u.password_confirmation = "supporter123"
    u.confirmed_at          = Time.current
  end

  survey = workspace.surveys.find_or_create_by(title: "Employee Satisfaction Q1 2026") do |s|
    s.user          = admin
    s.description   = "Quarterly employee satisfaction survey"
    s.status        = :active
    s.identity_mode = :anonymous
    s.show_progress = true
    s.response_count = 47
  end

  if survey.questions.empty?
    q1 = survey.questions.create!(title: "Overall, how satisfied are you with your work?", question_type: :nps, position: 0, required: true)
    q2 = survey.questions.create!(title: "How would you rate communication within your team?", question_type: :rating, position: 1, settings: { max_value: 5 })
    q3 = survey.questions.create!(title: "What do you enjoy most about working here?", question_type: :long_text, position: 2)
    q4 = survey.questions.create!(title: "Which area needs the most improvement?", question_type: :multiple_choice, position: 3)
    %w[Communication Compensation Work-Life\ Balance Tools Leadership].each_with_index do |opt, idx|
      q4.question_options.create!(label: opt, position: idx)
    end
  end

  vote = workspace.votes.find_or_create_by(title: "Should we have team lunch on Fridays?") do |v|
    v.user              = supporter
    v.vote_type         = :single_choice
    v.status            = :active
    v.identity_mode     = :anonymous
    v.show_results_live = true
  end

  if vote.vote_options.empty?
    [["Yes, every Friday", 23], ["Every other Friday", 14], ["No, prefer flex lunch", 10]].each_with_index do |(label, count), idx|
      vote.vote_options.create!(label: label, position: idx, votes_count: count)
    end
    vote.update!(participant_count: 47)
  end

  board = workspace.feedback_boards.find_or_create_by(title: "Office & Work Environment") do |b|
    b.user            = admin
    b.status          = :active
    b.identity_mode   = :user_choice
    b.auto_moderation = true
    b.allow_upvotes   = true
  end

  if board.feedbacks.empty?
    [
      { content: "The new standing desks are great! Could we get more in the open area?", upvotes_count: 12, status: :approved, moderation_status: :safe },
      { content: "Coffee machine on floor 3 has been broken for 2 weeks. Please fix!", upvotes_count: 8, status: :approved, moderation_status: :safe },
      { content: "Can we have more plants in the office? It would improve the atmosphere.", upvotes_count: 5, status: :approved, moderation_status: :safe }
    ].each { |d| board.feedbacks.create!(d.merge(workspace: workspace)) }
  end

  puts "\n── Demo workspace (dev/staging only) ──────────────────"
  puts "  Workspace Admin:  admin@demo.vox.vn / admin123"
  puts "  Supporter:        supporter@demo.vox.vn / supporter123"
end

load Rails.root.join("db/seeds/survey_templates.rb")

puts "\n✅ Seed complete!"
