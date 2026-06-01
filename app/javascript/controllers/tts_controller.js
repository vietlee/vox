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

    if (len === 0) {
      this.costEstimateTarget.textContent = "—"
      return
    }

    const credits = ttsCredits(len, model)
    this.costEstimateTarget.textContent = `${credits} credit${credits > 1 ? "s" : ""}`
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

      const isVietnamese = v =>
        /vietnamese|vietnam|việt|viet/i.test(v.name) || /vietnamese|vietnam/i.test(v.category)

      const sorted = [
        ...data.filter(v => isVietnamese(v)),
        ...data.filter(v => !isVietnamese(v))
      ]

      const viCount = sorted.filter(v => isVietnamese(v)).length
      sorted.forEach(v => {
        const opt           = document.createElement("option")
        opt.value           = v.id
        opt.textContent     = `${v.name} (${v.category})`
        opt.dataset.preview = v.preview_url || ""
        sel.appendChild(opt)
      })

      // Auto-select first Vietnamese voice, else Rachel, else first
      if (viCount > 0) {
        const sep = document.createElement("option")
        sep.disabled = true
        sep.textContent = this.element.dataset.ttsLabelOtherVoices || "── Other voices ──"
        sel.insertBefore(sep, sel.options[viCount])
      }

      const firstVi = Array.from(sel.options).find(o => !o.disabled && isVietnamese({ name: o.textContent }))
      const rachel  = Array.from(sel.options).find(o => o.textContent.includes("Rachel"))
      if (firstVi) sel.value = firstVi.value
      else if (rachel) sel.value = rachel.value
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

    this.setLoading(true)
    this.errorTarget.classList.add("hidden")
    this.resultTarget.classList.add("hidden")

    try {
      const formData = new FormData()
      formData.append("text",          text)
      formData.append("voice_id",      voiceId)
      formData.append("model",         model)
      formData.append("speed",         speed)
      formData.append("stability",     stability)
      formData.append("similarity",    similarity)
      formData.append("style",         style)
      formData.append("output_format", outputFormat)

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
    this.btnLabelTarget.textContent = loading
      ? (this.element.dataset.ttsLabelGenerating || "...")
      : (this.element.dataset.ttsLabelGenerate   || "🎙️ Generate")
  }

  showError(msg) {
    this.errorTarget.textContent = `⚠️ ${msg}`
    this.errorTarget.classList.remove("hidden")
  }

  get voicesUrl()   { return this.element.dataset.ttsVoicesUrl   || "/tts/voices" }
  get generateUrl() { return this.element.dataset.ttsGenerateUrl || "/tts/generate" }
}
