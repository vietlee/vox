class Participate::DynamicFormsController < Participate::BaseController
  before_action :set_form

  def show
    render :closed if @form.closed? || @form.draft?
  end

  def submit
    unless @form.active?
      render json: { error: @form.draft? ? "Form chưa được mở." : "Form đã đóng." }, status: :forbidden and return
    end

    data   = build_submission_data
    errors = validate_submission(data)

    if errors.any?
      render json: { errors: errors }, status: :unprocessable_entity and return
    end

    sub = @form.dynamic_form_submissions.create!(
      data:             data,
      respondent_token: respondent_token,
      ip_address:       request.remote_ip,
      assignee_id:      @form.workspace.admin_users.first&.id,
      custom_status:    @form.custom_statuses.first
    )

    # Attach uploaded files, store blob info back into data
    @form.dynamic_form_fields.where(field_type: "file").each do |field|
      uploaded = params.dig(:submission, field.field_key)
      files = Array(uploaded).select { |f| f.respond_to?(:read) }
      next if files.empty?

      file_data = files.map do |f|
        blob = ActiveStorage::Blob.create_and_upload!(
          io: f, filename: f.original_filename, content_type: f.content_type
        )
        sub.field_files.attach(blob)
        { filename: f.original_filename, blob_id: blob.signed_id }
      end

      sub.data[field.field_key] = file_data.length == 1 ? file_data.first : file_data
      sub.save!
    end

    # Send notification emails
    user_ids = Array(@form.settings["notification_user_ids"]).map(&:to_i).reject(&:zero?)
    if user_ids.any?
      User.where(id: user_ids).each do |user|
        NotificationMailer.new_dynamic_form_submission(sub, user).deliver_later
      end
    else
      # Default: workspace admins only
      @form.workspace.admin_users.each do |admin|
        NotificationMailer.new_dynamic_form_submission(sub, admin).deliver_later
      end
    end

    render json: { ok: true, message: "Đã gửi thành công!" }
  end

  private

  def set_form
    @form = DynamicForm.find_by!(slug: params[:slug])
    @workspace = @form.workspace
    set_locale_from_workspace
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end

  def build_submission_data
    data = {}
    @form.dynamic_form_fields.each do |field|
      next if field.field_type == "file"   # handled separately after create
      val = params.dig(:submission, field.field_key)
      data[field.field_key] = if field.field_type == "checkboxes"
        Array(val).map(&:to_s)
      else
        val.to_s.strip
      end
    end
    data
  end

  def validate_submission(data)
    errors = {}
    v = ->(key, **opts) { t("participate.dynamic_form.validation.#{key}", **opts) }

    @form.dynamic_form_fields.each do |field|
      # Skip validation for fields hidden by conditional logic
      next unless field_visible?(field, data)

      if field.field_type == "file"
        uploaded = Array(params.dig(:submission, field.field_key)).select { |f| f.respond_to?(:read) }
        if field.required && uploaded.empty?
          errors[field.field_key] = v.(:required, label: field.label)
        elsif field.max_size_mb.present?
          max_bytes = field.max_size_mb.to_i * 1024 * 1024
          big = uploaded.find { |f| f.size > max_bytes }
          errors[field.field_key] = v.(:file_too_large, filename: big.original_filename, max: field.max_size_mb) if big
        end
        next
      end

      val   = data[field.field_key]
      blank = val.is_a?(Array) ? val.empty? : val.to_s.strip.empty?

      if field.required && blank
        errors[field.field_key] = v.(:required, label: field.label)
        next
      end
      next if blank

      if %w[text email textarea url phone].include?(field.field_type)
        s = val.to_s
        errors[field.field_key] = v.(:min_length, min: field.min_length) if field.min_length.present? && s.length < field.min_length
        errors[field.field_key] = v.(:max_length, max: field.max_length) if field.max_length.present? && s.length > field.max_length
        errors[field.field_key] = v.(:invalid_email)                     if field.field_type == "email" && s !~ /\A[^@\s]+@[^@\s]+\z/
      end

      if field.field_type == "number"
        n = val.to_s.to_f
        errors[field.field_key] = v.(:min_value, min: field.min_value) if field.min_value.present? && n < field.min_value.to_f
        errors[field.field_key] = v.(:max_value, max: field.max_value) if field.max_value.present? && n > field.max_value.to_f
      end
    end
    errors
  end

  # Evaluate whether a field should be visible given submitted data
  def field_visible?(field, data)
    cl = field.conditional_logic
    return true unless cl.is_a?(Hash) && cl["enabled"]

    dep_key         = cl["field_key"].to_s
    operator        = cl["operator"].to_s.presence || "equals"
    condition_value = cl["value"].to_s
    return true if dep_key.blank?

    actual = data[dep_key]
    actual_str = actual.is_a?(Array) ? actual.join(",") : actual.to_s

    case operator
    when "equals"     then actual_str == condition_value
    when "not_equals" then actual_str != condition_value
    when "contains"   then actual_str.include?(condition_value)
    when "not_empty"  then actual_str.present?
    when "empty"      then actual_str.blank?
    else true
    end
  end
end
