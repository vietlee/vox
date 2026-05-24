# ────────────────────────────────────────────────────────────────
# Survey Template Seeds
# Run via: rails db:seed:survey_templates  OR  rails db:seed
# ────────────────────────────────────────────────────────────────

puts "\n── Seeding Survey Templates ────────────────────────────"

templates = [

  # ── SURVEYS ──────────────────────────────────────────────────

  {
    title:             "Khảo sát sự hài lòng nhân viên",
    description:       "Đo mức độ hài lòng, gắn kết và kỳ vọng của nhân viên. Giúp HR nắm bắt tâm tư để cải thiện môi trường làm việc.",
    category:          "hr",
    template_type:     "survey",
    icon:              "😊",
    color:             "#7C3AED",
    estimated_minutes: 5,
    position:          1,
    structure: {
      title:       "Khảo sát sự hài lòng nhân viên",
      description: "Ý kiến của bạn rất quan trọng để chúng tôi cải thiện môi trường làm việc.",
      questions: [
        { title: "Bạn hài lòng với công việc hiện tại như thế nào?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Bạn hài lòng với đội nhóm và đồng nghiệp của mình?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Mức độ bạn hài lòng với sự quản lý / hỗ trợ từ quản lý trực tiếp?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Bạn có thấy công việc của mình có ý nghĩa và tác động?", question_type: "single_choice", required: true, options: ["Rất có ý nghĩa", "Khá có ý nghĩa", "Bình thường", "Chưa thấy rõ"] },
        { title: "Điều gì bạn thích nhất khi làm việc ở đây?", question_type: "long_text", required: false },
        { title: "Điều gì cần cải thiện để bạn gắn bó hơn?", question_type: "long_text", required: false },
        { title: "Bạn có sẵn sàng giới thiệu công ty này cho bạn bè không? (0 = Không, 10 = Chắc chắn)", question_type: "nps", required: true },
      ]
    }
  },

  {
    title:             "Net Promoter Score (NPS)",
    description:       "Đo chỉ số trung thành của khách hàng. Chỉ 3 câu hỏi, đủ để biết ai là người ủng hộ và ai có nguy cơ rời bỏ.",
    category:          "customer",
    template_type:     "survey",
    icon:              "📊",
    color:             "#0EA5E9",
    estimated_minutes: 2,
    position:          2,
    structure: {
      title:       "Khảo sát NPS — Mức độ hài lòng khách hàng",
      description: "Chỉ mất 1 phút, phản hồi của bạn giúp chúng tôi cải thiện liên tục.",
      questions: [
        { title: "Bạn có khả năng giới thiệu chúng tôi cho bạn bè/đồng nghiệp ở mức nào? (0–10)", question_type: "nps", required: true },
        { title: "Điều gì khiến bạn chọn điểm đó? Hãy chia sẻ lý do chính.", question_type: "long_text", required: false },
        { title: "Có điều gì chúng tôi có thể làm tốt hơn không?", question_type: "long_text", required: false },
      ]
    }
  },

  {
    title:             "Khảo sát hài lòng khách hàng (CSAT)",
    description:       "Đánh giá toàn diện trải nghiệm của khách hàng sau khi mua hàng hoặc sử dụng dịch vụ.",
    category:          "customer",
    template_type:     "survey",
    icon:              "⭐",
    color:             "#F59E0B",
    estimated_minutes: 4,
    position:          3,
    structure: {
      title:       "Phản hồi trải nghiệm của bạn",
      description: "Giúp chúng tôi phục vụ bạn tốt hơn.",
      questions: [
        { title: "Bạn hài lòng với trải nghiệm tổng thể ở mức nào?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Chất lượng sản phẩm / dịch vụ đáp ứng kỳ vọng của bạn chưa?", question_type: "single_choice", required: true, options: ["Vượt kỳ vọng", "Đúng kỳ vọng", "Chưa đáp ứng", "Thất vọng"] },
        { title: "Tốc độ phục vụ / giao hàng của chúng tôi?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Thái độ của đội ngũ hỗ trợ?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Bạn có mua lại hoặc tiếp tục sử dụng không?", question_type: "single_choice", required: true, options: ["Chắc chắn có", "Có thể có", "Chưa chắc", "Không"] },
        { title: "Ý kiến / góp ý khác của bạn:", question_type: "long_text", required: false },
      ]
    }
  },

  {
    title:             "Đánh giá khóa học",
    description:       "Thu thập phản hồi từ học viên về nội dung, giảng viên và hiệu quả đào tạo. Cải thiện chất lượng cho khóa tiếp theo.",
    category:          "education",
    template_type:     "survey",
    icon:              "📚",
    color:             "#0891B2",
    estimated_minutes: 4,
    position:          4,
    structure: {
      title:       "Đánh giá khóa học",
      description: "Cảm ơn bạn đã tham gia! Hãy dành vài phút để đánh giá khóa học này.",
      questions: [
        { title: "Nội dung khóa học có đáp ứng mục tiêu học tập của bạn?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Giảng viên truyền đạt rõ ràng và dễ hiểu?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Độ khó của khóa học so với kỳ vọng của bạn?", question_type: "single_choice", required: true, options: ["Quá dễ", "Vừa sức", "Hơi khó", "Quá khó"] },
        { title: "Tài liệu học tập (slides, bài tập, video) có chất lượng tốt?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Bạn có sẵn sàng giới thiệu khóa học này cho người khác?", question_type: "single_choice", required: true, options: ["Chắc chắn có", "Có thể", "Không chắc", "Không"] },
        { title: "Điều bạn thích nhất trong khóa học:", question_type: "long_text", required: false },
        { title: "Đề xuất cải thiện cho khóa học:", question_type: "long_text", required: false },
      ]
    }
  },

  {
    title:             "Phản hồi sau sự kiện",
    description:       "Thu thập ý kiến người tham dự về nội dung, tổ chức và trải nghiệm tổng thể. Cơ sở để tổ chức sự kiện tốt hơn lần sau.",
    category:          "event",
    template_type:     "survey",
    icon:              "🎉",
    color:             "#EC4899",
    estimated_minutes: 4,
    position:          5,
    structure: {
      title:       "Phản hồi sự kiện",
      description: "Cảm ơn bạn đã tham gia! Chia sẻ cảm nhận để chúng tôi tổ chức sự kiện tốt hơn.",
      questions: [
        { title: "Trải nghiệm tổng thể của bạn tại sự kiện?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Chất lượng nội dung / chương trình?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Công tác tổ chức và hậu cần (địa điểm, thời gian, lịch trình)?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Bạn biết đến sự kiện qua kênh nào?", question_type: "multiple_choice", required: false, options: ["Mạng xã hội", "Email", "Bạn bè giới thiệu", "Website", "Khác"] },
        { title: "Điều ấn tượng nhất với bạn tại sự kiện?", question_type: "long_text", required: false },
        { title: "Bạn muốn chúng tôi cải thiện điều gì?", question_type: "long_text", required: false },
        { title: "Bạn có muốn tham dự sự kiện tiếp theo không?", question_type: "single_choice", required: true, options: ["Chắc chắn có", "Có thể", "Chưa biết", "Không"] },
      ]
    }
  },

  {
    title:             "Phỏng vấn thôi việc",
    description:       "Hiểu lý do nhân viên rời đi để cải thiện văn hóa và chính sách giữ chân nhân tài.",
    category:          "hr",
    template_type:     "survey",
    icon:              "💼",
    color:             "#6366F1",
    estimated_minutes: 5,
    position:          6,
    structure: {
      title:       "Phỏng vấn thôi việc",
      description: "Phản hồi của bạn hoàn toàn bảo mật và giúp chúng tôi cải thiện môi trường làm việc.",
      questions: [
        { title: "Lý do chính khiến bạn quyết định thôi việc?", question_type: "single_choice", required: true, options: ["Cơ hội phát triển tốt hơn", "Lương/phúc lợi", "Môi trường làm việc", "Lý do cá nhân", "Quản lý/sếp", "Khác"] },
        { title: "Trải nghiệm làm việc tại đây nhìn chung như thế nào?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Điều bạn trân trọng nhất khi làm việc ở đây?", question_type: "long_text", required: false },
        { title: "Điều gì có thể đã giữ bạn ở lại?", question_type: "long_text", required: false },
        { title: "Bạn có sẵn sàng quay lại công ty trong tương lai không?", question_type: "single_choice", required: true, options: ["Có, chắc chắn", "Có thể", "Khó", "Không"] },
        { title: "Bạn có giới thiệu công ty này cho người quen không?", question_type: "single_choice", required: true, options: ["Có", "Không", "Tùy vị trí"] },
        { title: "Lời nhắn cuối cho đội ngũ lãnh đạo:", question_type: "long_text", required: false },
      ]
    }
  },

  {
    title:             "Khảo sát trải nghiệm người dùng (UX)",
    description:       "Tìm hiểu cách người dùng thực sự cảm nhận sản phẩm của bạn. Dữ liệu để ưu tiên cải tiến chính xác hơn.",
    category:          "product",
    template_type:     "survey",
    icon:              "📱",
    color:             "#4F46E5",
    estimated_minutes: 4,
    position:          7,
    structure: {
      title:       "Khảo sát trải nghiệm sản phẩm",
      description: "Chỉ mất 3 phút. Phản hồi của bạn ảnh hưởng trực tiếp đến sản phẩm.",
      questions: [
        { title: "Mức độ dễ sử dụng của sản phẩm?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Bạn sử dụng sản phẩm với tần suất nào?", question_type: "single_choice", required: true, options: ["Hàng ngày", "Vài lần/tuần", "Vài lần/tháng", "Hiếm khi"] },
        { title: "Tính năng bạn dùng nhiều nhất?", question_type: "short_text", required: false },
        { title: "Tính năng nào còn gây khó chịu hoặc cần cải thiện?", question_type: "long_text", required: false },
        { title: "Bạn có gặp lỗi hay sự cố nào không?", question_type: "single_choice", required: true, options: ["Không có lỗi gì", "Lỗi nhỏ, không ảnh hưởng nhiều", "Có lỗi ảnh hưởng trải nghiệm", "Nhiều lỗi nghiêm trọng"] },
        { title: "Tính năng bạn muốn chúng tôi thêm vào nhất?", question_type: "long_text", required: false },
        { title: "Bạn có giới thiệu sản phẩm này không? (0–10)", question_type: "nps", required: true },
      ]
    }
  },

  {
    title:             "Nghiên cứu thị trường",
    description:       "Khám phá thói quen, nhu cầu và kỳ vọng của khách hàng mục tiêu trước khi ra mắt sản phẩm hoặc tính năng mới.",
    category:          "marketing",
    template_type:     "survey",
    icon:              "📈",
    color:             "#059669",
    estimated_minutes: 6,
    position:          8,
    structure: {
      title:       "Khảo sát nghiên cứu thị trường",
      description: "Giúp chúng tôi hiểu nhu cầu của bạn để phát triển sản phẩm phù hợp hơn.",
      questions: [
        { title: "Nhóm tuổi của bạn?", question_type: "single_choice", required: true, options: ["Dưới 22", "22–30", "31–40", "41–50", "Trên 50"] },
        { title: "Bạn biết đến chúng tôi qua kênh nào?", question_type: "multiple_choice", required: false, options: ["Google Search", "Mạng xã hội", "Bạn bè giới thiệu", "Quảng cáo", "Báo/Blog"] },
        { title: "Bạn đang sử dụng giải pháp nào hiện tại cho vấn đề này?", question_type: "short_text", required: false },
        { title: "Vấn đề lớn nhất bạn gặp phải hiện tại là gì?", question_type: "long_text", required: true },
        { title: "Bạn sẵn sàng trả bao nhiêu cho một giải pháp tốt?", question_type: "single_choice", required: false, options: ["Miễn phí là yêu cầu", "< 100.000 ₫/tháng", "100.000–300.000 ₫/tháng", "300.000–1.000.000 ₫/tháng", "> 1.000.000 ₫/tháng"] },
        { title: "Tính năng nào quan trọng nhất với bạn?", question_type: "multiple_choice", required: false, options: ["Dễ sử dụng", "Giá cả hợp lý", "Tích hợp với tool khác", "Hỗ trợ khách hàng tốt", "Bảo mật dữ liệu"] },
        { title: "Bạn có muốn tham gia thử nghiệm sản phẩm không?", question_type: "single_choice", required: false, options: ["Có, liên hệ tôi", "Không"] },
      ]
    }
  },

  {
    title:             "Đánh giá 360° nhân viên",
    description:       "Đánh giá toàn diện hiệu suất, kỹ năng và sự đóng góp của nhân viên từ nhiều góc nhìn: cấp trên, đồng nghiệp và bản thân.",
    category:          "hr",
    template_type:     "survey",
    icon:              "🔄",
    color:             "#8B5CF6",
    estimated_minutes: 7,
    position:          9,
    structure: {
      title:       "Đánh giá 360° nhân viên",
      description: "Phản hồi của bạn sẽ được bảo mật và chỉ dùng cho mục đích phát triển chuyên môn.",
      questions: [
        { title: "Nhân viên này hoàn thành tốt mục tiêu và cam kết công việc?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Khả năng làm việc nhóm và phối hợp với đồng nghiệp?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Kỹ năng giao tiếp và truyền đạt thông tin?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Mức độ chủ động giải quyết vấn đề?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Nhân viên này có những điểm mạnh nổi bật nào?", question_type: "long_text", required: false },
        { title: "Cần cải thiện kỹ năng hoặc thái độ nào?", question_type: "long_text", required: false },
        { title: "Nhân viên này phù hợp với vai trò lãnh đạo không?", question_type: "single_choice", required: false, options: ["Rất phù hợp", "Có tiềm năng cần đào tạo", "Chưa sẵn sàng", "Phù hợp hơn với vai trò chuyên môn"] },
      ]
    }
  },

  {
    title:             "Đánh giá giảng viên",
    description:       "Giúp học viên phản hồi về phương pháp giảng dạy, nội dung và sự tương tác của giảng viên.",
    category:          "education",
    template_type:     "survey",
    icon:              "🎓",
    color:             "#0284C7",
    estimated_minutes: 3,
    position:          10,
    structure: {
      title:       "Đánh giá giảng viên",
      description: "Phản hồi của bạn giúp giảng viên nâng cao chất lượng giảng dạy.",
      questions: [
        { title: "Giảng viên trình bày nội dung rõ ràng và có hệ thống?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Giảng viên khuyến khích học viên đặt câu hỏi và tham gia?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Mức độ phản hồi bài tập / câu hỏi của học viên kịp thời?", question_type: "rating", required: true, settings: { min: 1, max: 5 } },
        { title: "Điểm mạnh lớn nhất của giảng viên:", question_type: "long_text", required: false },
        { title: "Điều bạn muốn giảng viên cải thiện:", question_type: "long_text", required: false },
      ]
    }
  },

  # ── VOTES ─────────────────────────────────────────────────────

  {
    title:             "Chọn thời gian họp nhóm",
    description:       "Nhanh chóng tìm ra khung giờ phù hợp với tất cả thành viên. Không cần email qua lại.",
    category:          "general",
    template_type:     "vote",
    icon:              "🗓️",
    color:             "#6366F1",
    estimated_minutes: 1,
    position:          11,
    structure: {
      title:       "Chọn thời gian họp",
      description: "Bình chọn khung giờ phù hợp với bạn nhất.",
      vote_type:   "multiple_choice",
      options: ["Thứ 2 sáng (9–11h)", "Thứ 2 chiều (14–16h)", "Thứ 3 sáng (9–11h)", "Thứ 3 chiều (14–16h)", "Thứ 4 sáng (9–11h)", "Thứ 4 chiều (14–16h)", "Thứ 5 sáng (9–11h)", "Thứ 6 sáng (9–11h)"]
    }
  },

  {
    title:             "Bình chọn hoạt động team building",
    description:       "Để cả team cùng chọn hoạt động vui chơi gắn kết. Ai cũng hài lòng khi được bình chọn!",
    category:          "hr",
    template_type:     "vote",
    icon:              "🎮",
    color:             "#EC4899",
    estimated_minutes: 1,
    position:          12,
    structure: {
      title:       "Bình chọn hoạt động team building",
      description: "Hãy chọn hoạt động bạn muốn tham gia nhất!",
      vote_type:   "single_choice",
      options: ["Picnic ngoài trời", "Bowling", "Escape Room", "Karaoke", "Nấu ăn cùng nhau", "Chơi thể thao", "Board games / Game online"]
    }
  },

  {
    title:             "Ưu tiên tính năng mới",
    description:       "Để đội ngũ hoặc người dùng bình chọn tính năng nào nên được phát triển tiếp theo. Roadmap minh bạch hơn.",
    category:          "product",
    template_type:     "vote",
    icon:              "🚀",
    color:             "#4F46E5",
    estimated_minutes: 1,
    position:          13,
    structure: {
      title:       "Tính năng nào nên ưu tiên phát triển?",
      description: "Bình chọn tính năng bạn cần nhất trong roadmap tiếp theo.",
      vote_type:   "single_choice",
      options: ["Ứng dụng di động (iOS/Android)", "Dark mode", "Tích hợp API / Webhook", "Dashboard phân tích nâng cao", "Thông báo qua email tự động", "Xuất dữ liệu PDF / Excel", "Tích hợp Slack / Zalo"]
    }
  },

  {
    title:             "Chọn menu/địa điểm ăn trưa",
    description:       "Giải quyết câu hỏi kinh điển mỗi ngày: \"Hôm nay ăn gì?\" Nhanh, vui, dân chủ.",
    category:          "general",
    template_type:     "vote",
    icon:              "🍽️",
    color:             "#F59E0B",
    estimated_minutes: 1,
    position:          14,
    structure: {
      title:       "Hôm nay ăn gì?",
      description: "Bình chọn menu hoặc địa điểm ăn trưa của cả nhóm.",
      vote_type:   "single_choice",
      options: ["Cơm bình dân / văn phòng", "Bún / Phở / Hủ tiếu", "Pizza / Burger", "Cơm gà / Cơm tấm", "Buffet", "Đặt đồ ăn online (Grab/ShopeeFood)", "Mỗi người tự lo"]
    }
  },

  # ── FEEDBACK BOARDS ───────────────────────────────────────────

  {
    title:             "Góp ý tính năng sản phẩm",
    description:       "Tạo không gian để người dùng đề xuất tính năng mới, vote cho nhau và giúp bạn xây dựng roadmap dựa trên nhu cầu thực.",
    category:          "product",
    template_type:     "feedback",
    icon:              "💡",
    color:             "#4F46E5",
    estimated_minutes: 2,
    position:          15,
    structure: {
      title:       "Góp ý & đề xuất tính năng",
      description: "Bạn muốn chúng tôi thêm tính năng gì? Đề xuất ở đây và vote cho ý tưởng hay nhất!",
    }
  },

  {
    title:             "Phản hồi dịch vụ hỗ trợ khách hàng",
    description:       "Thu thập góp ý liên tục từ khách hàng về chất lượng support. Phát hiện vấn đề sớm và cải thiện kịp thời.",
    category:          "customer",
    template_type:     "feedback",
    icon:              "🤝",
    color:             "#0EA5E9",
    estimated_minutes: 2,
    position:          16,
    structure: {
      title:       "Phản hồi về dịch vụ hỗ trợ",
      description: "Hãy chia sẻ trải nghiệm của bạn với đội ngũ hỗ trợ. Mỗi góp ý giúp chúng tôi phục vụ bạn tốt hơn.",
    }
  },

  {
    title:             "Góp ý cải thiện nội dung khóa học",
    description:       "Bảng góp ý mở cho học viên đề xuất chủ đề mới, báo cáo nội dung cần cập nhật, và bình chọn cho ý tưởng hay.",
    category:          "education",
    template_type:     "feedback",
    icon:              "📖",
    color:             "#059669",
    estimated_minutes: 2,
    position:          17,
    structure: {
      title:       "Góp ý cải thiện chương trình học",
      description: "Đề xuất chủ đề mới, báo cáo nội dung cần cập nhật hoặc chia sẻ ý tưởng cải thiện.",
    }
  },
]

templates.each do |attrs|
  tpl = SurveyTemplate.find_or_initialize_by(title: attrs[:title], template_type: attrs[:template_type])
  tpl.assign_attributes(attrs)
  tpl.save!
  print "."
end

puts "\n  ✓ #{templates.size} templates seeded"
