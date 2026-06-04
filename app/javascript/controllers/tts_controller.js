import { Controller } from "@hotwired/stimulus"

// VOX credit cost by model
const CHARS_PER_CREDIT = {
  "eleven_flash_v2_5":      500,
  "eleven_turbo_v2_5":      500,  // alias for Flash v2.5
  "eleven_turbo_v2":        500,
  "eleven_multilingual_v2": 250,
  "eleven_multilingual_v3": 250,
  "eleven_v3":              250,
  "eleven_monolingual_v1":  250,
}
const ttsCredits = (chars, model) => {
  const rate = CHARS_PER_CREDIT[model] ?? 250
  return Math.max(Math.ceil(chars / rate), 1)
}

export default class extends Controller {
  static targets = [
    "text", "charCount", "charBar", "costEstimate",
    "voiceSelect", "voicePreview", "previewPlayer",
    "modelSelect",
    "speed", "speedVal",
    "stability", "stabilityVal",
    "similarity", "similarityVal",
    "style", "styleVal",
    "outputFormat",
    "generateBtn", "btnLabel", "spinner",
    "result", "player", "downloadLink",
    "error",
    "creditWarning", "creditWarningText"
  ]

  connect() {
    this.loadVoices()
    this.restoreText()
    this.restoreSettings()
    this.countChars()
  }

  // ── localStorage persistence ──────────────────────────────────────
  restoreText() {
    const saved = localStorage.getItem("tts_text")
    if (saved) this.textTarget.value = saved
  }

  saveText() {
    localStorage.setItem("tts_text", this.textTarget.value)
  }

  restoreSettings() {
    const s = key => localStorage.getItem(`tts_${key}`)

    if (s("model"))        this.modelSelectTarget.value   = s("model")
    if (s("speed"))        this.speedTarget.value         = s("speed")
    if (s("stability"))    this.stabilityTarget.value     = s("stability")
    if (s("similarity"))   this.similarityTarget.value    = s("similarity")
    if (s("style"))        this.styleTarget.value         = s("style")
    if (s("outputFormat")) this.outputFormatTarget.value  = s("outputFormat")

    // Update displayed values after restoring
    this.updateSliders()
    this.updateCost()
  }

  saveSettings() {
    localStorage.setItem("tts_model",        this.modelSelectTarget.value)
    localStorage.setItem("tts_speed",        this.speedTarget.value)
    localStorage.setItem("tts_stability",    this.stabilityTarget.value)
    localStorage.setItem("tts_similarity",   this.similarityTarget.value)
    localStorage.setItem("tts_style",        this.styleTarget.value)
    localStorage.setItem("tts_outputFormat", this.outputFormatTarget.value)
  }

  // ── Char counter + cost estimate ──────────────────────────────────
  countChars() {
    const len = this.textTarget.value.length
    this.charCountTarget.textContent = len.toLocaleString()

    // Progress bar
    const pct = Math.min(len / 5000 * 100, 100)
    this.charBarTarget.style.width = pct + "%"
    this.charBarTarget.className = `h-full rounded-full transition-all ${
      pct > 90 ? "bg-red-400" : pct > 70 ? "bg-amber-400" : "bg-indigo-400"
    }`

    this.updateCost()
  }

  updateCost() {
    const len   = this.textTarget.value.length
    const model = this.modelSelectTarget.value

    if (len === 0) {
      this.costEstimateTarget.textContent = "—"
      this.costEstimateTarget.className = "font-semibold text-indigo-600"
      this._clearCreditWarning()
      return
    }

    const credits  = ttsCredits(len, model)
    const remaining = this.remainingCredits

    if (remaining !== null && credits > remaining) {
      this.costEstimateTarget.textContent = `${credits} credits`
      this.costEstimateTarget.className   = "font-semibold text-red-600"
      this._showCreditWarning(credits, remaining)
    } else {
      this.costEstimateTarget.textContent = `${credits} credit${credits > 1 ? "s" : ""}`
      this.costEstimateTarget.className   = "font-semibold text-indigo-600"
      this._clearCreditWarning()
    }
  }

  // ── Credit guard helpers ──────────────────────────────────────────
  get remainingCredits() {
    // Prefer live value updated by deductDisplayCredits
    if (typeof window.__currentCredits === "number") return window.__currentCredits
    // Fall back to server-rendered value on page load
    const v = parseInt(this.element.dataset.ttsRemainingCredits)
    return isNaN(v) ? null : v
  }

  _showCreditWarning(needed, remaining) {
    if (this.hasCreditWarningTarget) {
      this.creditWarningTextTarget.textContent =
        `Cần ${needed} credit nhưng bạn chỉ còn ${remaining} credit. Vui lòng nạp thêm hoặc rút ngắn văn bản.`
      this.creditWarningTarget.classList.remove("hidden")
      this.creditWarningTarget.classList.add("flex")
    }
    this.generateBtnTarget.disabled = true
    this.generateBtnTarget.classList.add("opacity-50", "cursor-not-allowed")
  }

  _clearCreditWarning() {
    if (this.hasCreditWarningTarget) {
      this.creditWarningTarget.classList.add("hidden")
      this.creditWarningTarget.classList.remove("flex")
    }
    // Only re-enable if not currently loading
    if (!this._loading) {
      this.generateBtnTarget.disabled = false
      this.generateBtnTarget.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }

  // ── Slider display ─────────────────────────────────────────────────
  updateSliders() {
    this.speedValTarget.textContent      = parseFloat(this.speedTarget.value).toFixed(2) + "x"
    this.stabilityValTarget.textContent  = parseFloat(this.stabilityTarget.value).toFixed(2)
    this.similarityValTarget.textContent = parseFloat(this.similarityTarget.value).toFixed(2)
    this.styleValTarget.textContent      = parseFloat(this.styleTarget.value).toFixed(2)
  }

  // ── Load voices ───────────────────────────────────────────────────
  async loadVoices() {
    try {
      const res  = await fetch(this.voicesUrl, { headers: { "Accept": "application/json" } })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || "Failed to load voices")

      const sel = this.voiceSelectTarget
      sel.innerHTML = ""

      data.forEach(v => {
        const opt           = document.createElement("option")
        opt.value           = v.id
        opt.textContent     = v.name.length > 32 ? v.name.substring(0, 32) + "…" : v.name
        opt.dataset.preview = v.preview_url || ""
        opt.title           = v.name   // full name on hover
        sel.appendChild(opt)
      })

      // Restore saved voice, or fall back to first available
      const savedVoice = localStorage.getItem("tts_voice")
      const savedOpt   = savedVoice && Array.from(sel.options).find(o => !o.disabled && o.value === savedVoice)
      if (savedOpt) {
        sel.value = savedVoice
      } else if (sel.options.length > 0) {
        sel.value = sel.options[0].value
      }
      this.voiceChanged()
    } catch (e) {
      this.voiceSelectTarget.innerHTML = `<option value="">⚠️ ${e.message}</option>`
    }
  }

  // ── Voice preview ─────────────────────────────────────────────────
  voiceChanged() {
    localStorage.setItem("tts_voice", this.voiceSelectTarget.value)
    const selected = this.voiceSelectTarget.selectedOptions[0]
    const preview  = selected?.dataset?.preview

    if (preview) {
      this.previewPlayerTarget.src = preview
      this.voicePreviewTarget.classList.remove("hidden")
    } else {
      this.voicePreviewTarget.classList.add("hidden")
    }
  }

  // ── Generate TTS ──────────────────────────────────────────────────
  async generate() {
    const text         = this.textTarget.value.trim()
    const voiceId      = this.voiceSelectTarget.value
    const model        = this.modelSelectTarget.value
    const speed        = this.speedTarget.value
    const stability    = this.stabilityTarget.value
    const similarity   = this.similarityTarget.value
    const style        = this.styleTarget.value
    const outputFormat = this.outputFormatTarget.value

    if (!text) {
      this.showError("Vui lòng nhập nội dung văn bản")
      return
    }

    // Guard: re-check credits before sending request
    const needed    = ttsCredits(text.length, model)
    const remaining = this.remainingCredits
    if (remaining !== null && needed > remaining) {
      this._showCreditWarning(needed, remaining)
      return
    }

    this.setLoading(true)
    this.errorTarget.classList.add("hidden")
    this.resultTarget.classList.add("hidden")

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const buildBody = () => {
      const fd = new FormData()
      fd.append("text",          text)
      fd.append("voice_id",      voiceId)
      fd.append("model",         model)
      fd.append("speed",         speed)
      fd.append("stability",     stability)
      fd.append("similarity",    similarity)
      fd.append("style",         style)
      fd.append("output_format", outputFormat)
      return fd
    }

    const MAX_CLIENT_RETRIES = 2
    const RETRY_DELAY_MS     = 3000

    let lastError = null
    for (let attempt = 0; attempt <= MAX_CLIENT_RETRIES; attempt++) {
      try {
        if (attempt > 0) {
          this.btnLabelTarget.textContent = `Đang thử lại (${attempt}/${MAX_CLIENT_RETRIES})…`
          await new Promise(r => setTimeout(r, RETRY_DELAY_MS))
        }

        const res = await fetch(this.generateUrl, {
          method:  "POST",
          headers: { "X-CSRF-Token": csrfToken, "Accept": "audio/mpeg, application/json" },
          body:    buildBody()
        })

        // Retryable server errors — try again (client-side)
        if ([500, 502, 503, 504].includes(res.status) && attempt < MAX_CLIENT_RETRIES) {
          const err = await res.json().catch(() => ({ error: `Lỗi máy chủ ${res.status}` }))
          lastError = { message: err.error || `Lỗi máy chủ ${res.status}`, code: err.error_code || "server_error" }
          continue
        }

        if (!res.ok) {
          const err = await res.json().catch(() => ({ error: "Unknown error" }))
          throw { message: err.error || `Server error ${res.status}`, code: err.error_code || "unknown" }
        }

        const creditsUsed = parseInt(res.headers.get("X-Credits-Used") || "0")
        const blob = await res.blob()
        const url  = URL.createObjectURL(blob)

        this.playerTarget.src        = url
        this.downloadLinkTarget.href = url

        this.resultTarget.classList.remove("hidden")
        this.resultTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })

        // Update sidebar credit display without page reload
        if (creditsUsed > 0 && typeof window.deductDisplayCredits === "function") {
          window.deductDisplayCredits(creditsUsed)
        }

        lastError = null
        break  // success — exit retry loop
      } catch (e) {
        lastError = typeof e === "object" && e !== null ? e : { message: String(e), code: "unknown" }
        // Non-retryable (4xx, network abort, etc.) — stop immediately
        break
      }
    }

    if (lastError) this.showError(lastError.message, lastError.code)
    this.setLoading(false)
  }

  // ── Helpers ───────────────────────────────────────────────────────
  setLoading(loading) {
    this._loading = loading
    this.generateBtnTarget.disabled = loading
    this.spinnerTarget.classList.toggle("hidden", !loading)
    this.btnLabelTarget.textContent = loading
      ? (this.element.dataset.ttsLabelGenerating || "...")
      : (this.element.dataset.ttsLabelGenerate   || "🎙️ Generate")
    // After finishing, re-run credit check so disabled state is accurate
    if (!loading) this.updateCost()
  }

  showError(msg, code = "unknown") {
    const icons = {
      auth_error:    "🔑",
      rate_limited:  "⏳",
      invalid_data:  "📋",
      server_error:  "🔥",
      network_error: "🌐",
      timeout:       "⏱️",
      unknown:       "⚠️"
    }
    const icon = icons[code] || "⚠️"
    this.errorTarget.innerHTML = `
      <span class="font-semibold">${icon} ${this.errorCodeLabel(code)}</span>
      <span class="block text-sm mt-0.5 opacity-80">${msg}</span>
    `
    this.errorTarget.classList.remove("hidden")
  }

  errorCodeLabel(code) {
    const labels = {
      auth_error:    "Lỗi xác thực",
      rate_limited:  "Quá giới hạn",
      invalid_data:  "Dữ liệu không hợp lệ",
      server_error:  "Lỗi máy chủ ElevenLabs",
      network_error: "Lỗi kết nối mạng",
      timeout:       "Hết thời gian chờ",
      unknown:       "Lỗi không xác định"
    }
    return labels[code] || "Lỗi"
  }

  get voicesUrl()   { return this.element.dataset.ttsVoicesUrl   || "/tts/voices" }
  get generateUrl() { return this.element.dataset.ttsGenerateUrl || "/tts/generate" }
}
