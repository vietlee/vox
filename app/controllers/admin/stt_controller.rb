class Admin::SttController < Admin::BaseController
  # ElevenLabs accepts up to 2 GB — we allow up to 2 GB locally.
  # NOTE: production nginx is set to 2G (client_max_body_size).
  MAX_FILE_SIZE = 2.gigabytes

  # yt-dlp binary — installed via `pip3 install yt-dlp` as python3 module
  YTDLP_CMD = "python3 -m yt_dlp"

  # Optional cookies file to bypass YouTube bot detection (HTTP 429 / "Sign in" errors).
  # To set up: export cookies from a logged-in YouTube session using a browser extension
  # (e.g. "Get cookies.txt LOCALLY"), then upload to this path on the server:
  #   scp youtube_cookies.txt deploy@server:/var/www/vox/shared/youtube_cookies.txt
  YTDLP_COOKIES_FILE = Rails.root.join("..", "..", "shared", "youtube_cookies.txt").to_s

  # Domains supported by yt-dlp (non-exhaustive, shown in UI)
  URL_SUPPORTED_DOMAINS = %w[youtube.com youtu.be vimeo.com tiktok.com facebook.com
                              instagram.com twitter.com x.com dailymotion.com soundcloud.com].freeze

  # Billing: 1 credit per minute of audio (ceiling, minimum 1)
  # ElevenLabs Scribe v2 costs ~$0.40/hr → ~$0.0067/min
  # Our 1 credit ≈ $0.025 (derived from TTS Flash rate 500 chars/$0.05)
  # → 1 credit covers ~3.75 min, we charge 1 credit/min (adds margin)
  SECONDS_PER_CREDIT = 60

  # Summarize / Translate: 2 credits each (Claude Haiku, fast & cheap)
  POSTPROCESS_CREDITS = 2

  SUMMARY_LANGUAGES = {
    "vi" => "Vietnamese",   "en" => "English",
    "ja" => "Japanese",     "ko" => "Korean",
    "zh" => "Simplified Chinese", "fr" => "French",
    "de" => "German",       "es" => "Spanish",
    "th" => "Thai",         "id" => "Indonesian"
  }.freeze

  # Feature gate for AJAX endpoints (index handles its own gate in view)
  before_action :check_stt_feature, only: [:transcribe, :transcribe_url, :transcribe_chunk,
                                            :summarize, :translate, :history, :save_mic, :destroy_history]

  def index
    @has_stt             = current_workspace&.active_subscription&.has_feature?(:stt)
    @remaining_credits   = current_workspace&.active_subscription&.credit_balance.to_i
    @history_count       = @has_stt ? current_workspace.stt_transcripts.count : 0
  end

  # GET /stt/history — returns paginated transcripts as JSON
  HISTORY_PER_PAGE = 20

  def history
    page    = [params[:page].to_i, 1].max
    total   = current_workspace.stt_transcripts.count
    records = current_workspace.stt_transcripts.recent
                               .offset((page - 1) * HISTORY_PER_PAGE)
                               .limit(HISTORY_PER_PAGE)
    render json: {
      items:    records.map { |r|
        {
          id:              r.id,
          title:           r.display_title,
          full_title:      r.title,
          transcript_text: r.transcript_text,
          language_code:   r.language_code,
          duration_secs:   r.duration_secs.to_f,
          credits_used:    r.credits_used,
          source:          r.source,
          created_at:      r.created_at.strftime("%d/%m/%Y %H:%M")
        }
      },
      page:     page,
      per:      HISTORY_PER_PAGE,
      total:    total,
      has_more: (page * HISTORY_PER_PAGE) < total
    }
  end

  # DELETE /stt/history/:id
  def destroy_history
    record = current_workspace.stt_transcripts.find(params[:id])
    record.destroy
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Không tìm thấy" }, status: :not_found
  end

  # POST /stt/save_mic — save mic transcript after recording stops
  def save_mic
    text = params[:text].to_s.strip
    return render json: { ok: false } if text.blank?

    current_workspace.stt_transcripts.create!(
      title:           "Ghi âm #{Time.current.strftime('%d/%m/%Y %H:%M')}",
      transcript_text: text,
      language_code:   params[:language_code].presence,
      duration_secs:   params[:duration_secs].to_f,
      credits_used:    [params[:credits_used].to_i, 1].max,
      source:          "mic"
    )
    render json: { ok: true }
  rescue => e
    Rails.logger.warn "SttController#save_mic: #{e.message}"
    render json: { ok: false }
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
      credits:   credits,
      title:     file.original_filename,
      source:    "file"
    )
  end

  # POST /stt/transcribe_url — transcribe from a URL
  # Strategy:
  #   1. Pass the URL directly to ElevenLabs via `source_url` (supports YouTube, TikTok, etc.)
  #      — this avoids yt-dlp and YouTube bot-detection issues entirely.
  #   2. If ElevenLabs rejects the URL (invalid_data / server_error), fall back to yt-dlp
  #      download + upload (for generic audio/video file URLs that ElevenLabs won't fetch).
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

    # Must have at least 1 credit before attempting anything
    return unless require_credits!(1)

    model      = safe_model(params[:model])
    language   = params[:language_code].presence
    timestamps = %w[none word].include?(params[:timestamps]) ? params[:timestamps] : "none"
    diarize    = params[:diarize] == "true"

    service = ElevenLabsService.new

    begin
      # ── Primary path: ElevenLabs source_url (no download) ──────────────────
      # Always request word timestamps so we can calculate actual duration for
      # credit billing. The caller's requested granularity is applied below.
      result = service.speech_to_text_from_url(
        url:           url,
        model:         model,
        language_code: language,
        timestamps:    "word",   # needed to infer duration from last word end-time
        diarize:       diarize
      )

      # Strip words from the response if caller didn't request them
      result[:words] = [] if timestamps == "none"

      # Calculate actual credits from duration returned by ElevenLabs
      duration_secs = result[:duration_secs].to_f
      credits = credits_for_duration(duration_secs, 0)

      # If we need more than 1 credit, verify balance and deduct the remainder
      if credits > 1
        sub = current_workspace.active_subscription
        if sub && !sub.enterprise? && sub.credit_balance < credits
          render json: {
            error:               "Không đủ AI credits (cần #{credits} credit cho video này).",
            insufficient_credits: true
          }, status: :payment_required
          return
        end
      end

      current_workspace.active_subscription&.deduct_credits!(credits)
      response.headers["X-Credits-Used"] = credits.to_s

      # Save to history
      begin
        if result[:text].present?
          current_workspace.stt_transcripts.create!(
            title:           url.truncate(200),
            transcript_text: result[:text],
            language_code:   result[:language_code],
            duration_secs:   duration_secs,
            credits_used:    credits,
            source:          "url"
          )
        end
      rescue => e
        Rails.logger.warn "SttController: history save failed: #{e.message}"
      end

      render json: result

    rescue ElevenLabsService::Error => e
      # ── Fallback: yt-dlp download for non-video-platform URLs ──────────────
      # ElevenLabs may reject URLs that aren't from recognised video platforms
      # (e.g. direct .mp3 links from private CDNs). Fall back to local download.
      if e.code == :invalid_data || e.code == :server_error
        Rails.logger.warn "ElevenLabs source_url rejected (#{e.code}), falling back to yt-dlp: #{e.message}"
        transcribe_url_via_ytdlp(url)
      else
        render json: { error: e.message, error_code: e.code }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "SttController#transcribe_url: #{e.message}"
      render json: { error: e.message }, status: :unprocessable_entity
    end
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

  # POST /stt/summarize — summarize transcript using Claude Haiku
  def summarize
    text = params[:text].to_s.strip
    if text.blank?
      render json: { error: "Không có nội dung để tóm tắt" }, status: :unprocessable_entity
      return
    end
    return unless require_credits!(POSTPROCESS_CREDITS)

    lang_key  = params[:language].presence.then { |l| SUMMARY_LANGUAGES.key?(l) ? l : "vi" } || "vi"
    lang_name = SUMMARY_LANGUAGES[lang_key]

    result = ClaudeService.haiku.call(
      system_prompt: "You are a professional transcript summarizer. You ALWAYS write your response in the requested output language, regardless of the language of the input transcript. Never add a title or heading at the top — output the content directly.",
      user_prompt:   <<~PROMPT
        Summarize the following transcript. Your response MUST be written entirely in #{lang_name} — this is mandatory even if the transcript is in a different language.
        Rules:
        - Do NOT add any title, heading, or label at the start — begin directly with content
        - Start with 1-2 sentence overview paragraph
        - Then 4-6 bullet points covering key points (use "- " prefix)
        - Keep it concise (under 200 words total)
        - IMPORTANT: Write your entire response in #{lang_name} only

        Transcript:
        #{text.truncate(10_000)}
      PROMPT
    )

    current_workspace.active_subscription&.deduct_credits!(POSTPROCESS_CREDITS)
    response.headers["X-Credits-Used"] = POSTPROCESS_CREDITS.to_s
    render json: { result: result, type: "summary" }
  rescue => e
    Rails.logger.error "SttController#summarize: #{e.message}"
    render json: { error: "Tóm tắt thất bại. Vui lòng thử lại." }, status: :internal_server_error
  end

  # POST /stt/translate — translate transcript using Claude Haiku
  def translate
    text = params[:text].to_s.strip
    if text.blank?
      render json: { error: "Không có nội dung để dịch" }, status: :unprocessable_entity
      return
    end
    return unless require_credits!(POSTPROCESS_CREDITS)

    target_key  = params[:target_language].presence.then { |l| SUMMARY_LANGUAGES.key?(l) ? l : "en" } || "en"
    target_name = SUMMARY_LANGUAGES[target_key]

    result = ClaudeService.haiku.call(
      system_prompt: "You are a professional translator. You ALWAYS translate into the exact target language requested, regardless of the source language.",
      user_prompt:   <<~PROMPT
        Translate the following transcript into #{target_name}. Your entire response MUST be in #{target_name}.
        Rules:
        - Provide ONLY the translation — no explanations, no notes, no preamble
        - Preserve paragraph breaks and structure
        - Maintain the original tone (formal/informal)
        - IMPORTANT: Output exclusively in #{target_name}

        Transcript:
        #{text.truncate(10_000)}
      PROMPT
    )

    current_workspace.active_subscription&.deduct_credits!(POSTPROCESS_CREDITS)
    response.headers["X-Credits-Used"] = POSTPROCESS_CREDITS.to_s
    render json: { result: result, type: "translation" }
  rescue => e
    Rails.logger.error "SttController#translate: #{e.message}"
    render json: { error: "Dịch thất bại. Vui lòng thử lại." }, status: :internal_server_error
  end

  private

  # Fallback: download with yt-dlp then upload to ElevenLabs.
  # Called from transcribe_url when ElevenLabs rejects the source_url (e.g. generic CDN links).
  def transcribe_url_via_ytdlp(url)
    tmp_path  = download_audio_from_url(url)
    file_size = File.size(tmp_path)
    credits   = credits_for_duration(0, file_size)

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
      credits:   credits,
      title:     url.truncate(180),
      source:    "url"
    )
  rescue => e
    Rails.logger.error "SttController#transcribe_url_via_ytdlp: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Shared transcription logic
  def run_transcription(audio_io:, filename:, cleanup: false, tmp_path: nil,
                        timestamps: nil, diarize: nil, credits: 1,
                        title: nil, source: "file")
    model      = safe_model(params[:model])
    language   = params[:language_code].presence
    timestamps = timestamps || (%w[none word].include?(params[:timestamps]) ? params[:timestamps] : "none")
    diarize    = diarize.nil? ? params[:diarize] == "true" : diarize
    # Diarization requires word timestamps to build speaker segments in the UI
    timestamps = "word" if diarize && timestamps == "none"

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

    # Save to history (best-effort, never block the response)
    begin
      if result[:text].present? && source != "chunk"
        current_workspace.stt_transcripts.create!(
          title:           (title || filename.to_s).truncate(200),
          transcript_text: result[:text],
          language_code:   result[:language_code],
          duration_secs:   credits * SECONDS_PER_CREDIT.to_f,
          credits_used:    credits,
          source:          source
        )
      end
    rescue => e
      Rails.logger.warn "SttController: history save failed: #{e.message}"
    end

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

  # Maximum time allowed for yt-dlp to download + convert a remote video/audio.
  # Keeps a Puma thread from being blocked indefinitely.
  YTDLP_TIMEOUT_SECS = 300   # 5 minutes — generous for most videos, safe under Puma worker_timeout (720s)

  # Download audio from any yt-dlp-supported URL → returns local tmp file path
  def download_audio_from_url(url)
    dir      = Dir.mktmpdir("stt_url_")
    out_tmpl = File.join(dir, "audio.%(ext)s")

    # --socket-timeout 30  : abort if the remote server stops sending data for 30s
    # --retries 2          : retry transient network errors twice
    # --cookies            : use browser cookies to bypass YouTube bot detection (optional)
    cookies_flag = File.exist?(YTDLP_COOKIES_FILE) ? "--cookies #{Shellwords.escape(YTDLP_COOKIES_FILE)}" : ""
    cmd = "#{YTDLP_CMD} --no-playlist --extract-audio --audio-format mp3 " \
          "--audio-quality 0 --max-filesize 2048m " \
          "--socket-timeout 30 --retries 2 " \
          "#{cookies_flag} " \
          "--output #{Shellwords.escape(out_tmpl)} " \
          "#{Shellwords.escape(url)} 2>&1"

    Rails.logger.info "yt-dlp download: #{url}"

    output = nil
    begin
      Timeout.timeout(YTDLP_TIMEOUT_SECS) { output = `#{cmd}` }
    rescue Timeout::Error
      FileUtils.rm_rf(dir) rescue nil
      raise "Tải audio quá lâu (quá #{YTDLP_TIMEOUT_SECS / 60} phút). Vui lòng thử URL khác hoặc tải file thủ công."
    end

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
    if output.include?("429") || output.include?("Too Many Requests")
      "YouTube đang chặn server (rate limit / bot detection). " \
      "Vui lòng tải file audio/video về máy và upload trực tiếp qua tab 'File / URL'."
    elsif output.include?("Sign in") || output.include?("not a bot") || output.include?("login")
      "YouTube yêu cầu xác minh để tải video này. " \
      "Vui lòng tải file video về máy rồi upload trực tiếp — hoặc dùng tab 'File / URL' với file đã tải."
    elsif output.include?("Private video") || output.include?("private")
      "Video này là private, không thể tải tự động."
    elsif output.include?("not available") || output.include?("unavailable")
      "Video không khả dụng hoặc đã bị xóa."
    elsif output.include?("Unsupported URL")
      "URL không được hỗ trợ. Vui lòng tải file về máy và upload trực tiếp."
    elsif output.include?("age") || output.include?("18+")
      "Video bị giới hạn độ tuổi — không thể tải tự động."
    else
      "Không thể tải audio từ URL này. Vui lòng tải file về máy và upload trực tiếp."
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
