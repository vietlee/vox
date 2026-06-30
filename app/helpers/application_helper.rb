module ApplicationHelper
  ALLOWED_CONTENT_TAGS  = %w[h1 h2 h3 h4 p br ul ol li strong em code pre blockquote table thead tbody tr th td a hr b i s u].freeze
  ALLOWED_CONTENT_ATTRS = %w[href class].freeze

  def render_markdown(text)
    return "" if text.blank?
    raw sanitize(MarkdownRenderer.render(text), tags: ALLOWED_CONTENT_TAGS, attributes: ALLOWED_CONTENT_ATTRS)
  end

  # Renders content stored as either Quill HTML or legacy Markdown
  def render_content(text)
    return "" if text.blank?
    if text.strip.start_with?('<')
      raw sanitize(text, tags: ALLOWED_CONTENT_TAGS, attributes: ALLOWED_CONTENT_ATTRS)
    else
      render_markdown(text)
    end
  end

  def short_url_for(full_url, workspace: nil)
    sl = ShortLink.for_url(full_url, workspace: workspace)
    short_link_url(sl.code)
  rescue => e
    Rails.logger.warn "short_url_for failed: #{e.message}"
    full_url
  end

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

  # Render sanitized rich-text HTML from Quill, stripping leading/trailing empty paragraphs.
  EMPTY_P = /\A(\s*<p[^>]*>\s*(<br\s*\/?>)?\s*<\/p>\s*)+/i
  EMPTY_P_TAIL = /(\s*<p[^>]*>\s*(<br\s*\/?>)?\s*<\/p>\s*)+\z/i
  VOTE_OPTION_TAGS  = %w[p b br ul ol li strong em i u span].freeze
  VOTE_OPTION_ATTRS = %w[style].freeze

  def render_vote_desc(html, sanitize_opts: {})
    return nil if html.blank?
    cleaned = html.gsub(EMPTY_P, '').gsub(EMPTY_P_TAIL, '').strip
    return nil if cleaned.blank?
    raw sanitize(cleaned,
                 tags:       sanitize_opts[:tags]       || VOTE_OPTION_TAGS,
                 attributes: sanitize_opts[:attributes] || VOTE_OPTION_ATTRS)
  end

  def vote_status_badge(vote)
    classes = case vote.status
    when "active" then "bg-emerald-50 text-emerald-700"
    when "closed" then "bg-slate-100 text-slate-500"
    else "bg-amber-50 text-amber-700"
    end
    content_tag(:span, I18n.t("status.#{vote.status}"), class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold #{classes}")
  end
end
