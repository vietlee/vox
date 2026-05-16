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
      "multiple_choice" => "Multiple Choice",
      "checkbox"        => "Checkbox",
      "rating"          => "Rating ⭐",
      "short_text"      => "Short Text",
      "long_text"       => "Long Text",
      "dropdown"        => "Dropdown",
      "linear_scale"    => "Linear Scale",
      "matrix"          => "Matrix",
      "date_time"       => "Date/Time",
      "file_upload"     => "File Upload",
      "nps"             => "NPS Score"
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
