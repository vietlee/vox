class SuperAdmin::DashboardController < SuperAdmin::BaseController
  def index
    @workspaces_count  = Workspace.count
    @users_count       = User.count
    @surveys_count     = Survey.count
    @votes_count       = Vote.count
    @recent_workspaces = Workspace.order(created_at: :desc).limit(10)

    # Date range filter
    @date_from = params[:date_from].present? ? (Date.parse(params[:date_from]) rescue nil) : nil
    @date_to   = params[:date_to].present?   ? (Date.parse(params[:date_to])   rescue nil) : nil
    period_from = @date_from&.beginning_of_day || Time.current.beginning_of_month
    period_to   = @date_to&.end_of_day         || Time.current.end_of_month

    # Revenue stats
    @alltime_revenue = Payment.where(status: :completed).sum(:amount_cents)
    @period_revenue  = Payment.where(status: :completed)
                              .where(paid_at: period_from..period_to)
                              .sum(:amount_cents)
    @pending_revenue = Payment.where(status: :pending).sum(:amount_cents)
    @active_subs     = Subscription.where(status: :active).where.not(plan: :free).count

    # Last 6 months revenue (bar chart data)
    @monthly_revenue = 5.downto(0).map do |i|
      month = i.months.ago
      amt   = Payment.where(status: :completed)
                     .where(paid_at: month.beginning_of_month..month.end_of_month)
                     .sum(:amount_cents)
      { label: month.strftime("%b %Y"), amount: amt }
    end

    # Recent payments with workspace info (filtered by date range if set)
    payments_scope = Payment.includes(:workspace, :subscription).order(created_at: :desc)
    if @date_from || @date_to
      payments_scope = payments_scope.where(created_at: period_from..period_to)
    end
    @recent_payments = payments_scope.limit(15)

    # This month's subscriptions with payment status
    @month_subs = Subscription.includes(:workspace, :payments)
                              .where.not(plan: :free)
                              .where(created_at: Time.current.beginning_of_month..Time.current.end_of_month)
                              .order(created_at: :desc)

    # ElevenLabs API usage
    if ENV["ELEVENLABS_API_KEY"].present?
      @elevenlabs = ElevenLabsService.new.subscription_usage
      @elevenlabs_error = @elevenlabs.nil? ? :fetch_failed : nil
    else
      @elevenlabs_error = :no_key
    end
  end
end
