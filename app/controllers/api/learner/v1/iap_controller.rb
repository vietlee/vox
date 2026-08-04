class Api::Learner::V1::IapController < Api::Learner::V1::BaseController
  # Product id → credits granted. These ids MUST match the Consumable in-app
  # purchases created in App Store Connect.
  APPLE_PRODUCTS = {
    "vox_credits_50"  => 50,
    "vox_credits_100" => 100,
    "vox_credits_200" => 200,
    "vox_credits_500" => 500
  }.freeze

  # Verifies an Apple purchase receipt and grants credits (idempotent).
  def apple
    product_id = params[:product_id].to_s
    receipt    = params[:receipt_data].to_s
    credits    = APPLE_PRODUCTS[product_id]

    return render json: { error: "Sản phẩm không hợp lệ." }, status: :unprocessable_entity unless credits
    return render json: { error: "Thiếu dữ liệu giao dịch." }, status: :unprocessable_entity if receipt.blank?

    data = AppleReceiptVerifier.verify(receipt)
    unless data && data["status"].to_i.zero?
      return render json: { error: "Không xác thực được giao dịch với Apple." }, status: :unprocessable_entity
    end

    items = Array(data.dig("receipt", "in_app")) + Array(data["latest_receipt_info"])
    tx = items.select { |i| i["product_id"] == product_id }
              .max_by { |i| i["purchase_date_ms"].to_i }
    return render json: { error: "Không tìm thấy giao dịch phù hợp." }, status: :unprocessable_entity unless tx

    transaction_id = tx["transaction_id"].to_s
    added = 0

    if LearnerIapPurchase.exists?(platform: "apple", transaction_id: transaction_id)
      # Already processed (retry / duplicate delivery) — no double grant.
    else
      ActiveRecord::Base.transaction do
        LearnerIapPurchase.create!(
          learner: current_learner, platform: "apple", product_id: product_id,
          transaction_id: transaction_id, credits: credits, status: "granted"
        )
        current_learner.add_credits!(credits)
        added = credits
      end
    end

    render json: { ok: true, credits_added: added, credits: current_learner.reload.credits }
  rescue ActiveRecord::RecordNotUnique
    render json: { ok: true, credits_added: 0, credits: current_learner.reload.credits }
  rescue => e
    Rails.logger.error "[IapController#apple] learner #{current_learner&.id}: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
