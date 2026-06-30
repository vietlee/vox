require 'redcarpet'

module MarkdownRenderer
  _renderer = Redcarpet::Render::HTML.new(
    hard_wrap: true, filter_html: false, no_images: false, no_links: false,
    safe_links_only: true, with_toc_data: false, prettify: false
  )
  PARSER = Redcarpet::Markdown.new(
    _renderer,
    autolink: true, tables: true, fenced_code_blocks: true,
    strikethrough: true, superscript: true, underline: false
  )

  def self.render(text)
    PARSER.render(text)
  end
end
