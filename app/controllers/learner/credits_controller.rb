class Learner::CreditsController < Learner::BaseController
  PRICE_PER_CREDIT = 1_000 # 1.000₫ / credit

  def index
    @price_per_credit = PRICE_PER_CREDIT
  end

  def checkout
    # Placeholder — wire to PayOS
    render json: { error: "Tính năng mua credit đang được triển khai" }, status: :not_implemented
  end
end
