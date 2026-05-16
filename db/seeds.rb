puts "Seeding database..."

# Create Super Admin (system level - no workspace)
super_admin = User.find_or_create_by(email: "superadmin@vox.vn") do |u|
  u.name     = "Super Admin"
  u.role     = :super_admin
  u.password = "superadmin123"
  u.password_confirmation = "superadmin123"
  u.confirmed_at = Time.current
end
puts "✓ Super Admin: #{super_admin.email} / superadmin123"

# Create demo workspace
workspace = Workspace.find_or_create_by(slug: "demo-corp") do |w|
  w.name        = "Demo Corporation"
  w.brand_color = "#6366F1"
  w.language    = "vi"
  w.timezone    = "Asia/Ho_Chi_Minh"
  w.status      = :active
end

# Subscription
subscription = workspace.subscriptions.find_or_create_by(status: :active) do |s|
  s.plan           = :pro
  s.credit_balance = 500
  s.max_ai_credits = 500
  s.starts_at      = Time.current
  s.ends_at        = 1.year.from_now
end
puts "✓ Workspace: #{workspace.name} (Pro plan)"

# Admin user for demo workspace
admin = workspace.users.find_or_create_by(email: "admin@demo.vox.vn") do |u|
  u.name     = "HR Manager"
  u.role     = :admin
  u.password = "admin123"
  u.password_confirmation = "admin123"
  u.confirmed_at = Time.current
end
puts "✓ Admin: #{admin.email} / admin123"

# Supporter
supporter = workspace.users.find_or_create_by(email: "supporter@demo.vox.vn") do |u|
  u.name     = "Team Lead"
  u.role     = :supporter
  u.password = "supporter123"
  u.password_confirmation = "supporter123"
  u.confirmed_at = Time.current
end
puts "✓ Supporter: #{supporter.email} / supporter123"

# Sample survey
survey = workspace.surveys.find_or_create_by(title: "Employee Satisfaction Q1 2026") do |s|
  s.user         = admin
  s.description  = "Quarterly employee satisfaction survey"
  s.status       = :active
  s.identity_mode = :anonymous
  s.show_progress = true
  s.response_count = 47
end

# Questions
if survey.questions.empty?
  q1 = survey.questions.create!(title: "Overall, how satisfied are you with your work?", question_type: :nps, position: 0, required: true)
  q2 = survey.questions.create!(title: "How would you rate communication within your team?", question_type: :rating, position: 1, settings: { max_value: 5 })
  q3 = survey.questions.create!(title: "What do you enjoy most about working here?", question_type: :long_text, position: 2)
  q4 = survey.questions.create!(title: "Which area needs the most improvement?", question_type: :multiple_choice, position: 3)
  %w[Communication Compensation Work-Life\ Balance Tools Leadership].each_with_index do |opt, idx|
    q4.question_options.create!(label: opt, position: idx)
  end
  puts "✓ Sample survey with #{survey.questions.count} questions"
end

# Sample vote
vote = workspace.votes.find_or_create_by(title: "Should we have team lunch on Fridays?") do |v|
  v.user           = supporter
  v.vote_type      = :single_choice
  v.status         = :active
  v.identity_mode  = :anonymous
  v.show_results_live = true
end

if vote.vote_options.empty?
  [["Yes, every Friday", 23], ["Every other Friday", 14], ["No, prefer flex lunch", 10]].each_with_index do |(label, count), idx|
    vote.vote_options.create!(label: label, position: idx, votes_count: count)
  end
  vote.update!(participant_count: 47)
  puts "✓ Sample vote"
end

# Sample feedback board
board = workspace.feedback_boards.find_or_create_by(title: "Office & Work Environment") do |b|
  b.user           = admin
  b.status         = :active
  b.identity_mode  = :user_choice
  b.auto_moderation = true
  b.allow_upvotes  = true
end

if board.feedbacks.empty?
  [
    { content: "The new standing desks are great! Could we get more in the open area?", upvotes_count: 12, status: :approved, moderation_status: :safe },
    { content: "Coffee machine on floor 3 has been broken for 2 weeks. Please fix!", upvotes_count: 8, status: :approved, moderation_status: :safe },
    { content: "Can we have more plants in the office? It would improve the atmosphere.", upvotes_count: 5, status: :approved, moderation_status: :safe }
  ].each do |fb_data|
    board.feedbacks.create!(fb_data.merge(workspace: workspace))
  end
  puts "✓ Sample feedback board with #{board.feedbacks.count} feedbacks"
end

puts "\n✅ Seed complete!"
puts "\nLogin credentials:"
puts "  Super Admin: superadmin@vox.vn / superadmin123"
puts "  Workspace Admin: admin@demo.vox.vn / admin123"
puts "  Supporter: supporter@demo.vox.vn / supporter123"
