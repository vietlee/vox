# PRD – Vox SaaS Platform
### Nền tảng khảo sát, bình chọn & góp ý nội bộ doanh nghiệp
**Phiên bản:** 2.0 | **Ngày:** 2026-05-14 | **Trạng thái:** Draft (AI-Enhanced)


---

## 1. Tầm nhìn sản phẩm

Vox là nền tảng SaaS giúp doanh nghiệp thu thập ý kiến nhân viên một cách nhanh chóng, minh bạch và thông minh thông qua ba công cụ cốt lõi: **Survey** (khảo sát), **Live Vote** (bình chọn thời gian thực) và **Feedback** (góp ý ẩn danh/công khai).

**Điểm khác biệt cốt lõi**: AI không chỉ phân tích dữ liệu sau khi thu thập — mà tham gia vào **toàn bộ vòng đời**: giúp tạo câu hỏi tốt hơn, kiểm duyệt nội dung tự động, tóm tắt kết quả tức thì, và tạo báo cáo executive-ready cho ban lãnh đạo.

---

## 2. Đối tượng người dùng (Personas)

| Persona | Mô tả | Nhu cầu chính |
|---|---|---|
| **Admin(HR Manager...)** | Phụ trách tạo khảo sát, quản lý workspace, Xem dashboard phân tích  | Tạo nhanh, xem kết quả tổng quan, phân tích AI |
| **Supporter(Team Lead...)** | Hỗ trợ admin tạo khảo sát, tạo vote, chạy vote trong meeting | Mở vote realtime, xem feedback của team |
| **Nhân viên (End User)** | Tham gia khảo sát, vote, góp ý | Dễ dùng, nhanh, ẩn danh khi cần |
| **Super Admin (System)** | Quản trị toàn hệ thống | Tạo workspace, quản lý gói dịch vụ |
| **Giám đốc / C-Level của workspace đó** | Xem dashboard phân tích | Insight nhanh, AI tóm tắt, báo cáo executive |

---

## 3. Kiến trúc vai trò & phân quyền

### 3.1 Super Admin (System Level)
- Tạo / vô hiệu hóa workspace cho từng công ty
- Cấu hình thông tin workspace: tên công ty, logo, gói dịch vụ
- Gửi email mời kèm thông tin đăng nhập đến Admin của workspace
- Xem thống kê toàn hệ thống: số workspace, số survey/vote đang chạy, doanh thu
- Quản lý gói subscription của từng workspace (nâng cấp, hạ cấp, gia hạn, khóa)
- Reset mật khẩu cho Workspace Admin

### 3.2 Workspace Admin
- Toàn quyền trong phạm vi workspace của mình
- Quản lý danh sách Supporter (thêm, xóa, phân quyền)
- Xem tất cả Survey, Vote, Feedback trong workspace
- Truy cập AI Dashboard & báo cáo phân tích
- Cấu hình workspace: tên, logo, màu thương hiệu, ngôn ngữ mặc định
- Quản lý subscription & thanh toán
- Xem lịch sử hoạt động (audit log)

### 3.3 Supporter
- Tạo, chỉnh sửa, xóa Survey / Vote / Feedback session và có thể cấu hình cho survey, vote đó như ai được phép, ẩn danh hay bắt buộc email...
- Xem kết quả và báo cáo của các session mình tạo
- Không thể xem kết quả session của Supporter khác (trừ khi Admin cho phép)
- Không truy cập được AI Dashboard nâng cao
- Không thể quản lý thanh toán

### 3.4 End User (Người tham gia)
- Không cần tạo tài khoản (truy cập qua link hoặc QR code)
- Tham gia Survey, Vote, Feedback theo cài đặt của Admin
- Nhập email nếu session yêu cầu (không ẩn danh)
- Xem kết quả real-time nếu Admin cho phép hiển thị

---

## 4. Chức năng chi tiết

### 4.1 Module: Survey (Khảo sát)

#### 4.1.1 Tạo & quản lý Survey
- Tạo survey với tiêu đề, mô tả, ảnh banner tùy chọn
- **[AI] Tạo survey từ mô tả** *(xem mục 6.1)*: Admin nhập mục tiêu bằng ngôn ngữ tự nhiên → AI sinh toàn bộ câu hỏi phù hợp
- **Trình soạn thảo câu hỏi động (Drag & Drop)**:
  - Multiple choice (chọn một)
  - Checkbox (chọn nhiều)
  - Rating scale (1–5, 1–10, sao ⭐)
  - Text ngắn (single line)
  - Text dài (paragraph)
  - Dropdown list
  - Linear scale (ví dụ: Hoàn toàn không đồng ý → Hoàn toàn đồng ý)
  - Matrix / Grid (đánh giá nhiều tiêu chí cùng lúc)
  - Date / Time picker
  - File upload (ảnh, PDF)
  - NPS Score (Net Promoter Score 0–10)
- **[AI] Gợi ý cải thiện câu hỏi** *(xem mục 6.1)*: Khi Admin soạn câu hỏi, AI phát hiện câu hỏi dẫn dắt (leading question), câu hỏi mơ hồ, hoặc câu hỏi kép (double-barreled) và đề xuất viết lại
- Mỗi câu hỏi có thể: bắt buộc / không bắt buộc, thêm mô tả phụ, thêm ảnh minh họa
- **Phân nhánh điều kiện (Conditional Logic)**: câu hỏi tiếp theo thay đổi dựa theo câu trả lời trước
- **Chấm điểm**: gán điểm cho từng lựa chọn, tự động tính tổng điểm và hiển thị kết quả sau khi submit
- Nhóm câu hỏi thành các Section (trang)
- Preview survey trước khi publish
- Sao chép survey hiện có

#### 4.1.2 Cài đặt Survey
- Trạng thái: Draft / Active / Closed / Archived
- Thời gian mở/đóng tự động (schedule)
- **Chế độ danh tính**:
  - Ẩn danh hoàn toàn
  - Yêu cầu nhập email
  - Yêu cầu đăng nhập (tích hợp SSO cho google và ms)
- Giới hạn số lần submit (một người chỉ làm 1 lần / nhiều lần)
- Giới hạn tổng số người tham gia
- Hiển thị thanh tiến trình
- Hiển thị kết quả sau khi submit (có/không)
- Cho phép chỉnh sửa câu trả lời sau khi submit
- Thông điệp cảm ơn tùy chỉnh sau khi hoàn thành
- Chuyển hướng về URL tùy chỉnh sau khi submit

#### 4.1.3 Phân phối Survey
- Link trực tiếp (shareable URL)
- Mã QR tự động sinh sau khi publish
- Embed vào website (iframe code)
- Gửi email mời tham gia (danh sách email)

#### 4.1.4 Kết quả & Báo cáo Survey
- Dashboard kết quả theo từng câu hỏi (biểu đồ cột, tròn, dạng text)
- Lọc kết quả theo thời gian, theo nhóm người trả lời
- Export kết quả ra Excel / CSV / PDF
- **[AI] Export báo cáo executive (PDF/Word)** *(xem mục 6.5)*: AI tự động tạo báo cáo định dạng chuyên nghiệp
- Xem câu trả lời thô từng người (nếu không ẩn danh)
- **[AI] Phân tích tổng hợp AI** *(xem mục 6.2)*

---

### 4.2 Module: Live Vote (Bình chọn thời gian thực)

#### 4.2.1 Tạo & quản lý Vote
- Tạo vote với câu hỏi và các lựa chọn (tối thiểu 2, tối đa 10 lựa chọn)
- Hỗ trợ các loại vote:
  - Single choice
  - Multiple choice
  - Word cloud (người dùng nhập từ khóa, tạo cloud realtime)
  - Open-ended (người dùng nhập câu trả lời ngắn, hiển thị realtime)
  - Ranking (kéo thả để xếp hạng ưu tiên)
  - Q&A upvote (người tham gia gửi câu hỏi, upvote câu hỏi hay)
- Cài đặt thời gian đếm ngược (countdown timer)
- Ẩn / hiện kết quả trong khi vote đang diễn ra
- Mở / đóng vote thủ công (Admin bấm nút)

#### 4.2.2 Trải nghiệm realtime
- Kết quả cập nhật tức thì không cần refresh (WebSocket)
- Màn hình chiếu (Presenter View): Admin mở trên màn hình lớn, tự động cập nhật
- Màn hình tham gia (Participant View): giao diện tối giản trên mobile, quét QR là vào được ngay
- Hiển thị số người đang tham gia (online count)
- Hiệu ứng animation khi vote thay đổi (bars grow, numbers count up)

#### 4.2.3 Kết quả Vote
- Lưu lịch sử tất cả các lần vote
- So sánh kết quả giữa các lần vote cùng chủ đề
- **[AI] Tóm tắt kết quả vote tức thì** *(xem mục 6.3)*: Ngay sau khi vote đóng, AI sinh 2–3 câu nhận xét về kết quả
- Export kết quả

---

### 4.3 Module: Feedback & Góp ý

#### 4.3.1 Tạo Feedback Board
- Admin tạo các "board" góp ý theo chủ đề (ví dụ: "Góp ý văn phòng", "Góp ý quy trình làm việc")
- Cài đặt danh tính:
  - Ẩn danh hoàn toàn
  - Công khai tên tuổi
  - Cho người dùng tự chọn (ẩn danh hoặc để tên)
- **[AI] Kiểm duyệt tự động** *(xem mục 6.4)*: AI lọc nội dung không phù hợp, spam trước khi hiển thị
- Cài đặt kiểm duyệt thủ công: feedback phải được Admin duyệt trước khi hiển thị / hiển thị ngay
- Tag / category cho mỗi board

#### 4.3.2 Trải nghiệm người dùng
- Viết góp ý (text, tối đa 1000 ký tự)
- Đính kèm ảnh (tùy chọn)
- Upvote các góp ý của người khác
- Reply / bình luận vào góp ý (nếu Admin bật)
- Đánh dấu trạng thái của góp ý: Mới / Đang xem xét / Đã triển khai / Từ chối (Admin cập nhật)

#### 4.3.3 Quản lý Feedback (Admin/Supporter)
- Xem tất cả góp ý, lọc theo trạng thái / tag / thời gian
- Duyệt / ẩn / xóa góp ý
- Cập nhật trạng thái và thêm phản hồi chính thức từ Admin
- Pin các góp ý quan trọng lên đầu
- **[AI] Tóm tắt và phân loại chủ đề** *(xem mục 6.2)*

---

### 4.4 Module: Workspace Management

#### 4.4.1 Super Admin – Tạo Workspace
- Form tạo workspace: Tên công ty, Logo, Tên Admin, Email Admin, Gói dịch vụ
- Hệ thống tự động:
  - Tạo workspace 
  - Tạo tài khoản Admin với mật khẩu ngẫu nhiên an toàn
  - Gửi email chào mừng kèm thông tin đăng nhập và link đổi mật khẩu (bắt buộc đổi lần đầu)
- Danh sách workspace: tìm kiếm, lọc theo gói, trạng thái

#### 4.4.2 Workspace Settings (Admin)
- Thông tin cơ bản: tên, logo, màu chủ đạo (brand color), favicon
- Cài đặt ngôn ngữ mặc định (Tiếng Việt / English)
- Cài đặt múi giờ
- Tùy chỉnh email template (logo, màu sắc trong email gửi đi)
- Cài đặt bảo mật: 2FA bắt buộc cho Admin/Supporter, timeout session

#### 4.4.3 Quản lý thành viên (Admin)
- Danh sách Supporter: email, trạng thái, ngày tham gia, số session đã tạo
- Mời Supporter qua email
- Thay đổi quyền / vô hiệu hóa tài khoản Supporter
- Xem audit log: ai làm gì, lúc nào

---

### 4.5 Module: Authentication & Security

#### 4.5.1 Đăng nhập
- Email + Password (bắt buộc đổi mật khẩu lần đầu đối với tài khoản được tạo tự động)
- Forgot password qua email
- Two-Factor Authentication (2FA) qua Authenticator App (TOTP)
- Session timeout cấu hình được (mặc định 2 tháng)
- Đăng nhập theo workspace (mỗi workspace là một tenant độc lập)

#### 4.5.2 Bảo mật dữ liệu
- Mã hóa mật khẩu bằng bcrypt
- HTTPS bắt buộc toàn bộ
- Rate limiting trên tất cả API endpoints
- CSRF protection
- Dữ liệu ẩn danh thực sự: không lưu IP hoặc bất kỳ định danh nào khi người dùng chọn ẩn danh
- Phân tách dữ liệu giữa các workspace (multi-tenancy strict isolation)

---

### 4.6 Module: QR Code

- Tự động sinh QR code sau khi publish bất kỳ Survey / Vote / Feedback board nào
- QR code dẫn đến link tương ứng (mobile-optimized landing page)
- Download QR code dạng PNG (độ phân giải cao), SVG, hoặc PDF in ấn
- Tùy chỉnh QR code: màu sắc, logo công ty ở giữa
- QR code hợp lệ trong suốt vòng đời của session (tự động redirect nếu session đã đóng)
- Tracking: đếm số lượt quét QR (so sánh với số lượt truy cập qua link trực tiếp)

---

### 4.7 Module: Subscription & Thanh toán

#### 4.7.1 Các gói dịch vụ

| Tính năng | Free | Pro (1.000.000 VNĐ/tháng) | Enterprise (Liên hệ) |
|---|---|---|---|
| Số Survey | 3 lần tạo | Không giới hạn | Không giới hạn |
| Số Vote | 3 lần tạo | Không giới hạn | Không giới hạn |
| Số Feedback (lượt góp ý) | 10 lượt | Không giới hạn | Không giới hạn |
| Số Supporter | 0 | 10 người | Không giới hạn |
| **AI Survey Builder** | ❌ | ✅ 10 lần/tháng | Không giới hạn |
| **AI Analysis (Survey/Feedback)** | ❌ | ✅ | ✅ |
| **AI Executive Report** | ❌ | ✅ 5 báo cáo/tháng | Không giới hạn |
| **AI Chat Assistant** | ❌ | ❌ | ✅ |
| **AI Content Moderation** | ❌ | ✅ tự động | ✅ |
| AI Credit/tháng | 0 | 500 credits | Unlimited |
| Custom branding | ❌ | ✅ | ✅ |
| Custom domain | ❌ | ❌ | ✅ |
| Export Excel/PDF | ❌ | ✅ | ✅ |
| QR code tùy chỉnh | Basic | Full | Full |
| SSO (SAML/OIDC) | ❌ | ❌ | ✅ |
| SLA & dedicated support | ❌ | Email | Dedicated CSM |
- CHo phép thay đổi những thông số của góp dịch vụ bởi admin, kể cả giá, số survey...

> **AI Credit system**: Mỗi tính năng AI tiêu thụ một lượng credit khác nhau (ví dụ: tóm tắt survey 200 phản hồi = 10 credits; tạo survey từ prompt = 5 credits). Hệ thống credit linh hoạt hơn giới hạn cứng "100 lần gọi/tháng" vốn không phản ánh đúng mức tiêu thụ thực tế.

#### 4.7.2 Cổng thanh toán
- Tích hợp: **VNPay**, **MoMo**, **Stripe** (thẻ quốc tế)
- Thanh toán theo tháng hoặc năm (năm giảm 20%)
- Tự động gia hạn (recurring billing)
- Hóa đơn điện tử (VAT invoice) tự động gửi email
- Khi hết hạn: workspace chuyển về Free tier, dữ liệu giữ nguyên 90 ngày
- Cảnh báo email trước khi hết hạn: 7 ngày, 3 ngày, 1 ngày

#### 4.7.3 Quản lý subscription (Admin)
- Xem gói hiện tại, ngày gia hạn, lịch sử thanh toán
- **Xem AI credit còn lại trong tháng** (progress bar rõ ràng)
- Nâng cấp / hủy gói
- Download hóa đơn

---

## 5. Notification & Communication

### 5.1 Email Notifications
| Sự kiện | Người nhận |
|---|---|
| Workspace được tạo | Workspace Admin |
| Mời Supporter | Supporter mới |
| Survey/Vote mới được tạo | (Tùy cài đặt) |
| Có feedback mới cần duyệt | Admin/Supporter |
| Subscription sắp hết hạn | Admin |
| Thanh toán thành công | Admin |
| Có người submit survey (notification digest) | Admin (tổng hợp theo giờ) |
| **[AI] Báo cáo tháng tự động (Monthly Digest)** | Admin, C-Level |
| **[AI] Cảnh báo bất thường** (response rate giảm đột ngột, sentiment tiêu cực tăng) | Admin |
| **AI Credit sắp hết** (còn < 20%) | Admin |

### 5.2 In-app Notifications
- Bell icon trên header với badge đếm
- Realtime notification qua WebSocket
- Đánh dấu đã đọc / đọc tất cả

---

## 6. AI Intelligence – Trung tâm Giá trị Sản phẩm (Claude API)

> **Triết lý thiết kế AI**: AI tham gia vào **4 giai đoạn** của vòng đời dữ liệu — không chỉ phân tích sau khi thu thập.
>
> `[Tạo nội dung] → [Thu thập] → [Kiểm soát chất lượng] → [Phân tích & Báo cáo]`

---

### 6.1 AI Survey Builder & Question Assistant *(Giai đoạn: Tạo nội dung)*

**Đây là tính năng giúp hạ thấp rào cản sử dụng — người không biết cách đặt câu hỏi vẫn tạo được survey chuyên nghiệp.**

#### 6.1.1 Tạo Survey từ prompt (AI Survey Generator)
- Admin nhập mô tả mục tiêu bằng ngôn ngữ tự nhiên:
  > *"Tôi muốn đo mức độ hài lòng của nhân viên sau đợt triển khai quy trình mới tháng 4, đặc biệt về khâu training và hỗ trợ kỹ thuật."*
- AI sinh ra toàn bộ survey: tiêu đề, mô tả, 8–12 câu hỏi đa dạng loại (NPS, rating, open-ended...), thứ tự logic
- Admin có thể chỉnh sửa, xóa bớt, thêm câu hỏi tùy ý trước khi publish
- **Output mẫu**: Survey "Đánh giá sau triển khai Q1" với 10 câu hỏi, bao gồm NPS, 3 câu Likert, 2 câu open-ended

#### 6.1.2 AI Question Quality Checker
- Khi Admin gõ câu hỏi, AI phân tích realtime và cảnh báo:
  - **Leading question**: *"Bạn có đồng ý rằng quy trình mới tốt hơn không?"* → Gợi ý: *"Bạn đánh giá quy trình mới như thế nào?"*
  - **Double-barreled**: *"Bạn có hài lòng với lương và phúc lợi không?"* → Gợi ý: Tách thành 2 câu riêng
  - **Quá mơ hồ**: *"Bạn cảm thấy thế nào?"* → Gợi ý thêm context cụ thể
- Không chặn — chỉ hiển thị warning nhỏ để Admin tự quyết định

#### 6.1.3 AI Template Library (gợi ý template theo ngữ cảnh)
- Khi Admin tạo survey mới, AI gợi ý template phù hợp dựa trên:
  - Ngành công ty (nếu đã khai báo)
  - Lịch sử survey đã tạo trước đó
  - Thời điểm trong năm (cuối năm → performance review, đầu năm → kế hoạch)
- Template được viết sẵn, Admin chỉ cần điều chỉnh cho phù hợp

---

### 6.2 AI Survey & Feedback Analysis *(Giai đoạn: Phân tích)*

#### 6.2.1 Tóm tắt tổng quan (Executive Summary)
- Sau khi survey đạt đủ phản hồi tối thiểu (≥ 10), AI tự động sinh paragraph tóm tắt bằng tiếng Việt
- Bao gồm: điểm nổi bật, xu hướng chính, con số đáng chú ý
- Ví dụ output:
  > *"72% nhân viên đánh giá tích cực về quy trình mới, cao nhất ở khâu training (4.3/5). Tuy nhiên, hỗ trợ kỹ thuật sau triển khai nhận điểm thấp nhất (2.8/5), với 34% phản hồi đề cập đến thời gian phản hồi chậm. Nhóm Engineering hài lòng hơn đáng kể so với nhóm Sales (3.9 vs 2.6)."*

#### 6.2.2 Sentiment Analysis (Phân tích cảm xúc)
- Phân loại câu trả lời text thành: Tích cực / Trung lập / Tiêu cực
- Biểu đồ sentiment theo từng câu hỏi open-ended
- Drill-down vào từng nhóm sentiment để xem câu trả lời cụ thể

#### 6.2.3 Key Themes Extraction (Trích xuất chủ đề)
- Tự động nhóm câu trả lời open-ended theo chủ đề nổi bật
- Mỗi chủ đề: tên chủ đề, số lượt đề cập, tỷ lệ %, các câu trả lời đại diện
- Không cần Admin tag thủ công
- Ví dụ: Từ 200 phản hồi, AI tìm ra 5 chủ đề: "Giao tiếp nội bộ", "Phúc lợi", "Cơ hội thăng tiến", "Workload", "Văn hóa công ty"

#### 6.2.4 Anomaly Detection (Phát hiện bất thường)
- Phát hiện phản hồi đánh giá cực đoan bất thường (outlier)
- Phát hiện straight-lining (trả lời máy móc, tất cả cùng điểm)
- Phát hiện tốc độ hoàn thành quá nhanh (dưới 30 giây cho survey 10 câu)
- Admin có thể chọn loại trừ các phản hồi kém chất lượng khỏi báo cáo

#### 6.2.5 Trend Analysis (So sánh xu hướng)
- So sánh kết quả giữa các đợt survey cùng chủ đề theo thời gian
- Biểu đồ xu hướng NPS / satisfaction score theo tháng/quý
- AI nhận xét tự động khi có biến động lớn: *"Điểm hài lòng giảm 0.6 điểm so với tháng trước — cần xem xét nguyên nhân"*

#### 6.2.6 Actionable Recommendations (Khuyến nghị hành động)
- AI đề xuất 3–5 hành động cụ thể dựa trên kết quả
- Ví dụ: *"67% nhân viên đánh giá thấp về giao tiếp giữa các phòng ban → Cân nhắc tổ chức all-hands meeting hàng tuần hoặc town-hall hàng tháng"*
- Mỗi khuyến nghị có link đến phần dữ liệu cụ thể làm căn cứ

#### 6.2.7 Cross-segment Comparison (So sánh nhóm)
- So sánh kết quả theo phòng ban, cấp bậc, thâm niên (nếu thu thập thông tin này)
- Biểu đồ heatmap so sánh trực quan
- AI tự động highlight nhóm có điểm cao nhất / thấp nhất kèm nhận xét

---

### 6.3 AI Post-Vote Instant Insight *(Giai đoạn: Phân tích tức thì)*

**Tính năng nhỏ nhưng tạo WOW moment trong meeting.**

- Ngay sau khi Vote session đóng, AI sinh 2–4 câu nhận xét tự động, hiển thị trên Presenter View
- Ví dụ output sau vote "Nên tổ chức event tháng 6 vào cuối tuần hay ngày thường?":
  > *"Đa số (68%) ủng hộ cuối tuần. Tỷ lệ này khá đồng đều giữa các phòng ban. Ý kiến phân hóa rõ nhất ở nhóm có con nhỏ — cân nhắc tổ chức ban ngày cuối tuần thay vì tối."*
  *(Lưu ý: câu cuối chỉ khả thi nếu có thêm câu hỏi phụ về hoàn cảnh)*
- Với Word Cloud vote: AI tóm tắt các từ khóa nổi bật thành 1–2 câu nhận xét
- Với Open-ended vote: AI nhóm các câu trả lời tương tự và highlight top themes

---

### 6.4 AI Content Moderation *(Giai đoạn: Thu thập & Kiểm soát chất lượng)*

**Tính năng này giải quyết nỗi đau thực tế của Admin: không thể đọc hết mọi góp ý.**

#### 6.4.1 Auto-moderation cho Feedback Board
- AI tự động scan mỗi góp ý khi submit và phân loại:
  - ✅ **An toàn**: Hiển thị ngay (hoặc đưa vào queue duyệt tùy cài đặt)
  - ⚠️ **Cần xem xét**: Nội dung nhạy cảm, có thể xúc phạm cá nhân — đưa vào queue ưu tiên
  - 🚫 **Từ chối tự động**: Spam rõ ràng, nội dung không liên quan, ngôn từ thù ghét
- Admin luôn có thể override quyết định của AI
- Hiển thị lý do AI đánh dấu để Admin đưa ra quyết định có thông tin

#### 6.4.2 Smart Queue Prioritization
- Trong queue duyệt, AI sắp xếp góp ý theo mức độ ưu tiên:
  - Góp ý được upvote nhiều + sentiment tiêu cực mạnh → ưu tiên cao
  - Góp ý tương tự nhau → nhóm lại để Admin duyệt 1 lần
- Admin tiết kiệm 60–80% thời gian kiểm duyệt

#### 6.4.3 Similar Feedback Grouping
- Tự động gom nhóm các góp ý có nội dung tương tự
- Admin duyệt/từ chối theo nhóm thay vì từng item
- Giúp tránh trùng lặp trên board hiển thị

---

### 6.5 AI Executive Report Generator *(Giai đoạn: Báo cáo)*

**Tính năng giải quyết bài toán: Admin có data nhưng không có thời gian/kỹ năng tạo báo cáo chuyên nghiệp cho ban lãnh đạo.**

#### 6.5.1 On-demand Report
- Admin chọn survey/khoảng thời gian → AI tạo báo cáo PDF/Word trong 30–60 giây
- Cấu trúc báo cáo tự động:
  1. Executive Summary (1 trang)
  2. Kết quả chi tiết theo từng câu hỏi (biểu đồ + nhận xét)
  3. Top insights & điểm đáng chú ý
  4. Khuyến nghị hành động ưu tiên
  5. Appendix: dữ liệu thô
- Tự động thêm logo công ty, màu thương hiệu (dùng brand color từ workspace settings)
- Ngôn ngữ: Tiếng Việt / English (Admin chọn)

#### 6.5.2 Automated Monthly Digest
- Vào cuối mỗi tháng, hệ thống tự động tổng hợp:
  - Tất cả surveys đã hoàn thành trong tháng
  - Tất cả feedback đã thu thập
  - Xu hướng so với tháng trước
- Email báo cáo gửi cho Admin và danh sách C-Level được cấu hình
- Format: PDF đính kèm + summary ngắn trong body email

---

### 6.6 AI Chat Assistant *(Dashboard — Enterprise)*

- Chat interface trên dashboard để Admin/C-Level đặt câu hỏi tự nhiên về dữ liệu
- Ví dụ câu hỏi:
  - *"Vòng khảo sát tháng 4 có những vấn đề gì nổi bật nhất?"*
  - *"So sánh mức độ hài lòng giữa phòng Engineering và Sales trong 3 tháng gần đây"*
  - *"Những nhân viên nào thường xuyên góp ý tiêu cực?"* (nếu không ẩn danh)
  - *"Tạo cho tôi slide deck tóm tắt kết quả quarter 1"*
- AI trả lời kèm biểu đồ trực quan nếu phù hợp
- Hỗ trợ follow-up questions, nhớ context trong conversation
- **Chỉ dành cho Enterprise** — vì tiêu thụ API cost cao nhất

---

### 6.7 Quy tắc thiết kế AI (AI Design Principles)

1. **AI là trợ lý, không phải người quyết định**: Mọi hành động AI (kiểm duyệt, gợi ý) đều có thể bị Admin override. Không có "black box" decisions.

2. **Transparent về giới hạn**: Khi không đủ dữ liệu (< 10 phản hồi), AI không đưa ra nhận xét — hiển thị thông báo rõ ràng thay vì kết quả không đáng tin.

3. **Privacy-first**: AI chỉ phân tích nội dung, không cố gắng de-anonymize người dùng ẩn danh. Với survey ẩn danh, AI không nhắc đến cá nhân trong output.

4. **Hiển thị "Powered by Claude AI"** nhỏ ở góc component AI — minh bạch với người dùng.

5. **Graceful degradation**: Nếu API Claude không phản hồi, hệ thống vẫn hoạt động bình thường — chỉ các tính năng AI bị tạm ẩn, không ảnh hưởng core flow.

---

### 6.8 AI Credit & Giới hạn

> **Lý do dùng Credit thay vì "lần gọi"**: Một phân tích survey với 500 phản hồi tốn nhiều token hơn một phân tích 20 phản hồi. Credit phản ánh đúng mức tiêu thụ thực tế hơn.

| Tính năng | Credit tiêu thụ |
|---|---|
| AI Survey Builder (tạo 1 survey) | 5 credits |
| Question Quality Check (per question) | 0.5 credits |
| Survey Analysis (per 100 responses) | 5 credits |
| Feedback Analysis (per 50 feedbacks) | 3 credits |
| Post-Vote Insight | 2 credits |
| Content Moderation (per feedback) | 0.2 credits |
| Executive Report (per report) | 15 credits |
| AI Chat (per message) | 2 credits |

| Gói | Credit/tháng | Rollover |
|---|---|---|
| Free | 0 | — |
| Pro | 500 credits | Không (reset mỗi tháng) |
| Enterprise | Unlimited | — |

*Admin xem credit còn lại trong dashboard. Khi hết credit, tính năng AI bị disabled đến tháng sau hoặc mua thêm credit add-on.*

---

## 7. UI/UX Requirements

### 7.1 Design Principles
- **Mobile-first**: Tất cả giao diện người dùng cuối phải hoạt động hoàn hảo trên màn hình 320px trở lên
- **Clean & Modern**: Phong cách tối giản, dùng nhiều whitespace, typography rõ ràng
- **Accessible**: Tuân theo WCAG 2.1 AA (contrast ratio, keyboard navigation, screen reader)
- **Fast**: Thời gian load trang < 2 giây, survey/vote < 1 giây
- **AI-forward**: Các tính năng AI được đặt ở vị trí nổi bật, không giấu trong menu — đây là điểm bán hàng chính

### 7.2 Giao diện người dùng cuối (End User)
- Landing page survey/vote: **không có navigation**, không distraction, chỉ có nội dung cần làm
- Progress indicator rõ ràng (Câu 3/10)
- Nút CTA lớn, dễ bấm trên mobile (tối thiểu 44px touch target)
- Auto-scroll mượt mà đến câu hỏi tiếp theo
- Lưu tạm thời (nếu người dùng thoát giữa chừng và quay lại)

### 7.3 Giao diện Admin / Supporter
- Sidebar navigation với icon + label
- Breadcrumb navigation
- Dark mode / Light mode toggle
- Dashboard với widgets kéo thả được
- **AI Insight Panel**: Sidebar hoặc floating panel hiển thị AI insights mới nhất
- Data table có sort, filter, pagination, search
- Bulk actions (chọn nhiều, xóa hàng loạt)
- Toast notifications (success/error/info)

### 7.4 Presenter View (Vote)
- Giao diện fullscreen tối màu cho chiếu màn hình lớn
- Chữ to, contrast cao, nhìn rõ từ xa
- Hiển thị QR code lớn để người tham gia quét
- Animation khi kết quả thay đổi
- Countdown timer hiển thị rõ
- **[AI] Instant insight box** hiển thị ngay sau khi vote đóng

### 7.5 Color & Typography (Gợi ý)
- Primary: `#6366F1` (Indigo)
- Success: `#22C55E` (Green)
- Warning: `#F59E0B` (Amber)
- Danger: `#EF4444` (Red)
- AI Accent: `#8B5CF6` (Violet — dùng riêng cho mọi UI element AI)
- Font: Inter (UI)
- Border radius: 8px (cards), 6px (buttons), 4px (inputs)

---

## 8. Technical Architecture

### 8.1 Tech Stack

#### Framework chính — Ruby on Rails (Monolith)

**Lý do chọn Rails monolith cho MVP**: Tốc độ phát triển nhanh, convention rõ ràng, không cần quản lý nhiều service riêng biệt. Sau này có thể tách API nếu cần mobile app hoặc frontend riêng.

---

**Core Framework:**
- **Ruby on Rails 7.2+** — full-stack framework chính
- **Ruby 3.3+**
- **PostgreSQL** — primary database
- **Redis** — cache, session store, pub/sub cho realtime

**Frontend (trong Rails):**
- **Hotwire (Turbo + Stimulus)** — reactivity và partial page update không cần viết nhiều JS
- **ActionCable** — WebSocket built-in của Rails, dùng cho Live Vote realtime
- **Tailwind CSS** — utility-first styling (tích hợp sẵn Rails 7 via `cssbundling-rails`)
- **Flowbite** hoặc **DaisyUI** — component library Tailwind, không cần React
- **Chartkick + Chart.js** — biểu đồ data visualization trong ERB views
- **SortableJS** (qua Stimulus) — drag & drop survey builder

**Authentication & Authorization:**
- **Devise** — đăng nhập, đăng ký, forgot password, 2FA (via `devise-two-factor`)
- **OmniAuth** — SSO Google + Microsoft (phase 2)
- **Pundit** — phân quyền theo role (SuperAdmin / Admin / Supporter)

**Background Jobs:**
- **Sidekiq** — background job processing (thay BullMQ), chạy trên Redis
- **sidekiq-cron** — scheduled jobs (monthly digest email, auto-close surveys)

**Email:**
- **Action Mailer** (built-in Rails) + **SendGrid** hoặc **Resend** — email delivery

**File Storage:**
- **ActiveStorage** — upload file (logo, ảnh feedback, attachments)
- **AWS S3** hoặc **Cloudflare R2** — cloud storage backend

**QR Code:**
- **rqrcode** gem — sinh QR code PNG/SVG

**PDF Export:**
- **Grover** (Chrome headless) hoặc **Prawn** — xuất báo cáo PDF
- **Axlsx** — xuất Excel

**AI Layer:**
- **faraday** hoặc `anthropic` gem — gọi Anthropic Claude API
- **claude-haiku** — moderation, post-vote insight, question checker (nhanh, rẻ)
- **claude-sonnet** — survey analysis, executive report generation (chất lượng cao)
- **Sidekiq** — xử lý AI jobs async (không block request)
- **Redis cache** — lưu kết quả AI analysis, tránh gọi lại cho cùng dataset

**Infrastructure:**
- **Docker + Docker Compose** — containerization
- **Nginx** — reverse proxy, subdomain routing (`{slug}.vox.vn`)
- **Railway** hoặc **Render** — deployment đơn giản cho MVP
- **AWS S3 / Cloudflare R2** — file storage

---

**Tóm tắt gems quan trọng:**

```ruby
# Gemfile (core)
gem 'devise'                  # authentication
gem 'devise-two-factor'       # 2FA TOTP
gem 'omniauth-google-oauth2'  # SSO Google
gem 'omniauth-microsoft-graph'# SSO Microsoft
gem 'pundit'                  # authorization

gem 'sidekiq'                 # background jobs
gem 'sidekiq-cron'            # scheduled jobs
gem 'redis'                   # cache + ActionCable

gem 'faraday'                 # HTTP client (Claude API)
gem 'rqrcode'                 # QR code generation
gem 'grover'                  # PDF export (headless Chrome)
gem 'axlsx_rails'             # Excel export
gem 'chartkick'               # charts in views
gem 'pagy'                    # pagination
gem 'image_processing'        # ActiveStorage image variants
```

---

### 8.2 Database Schema (Core Entities)

```
Workspace → has many Users, Surveys, Votes, FeedbackBoards, AIJobs
User → belongs to Workspace, has role enum (super_admin / admin / supporter)
Survey → has many Questions, Responses, AiAnalysisResults
  Question → has many Options; has question_type enum; has conditional_logic (jsonb)
  Response → belongs to Survey; has many Answers; has quality_score (float, AI)
  AiAnalysisResult → type, output (jsonb), credits_cost, created_at
Vote → has many VoteOptions, VoteResults; has AiInsight
FeedbackBoard → has many Feedbacks
  Feedback → moderation_status enum (pending/safe/flagged/rejected, AI)
             priority_score (float, AI); cluster_label (string, AI)
Subscription → belongs to Workspace; plan enum; credit_balance; credit_used
AiJob → belongs to Workspace; status enum (pending/running/done/failed)
        job_type; input_ref; output_ref (jsonb)
```

*Dùng **Row-level isolation** với `workspace_id` trên mọi bảng + PostgreSQL RLS — đảm bảo multi-tenancy strict, không bao giờ leak dữ liệu giữa các workspace.*

---

### 8.3 AI Processing Architecture (Async via Sidekiq)

```
Admin trigger AI action (HTTP request)
        ↓
Controller validates credit balance
        ↓
AiJob record created (status: pending)
        ↓
Sidekiq worker picks up job
        ↓
Worker calls Claude API (haiku hoặc sonnet tùy job type)
        ↓
Result stored in DB + Redis cache
        ↓
ActionCable broadcasts đến Admin: "Phân tích AI hoàn tất ✓"
        ↓
credit_balance deducted trên Subscription
```

**Lý do async**: Tránh HTTP timeout cho request lớn (survey 500 người). Admin không phải đợi — họ làm việc khác, nhận realtime notification khi xong.

---

### 8.4 Realtime Architecture (ActionCable)

```
Client (Turbo Stream) ←→ ActionCable Server ←→ Redis Pub/Sub
                                                      ↑
                                               Vote submissions / AI job done
```

ActionCable thay thế hoàn toàn Socket.io. Khi có vote mới hoặc AI job hoàn tất, server publish event qua Redis → broadcast Turbo Stream fragment đến tất cả client đang xem session đó → browser tự update DOM không cần reload.

---


## 9. Non-functional Requirements

| Category | Requirement |
|---|---|
| **Performance** | Trang load < 2s (P95), Vote realtime latency < 500ms, AI response < 30s (async) |
| **Availability** | Uptime 99.5% core features; AI features có thể degraded gracefully |
| **Scalability** | 1.000 concurrent users / vote session; AI jobs queue không block core app |
| **Security** | OWASP Top 10, HTTPS only, no PII trong logs, AI prompts không chứa PII |
| **Privacy** | Dữ liệu ẩn danh không thể truy nguyên; AI không được dùng dữ liệu 1 workspace để train/improve cho workspace khác |
| **Browser support** | Chrome, Firefox, Safari, Edge (2 phiên bản gần nhất), iOS Safari, Chrome Android |
| **Localization** | Tiếng Việt (mặc định), Tiếng Anh |
| **AI Reliability** | Retry logic khi Claude API lỗi; fallback message rõ ràng khi AI không khả dụng |
| **Multiple language** | Hổ trợ tiếng anh và tiếng việt cho cả admin side và user side |


---

