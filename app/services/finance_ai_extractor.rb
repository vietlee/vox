# Extracts finance rows (date / income-or-expense / amount / category / note)
# from an uploaded image (receipt, handwritten list, bank screenshot) or pasted
# text, using Claude. Returns an array of hashes for the teacher to preview/edit.
class FinanceAiExtractor
  def initialize(image: nil, text: "", workspace: nil)
    @image = image
    @text  = text.to_s.strip
    @workspace = workspace
  end

  SYSTEM = <<~PROMPT
    Bạn là trợ lý kế toán cho giáo viên. Từ ảnh hoặc văn bản được cung cấp (biên lai,
    danh sách thu học phí, sao kê, tin nhắn chuyển khoản...), hãy trích xuất các khoản
    thu/chi. CHỈ trả về JSON hợp lệ, không giải thích, dạng:
    {"rows":[{"date":"YYYY-MM-DD","kind":"income|expense","amount":<số nguyên VND>,"category":"...","note":"..."}]}
    - kind: "income" nếu là tiền thu vào (học phí, nộp tiền), "expense" nếu chi ra.
    - amount: số nguyên tiền VND (bỏ dấu chấm/phẩy, không có ký hiệu).
    - date: nếu không rõ ngày thì dùng ngày hôm nay.
    - category: ngắn gọn (VD "Học phí", "Thuê phòng", "Lương trợ giảng").
    - note: tên người nộp / mô tả nếu có.
    Nếu không tìm thấy khoản nào, trả {"rows":[]}.
  PROMPT

  def call
    content = []
    if @image.respond_to?(:read)
      data = Base64.strict_encode64(@image.read)
      mime = @image.content_type.presence || "image/jpeg"
      content << { type: "image", source: { type: "base64", media_type: mime, data: data } }
    end
    user_text = @text.present? ? "Văn bản:\n#{@text}" : "Trích xuất các khoản thu/chi từ ảnh trên."
    content << { type: "text", text: user_text }

    svc = ClaudeService.new(model: ClaudeService::SONNET_MODEL, timeout: 60)
    raw = svc.call(system_prompt: SYSTEM, messages: [{ role: "user", content: content }], max_tokens: 2000)
    parse_rows(raw)
  end

  private

  def parse_rows(raw)
    json = raw.to_s[/\{.*\}/m] || "{}"
    data = JSON.parse(json) rescue {}
    Array(data["rows"]).map do |r|
      {
        date:     (Date.parse(r["date"].to_s) rescue Date.current).iso8601,
        kind:     (r["kind"] == "expense" ? "expense" : "income"),
        amount:   r["amount"].to_s.gsub(/[^\d]/, "").to_i,
        category: r["category"].to_s.strip,
        note:     r["note"].to_s.strip,
      }
    end.select { |r| r[:amount] > 0 }
  end
end
