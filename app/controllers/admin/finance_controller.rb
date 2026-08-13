# Teacher revenue/expense management: tuition tracking per class + period, a
# unified income/expense ledger, an AI-assisted importer, and a stats dashboard.
class Admin::FinanceController < Admin::BaseController
  before_action :set_folder,  only: [:update_tuition_plan, :generate_roster]
  before_action :set_tuition, only: [:mark_paid, :mark_unpaid]

  # ── Dashboard ───────────────────────────────────────────────────────────
  def dashboard
    @from, @to = resolve_range
    entries = current_workspace.finance_entries.in_range(@from, @to)
    @income_total  = entries.income.sum(:amount_cents)
    @expense_total = entries.expense.sum(:amount_cents)
    @net           = @income_total - @expense_total
    @entries       = current_workspace.finance_entries.recent.includes(:learner_folder, :learner).limit(60)

    @folders = current_workspace.learner_folders.order(:name).to_a
    @period_key = params[:period].presence || default_period_key(@folders.first)
    # Per-class tuition summary for the selected period
    @class_summaries = @folders.map do |f|
      recs = f.tuition_payments.for_period(@period_key)
      { folder: f, total: recs.count, paid: recs.paid.count,
        collected: recs.paid.sum(:amount_cents), members: f.member_count }
    end
  end

  # ── Ledger entries ──────────────────────────────────────────────────────
  def create_entry
    e = current_workspace.finance_entries.new(entry_params)
    e.created_by = current_user
    e.source = :manual
    if e.save
      redirect_to finance_path, notice: "Đã lưu khoản #{e.income? ? 'thu' : 'chi'}."
    else
      redirect_to finance_path, alert: e.errors.full_messages.to_sentence
    end
  end

  def destroy_entry
    e = current_workspace.finance_entries.find(params[:id])
    # If it came from a tuition payment, revert that record to unpaid.
    e.tuition_payment&.update(status: :unpaid, paid_on: nil)
    e.destroy
    redirect_to finance_path, notice: "Đã xoá khoản."
  end

  # ── Tuition ─────────────────────────────────────────────────────────────
  def update_tuition_plan
    @folder.update(tuition_amount_cents: params[:tuition_amount_cents].to_i,
                   tuition_cycle: params[:tuition_cycle].presence || "monthly")
    redirect_to finance_path(period: params[:period]), notice: "Đã cập nhật học phí lớp #{@folder.name}."
  end

  def generate_roster
    key = params[:period_key].presence || default_period_key(@folder)
    n = @folder.generate_tuition_roster!(key)
    redirect_to finance_class_path(@folder, period: key), notice: "Đã tạo danh sách #{n} học viên cần nộp."
  end

  # Per-class tuition detail (roster with paid/unpaid)
  def klass
    @folder = current_workspace.learner_folders.find(params[:id])
    @period_key = params[:period].presence || default_period_key(@folder)
    @records = @folder.tuition_payments.for_period(@period_key)
                      .includes(:learner).order("learners.name")
    @periods = @folder.tuition_payments.distinct.pluck(:period_key).sort.reverse
    @periods = [@period_key] if @periods.empty?
  end

  def mark_paid
    @tuition.mark_paid!(on: Date.current, by: current_user)
    redirect_back fallback_location: finance_path, notice: "Đã đánh dấu đã nộp."
  end

  def mark_unpaid
    @tuition.mark_unpaid!
    redirect_back fallback_location: finance_path, notice: "Đã chuyển về chưa nộp."
  end

  # ── AI import ───────────────────────────────────────────────────────────
  # Step 1: upload an image/paste text → Claude extracts rows → JSON for preview.
  def ai_extract
    return unless require_credits!(:document_summary)
    rows = FinanceAiExtractor.new(
      image: params[:image], text: params[:text].to_s,
      workspace: current_workspace
    ).call
    charge_credits!(:document_summary)
    render json: { rows: rows }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Step 2: import the (user-edited) rows into the ledger.
  def ai_import
    rows = params[:rows] || []
    created = 0
    rows.each do |r|
      amt = r[:amount].to_s.gsub(/[^\d]/, "").to_i
      next if amt <= 0
      current_workspace.finance_entries.create!(
        kind: (r[:kind] == "expense" ? :expense : :income),
        amount_cents: amt,
        occurred_on: (Date.parse(r[:date].to_s) rescue Date.current),
        category: r[:category].presence || (r[:kind] == "expense" ? "Chi khác" : "Thu khác"),
        note: r[:note], source: :ai_import, created_by: current_user
      )
      created += 1
    end
    redirect_to finance_path, notice: "Đã nhập #{created} khoản từ AI."
  end

  private

  def set_folder
    @folder = current_workspace.learner_folders.find(params[:folder_id])
  end

  def set_tuition
    @tuition = current_workspace.tuition_payments.find(params[:id])
  end

  def entry_params
    params.require(:finance_entry).permit(:kind, :amount_cents, :occurred_on, :category, :note, :learner_folder_id)
  end

  def default_period_key(folder)
    TuitionPayment.key_for(folder&.tuition_cycle || "monthly")
  end

  def resolve_range
    case params[:range]
    when "quarter"
      q = (Date.current.month - 1) / 3
      [Date.new(Date.current.year, q * 3 + 1, 1), Date.current.end_of_month]
    when "year"
      [Date.current.beginning_of_year, Date.current.end_of_year]
    when "custom"
      [(Date.parse(params[:from]) rescue Date.current.beginning_of_month),
       (Date.parse(params[:to]) rescue Date.current.end_of_month)]
    else # month
      [Date.current.beginning_of_month, Date.current.end_of_month]
    end
  end
end
