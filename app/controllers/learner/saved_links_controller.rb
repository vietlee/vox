class Learner::SavedLinksController < Learner::BaseController
  before_action :set_link, only: [:show, :destroy, :update]

  def index
    @links = current_learner.learner_saved_links.order(:position, :created_at)
  end

  def show
  end

  def create
    @link = current_learner.learner_saved_links.build(link_params)
    @link.position = current_learner.learner_saved_links.maximum(:position).to_i + 1
    if @link.save
      render json: { success: true, link: link_json(@link) }
    else
      render json: { success: false, errors: @link.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @link.update(link_params)
      render json: { success: true }
    else
      render json: { success: false, errors: @link.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @link.destroy
    render json: { success: true }
  end

  def reorder
    ids = Array(params[:ids])
    ids.each_with_index do |id, index|
      current_learner.learner_saved_links.where(id: id).update_all(position: index)
    end
    render json: { success: true }
  end

  def detect
    url = params[:url].to_s.strip
    url = "https://#{url}" unless url.match?(/\Ahttps?:\/\//i)

    result = {
      title: nil, favicon: nil, description: nil, thumbnail: nil,
      link_type: LearnerSavedLink.infer_type(url)
    }

    begin
      uri = URI.parse(url)
      raise ArgumentError, 'invalid scheme' unless %w[http https].include?(uri.scheme)

      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = 'Mozilla/5.0 (compatible; VOXBot/1.0; +https://vox.edu.vn)'
      req['Accept'] = 'text/html,application/xhtml+xml'
      req['Accept-Language'] = 'vi,en-US;q=0.9,en;q=0.8'

      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == 'https',
                                 open_timeout: 6, read_timeout: 6) do |http|
        http.request(req)
      end

      if response.is_a?(Net::HTTPRedirection) && response['location']
        redirect_url = URI.join(url, response['location']).to_s
        uri2 = URI.parse(redirect_url)
        if %w[http https].include?(uri2.scheme)
          req2 = Net::HTTP::Get.new(uri2)
          req2['User-Agent'] = req['User-Agent']
          req2['Accept'] = req['Accept']
          response = Net::HTTP.start(uri2.host, uri2.port,
                                     use_ssl: uri2.scheme == 'https',
                                     open_timeout: 6, read_timeout: 6) { |h| h.request(req2) }
        end
      end

      if response.is_a?(Net::HTTPSuccess)
        html = response.body.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)

        og_title  = html[/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']{1,300})["']/im, 1] ||
                    html[/<meta[^>]+content=["']([^"']{1,300})["'][^>]+property=["']og:title["']/im, 1]
        title_tag = html[/<title[^>]*>([^<]{1,300})<\/title>/im, 1]
        result[:title] = (og_title || title_tag)&.strip&.gsub(/\s+/, ' ')&.first(200)

        og_image = html[/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/im, 1] ||
                   html[/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/im, 1]
        result[:thumbnail] = og_image&.strip&.first(500)

        og_desc = html[/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']{1,500})["']/im, 1] ||
                  html[/<meta[^>]+content=["']([^"']{1,500})["'][^>]+property=["']og:description["']/im, 1]
        result[:description] = og_desc&.strip&.first(300)

        fav = html[/<link[^>]+rel=["'][^"']*(?:shortcut )?icon[^"']*["'][^>]+href=["']([^"']+)["']/im, 1]
        result[:favicon] = if fav
          (URI.join(url, fav).to_s rescue fav)
        else
          "#{uri.scheme}://#{uri.host}/favicon.ico"
        end
      end
    rescue => _e
      # silent — return partial result
    end

    if result[:link_type] == 'youtube'
      vid = url.match(/(?:v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/)&.[](1)
      if vid
        begin
          oembed_uri = URI("https://www.youtube.com/oembed?url=#{URI.encode_www_form_component("https://www.youtube.com/watch?v=#{vid}")}&format=json")
          oembed_res = Net::HTTP.start(oembed_uri.host, oembed_uri.port, use_ssl: true, open_timeout: 4, read_timeout: 4) { |h| h.get(oembed_uri.request_uri) }
          if oembed_res.is_a?(Net::HTTPSuccess)
            oembed = JSON.parse(oembed_res.body)
            result[:title]     = oembed['title']
            result[:thumbnail] = oembed['thumbnail_url']
          end
        rescue => _e
          result[:thumbnail] ||= "https://img.youtube.com/vi/#{vid}/hqdefault.jpg"
        end
        result[:embed_url] = "https://www.youtube.com/embed/#{vid}"
      end
    end

    render json: result
  end

  private

  def set_link
    @link = current_learner.learner_saved_links.find(params[:id])
  end

  def link_params
    params.require(:saved_link).permit(:url, :title, :description, :thumbnail, :favicon, :category, :link_type)
  end

  def link_json(link)
    { id: link.id, url: link.url, title: link.title, description: link.description,
      thumbnail: link.thumbnail, favicon: link.favicon, category: link.category,
      link_type: link.link_type, position: link.position,
      embed_url: link.embed_url, embeddable: link.embeddable? }
  end
end
