class SuperAdmin::BroadcastsController < SuperAdmin::BaseController
  def index
    @broadcasts = Notification.where(notification_type: "system_broadcast")
                               .order(created_at: :desc)
                               .limit(100)
    @workspaces_count = Workspace.active.count
    @sent_count = Notification.where(notification_type: "system_broadcast").distinct.count(:workspace_id)
  end

  def new
    @workspaces = Workspace.active.order(:name)
  end

  def create
    title  = params[:title].to_s.strip
    body   = params[:body].to_s.strip.presence
    target = params[:target]

    if title.blank?
      @workspaces = Workspace.active.order(:name)
      flash.now[:alert] = t("super_admin.broadcasts.title_required")
      return render :new, status: :unprocessable_entity
    end

    workspaces = if target == "all"
      Workspace.active
    else
      Workspace.active.where(id: params[:workspace_ids].to_a.map(&:to_i))
    end

    if workspaces.empty?
      @workspaces = Workspace.active.order(:name)
      flash.now[:alert] = t("super_admin.broadcasts.no_target")
      return render :new, status: :unprocessable_entity
    end

    sent = 0
    workspaces.each do |ws|
      Notification.broadcast_to_workspace(workspace: ws, title: title, body: body)
      sent += 1
    end

    redirect_to super_admin_broadcasts_path,
      notice: t("super_admin.broadcasts.sent_success", count: sent)
  end
end
