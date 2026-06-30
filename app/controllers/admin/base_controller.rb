class Admin::BaseController < ApplicationController
  before_action :require_workspace_member!
  before_action :require_workspace_active!
  layout "admin"

  private

  def require_workspace_member!
    # Participant users cannot access admin dashboard
    if current_user&.participant?
      redirect_to my_participations_path, alert: t("errors.access_denied")
      return
    end
    unless current_workspace_role.present?
      redirect_to new_user_session_path, alert: t("errors.access_denied")
    end
  end

  def require_workspace_active!
    return if current_workspace.nil?
    unless current_workspace.active?
      sign_out current_user
      redirect_to new_user_session_path, alert: t("errors.workspace_suspended")
    end
  end

  def audit_log(action, resource: nil, changes: {})
    AuditLog.record(
      user:      current_user,
      workspace: current_workspace,
      action:    action,
      resource:  resource,
      changes:   changes,
      request:   request
    )
  end

  def require_admin!
    unless current_workspace_admin?
      redirect_to dashboard_path, alert: t("errors.admin_only")
    end
  end

  def markdown_to_html(text)
    text = ERB::Util.html_escape(text)
    text = text.gsub(/^# (.+)$/) { "<h1 style='font-size:16px;font-weight:800;color:#0f172a;margin:0 0 6px;line-height:1.4'>#{$1}</h1>" }
    section_colors = { 0 => "#10b981", 1 => "#f59e0b", 2 => "#6366f1", 3 => "#3b82f6" }
    section_idx = -1
    text = text.gsub(/^## (.+)$/) do
      section_idx += 1
      color = section_colors[section_idx % 4]
      "<div style='display:flex;align-items:center;gap:8px;margin:20px 0 10px'><div style='width:4px;height:20px;border-radius:2px;background:#{color};flex-shrink:0'></div><h2 style='font-size:14px;font-weight:800;color:#1e293b;margin:0'>#{$1}</h2></div>"
    end
    text = text.gsub(/^### (.+)$/) { "<h3 style='font-size:13px;font-weight:700;color:#334155;margin:14px 0 6px'>#{$1}</h3>" }
    text = text.gsub(/^---+$/, "<hr style='border:none;border-top:1px solid #e2e8f0;margin:16px 0'>")
    text = text.gsub(/\*\*(.+?)\*\*/, '<strong style="color:#0f172a">\1</strong>')
    text = text.gsub(/\*(.+?)\*/, '<em>\1</em>')
    text = text.gsub(/^[-•] (.+)$/, '<li style="margin:4px 0;color:#334155">\1</li>')
    text = text.gsub(/^(\d+)\. (.+)$/, '<li style="margin:4px 0;color:#334155">\2</li>')
    text = text.gsub(/(<li[^>]*>.*?<\/li>(\s*<li[^>]*>.*?<\/li>)*)/m) { "<ul style='margin:6px 0 8px 16px;padding:0;list-style:disc'>#{$1}</ul>" }
    text = text.gsub(/\n{2,}/, "</p><p style='margin:6px 0;color:#475569;line-height:1.65;font-size:13px'>")
    text = text.gsub(/\n/, "<br>")
    "<p style='margin:0 0 6px;color:#475569;line-height:1.65;font-size:13px'>#{text}</p>"
  end

  # Simple pagination helper
  def pagy(scope, items: 15, page: nil)
    page  = (page || params[:page] || 1).to_i
    total = scope.count
    pages = [(total.to_f / items).ceil, 1].max
    page  = [[page, 1].max, pages].min
    records = scope.offset((page - 1) * items).limit(items)
    from = total.zero? ? 0 : (page - 1) * items + 1
    to   = [page * items, total].min
    prev_page = page > 1 ? page - 1 : nil
    next_page = page < pages ? page + 1 : nil
    pagy_obj = Struct.new(:page, :items, :count, :pages, :from, :to, :prev, :next)
                     .new(page, items, total, pages, from, to, prev_page, next_page)
    [pagy_obj, records]
  end
end
