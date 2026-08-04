require "net/http"
require "json"

# Verifies an iOS App Store receipt (the base64 `serverVerificationData` from
# the in_app_purchase package) with Apple's verifyReceipt endpoint. Falls back
# to the sandbox endpoint automatically (status 21007) so TestFlight/sandbox
# purchases work too. Needs ENV["APPLE_IAP_SHARED_SECRET"] (App-Specific Shared
# Secret from App Store Connect).
module AppleReceiptVerifier
  PROD    = "https://buy.itunes.apple.com/verifyReceipt".freeze
  SANDBOX = "https://sandbox.itunes.apple.com/verifyReceipt".freeze

  module_function

  def verify(receipt_data)
    body = {
      "receipt-data" => receipt_data,
      "password"     => ENV["APPLE_IAP_SHARED_SECRET"],
      "exclude-old-transactions" => true
    }
    res = post(PROD, body)
    res = post(SANDBOX, body) if res && res["status"].to_i == 21007
    res
  end

  def post(url, body)
    uri  = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 10
    http.read_timeout = 15
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = body.to_json
    JSON.parse(http.request(req).body)
  rescue => e
    Rails.logger.warn "[AppleReceiptVerifier] #{e.message}"
    nil
  end
end
