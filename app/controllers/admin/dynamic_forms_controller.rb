require "csv"
class Admin::DynamicFormsController < Admin::BaseController
  before_action :set_form,            only: [:show, :edit, :update, :destroy, :close, :reopen, :submissions, :export_csv, :publish, :update_submission_status, :update_submission_assignee, :show_submission, :destroy_submission, :update_submission_data]
  before_action :authorize_form_access!, only: [:show, :edit, :update, :destroy, :close, :reopen, :submissions, :export_csv, :publish, :update_submission_status, :update_submission_assignee, :show_submission, :destroy_submission, :update_submission_data]

  def index
    scope = if current_workspace_admin?
      current_workspace.dynamic_forms
    else
      current_workspace.dynamic_forms
        .joins(:dynamic_form_assignments)
        .where(dynamic_form_assignments: { user_id: current_user.id })
    end
    scope = scope.where("title ILIKE ?", "%#{params[:q].strip}%") if params[:q].present?
    scope = scope.order(created_at: :desc)
    @pagy, @forms = pagy(scope, items: 15)
    @search_query = params[:q]
  end

  def show
    @submissions = @form.dynamic_form_submissions.order(created_at: :desc).limit(50)
  end

  def new
    @form = current_workspace.dynamic_forms.build
    @form.dynamic_form_fields.build(position: 0)
  end

  def create
    subscription = current_workspace.active_subscription
    unless subscription&.within_dynamic_form_limit?
      msg = subscription&.free? ? t("dynamic_forms.limit_reached_free", date: subscription.next_reset_date_formatted) : t("dynamic_forms.limit_reached")
      redirect_to dynamic_forms_path, alert: msg and return
    end

    @form = current_workspace.dynamic_forms.build(form_params)
    @form.user = current_user

    if @form.save
      current_workspace.increment!(:dynamic_forms_created_count)
      save_fields!
      redirect_to edit_dynamic_form_path(@form), notice: "Tạo form thành công!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @members              = current_workspace.members.order(:name, :email)
    @assignee_ids         = @form.assignees.pluck(:id)
    @form_assignees       = @form.assignees.order(:name, :email)
    @notification_user_ids = Array(@form.settings["notification_user_ids"]).map(&:to_i)
  end

  def update
    remove_logo = params.dig(:dynamic_form, :remove_logo) == "1"
    if @form.update(form_params)
      @form.logo.purge if remove_logo && @form.logo.attached?
      save_fields!
      save_assignees!
      save_settings!
      redirect_to edit_dynamic_form_path(@form), notice: "Đã lưu thay đổi."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @form.deletable?
      @form.destroy
      redirect_to dynamic_forms_path, notice: "Đã xoá form."
    else
      redirect_to dynamic_forms_path, alert: "Chỉ xoá được form ở trạng thái Draft hoặc Đã đóng."
    end
  end

  def publish
    @form.update!(status: :active)
    redirect_back fallback_location: edit_dynamic_form_path(@form), notice: "Form đã được mở và sẵn sàng nhận submissions."
  end

  def close
    @form.update!(status: :closed)
    redirect_back fallback_location: edit_dynamic_form_path(@form), notice: "Form đã đóng."
  end

  def reopen
    @form.update!(status: :active)
    redirect_back fallback_location: edit_dynamic_form_path(@form), notice: "Form đã mở lại."
  end

  def submissions
    @time_order = params[:order] == "asc" ? "asc" : "desc"
    scope = @form.dynamic_form_submissions.includes(:assignee).order(created_at: @time_order)
    if params[:status].present?
      if @form.custom_statuses.any?
        scope = scope.where(custom_status: params[:status])
      elsif DynamicFormSubmission.statuses.key?(params[:status])
        scope = scope.where(status: params[:status])
      end
    end
    scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    scope = scope.search_data(params[:q])             if params[:q].present?
    @pagy, @submissions = pagy(scope, items: 15)
    @fields       = @form.dynamic_form_fields
    @assignees    = @form.assignees.order(:name, :email)
    @ws_admins    = @form.workspace.admin_users.order(:name, :email)
    @all_handlers = (@assignees + @ws_admins).uniq(&:id)
    @status_filter   = params[:status]
    @assignee_filter = params[:assignee_id]
    @search_query    = params[:q]
    @time_order      = @time_order
  end

  def show_submission
    @submission  = @form.dynamic_form_submissions.find(params[:submission_id])
    @fields      = @form.dynamic_form_fields
    @all_handlers = (@form.assignees + @form.workspace.admin_users).uniq(&:id).sort_by { |u| u.name.presence || u.email }
  end

  def update_submission_data
    sub = @form.dynamic_form_submissions.find(params[:submission_id])
    updates = params[:data].to_unsafe_h rescue {}
    # Only allow fields marked as admin_editable
    editable_keys = @form.dynamic_form_fields.where(admin_editable: true).pluck(:field_key)
    filtered = updates.slice(*editable_keys)
    sub.update_column(:data, sub.data.merge(filtered))
    render json: { ok: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy_submission
    sub = @form.dynamic_form_submissions.find(params[:submission_id])
    sub.destroy!
    @form.decrement!(:submissions_count)
    render json: { ok: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update_submission_status
    sub = @form.dynamic_form_submissions.find(params[:submission_id])
    if @form.custom_statuses.any?
      sub.update!(custom_status: params[:status])
      render json: { ok: true, status: sub.custom_status }
    else
      sub.update!(status: params[:status])
      render json: { ok: true, status: sub.status }
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update_submission_assignee
    sub = @form.dynamic_form_submissions.find(params[:submission_id])
    sub.update!(assignee_id: params[:assignee_id].presence)

    # Send assignee notification email if setting enabled and requested
    if params[:send_notification].to_s == "true" && sub.assignee && @form.notify_assignee?
      NotificationMailer.assignee_notification(sub, sub.assignee).deliver_later
    end

    assignee = sub.assignee
    render json: { ok: true, assignee_id: sub.assignee_id,
                   name: assignee ? (assignee.name.presence || assignee.email) : nil,
                   initials: assignee ? (assignee.name.presence || assignee.email).first.upcase : "?" }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def export_csv
    @fields      = @form.dynamic_form_fields
    @submissions = @form.dynamic_form_submissions.order(created_at: :desc)

    status_labels = { "pending" => "Chưa xử lý", "processing" => "Đang xử lý", "done" => "Đã xử lý" }
    csv = CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << ["#", "Thời gian", "Trạng thái", "Người xử lý"] + @fields.map(&:label)
      @submissions.each_with_index do |sub, i|
        assignee_name = sub.assignee ? (sub.assignee.name.presence || sub.assignee.email) : ""
        row = [i + 1, I18n.l(sub.created_at, format: :short), status_labels[sub.status] || sub.status, assignee_name]
        @fields.each do |f|
          val = sub.value_for(f.field_key)
          row << format_csv_value(val)
        end
        csv << row
      end
    end

    send_data "\xEF\xBB\xBF#{csv}",
              filename: "#{@form.slug}-submissions-#{Date.today}.csv",
              type: "text/csv; charset=utf-8"
  end

  private

  def set_form
    @form = current_workspace.dynamic_forms.find(params[:id])
  end

  def authorize_form_access!
    return if current_workspace_admin?
    unless @form.assignees.include?(current_user)
      redirect_to dynamic_forms_path, alert: "Bạn không có quyền truy cập form này."
    end
  end

  def form_params
    params.require(:dynamic_form).permit(:title, :description, :slug, :logo)
  end

  # Handle fields as a JSON array from hidden input
  def save_fields!
    fields_json = params[:fields_data]
    return if fields_json.blank?

    incoming     = JSON.parse(fields_json) rescue []
    existing_ids = @form.dynamic_form_fields.pluck(:id)
    incoming_ids = incoming.map { |f| f["id"].to_i }.select(&:positive?)

    # Delete removed fields
    (existing_ids - incoming_ids).each { |id| @form.dynamic_form_fields.find_by(id: id)&.destroy }

    incoming.each_with_index do |fdata, idx|
      next if fdata["label"].to_s.strip.blank?

      opts = (fdata["options"] || []).map { |o| { "label" => o["label"].to_s.strip, "value" => o["value"].to_s.strip } }
                                      .reject { |o| o["label"].blank? }
      cond = fdata["conditional_logic"]
      cond_attrs = if cond.is_a?(Hash) && cond["enabled"]
        { "enabled" => true, "field_key" => cond["field_key"].to_s,
          "operator" => cond["operator"].to_s.presence || "equals",
          "value" => cond["value"].to_s }
      else
        {}
      end

      attrs = {
        label:             fdata["label"].to_s.strip,
        field_key:         fdata["field_key"].to_s.strip,
        field_type:        fdata["field_type"].to_s,
        placeholder:       fdata["placeholder"].to_s.strip,
        hint:              fdata["hint"].to_s.strip,
        required:          fdata["required"].to_s == "true",
        options:           opts,
        min_length:        fdata["min_length"].presence,
        max_length:        fdata["max_length"].presence,
        min_value:         fdata["min_value"].to_s.presence,
        max_value:         fdata["max_value"].to_s.presence,
        accept:            fdata["accept"].to_s.presence,
        max_size_mb:       fdata["max_size_mb"].presence,
        multiple:          fdata["multiple"].to_s == "true",
        admin_only:        fdata["admin_only"].to_s == "true",
        admin_editable:    fdata["admin_editable"].to_s == "true",
        conditional_logic: cond_attrs,
        position:          idx,
      }

      if fdata["id"].to_i > 0
        @form.dynamic_form_fields.find_by(id: fdata["id"])&.update!(attrs)
      else
        @form.dynamic_form_fields.create!(attrs)
      end
    end
  end

  def format_csv_value(val)
    return "" if val.nil?

    blobs = if val.is_a?(Array) && val.first.is_a?(Hash) && val.first["blob_id"]
      val
    elsif val.is_a?(Hash) && val["blob_id"]
      [val]
    end

    if blobs
      blobs.map do |b|
        begin
          blob = ActiveStorage::Blob.find_signed(b["blob_id"])
          rails_blob_url(blob, host: request.base_url)
        rescue
          b["filename"].to_s
        end
      end.join(", ")
    elsif val.is_a?(Array)
      val.join(", ")
    else
      val.to_s
    end
  end

  def save_settings!
    settings_json = params[:settings_data]
    return if settings_json.blank?
    incoming = JSON.parse(settings_json) rescue {}
    return unless incoming.is_a?(Hash)
    # Merge & persist
    @form.update_column(:settings, @form.settings.merge(incoming))
  end

  def save_assignees!
    assignee_ids = Array(params[:assignee_ids]).map(&:to_i).select(&:positive?)
    valid_ids    = current_workspace.members.where(id: assignee_ids).pluck(:id)
    @form.dynamic_form_assignments.where.not(user_id: valid_ids).destroy_all
    valid_ids.each { |uid| @form.dynamic_form_assignments.find_or_create_by!(user_id: uid) }
  end
end
