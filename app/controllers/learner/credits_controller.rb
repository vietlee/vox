class Learner::CreditsController < Learner::BaseController
  PACKAGES = [
    { credits: 50,  price: 29_000,  label: "Gói Nhỏ" },
    { credits: 150, price: 79_000,  label: "Gói Vừa" },
    { credits: 400, price: 179_000, label: "Gói Lớn" }
  ].freeze

  def index
    @packages = PACKAGES
    @history  = [] # future: LearnerCreditTransaction
  end

  def checkout
    # Placeholder — wire to PayOS same as workspace subscriptions
    render json: { error: "Tính năng mua credit đang được triển khai" }, status: :not_implemented
  end
end
