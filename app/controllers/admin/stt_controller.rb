class Admin::SttController < Admin::BaseController
  # ElevenLabs accepts up to 2 GB — we allow up to 2 GB locally.
  # NOTE: production nginx is set to 2G (client_max_body_size).
  MAX_FILE_SIZE = 2.gigabytes

  # yt-dlp binary — installed via `pip3 install yt-dlp` as python3 module
  YTDLP_CMD = "python3 -m yt_dlp"

  # Domains supported by yt-dlp (non-exhaustive, shown in UI)
  URL_SUPPORTED_DOMAINS = %w[youtube.com youtu.be vimeo.com tiktok.com facebook.com
                              instagram.com twitter.com x.com dailymotion.com soundcloud.com].freeze

  # Billing: 1 credit per minute of audio (ceiling, minimum 1)
  # ElevenLabs Scribe v2 costs ~$0.40/hr → ~$0.0067/min
  # Our 1 credit ≈ $0.025 (derived from TTS Flash rate 500 chars/$0.05)
  # → 1 credit covers ~3.75 min, we charge 1 credit/min (adds margin)
  SECONDS_PER_CREDIT = 60

  # Feature gate for AJAX endpoints (index handles its own gate in view)
  before_action :check_stt_feature, only: [:transcribe, :transcribe_url, :transcribe_chunk]

  def index
    @has_stt             = current_workspace&.active_subscription&.has_feature?(:stt)
    @remaining_credits   = current_workspace&.active_subscription&.credit_balance.to_i
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

    duration_secs = params[:duration_secs].to_f
    credits       = credits_for_duration(duration_secs, file.size)
    return unless require_credits!(credits)

    run_transcription(
      audio_io:  file.tempfile,
      filename:  file.original_filename,
      cleanup:   false,
      credits:   credits
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

    # Must have at least 1 credit before we even attempt the download
    return unless require_credits!(1)

    tmp_path = download_audio_from_url(url)
    file_size = File.size(tmp_path)
    credits   = credits_for_duration(0, file_size)  # estimate from file size
    # Charge extra if needed (already confirmed at least 1)
    if credits > 1
      sub = current_workspace.active_subscription
      if sub && !sub.enterprise? && sub.credit_balance < credits
        render json: {
          error:               "Không đủ AI credits (ước tính cần #{credits} credit cho file này).",
          insufficient_credits: true
        }, status: :payment_required
        FileUtils.rm_rf(File.dirname(tmp_path)) rescue nil
        return
      end
    end

    run_transcription(
      audio_io:  File.open(tmp_path, "rb"),
      filename:  File.basename(tmp_path),
      cleanup:   true,
      tmp_path:  tmp_path,
      credits:   credits
    )
  rescue => e
    Rails.logger.error "SttController#transcribe_url: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /stt/transcribe_chunk — realtime mic chunk (binary blob)
  # Each chunk is ~5 seconds → always 1 credit
  def transcribe_chunk
    blob = params[:chunk]

    unless blob.present?
      render json: { error: "Không có dữ liệu âm thanh" }, status: :unprocessable_entity
      return
    end

    return unless require_credits!(1)

    tmp = Tempfile.new(["stt_chunk", ".webm"])
    tmp.binmode
    tmp.write(blob.read)
    tmp.rewind

    run_transcription(
      audio_io:   tmp,
      filename:   "chunk.webm",
      timestamps: "none",
      diarize:    false,
      cleanup:    false,
      credits:    1
    )
  ensure
    tmp&.close
    tmp&.unlink
  end

  private

  # Shared transcription logic
  def run_transcription(audio_io:, filename:, cleanup: false, tmp_path: nil,
                        timestamps: nil, diarize: nil, credits: 1)
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

    # Deduct credits after successful transcription
    current_workspace.active_subscription&.deduct_credits!(credits)
    response.headers["X-Credits-Used"] = credits.to_s

    render json: result
  rescue ElevenLabsService::Error => e
    render json: { error: e.message, error_code: e.code }, status: :service_unavailable
  rescue => e
    Rails.logger.error "SttController#run_transcription: #{e.message}"
    render json: { error: "Lỗi không xác định. Vui lòng thử lại." }, status: :internal_server_error
  ensure
    if cleanup && tmp_path && File.exist?(tmp_path.to_s)
      FileUtils.rm_rf(File.dirname(tmp_path)) rescue nil
    end
  end

  # Download audio from any yt-dlp-supported URL → returns local tmp file path
  def download_audio_from_url(url)
    dir      = Dir.mktmpdir("stt_url_")
    out_tmpl = File.join(dir, "audio.%(ext)s")

    cmd = "#{YTDLP_CMD} --no-playlist --extract-audio --audio-format mp3 " \
          "--audio-quality 0 --max-filesize 2048m " \
          "--output #{Shellwords.escape(out_tmpl)} " \
          "#{Shellwords.escape(url)} 2>&1"

    Rails.logger.info "yt-dlp download: #{url}"
    output = `#{cmd}`
    Rails.logger.info "yt-dlp output: #{output.last(500)}"

    unless $?.success?
      friendly = extract_ytdlp_error(output)
      raise friendly
    end

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

  # Credit calculation: 1 credit per SECONDS_PER_CREDIT seconds (ceiling, min 1)
  # duration_secs: from JS (accurate) — preferred
  # file_size:     fallback estimate assuming ~128 kbps encoded audio
  def credits_for_duration(duration_secs, file_size = 0)
    if duration_secs > 0
      [(duration_secs / SECONDS_PER_CREDIT.to_f).ceil, 1].max
    else
      # Estimate: 128 kbps → 16_000 bytes/sec → file_size/16_000 seconds
      estimated_secs = [file_size.to_f / 16_000, 1.0].max
      [(estimated_secs / SECONDS_PER_CREDIT.to_f).ceil, 1].max
    end
  end

  def check_stt_feature
    unless current_workspace&.active_subscription&.has_feature?(:stt)
      render json: {
        error:            t("stt.upgrade_required"),
        upgrade_required: true
      }, status: :payment_required
    end
  end
end
