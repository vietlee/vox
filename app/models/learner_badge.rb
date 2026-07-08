class LearnerBadge < ApplicationRecord
  belongs_to :learner

  BADGES = {
    "streak_3"        => { icon: "🔥", title: "3 ngày liên tiếp",     desc: "Duy trì streak 3 ngày liên tiếp" },
    "streak_7"        => { icon: "🌟", title: "Tuần học tập",          desc: "Duy trì streak 7 ngày liên tiếp" },
    "streak_30"       => { icon: "🏆", title: "Tháng học tập",         desc: "Duy trì streak 30 ngày liên tiếp" },
    "quiz_first"      => { icon: "📝", title: "Quiz đầu tiên",         desc: "Hoàn thành bài kiểm tra đầu tiên" },
    "quiz_10"         => { icon: "🎯", title: "Quiz Master",           desc: "Hoàn thành 10 bài kiểm tra" },
    "flashcard_first" => { icon: "🃏", title: "Thẻ đầu tiên",         desc: "Hoàn thành session flashcard đầu tiên" },
    "flashcard_100"   => { icon: "💎", title: "100 thẻ",              desc: "Đã ôn 100 thẻ flashcard" },
    "xp_500"          => { icon: "⚡", title: "500 XP",               desc: "Đạt 500 XP tích lũy" },
    "xp_1000"         => { icon: "🚀", title: "1000 XP",              desc: "Đạt 1000 XP tích lũy" },
    "plan_first"      => { icon: "🗺️", title: "Lập kế hoạch",        desc: "Tạo study plan đầu tiên" },
    "speaking_first"  => { icon: "🎤", title: "Luyện nói",            desc: "Tập nói với AI lần đầu" },
    "challenge_first" => { icon: "⚔️", title: "Thử thách đầu tiên",  desc: "Hoàn thành daily challenge lần đầu" },
    "challenge_7"     => { icon: "🗓️", title: "7 thử thách",         desc: "Hoàn thành 7 daily challenges" }
  }.freeze

  def self.award!(learner, key)
    return nil unless BADGES.key?(key.to_s)
    return nil if learner.learner_badges.exists?(key: key.to_s)
    create!(learner: learner, key: key.to_s, earned_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def info
    BADGES[key] || { icon: "🎖️", title: key, desc: "" }
  end
end
