module ApplicationHelper

  def survey_status_class(status)
    {
      "draft"    => "bg-slate-100 text-slate-600",
      "active"   => "bg-emerald-50 text-emerald-700",
      "closed"   => "bg-amber-50 text-amber-700",
      "archived" => "bg-slate-100 text-slate-400"
    }[status.to_s] || "bg-slate-100 text-slate-600"
  end

  def question_type_label(type)
    {
      "single_choice"   => t("surveys.question_types.single_choice"),
      "multiple_choice" => t("surveys.question_types.multiple_choice"),
      "rating"          => t("surveys.question_types.rating"),
      "short_text"      => t("surveys.question_types.short_text"),
      "long_text"       => t("surveys.question_types.long_text"),
      "dropdown"        => t("surveys.question_types.dropdown"),
      "linear_scale"    => t("surveys.question_types.linear_scale"),
      "matrix"          => t("surveys.question_types.matrix"),
      "date_time"       => t("surveys.question_types.date_time"),
      "file_upload"     => t("surveys.question_types.file_upload"),
      "nps"             => t("surveys.question_types.nps")
    }[type.to_s] || type.to_s.humanize
  end

  def vote_status_badge(vote)
    classes = case vote.status
    when "active" then "bg-emerald-50 text-emerald-700"
    when "closed" then "bg-slate-100 text-slate-500"
    else "bg-amber-50 text-amber-700"
    end
    content_tag(:span, vote.status.capitalize, class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold #{classes}")
  end
end
