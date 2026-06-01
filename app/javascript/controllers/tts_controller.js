import { Controller } from "@hotwired/stimulus"

// ElevenLabs pricing per 1K characters (USD)
const MODEL_RATES = {
  "eleven_turbo_v2_5":    0.05,
  "eleven_multilingual_v2": 0.10,
  "eleven_multilingual_v3": 0.10,
  "eleven_monolingual_v1":  0.10,
}
const USD_TO_VND = 25000

export default class extends Controller {
  static targets = [
    "text", "charCount", "charBar", "costEstimate",
    "voiceSelect", "voicePreview", "previewPlayer",
    "modelSelect",
    "stability", "stabilityVal",
    "similarity", "similarityVal",
    "style", "styleVal",
    "generateBtn", "btnLabel", "spinner",
    "result", "player", "downloadLink",
    "error"
  ]

  connect() {
    this.loadVoices()
    this.countChars()
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
    const rate  = MODEL_RATES[model] ?? 0.10

    if (len === 0) {
      this.costEstimateTarget.textContent = "—"
      return
    }

    const usd = (len / 1000) * rate
    const vnd = Math.ceil(usd * USD_TO_VND)

    if (usd < 0.001) {
      this.costEstimateTarget.textContent = "< $0.001"
    } else {
      const usdStr = usd < 0.01 ? usd.toFixed(4) : usd.toFixed(3)
      this.costEstimateTarget.textContent = `~$${usdStr} (~${vnd.toLocaleString()}₫)`
    }
  }

  // ── Slider display ─────────────────────────────────────────────────
  updateSliders() {
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
        opt.textContent     = `${v.name} (${v.category})`
        opt.dataset.preview = v.preview_url || ""
        sel.appendChild(opt)
      })

      // Auto-select Rachel if present, else first
      const rachel = Array.from(sel.options).find(o => o.textContent.includes("Rachel"))
      if (rachel) sel.value = rachel.value
      this.voiceChanged()
    } catch (e) {
      this.voiceSelectTarget.innerHTML = `<option value="">⚠️ ${e.message}</option>`
    }
  }

  // ── Voice preview ─────────────────────────────────────────────────
  voiceChanged() {
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
    const text       = this.textTarget.value.trim()
    const voiceId    = this.voiceSelectTarget.value
    const model      = this.modelSelectTarget.value
    const stability  = this.stabilityTarget.value
    const similarity = this.similarityTarget.value
    const style      = this.styleTarget.value

    if (!text) {
      this.showError("Vui lòng nhập nội dung văn bản")
      return
    }

    this.setLoading(true)
    this.errorTarget.classList.add("hidden")
    this.resultTarget.classList.add("hidden")

    try {
      const formData = new FormData()
      formData.append("text",       text)
      formData.append("voice_id",   voiceId)
      formData.append("model",      model)
      formData.append("stability",  stability)
      formData.append("similarity", similarity)
      formData.append("style",      style)

      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const res = await fetch(this.generateUrl, {
        method:  "POST",
        headers: { "X-CSRF-Token": csrfToken, "Accept": "audio/mpeg, application/json" },
        body:    formData
      })

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: "Unknown error" }))
        throw new Error(err.error || `Server error ${res.status}`)
      }

      const blob = await res.blob()
      const url  = URL.createObjectURL(blob)

      this.playerTarget.src        = url
      this.downloadLinkTarget.href = url

      this.resultTarget.classList.remove("hidden")
      this.resultTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
    } catch (e) {
      this.showError(e.message)
    } finally {
      this.setLoading(false)
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────
  setLoading(loading) {
    this.generateBtnTarget.disabled = loading
    this.spinnerTarget.classList.toggle("hidden", !loading)
    this.btnLabelTarget.textContent = loading ? "Đang tạo..." : "🎙️ Tạo giọng nói"
  }

  showError(msg) {
    this.errorTarget.textContent = `⚠️ ${msg}`
    this.errorTarget.classList.remove("hidden")
  }

  get voicesUrl()   { return this.element.dataset.ttsVoicesUrl   || "/tts/voices" }
  get generateUrl() { return this.element.dataset.ttsGenerateUrl || "/tts/generate" }
}
