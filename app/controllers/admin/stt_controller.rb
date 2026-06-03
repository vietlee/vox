class Admin::SttController < Admin::BaseController
  # ElevenLabs accepts up to 2 GB — we allow up to 2 GB locally.
  # NOTE: production nginx is currently set to 50M (client_max_body_size).
  # Increase that value in config/nginx/vox.czin.net.conf before deploying large-file support.
  MAX_FILE_SIZE = 2.gigabytes

  # yt-dlp binary — installed via `pip3 install yt-dlp` as python3 module
  YTDLP_CMD = "python3 -m yt_dlp"

  # Domains supported by yt-dlp (non-exhaustive, shown in UI)
  URL_SUPPORTED_DOMAINS = %w[youtube.com youtu.be vimeo.com tiktok.com facebook.com
                              instagram.com twitter.com x.com dailymotion.com soundcloud.com].freeze

  def index
  end

  # POST /stt/transcribe — file upload
  def transcribe
    file = params[:audio_file]

    unless file.present?
      render json: { error: "Vui lòng chọn file audio/video" }, status: :unprocessable_entity
      return
    end

    if file.size > MAX_FILE_SIZE
      render json: { error: "File quá lớn (tối đa 2 GB)" }, status: :unprocessable_entity
      return
    end

    run_transcription(
      audio_io:  file.tempfile,
      filename:  file.original_filename,
      cleanup:   false
    )
  end

  # POST /stt/transcribe_url — download from URL then transcribe
  def transcribe_url
    url = params[:url].to_s.strip

    if url.blank?
      render json: { error: "Vui lòng nhập URL" }, status: :unprocessable_entity
      return
    end

    unless url.match?(/\Ahttps?:\/\//i)
      render json: { error: "URL không hợp lệ (phải bắt đầu bằng http/https)" }, status: :unprocessable_entity
      return
    end

    tmp_path = download_audio_from_url(url)
    run_transcription(
      audio_io:  File.open(tmp_path, "rb"),
      filename:  File.basename(tmp_path),
      cleanup:   true,
      tmp_path:  tmp_path
    )
  rescue => e
    Rails.logger.error "SttController#transcribe_url: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /stt/transcribe_chunk — realtime mic chunk (binary blob)
  def transcribe_chunk
    blob = params[:chunk]

    unless blob.present?
      render json: { error: "Không có dữ liệu âm thanh" }, status: :unprocessable_entity
      return
    end

    tmp = Tempfile.new(["stt_chunk", ".webm"])
    tmp.binmode
    tmp.write(blob.read)
    tmp.rewind

    run_transcription(
      audio_io:   tmp,
      filename:   "chunk.webm",
      timestamps: "none",
      diarize:    false,
      cleanup:    false
    )
  ensure
    tmp&.close
    tmp&.unlink
  end

  private

  # Shared transcription logic
  def run_transcription(audio_io:, filename:, cleanup: false, tmp_path: nil,
                        timestamps: nil, diarize: nil)
    model      = safe_model(params[:model])
    language   = params[:language_code].presence
    timestamps = timestamps || (%w[none word].include?(params[:timestamps]) ? params[:timestamps] : "none")
    diarize    = diarize.nil? ? params[:diarize] == "true" : diarize

    service = ElevenLabsService.new
    result  = service.speech_to_text(
      audio_io:      audio_io,
      filename:      filename,
      model:         model,
      language_code: language,
      timestamps:    timestamps,
      diarize:       diarize
    )

    render json: result
  rescue ElevenLabsService::Error => e
    render json: { error: e.message, error_code: e.code }, status: :service_unavailable
  rescue => e
    Rails.logger.error "SttController#run_transcription: #{e.message}"
    render json: { error: "Lỗi không xác định. Vui lòng thử lại." }, status: :internal_server_error
  ensure
    if cleanup && tmp_path && File.exist?(tmp_path.to_s)
      File.delete(tmp_path) rescue nil
    end
  end

  # Download audio from any yt-dlp-supported URL → returns local tmp file path
  def download_audio_from_url(url)
    dir      = Dir.mktmpdir("stt_url_")
    out_tmpl = File.join(dir, "audio.%(ext)s")

    # yt-dlp: extract audio only, best quality, max 3 hours to avoid runaway
    cmd = "#{YTDLP_CMD} --no-playlist --extract-audio --audio-format mp3 " \
          "--audio-quality 0 --max-filesize 2048m " \
          "--output #{Shellwords.escape(out_tmpl)} " \
          "#{Shellwords.escape(url)} 2>&1"

    Rails.logger.info "yt-dlp download: #{url}"
    output = `#{cmd}`
    Rails.logger.info "yt-dlp output: #{output.last(500)}"

    unless $?.success?
      # Extract a friendly error from yt-dlp output
      friendly = extract_ytdlp_error(output)
      raise friendly
    end

    # Find the downloaded file
    files = Dir.glob(File.join(dir, "*")).select { |f| File.file?(f) }
    raise "yt-dlp không tải được file âm thanh. Vui lòng kiểm tra URL." if files.empty?

    files.first
  end

  def extract_ytdlp_error(output)
    if output.include?("Sign in") || output.include?("login")
      "Video yêu cầu đăng nhập — không thể tải tự động."
    elsif output.include?("Private video") || output.include?("private")
      "Video này là private."
    elsif output.include?("not available") || output.include?("unavailable")
      "Video không khả dụng hoặc đã bị xóa."
    elsif output.include?("Unsupported URL")
      "URL không được hỗ trợ. yt-dlp không nhận diện được nguồn này."
    elsif output.include?("age") || output.include?("18+")
      "Video bị giới hạn độ tuổi — không thể tải tự động."
    else
      "Không thể tải audio từ URL này. Chi tiết: #{output.last(200)}"
    end
  end

  def safe_model(val)
    %w[scribe_v1 scribe_v2].include?(val.to_s) ? val.to_s : "scribe_v2"
  end
end
