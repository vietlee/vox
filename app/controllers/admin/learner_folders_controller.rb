require "axlsx"
require "roo"

class Admin::LearnerFoldersController < Admin::BaseController
  before_action :set_folder, only: [:show, :edit, :update, :destroy, :add_learner, :remove_learner, :template, :import]

  def index
    @folders = current_workspace.learner_folders.includes(:created_by).order(created_at: :desc)
    # Count all learners across workspace (union of all folders)
    @total_learners = LearnerFolderMember
                        .joins(:learner_folder)
                        .where(learner_folders: { workspace_id: current_workspace.id })
                        .distinct.count(:learner_id)
  end

  def show
    scope = @folder.learner_folder_members.includes(:learner)
    if params[:q].present?
      q = "%#{params[:q].strip.downcase}%"
      scope = scope.joins(:learner).where("LOWER(learners.name) LIKE :q OR LOWER(learners.email) LIKE :q", q: q)
    end
    scope = scope.order("learners.email")
    @search_query = params[:q]
    @pagy, @members = pagy(scope, items: 20)

    # ── Class dashboard stats ──────────────────────────────────────────
    all_learners   = @folder.learners.select(:id, :name, :email, :last_seen_at, :invite_token, :password_set)
    learner_ids    = all_learners.map(&:id)
    learner_emails = all_learners.map(&:email)

    if learner_ids.any?
      class_assignments = QuizAssignment
                            .joins(:quiz_set)
                            .where(quiz_sets: { workspace_id: current_workspace.id }, learner_id: learner_ids)
                            .includes(:quiz_set, :learner)

      class_attempts = QuizAttempt
                         .joins(:quiz_set)
                         .where(quiz_sets: { workspace_id: current_workspace.id })
                         .where(participant_email: learner_emails)

      class_fc_assignments = FlashcardAssignment
                               .joins(:flashcard_deck)
                               .where(flashcard_decks: { workspace_id: current_workspace.id }, learner_id: learner_ids)
                               .includes(:flashcard_deck, :learner)

      class_lp_assignments = LearningPathAssignment
                               .joins(:learning_path)
                               .where(learning_paths: { workspace_id: current_workspace.id })
                               .where(learner_id: learner_ids)
                               .includes(:learning_item_progresses, :learner, learning_path: :learning_path_items)
    else
      class_assignments    = QuizAssignment.none
      class_attempts       = QuizAttempt.none
      class_fc_assignments = FlashcardAssignment.none
      class_lp_assignments = LearningPathAssignment.none
    end

    assignments_by_quiz    = class_assignments.group_by(&:quiz_set_id)
    attempts_by_quiz       = class_attempts.group_by(&:quiz_set_id)
    assignments_by_deck    = class_fc_assignments.group_by(&:flashcard_deck_id)
    assignments_by_lp      = class_lp_assignments.group_by(&:learning_path_id)

    assignments_by_learner = class_assignments.group_by(&:learner_id)
    fc_by_learner          = class_fc_assignments.group_by(&:learner_id)
    lp_by_learner          = class_lp_assignments.group_by(&:learner_id)
    attempts_by_email      = class_attempts.group_by(&:participant_email)

    @quiz_dashboard = assignments_by_quiz.map do |quiz_set_id, asgns|
      qs        = asgns.first.quiz_set
      attempts  = attempts_by_quiz[quiz_set_id] || []
      completed = asgns.count { |a| a.status == "completed" }
      assigned  = asgns.size
      avg_score = attempts.any? ? (attempts.sum(&:score_pct) / attempts.size.to_f).round : nil
      not_started_learners = asgns.select { |a| a.status == "pending" }.map(&:learner)
      {
        quiz_set:       qs,
        assigned:       assigned,
        completed:      completed,
        completion_pct: assigned > 0 ? (completed * 100.0 / assigned).round : 0,
        avg_score:      avg_score,
        not_started:    not_started_learners
      }
    end.sort_by { |q| [-q[:completion_pct], q[:quiz_set].title] }

    @fc_dashboard = assignments_by_deck.map do |_deck_id, asgns|
      deck      = asgns.first.flashcard_deck
      completed = asgns.count { |a| a.status == "completed" }
      assigned  = asgns.size
      in_prog   = asgns.count { |a| a.status == "in_progress" }
      not_started = asgns.select { |a| a.status == "pending" }.map(&:learner)
      {
        deck:           deck,
        assigned:       assigned,
        completed:      completed,
        in_progress:    in_prog,
        completion_pct: assigned > 0 ? (completed * 100.0 / assigned).round : 0,
        not_started:    not_started
      }
    end.sort_by { |f| [-f[:completion_pct], f[:deck].title] }

    @lp_dashboard = assignments_by_lp.map do |_lp_id, asgns|
      lp        = asgns.first.learning_path
      completed = asgns.count { |a| a.status == "completed" }
      assigned  = asgns.size
      avg_progress = asgns.any? ? (asgns.sum(&:progress_pct) / asgns.size.to_f).round : nil
      not_started  = asgns.select { |a| a.status != "completed" && a.learning_item_progresses.empty? }.map(&:learner).compact
      {
        lp:             lp,
        assigned:       assigned,
        completed:      completed,
        completion_pct: assigned > 0 ? (completed * 100.0 / assigned).round : 0,
        avg_progress:   avg_progress,
        not_started:    not_started
      }
    end.sort_by { |l| [-l[:completion_pct], l[:lp].title] }

    total_assigned  = class_assignments.size + class_fc_assignments.size + class_lp_assignments.size
    total_completed = class_assignments.count { |a| a.status == "completed" } +
                      class_fc_assignments.count { |a| a.status == "completed" } +
                      class_lp_assignments.count { |a| a.status == "completed" }

    @at_risk = all_learners.select do |l|
      qa  = assignments_by_learner[l.id] || []
      fca = fc_by_learner[l.id]          || []
      lpa = lp_by_learner[l.id]          || []
      all_asgns = qa + fca + lpa
      next false unless all_asgns.present?
      completed_count  = qa.count  { |a| a.status == "completed" } +
                         fca.count { |a| a.status == "completed" } +
                         lpa.count { |a| a.status == "completed" }
      learner_attempts = attempts_by_email[l.email] || []
      avg = learner_attempts.any? ? learner_attempts.sum(&:score_pct) / learner_attempts.size.to_f : nil
      (completed_count.to_f / all_asgns.size) < 0.5 && (learner_attempts.empty? || (avg && avg < 60))
    end

    @class_stats = {
      total:          all_learners.size,
      active:         all_learners.count { |l| l.last_seen_at.present? },
      content_count:  @quiz_dashboard.size + @fc_dashboard.size + @lp_dashboard.size,
      completion_avg: total_assigned > 0 ? (total_completed * 100.0 / total_assigned).round : nil,
      at_risk_count:  @at_risk.size
    }
  end

  def new
    @folder = LearnerFolder.new
  end

  def create
    @folder = current_workspace.learner_folders.new(folder_params.merge(created_by: current_user))
    if @folder.save
      redirect_to learner_folder_path(@folder), notice: "Tạo folder thành công."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @folder.update(folder_params)
      redirect_to learner_folder_path(@folder), notice: "Đã lưu."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @folder.destroy!
    redirect_to learner_folders_path, notice: "Đã xoá folder."
  end

  # POST /learner_folders/:id/add_learner
  def add_learner
    email = params[:email].to_s.strip.downcase
    name  = params[:name].to_s.strip

    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to learner_folder_path(@folder), alert: "Email không hợp lệ."; return
    end

    learner = Learner.find_or_invite!(email: email, name: name, assigned_by: current_user)

    if @folder.learner_folder_members.exists?(learner: learner)
      redirect_to learner_folder_path(@folder), alert: "#{email} đã có trong folder này."; return
    end

    @folder.learner_folder_members.create!(learner: learner)
    redirect_to learner_folder_path(@folder), notice: "Đã thêm #{learner.email}."
  rescue => e
    redirect_to learner_folder_path(@folder), alert: "Lỗi: #{e.message}"
  end

  # DELETE /learner_folders/:id/remove_learner
  def remove_learner
    member = @folder.learner_folder_members.find_by!(learner_id: params[:learner_id])
    member.destroy!
    redirect_to learner_folder_path(@folder), notice: "Đã xoá khỏi folder."
  end

  # GET /learner_folders/:id/template
  def template
    send_data excel_template_data,
              filename: "learner_template.xlsx",
              type:     "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end

  # POST /learner_folders/:id/import
  def import
    file = params[:file]
    unless file
      redirect_to learner_folder_path(@folder), alert: "Vui lòng chọn file."; return
    end

    ext = File.extname(file.original_filename).downcase
    unless [".xlsx", ".csv"].include?(ext)
      redirect_to learner_folder_path(@folder), alert: "Chỉ hỗ trợ file .xlsx hoặc .csv."; return
    end

    rows = parse_import_file(file, ext)
    imported = 0
    errors   = []

    rows.each do |row|
      email = row[:email].to_s.strip.downcase
      name  = row[:name].to_s.strip
      next if email.blank?
      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        errors << "Email không hợp lệ: #{email}"; next
      end
      learner = Learner.find_or_invite!(email: email, name: name, assigned_by: current_user)
      next if @folder.learner_folder_members.exists?(learner: learner)
      @folder.learner_folder_members.create!(learner: learner)
      imported += 1
    rescue => e
      errors << "#{email}: #{e.message}"
    end

    msg = "Đã import #{imported} learner thành công."
    msg += " Lỗi: #{errors.join('; ')}" if errors.any?
    redirect_to learner_folder_path(@folder), notice: msg
  end

  # GET /learners/:learner_id
  def learner_detail
    @learner = find_workspace_learner(params[:learner_id])
    @folders = current_workspace.learner_folders.joins(:learner_folder_members)
                 .where(learner_folder_members: { learner_id: @learner.id })

    @quiz_assignments = @learner.quiz_assignments
                          .joins(:quiz_set)
                          .where(quiz_sets: { workspace_id: current_workspace.id })
                          .includes(:quiz_set)
                          .order(created_at: :desc)

    @flashcard_assignments = @learner.flashcard_assignments
                               .joins(:flashcard_deck)
                               .where(flashcard_decks: { workspace_id: current_workspace.id })
                               .includes(:flashcard_deck)
                               .order(created_at: :desc)

    @lp_assignments = @learner.learning_path_assignments
                        .joins(:learning_path)
                        .where(learning_paths: { workspace_id: current_workspace.id })
                        .includes(:learning_path, :learning_item_progresses)
                        .order(created_at: :desc)

    # Quiz attempts for this learner in this workspace
    @quiz_attempts = QuizAttempt.joins(:quiz_set)
                       .where(quiz_sets: { workspace_id: current_workspace.id })
                       .where(participant_email: @learner.email)
                       .includes(:quiz_set)
                       .order(submitted_at: :desc)

    # Stats
    completed_quiz = @quiz_assignments.count { |a| a.status == "completed" }
    completed_fc   = @flashcard_assignments.count { |a| a.status == "completed" }
    completed_lp   = @lp_assignments.count { |a| a.status == "completed" }
    @total_assigned   = @quiz_assignments.size + @flashcard_assignments.size + @lp_assignments.size
    @total_completed  = completed_quiz + completed_fc + completed_lp
    @avg_quiz_score   = @quiz_attempts.any? ? (@quiz_attempts.sum(&:score_pct) / @quiz_attempts.size).round : nil
    @quiz_pass_rate   = @quiz_attempts.any? ? (@quiz_attempts.count(&:passed?) * 100.0 / @quiz_attempts.size).round : nil

    # Gamification
    @learner_badges = @learner.learner_badges.order(earned_at: :desc)
  end

  # POST /learners/:learner_id/ai_analyze
  def ai_analyze_learner
    @learner = find_workspace_learner(params[:learner_id])

    quiz_assignments = @learner.quiz_assignments
                        .joins(:quiz_set).where(quiz_sets: { workspace_id: current_workspace.id })
                        .includes(:quiz_set)
    flashcard_assignments = @learner.flashcard_assignments
                              .joins(:flashcard_deck).where(flashcard_decks: { workspace_id: current_workspace.id })
                              .includes(:flashcard_deck)
    lp_assignments = @learner.learning_path_assignments
                       .joins(:learning_path).where(learning_paths: { workspace_id: current_workspace.id })
                       .includes(:learning_path, :learning_item_progresses)
    quiz_attempts = QuizAttempt.joins(:quiz_set)
                      .where(quiz_sets: { workspace_id: current_workspace.id })
                      .where(participant_email: @learner.email)
                      .includes(:quiz_set)
                      .order(submitted_at: :desc)

    # Build context for AI
    quiz_lines = quiz_attempts.map do |a|
      "  • #{a.quiz_set.title}: #{a.score_pct}% (#{a.passed? ? 'ĐẠT' : 'CHƯA ĐẠT'}), #{a.earned_points}/#{a.total_points} điểm, #{a.time_spent_seconds ? "#{(a.time_spent_seconds/60.0).round(1)} phút" : 'N/A'}"
    end.join("\n")

    fc_lines = flashcard_assignments.map do |a|
      "  • #{a.flashcard_deck.title}: #{a.status}"
    end.join("\n")

    lp_lines = lp_assignments.map do |a|
      pct = a.progress_pct rescue 0
      "  • #{a.learning_path.title}: #{a.status}, tiến độ #{pct}%"
    end.join("\n")

    prompt = <<~PROMPT
      Bạn là chuyên gia phân tích học tập. Hãy phân tích toàn diện về học viên dưới đây và đưa ra nhận xét cụ thể, có giá trị.

      **Học viên:** #{@learner.name} (#{@learner.email})

      **KẾT QUẢ QUIZ (#{quiz_attempts.size} lần làm bài):**
      #{quiz_lines.presence || "  Chưa có dữ liệu"}

      **FLASHCARD (#{flashcard_assignments.size} bộ được giao):**
      #{fc_lines.presence || "  Chưa có dữ liệu"}

      **LỘ TRÌNH HỌC (#{lp_assignments.size} lộ trình được giao):**
      #{lp_lines.presence || "  Chưa có dữ liệu"}

      Hãy trả lời bằng tiếng Việt với cấu trúc HTML (dùng thẻ <p>, <ul>, <li>, <strong>, <em>). Bao gồm:
      1. **Tổng quan** (2-3 câu nhận xét tổng quát về học viên này)
      2. **Điểm mạnh** (cụ thể, dựa vào dữ liệu thực)
      3. **Điểm cần cải thiện** (cụ thể, không chung chung)
      4. **Hướng hỗ trợ** (3-5 gợi ý hành động cụ thể mà giáo viên/admin có thể làm để giúp học viên này)

      Nếu dữ liệu ít, hãy nêu điều đó và đưa ra nhận xét dựa trên những gì có.
    PROMPT

    svc = ClaudeService.for_feature("learner_analysis", timeout: 60)
    analysis = svc.call(
      system_prompt: "Bạn là chuyên gia phân tích học tập. Trả lời bằng tiếng Việt với HTML (dùng <p>, <ul>, <li>, <strong>).",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 1200
    )

    @learner.update_columns(ai_analysis_html: analysis, ai_analyzed_at: Time.current)
    render json: { ok: true, html: analysis }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  # GET /workspace_learners.json
  def workspace_learners_json
    folders = current_workspace.learner_folders.includes(learner_folder_members: :learner).order(:name)
    render json: {
      folders: folders.map { |f|
        {
          id:   f.id,
          name: f.name,
          learner_ids: f.learners.map(&:id)
        }
      },
      learners: folders.flat_map(&:learners).uniq.map { |l|
        { id: l.id, name: l.name, email: l.email }
      }
    }
  end

  private

  def find_workspace_learner(learner_id)
    Learner.joins("INNER JOIN learner_folder_members ON learner_folder_members.learner_id = learners.id")
           .joins("INNER JOIN learner_folders ON learner_folders.id = learner_folder_members.learner_folder_id")
           .where(learner_folders: { workspace_id: current_workspace.id })
           .find(learner_id)
  end

  def set_folder
    @folder = current_workspace.learner_folders.find(params[:id])
  end

  def folder_params
    params.require(:learner_folder).permit(:name)
  end

  def parse_import_file(file, ext)
    if ext == ".csv"
      require "csv"
      CSV.read(file.path, headers: true, encoding: "UTF-8").map do |row|
        { email: row["email"] || row["Email"], name: row["name"] || row["Name"] || row["Tên"] }
      end
    else
      spreadsheet = Roo::Excelx.new(file.path)
      sheet = spreadsheet.sheet(0)
      headers = sheet.row(1).map { |h| h.to_s.downcase.strip }
      email_col = headers.index { |h| h.include?("email") }
      name_col  = headers.index { |h| h.include?("tên") || h.include?("name") }
      (2..sheet.last_row).map do |i|
        row = sheet.row(i)
        { email: email_col ? row[email_col] : nil, name: name_col ? row[name_col] : nil }
      end
    end
  end

  def excel_template_data
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Learners") do |ws|
      header_style = ws.styles.add_style(
        bg_color: "4F46E5", fg_color: "FFFFFF",
        b: true, sz: 12, alignment: { horizontal: :center }
      )
      ws.add_row ["Email", "Tên"], style: [header_style, header_style]
      ws.add_row ["learner@example.com", "Nguyễn Văn A"]
      ws.add_row ["another@example.com", "Trần Thị B"]
      ws.column_info[0].width = 30
      ws.column_info[1].width = 25
    end
    package.to_stream.read
  end
end
