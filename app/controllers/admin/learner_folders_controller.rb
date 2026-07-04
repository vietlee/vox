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
    @members = @folder.learner_folder_members.includes(:learner).order("learners.email")
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
    redirect_to learner_folder_path(@folder), notice: "Đã thêm #{learner.email} vào folder."
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

  private

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
      spreadsheet = Roo::Xlsx.new(file.path)
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
