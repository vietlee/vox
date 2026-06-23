#!/usr/bin/env python3
"""
Generate a professional PPTX from slide JSON with theme-based coloring.
Usage: python3 generate_pptx.py <slides_json> <output_path> [theme]
Themes: green, blue, purple, red, teal, amber, slate
"""
import sys, json, math, io, tempfile, os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from PIL import Image, ImageDraw

# ── Dimensions (standard widescreen 16:9) ─────────────────────────────
SW = 9144000
SH = 5143500

def I(inches):
    return int(inches * 914400)

# ── Theme palettes ─────────────────────────────────────────────────────
THEMES = {
    "green": {
        "cover_bg":   (0x1B, 0x43, 0x32),
        "primary_dk": (0x1B, 0x43, 0x32),
        "primary":    (0x2D, 0x6A, 0x4F),
        "primary_lt": (0x74, 0xC6, 0x9D),
        "primary_xl": (0xD8, 0xF3, 0xDC),
        "accent2":    (0xE8, 0x60, 0x2C),
        "accent3":    (0x40, 0x91, 0x6C),
        "accent4":    (0x52, 0xB7, 0x88),
        "content_bg": (0xF0, 0xF7, 0xF2),
        "card_bg":    (0xFF, 0xFF, 0xFF),
        "title_color": (0xFF, 0xFF, 0xFF),
    },
    "blue": {
        "cover_bg":   (0x1E, 0x3A, 0x5F),
        "primary_dk": (0x1E, 0x3A, 0x5F),
        "primary":    (0x3B, 0x82, 0xF6),
        "primary_lt": (0x93, 0xC5, 0xFD),
        "primary_xl": (0xDB, 0xEA, 0xFE),
        "accent2":    (0xF5, 0x9E, 0x0B),
        "accent3":    (0x06, 0xB6, 0xD4),
        "accent4":    (0x60, 0xA5, 0xFA),
        "content_bg": (0xF0, 0xF4, 0xF8),
        "card_bg":    (0xFF, 0xFF, 0xFF),
        "title_color": (0xFF, 0xFF, 0xFF),
    },
    "purple": {
        "cover_bg":   (0x31, 0x30, 0x8C),
        "primary_dk": (0x31, 0x30, 0x8C),
        "primary":    (0x7C, 0x3A, 0xED),
        "primary_lt": (0xC4, 0xB5, 0xFD),
        "primary_xl": (0xED, 0xE9, 0xFE),
        "accent2":    (0xEC, 0x48, 0x99),
        "accent3":    (0x8B, 0x5C, 0xF6),
        "accent4":    (0xA7, 0x8B, 0xFA),
        "content_bg": (0xF5, 0xF3, 0xFF),
        "card_bg":    (0xFF, 0xFF, 0xFF),
        "title_color": (0xFF, 0xFF, 0xFF),
    },
    "red": {
        "cover_bg":   (0x7F, 0x1D, 0x1D),
        "primary_dk": (0x7F, 0x1D, 0x1D),
        "primary":    (0xDC, 0x26, 0x26),
        "primary_lt": (0xFC, 0xA5, 0xA5),
        "primary_xl": (0xFE, 0xE2, 0xE2),
        "accent2":    (0xF5, 0x9E, 0x0B),
        "accent3":    (0xEF, 0x44, 0x44),
        "accent4":    (0xF8, 0x71, 0x71),
        "content_bg": (0xFE, 0xF2, 0xF2),
        "card_bg":    (0xFF, 0xFF, 0xFF),
        "title_color": (0xFF, 0xFF, 0xFF),
    },
    "teal": {
        "cover_bg":   (0x13, 0x47, 0x4E),
        "primary_dk": (0x13, 0x47, 0x4E),
        "primary":    (0x0D, 0x94, 0x88),
        "primary_lt": (0x5E, 0xEA, 0xD4),
        "primary_xl": (0xCC, 0xFB, 0xF1),
        "accent2":    (0xF5, 0x9E, 0x0B),
        "accent3":    (0x14, 0xB8, 0xA6),
        "accent4":    (0x2D, 0xD4, 0xBF),
        "content_bg": (0xF0, 0xFD, 0xFA),
        "card_bg":    (0xFF, 0xFF, 0xFF),
        "title_color": (0xFF, 0xFF, 0xFF),
    },
    "amber": {
        "cover_bg":   (0x78, 0x35, 0x0F),
        "primary_dk": (0x78, 0x35, 0x0F),
        "primary":    (0xD9, 0x77, 0x06),
        "primary_lt": (0xFC, 0xD3, 0x4D),
        "primary_xl": (0xFE, 0xF3, 0xC7),
        "accent2":    (0xEF, 0x44, 0x44),
        "accent3":    (0xF5, 0x9E, 0x0B),
        "accent4":    (0xFB, 0xBF, 0x24),
        "content_bg": (0xFF, 0xFB, 0xEB),
        "card_bg":    (0xFF, 0xFF, 0xFF),
        "title_color": (0xFF, 0xFF, 0xFF),
    },
    "slate": {
        "cover_bg":   (0x1E, 0x29, 0x3B),
        "primary_dk": (0x1E, 0x29, 0x3B),
        "primary":    (0x47, 0x55, 0x69),
        "primary_lt": (0x94, 0xA3, 0xB8),
        "primary_xl": (0xE2, 0xE8, 0xF0),
        "accent2":    (0x3B, 0x82, 0xF6),
        "accent3":    (0x64, 0x74, 0x8B),
        "accent4":    (0x94, 0xA3, 0xB8),
        "content_bg": (0xF1, 0xF5, 0xF9),
        "card_bg":    (0xFF, 0xFF, 0xFF),
        "title_color": (0xFF, 0xFF, 0xFF),
    },
}

T = None
WHITE       = RGBColor(0xFF, 0xFF, 0xFF)
DARK        = RGBColor(0x1B, 0x2B, 0x22)
HEADING     = RGBColor(0x1B, 0x43, 0x32)
MID         = RGBColor(0x5B, 0x6B, 0x61)
LIGHT_TEXT  = RGBColor(0x94, 0xA3, 0xB8)
CARD_BORDER = RGBColor(0xE2, 0xE8, 0xF0)

# Margins matching cowork: 0.60" left/right
LM = I(0.60)
RM = I(0.60)
CW = SW - LM - RM  # content width

def _rgb(tup):
    return RGBColor(tup[0], tup[1], tup[2])

def _resolve_theme(name):
    raw = THEMES.get(name, THEMES["blue"])
    return {k: _rgb(v) if isinstance(v, tuple) else v for k, v in raw.items()}

def _accents():
    return [T["primary_dk"], T["primary"], T["accent2"], T["accent3"], T["primary_lt"], T["accent4"]]

def _accent_lights():
    return [T["primary_xl"]] * 6


# ── Icon generation (PNG via Pillow) ───────────────────────────────────
_icon_cache = {}

def _make_icon_png(rgb_tuple, size=120):
    key = ("icon", rgb_tuple[0], rgb_tuple[1], rgb_tuple[2], size)
    if key in _icon_cache: return _icon_cache[key]
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    r, g, b = rgb_tuple
    draw.ellipse([0, 0, size-1, size-1], fill=(r, g, b, 255))
    m = size // 4
    draw.ellipse([m, m, size-m-1, size-m-1], fill=(255, 255, 255, 255))
    m2 = size * 3 // 8
    draw.ellipse([m2, m2, size-m2-1, size-m2-1], fill=(r, g, b, 255))
    buf = io.BytesIO(); img.save(buf, format="PNG"); buf.seek(0)
    _icon_cache[key] = buf.getvalue()
    return _icon_cache[key]

def _make_avatar_png(rgb_tuple, size=120):
    key = ("avatar", rgb_tuple[0], rgb_tuple[1], rgb_tuple[2], size)
    if key in _icon_cache: return _icon_cache[key]
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    r, g, b = rgb_tuple
    draw.ellipse([0, 0, size-1, size-1], fill=(r, g, b, 255))
    hx, hy = size // 2, size * 5 // 14
    hr = size // 7
    draw.ellipse([hx-hr, hy-hr, hx+hr, hy+hr], fill=(255, 255, 255, 255))
    sw, sh, sy = size // 3, size // 5, size * 9 // 14
    draw.ellipse([hx-sw, sy, hx+sw, sy+sh*2], fill=(255, 255, 255, 255))
    buf = io.BytesIO(); img.save(buf, format="PNG"); buf.seek(0)
    _icon_cache[key] = buf.getvalue()
    return _icon_cache[key]

def _add_icon(slide, left, top, size, rgb_color, avatar=False):
    s = str(rgb_color)
    rgb_tuple = (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))
    png = _make_avatar_png(rgb_tuple, 120) if avatar else _make_icon_png(rgb_tuple, 120)
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp.write(png); tmp.close()
    pic = slide.shapes.add_picture(tmp.name, left, top, size, size)
    os.unlink(tmp.name)
    return pic


# ── Shape helpers ──────────────────────────────────────────────────────

def _shape(slide, stype, l, t, w, h, fill=None, line=None):
    s = slide.shapes.add_shape(stype, l, t, w, h)
    if fill: s.fill.solid(); s.fill.fore_color.rgb = fill
    else: s.fill.background()
    if line: s.line.color.rgb = line; s.line.width = Pt(0.75)
    else: s.line.fill.background()
    return s

def _rect(slide, l, t, w, h, fill, line=None):
    return _shape(slide, MSO_SHAPE.RECTANGLE, l, t, w, h, fill, line)

def _rrect(slide, l, t, w, h, fill=None, line=None, radius=0.06):
    f = fill if fill else WHITE
    s = _shape(slide, MSO_SHAPE.ROUNDED_RECTANGLE, l, t, w, h, f, line)
    s.adjustments[0] = radius
    return s

def _oval(slide, cx, cy, r, fill):
    return _shape(slide, MSO_SHAPE.OVAL, cx - r, cy - r, r*2, r*2, fill)

def _tb(slide, text, l, t, w, h, sz=12, bold=False, color=None, align=PP_ALIGN.LEFT, font="Calibri"):
    if color is None: color = DARK
    s = _shape(slide, MSO_SHAPE.RECTANGLE, l, t, w, h)
    s.fill.background()
    tf = s.text_frame; tf.word_wrap = True
    tf.margin_left = Pt(2); tf.margin_right = Pt(2)
    tf.margin_top = Pt(1); tf.margin_bottom = Pt(1)
    p = tf.paragraphs[0]; p.alignment = align
    p.space_before = Pt(0); p.space_after = Pt(0)
    r = p.add_run(); r.text = text
    r.font.size = Pt(sz); r.font.bold = bold; r.font.color.rgb = color; r.font.name = font
    return s

def _bg(slide, color):
    f = slide.background.fill; f.solid(); f.fore_color.rgb = color


# ── Shared content slide layout (cowork style) ───────────────────────
# Category label (13pt accent) → Large title (26pt dark) → content

def _category_label(slide, text):
    _tb(slide, text, LM, I(0.42), CW, I(0.35),
        sz=13, bold=True, color=T["accent2"])

def _slide_title(slide, text, y=None):
    if y is None: y = I(0.78)
    _tb(slide, text, LM, y, CW, I(0.85),
        sz=26, bold=True, color=T["primary_dk"], font="Calibri")

def _footer_note(slide, text):
    _tb(slide, text, LM, SH - I(0.32), SW - LM * 2, I(0.30),
        sz=9, color=MID)

def _page_num(slide, num, total):
    _tb(slide, f"{num:02d} / {total:02d}",
        SW - I(1.0), SH - I(0.30), I(0.90), I(0.25),
        sz=9, color=MID, align=PP_ALIGN.RIGHT)

def _source_bar(slide, text):
    _rrect(slide, LM, SH - I(0.55), CW, I(0.45), T["primary_dk"], radius=0.04)
    _tb(slide, text, LM + I(0.15), SH - I(0.50), CW - I(0.30), I(0.35),
        sz=10, color=T["primary_xl"])

def _insight_bar(slide, text):
    _rrect(slide, LM, SH - I(0.68), CW, I(0.50), T["primary_dk"], radius=0.04)
    _tb(slide, text, LM + I(0.20), SH - I(0.63), CW - I(0.40), I(0.40),
        sz=12, color=WHITE)


# ── Style helper ──────────────────────────────────────────────────────

def _style(s, key, default=None):
    return s.get("style", {}).get(key, default)


# ── Content card (icon-left style, cowork) ────────────────────────────

def _content_card(slide, x, y, w, h, idx, title, desc=""):
    accents = _accents()
    ac = accents[idx % len(accents)]
    _rrect(slide, x, y, w, h, T["card_bg"], CARD_BORDER)
    icon_sz = I(0.50)
    icon_circle = I(0.62)
    _rrect(slide, x + I(0.12), y + I(0.12), icon_circle, icon_circle, ac, radius=0.15)
    _add_icon(slide, x + I(0.12) + (icon_circle - icon_sz) // 2,
              y + I(0.12) + (icon_circle - icon_sz) // 2, icon_sz, WHITE)
    tx = x + I(0.85)
    tw = w - I(1.0)
    if desc:
        _tb(slide, title, tx, y + I(0.10), tw, I(0.30), sz=13, bold=True, color=T["primary_dk"])
        _tb(slide, desc, tx, y + I(0.42), tw, h - I(0.50), sz=10, color=DARK)
    else:
        _tb(slide, title, tx, y + (h - I(0.30)) // 2, tw, I(0.30), sz=13, bold=True, color=T["primary_dk"])


# ═══════════════════════════════════════════════════════════════════════
# SLIDE BUILDERS
# ═══════════════════════════════════════════════════════════════════════

def _setup_content_slide(prs, s):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    is_dark = _style(s, "bg") == "dark"
    bg = T["cover_bg"] if is_dark else T["content_bg"]
    _bg(slide, bg)

    subtitle = s.get("subtitle", "")
    cat = _style(s, "category", "")

    if is_dark:
        if cat:
            _tb(slide, cat, LM, I(0.42), CW, I(0.35),
                sz=13, bold=True, color=T["primary_lt"])
        _tb(slide, s["title"], LM, I(0.78), CW, I(0.85),
            sz=28, bold=True, color=WHITE, font="Calibri")
    else:
        if cat:
            _category_label(slide, cat)
        _slide_title(slide, s["title"])

    top = I(1.70)

    if s.get("footer"):
        _footer_note(slide, s["footer"])
    return slide, top


def make_cover(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    is_dark = _style(s, "bg", "dark") == "dark"
    bg = T["cover_bg"] if is_dark else T["content_bg"]
    _bg(slide, bg)

    if _style(s, "decorations", True):
        _oval(slide, SW + I(1.2), I(-0.8), I(2.6), T["primary"])
        _oval(slide, SW + I(1.8), I(1.5), I(1.5), T["primary_lt"])
        _oval(slide, I(-0.3), SH - I(0.5), I(0.5), T["primary_lt"])

    logo_sz = I(0.90)
    _rrect(slide, I(0.70), I(0.65), logo_sz, logo_sz, T["primary_lt"], radius=0.15)
    _add_icon(slide, I(0.82), I(0.77), I(0.46) + I(0.20), T["primary_dk"])

    cat = _style(s, "category", "")
    if cat:
        _tb(slide, cat, I(0.70), I(1.75), I(2.0), I(0.35),
            sz=12, bold=True, color=T["accent2"])

    title_color = WHITE if is_dark else T["primary_dk"]
    title_y = I(2.05) if cat else I(1.75)
    _tb(slide, s["title"], I(0.65), title_y, I(8.50), I(1.30),
        sz=52, bold=True, color=title_color, font="Calibri")

    sub_color = T["primary_xl"] if is_dark else MID
    if s.get("subtitle"):
        _tb(slide, s["subtitle"], I(0.68), I(3.25), I(7.20), I(0.60),
            sz=18, color=sub_color)

    if s.get("bullets"):
        btext = "   ".join(s["bullets"][:3])
        _tb(slide, btext, I(0.90), I(4.55), I(6.0), I(0.40),
            sz=13, bold=True, color=WHITE if is_dark else T["primary_dk"])

    if s.get("footer"):
        _tb(slide, s["footer"], I(0.65), SH - I(0.42), I(7.0), I(0.30),
            sz=10, color=T["primary_lt"] if is_dark else MID)


def make_section(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["cover_bg"])
    if _style(s, "decorations", True):
        _oval(slide, SW // 2, I(0.8), I(2.8), T["primary"])
    _tb(slide, s["title"], I(0.5), I(1.3), SW - I(1.0), I(1.2),
        sz=30, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Calibri")
    if s.get("subtitle"):
        _tb(slide, s["subtitle"], I(0.8), I(2.9), SW - I(1.6), I(0.4),
            sz=12, color=T["primary_lt"], align=PP_ALIGN.CENTER)
    _page_num(slide, idx, total)


def make_bullets(prs, s, idx, total):
    slide, top = _setup_content_slide(prs, s)

    bullets = s.get("bullets", [])
    if not bullets: _page_num(slide, idx, total); return

    n = len(bullets)
    bot = SH - I(0.45)
    avail = bot - top
    card_gap = I(0.12)
    accents = _accents()

    if n >= 5:
        cols = 2
        col_w = (CW - I(0.20)) // 2
        rows = (n + 1) // 2
        card_h = min(I(0.80), (avail - card_gap * (rows - 1)) // rows)
        for i, b in enumerate(bullets[:10]):
            c = i % 2; r = i // 2
            x = LM + c * (col_w + I(0.20))
            y = top + r * (card_h + card_gap)
            if y + card_h > bot: break
            _content_card(slide, x, y, col_w, card_h, i, b)
    elif n <= 3:
        col_w = (CW - I(0.20) * (n - 1)) // n
        card_h = min(I(2.35), avail)
        for i, b in enumerate(bullets):
            ac = accents[i % len(accents)]
            x = LM + i * (col_w + I(0.20))
            _rrect(slide, x, top, col_w, card_h, T["card_bg"], CARD_BORDER)
            icon_circle = I(0.65)
            _rrect(slide, x + I(0.15), top + I(0.18), icon_circle, icon_circle, ac, radius=0.15)
            _add_icon(slide, x + I(0.15) + (icon_circle - I(0.33)) // 2,
                      top + I(0.18) + (icon_circle - I(0.33)) // 2, I(0.33), WHITE)
            _tb(slide, b, x + I(0.15), top + I(0.95), col_w - I(0.30), I(0.45),
                sz=13, bold=True, color=T["primary_dk"])
    else:
        card_h = min(I(0.80), (avail - card_gap * (n - 1)) // n)
        for i, b in enumerate(bullets):
            y = top + i * (card_h + card_gap)
            if y + card_h > bot: break
            _content_card(slide, LM, y, CW, card_h, i, b)
    _page_num(slide, idx, total)


def make_stats(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 4)
    accents = _accents()

    if n <= 2:
        gap = I(0.20)
        card_w = I(2.90)
        card_h = I(1.50)
        sx = LM
        for i, item in enumerate(items[:n]):
            ac = accents[i % len(accents)]
            x = sx
            cy = top_y + i * (card_h + I(0.15))
            _rrect(slide, x, cy, card_w, card_h, T["primary_dk"], radius=0.05)
            _rect(slide, x, cy, I(0.09), card_h, ac)
            _tb(slide, item.get("value", ""),
                x + I(0.30), cy + I(0.18), card_w - I(0.50), I(0.65),
                sz=34, bold=True, color=WHITE, font="Calibri")
            _tb(slide, item.get("label", ""),
                x + I(0.30), cy + I(0.85), card_w - I(0.50), I(0.55),
                sz=11, color=T["primary_xl"])
    else:
        gap = I(0.15)
        card_w = (CW - gap * (n - 1)) // n
        card_h = I(1.50)
        sx = LM
        cy = top_y
        for i, item in enumerate(items[:n]):
            ac = accents[i % len(accents)]
            x = sx + i * (card_w + gap)
            _rrect(slide, x, cy, card_w, card_h, T["primary_dk"], radius=0.05)
            _rect(slide, x, cy, I(0.09), card_h, ac)
            _tb(slide, item.get("value", ""),
                x + I(0.30), cy + I(0.18), card_w - I(0.50), I(0.65),
                sz=34, bold=True, color=WHITE, font="Calibri")
            _tb(slide, item.get("label", ""),
                x + I(0.30), cy + I(0.85), card_w - I(0.50), I(0.55),
                sz=11, color=T["primary_xl"])

    _page_num(slide, idx, total)


def make_chart(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 6)
    max_val = max(item.get("value", 1) for item in items[:n]) or 1
    accents = _accents()

    _rrect(slide, LM, top_y, CW, SH - top_y - I(0.50), T["card_bg"], CARD_BORDER)

    chart_h = I(2.4)
    chart_top = top_y + I(0.30)
    bar_w = I(0.85)
    gap = I(0.30)
    total_w = n * bar_w + (n - 1) * gap
    start_x = (SW - total_w) // 2

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        val = item.get("value", 0)
        pct = val / max_val if max_val else 0
        bar_h = max(int(chart_h * pct), I(0.12))
        x = start_x + i * (bar_w + gap)
        y_bar = chart_top + chart_h - bar_h

        _rrect(slide, x, y_bar, bar_w, bar_h, ac, radius=0.08)
        _tb(slide, str(val), x, y_bar - I(0.22), bar_w, I(0.2),
            sz=11, bold=True, color=ac, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("label", ""),
            x - I(0.08), chart_top + chart_h + I(0.08), bar_w + I(0.16), I(0.35),
            sz=9, color=MID, align=PP_ALIGN.CENTER)
    _page_num(slide, idx, total)


def make_two_col(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    headers = s.get("headers", ["", ""])
    col1, col2 = s.get("col1", []), s.get("col2", [])
    gap_x = I(0.20)
    gap_y = I(0.15)
    col_w = (CW - gap_x) // 2
    accents = _accents()

    all_items = []
    for i, item in enumerate(col1):
        all_items.append((0, i, item))
    for i, item in enumerate(col2):
        all_items.append((1, i, item))

    n1, n2 = len(col1), len(col2)
    card_h = I(1.55)

    for ci, (items, hdr) in enumerate(zip([col1, col2], headers)):
        for i, item in enumerate(items[:3]):
            ac = accents[(ci * 3 + i) % len(accents)]
            x = LM + ci * (col_w + gap_x)
            y = top_y + i * (card_h + gap_y)
            if y + card_h > SH - I(0.45): break

            _rrect(slide, x, y, col_w, card_h, T["card_bg"], CARD_BORDER)
            icon_circle = I(0.60)
            _rrect(slide, x + I(0.15), y + I(0.15), icon_circle, icon_circle, ac, radius=0.15)
            _add_icon(slide, x + I(0.15) + (icon_circle - I(0.30)) // 2,
                      y + I(0.15) + (icon_circle - I(0.30)) // 2, I(0.30), WHITE)
            _tb(slide, item, x + I(0.90), y + I(0.12), col_w - I(1.05), I(0.40),
                sz=13, bold=True, color=T["primary_dk"])

    _page_num(slide, idx, total)


def make_timeline(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 5)
    gap = I(0.12)
    step_w = (CW - gap * (n - 1)) // n
    sx = LM
    y = top_y
    card_h = I(2.50)
    accents = _accents()

    _rect(slide, sx, y + I(0.50), CW, Pt(2), T["primary_xl"])

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = sx + i * (step_w + gap)
        _rrect(slide, x, y, step_w, card_h, T["card_bg"], CARD_BORDER)
        _rect(slide, x, y, step_w, I(0.04), ac)
        nsz = I(0.32)
        _oval(slide, x + step_w // 2, y + I(0.22) + nsz // 2, nsz // 2, ac)
        _tb(slide, str(i + 1), x + step_w // 2 - nsz // 2, y + I(0.22),
            nsz, nsz, sz=14, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("step", ""),
            x + I(0.08), y + I(0.58), step_w - I(0.16), I(0.35),
            sz=11, bold=True, color=ac, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("desc", ""),
            x + I(0.08), y + I(0.95), step_w - I(0.16), card_h - I(1.05),
            sz=9, color=DARK, align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


def make_pillars(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 4)
    gap = I(0.15)
    col_w = (CW - gap * (n - 1)) // n
    sx = LM
    y = top_y
    max_bullets = max((len(it.get("bullets", [])) for it in items[:n]), default=3)
    card_h = min(I(0.95) + min(max_bullets, 5) * I(0.38) + I(0.10), I(3.0))
    accents = _accents()

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = sx + i * (col_w + gap)
        _rrect(slide, x, y, col_w, card_h, T["card_bg"], CARD_BORDER)
        _rect(slide, x, y, col_w, I(0.04), ac)
        icon_sz = I(0.50)
        icon_circle = I(0.60)
        _rrect(slide, x + (col_w - icon_circle) // 2, y + I(0.10), icon_circle, icon_circle, ac, radius=0.15)
        _add_icon(slide, x + (col_w - icon_sz) // 2, y + I(0.10) + (icon_circle - icon_sz) // 2, icon_sz, WHITE)
        _tb(slide, item.get("title", ""),
            x + I(0.08), y + I(0.75), col_w - I(0.16), I(0.28),
            sz=12, bold=True, color=T["primary_dk"], align=PP_ALIGN.CENTER)
        for bi, b in enumerate(item.get("bullets", [])[:5]):
            by = y + I(1.08) + bi * I(0.36)
            if by + I(0.30) > y + card_h - I(0.05): break
            _oval(slide, x + I(0.15), by + I(0.10), Pt(3), ac)
            _tb(slide, b, x + I(0.28), by, col_w - I(0.36), I(0.30), sz=9, color=DARK)
    _page_num(slide, idx, total)


def make_agenda(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    row_h = I(0.55)
    gap = I(0.08)
    accents = _accents()

    for i, item in enumerate(items[:8]):
        ac = accents[i % len(accents)]
        y = top_y + i * (row_h + gap)
        if y + row_h > SH - I(0.40): break

        _rrect(slide, LM, y, CW, row_h, T["card_bg"], CARD_BORDER)
        nsz = I(0.30)
        _oval(slide, LM + I(0.20) + nsz // 2, y + row_h // 2, nsz // 2, ac)
        _tb(slide, item.get("num", str(i + 1)),
            LM + I(0.20), y + (row_h - I(0.22)) // 2, nsz, I(0.22),
            sz=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("title", ""), LM + I(0.60), y + I(0.06), I(3.5), I(0.24),
            sz=12, bold=True, color=T["primary_dk"])
        _tb(slide, item.get("desc", ""), LM + I(0.60), y + I(0.30), CW - I(0.80), I(0.22),
            sz=9, color=MID)
    _page_num(slide, idx, total)


def make_roles(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 3)
    gap = I(0.15)
    col_w = (CW - gap * (n - 1)) // n
    sx = LM
    y = top_y
    max_bullets = max((len(it.get("bullets", [])) for it in items[:n]), default=3)
    card_h = min(I(1.40) + min(max_bullets, 4) * I(0.36) + I(0.15), I(3.35))
    accents = _accents()

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = sx + i * (col_w + gap)
        _rrect(slide, x, y, col_w, card_h, T["card_bg"], CARD_BORDER)
        _rect(slide, x, y, col_w, I(0.06), ac)

        avatar_circle = I(0.85)
        _oval(slide, x + col_w // 2, y + I(0.15) + avatar_circle // 2, avatar_circle // 2, T["primary_dk"])
        _add_icon(slide, x + col_w // 2 - I(0.22), y + I(0.15) + avatar_circle // 2 - I(0.22), I(0.44), WHITE, avatar=True)

        name_y = y + I(0.15) + avatar_circle + I(0.10)
        _tb(slide, item.get("role", ""),
            x + I(0.08), name_y, col_w - I(0.16), I(0.30),
            sz=13, bold=True, color=T["primary_dk"], align=PP_ALIGN.CENTER)

        if item.get("type"):
            _tb(slide, item["type"],
                x + I(0.08), name_y + I(0.30), col_w - I(0.16), I(0.25),
                sz=10, bold=True, color=T["accent2"], align=PP_ALIGN.CENTER)

        sep_y = name_y + I(0.60)
        _rect(slide, x + I(0.20), sep_y, col_w - I(0.40), Pt(1), CARD_BORDER)

        for bi, b in enumerate(item.get("bullets", [])[:4]):
            by = sep_y + I(0.12) + bi * I(0.36)
            if by + I(0.28) > y + card_h - I(0.05): break
            _oval(slide, x + I(0.18), by + I(0.10), Pt(3), ac)
            _tb(slide, b, x + I(0.30), by, col_w - I(0.40), I(0.30), sz=9, color=DARK)

    _page_num(slide, idx, total)


def make_okr(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return
    accents = _accents()

    row_h = I(0.65)
    for i, item in enumerate(items[:5]):
        ac = accents[i % len(accents)]
        y = top_y + i * (row_h + I(0.08))
        if y + row_h > SH - I(0.40): break
        _rrect(slide, LM, y, CW, row_h, T["card_bg"], CARD_BORDER)
        _rect(slide, LM, y + I(0.06), Pt(4), row_h - I(0.12), ac)
        _tb(slide, item.get("objective", ""),
            LM + I(0.20), y + I(0.06), I(2.8), I(0.24), sz=11, bold=True, color=ac)
        for ki, kr in enumerate(item.get("krs", [])[:3]):
            kx = I(3.6) + ki * I(1.7)
            _tb(slide, f"✓ {kr}", kx, y + I(0.06), I(1.6), row_h - I(0.12), sz=9, color=MID)
    _page_num(slide, idx, total)


def make_principles(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)

    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    cols = 2
    gap_x, gap_y = I(0.15), I(0.10)
    col_w = (CW - gap_x) // 2
    card_h = I(0.85)

    for i, item in enumerate(items[:6]):
        c = i % cols; r = i // cols
        x = LM + c * (col_w + gap_x)
        y = top_y + r * (card_h + gap_y)
        if y + card_h > SH - I(0.40): break
        _content_card(slide, x, y, col_w, card_h, i,
                      item.get("title", ""), item.get("desc", ""))
    _page_num(slide, idx, total)


def make_summary(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["cover_bg"])

    if _style(s, "decorations", True):
        _oval(slide, I(-0.9), I(1.3), I(2.5), T["primary"])
        _oval(slide, SW + I(0.5), I(-0.7), I(1.7), T["primary_lt"])

    logo_sz = I(0.90)
    _rrect(slide, SW // 2 - logo_sz // 2, I(0.55), logo_sz, logo_sz, T["primary_lt"], radius=0.15)
    _add_icon(slide, SW // 2 - I(0.33), I(0.77), I(0.46) + I(0.20), T["primary_dk"])

    _tb(slide, s["title"], I(0.80), I(1.70), SW - I(1.60), I(1.30),
        sz=28, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Calibri")

    if s.get("bullets"):
        cta_text = s["bullets"][0] if s["bullets"] else ""
        if cta_text:
            btn_w = I(5.10)
            _rrect(slide, SW // 2 - btn_w // 2, I(3.15), btn_w, I(0.70), T["accent2"], radius=0.08)
            _tb(slide, cta_text, SW // 2 - btn_w // 2, I(3.15), btn_w, I(0.70),
                sz=16, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

        contact_parts = s["bullets"][1:4]
        if contact_parts:
            contact_line = "   |   ".join(contact_parts)
            _tb(slide, contact_line, I(0.80), I(4.35), SW - I(1.60), I(0.40),
                sz=13, color=T["primary_xl"], align=PP_ALIGN.CENTER)

    if s.get("footer"):
        _tb(slide, s["footer"], I(0.80), I(4.85), SW - I(1.60), I(0.40),
            sz=12, color=T["primary_lt"], align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


# ═══════════════════════════════════════════════════════════════════════
LAYOUT_MAP = {
    "bullets": make_bullets, "stats": make_stats, "chart": make_chart,
    "two-col": make_two_col, "timeline": make_timeline, "pillars": make_pillars,
    "agenda": make_agenda, "roles": make_roles, "okr": make_okr,
    "principles": make_principles,
}

def _embed_images(slide, s, image_map):
    if not image_map or not s.get("bullets"):
        return
    new_bullets = []
    for b in s["bullets"]:
        text = b if isinstance(b, str) else (b.get("text", "") if isinstance(b, dict) else str(b))
        if text.strip().startswith("IMAGE:"):
            key = text.strip().split(":", 1)[1].strip()
            img_path = image_map.get(key)
            if img_path and os.path.exists(img_path):
                try:
                    pic = slide.shapes.add_picture(img_path, I(1), I(2), I(4), I(2.5))
                except Exception:
                    new_bullets.append(b)
            else:
                new_bullets.append(b)
        else:
            new_bullets.append(b)
    s["bullets"] = new_bullets


def generate(slides_json_str, output_path, theme_name="blue", image_paths=None):
    global T
    T = _resolve_theme(theme_name)

    # Update heading color to match theme
    global HEADING
    HEADING = T["primary_dk"]

    image_map = {}
    if image_paths:
        for i, p in enumerate(image_paths):
            image_map[f"image_{i+1}"] = p

    slides = json.loads(slides_json_str)
    total = len(slides)
    prs = Presentation()
    prs.slide_width = SW
    prs.slide_height = SH

    for i, s in enumerate(slides):
        idx = i + 1
        if image_map:
            _embed_images(None, s, {})
        layout = s.get("layout", "bullets")
        if i == 0:
            make_cover(prs, s, idx, total)
        elif i == total - 1:
            make_summary(prs, s, idx, total)
        elif layout in LAYOUT_MAP:
            LAYOUT_MAP[layout](prs, s, idx, total)
        else:
            make_bullets(prs, s, idx, total)
        if image_map:
            _embed_slide_images(prs.slides[-1], s, image_map)
        if s.get("note"):
            prs.slides[-1].notes_slide.notes_text_frame.text = s["note"]

    prs.save(output_path)
    print(f"OK:{output_path}")


def _embed_slide_images(slide, s, image_map):
    if not s.get("_images"):
        return
    for img_key in s["_images"]:
        img_path = image_map.get(img_key)
        if img_path and os.path.exists(img_path):
            try:
                slide.shapes.add_picture(img_path, I(5), I(1.5), I(3.5), I(3))
            except Exception:
                pass


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: generate_pptx.py <slides_json> <output_path> [theme] [--images path1,path2]", file=sys.stderr)
        sys.exit(1)
    theme = sys.argv[3] if len(sys.argv) > 3 else "blue"
    img_paths = None
    if "--images" in sys.argv:
        idx = sys.argv.index("--images")
        if idx + 1 < len(sys.argv):
            img_paths = [p for p in sys.argv[idx + 1].split(",") if p]
    generate(sys.argv[1], sys.argv[2], theme, img_paths)
