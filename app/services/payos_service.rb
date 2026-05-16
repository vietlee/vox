class PayosService
  BASE_URL = "https://api-merchant.payos.vn"

  def initialize
    @client_id    = ENV.fetch("PAYOS_CLIENT_ID", "")
    @api_key      = ENV.fetch("PAYOS_API_KEY", "")
    @checksum_key = ENV.fetch("PAYOS_CHECKSUM_KEY", "")
  end

  # Creates a PayOS payment link. Returns the data hash on success, nil on failure.
  # data keys: "paymentLinkId", "checkoutUrl", "qrCode", "orderCode"
  def create_payment_link(order_code:, amount:, description:, return_url:, cancel_url:, expired_at: nil)
    payload = {
      orderCode:   order_code,
      amount:      amount.to_i,
      description: description.truncate(25),
      returnUrl:   return_url,
      cancelUrl:   cancel_url
    }
    payload[:expiredAt] = expired_at.to_i if expired_at
    payload[:signature] = sign_create(payload)

    response = HTTParty.post(
      "#{BASE_URL}/v2/payment-requests",
      headers: headers,
      body:    payload.to_json,
      timeout: 10
    )

    parsed = response.parsed_response
    return nil unless parsed.is_a?(Hash) && parsed["code"] == "00"
    parsed["data"]
  rescue => e
    Rails.logger.error("[PayOS] create_payment_link error: #{e.message}")
    nil
  end

  # Verifies the webhook payload signature. Call with the parsed JSON body hash.
  def verify_webhook(payload)
    data = payload["data"]
    return false unless data.is_a?(Hash)
    expected = sign_webhook(data)
    ActiveSupport::SecurityUtils.secure_compare(data["signature"].to_s, expected)
  end

  private

  def headers
    {
      "x-client-id"  => @client_id,
      "x-api-key"    => @api_key,
      "Content-Type" => "application/json"
    }
  end

  # PayOS signature for creating a payment: alphabetically sorted subset of fields
  def sign_create(payload)
    str = "amount=#{payload[:amount]}" \
          "&cancelUrl=#{payload[:cancelUrl]}" \
          "&description=#{payload[:description]}" \
          "&orderCode=#{payload[:orderCode]}" \
          "&returnUrl=#{payload[:returnUrl]}"
    OpenSSL::HMAC.hexdigest("SHA256", @checksum_key, str)
  end

  # PayOS signature for webhook: all data fields sorted alphabetically
  def sign_webhook(data)
    sorted = data.except("signature").sort.map { |k, v| "#{k}=#{v}" }.join("&")
    OpenSSL::HMAC.hexdigest("SHA256", @checksum_key, sorted)
  end
end
