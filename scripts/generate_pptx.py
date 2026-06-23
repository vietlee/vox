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
# Each theme: cover_bg, primary_dk, primary, primary_lt, accent2, accent3, content_bg, card_bg
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
        "content_bg": (0xF8, 0xF6, 0xEF),
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

# Resolved at generate() time
T = None  # current theme dict with RGBColor values

WHITE       = RGBColor(0xFF, 0xFF, 0xFF)
DARK        = RGBColor(0x1E, 0x29, 0x3B)
MID         = RGBColor(0x47, 0x55, 0x69)
LIGHT_TEXT  = RGBColor(0x94, 0xA3, 0xB8)
CARD_BORDER = RGBColor(0xE2, 0xE8, 0xF0)

def _rgb(tup):
    return RGBColor(tup[0], tup[1], tup[2])

def _resolve_theme(name):
    raw = THEMES.get(name, THEMES["blue"])
    return {k: _rgb(v) if isinstance(v, tuple) else v for k, v in raw.items()}

# Accent colors derived from theme
def _accents():
    return [T["primary"], T["accent3"], T["accent2"], T["primary_lt"], T["accent4"]]

def _accent_lights():
    return [T["primary_xl"]] * 5


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

def _tb(slide, text, l, t, w, h, sz=12, bold=False, color=None, align=PP_ALIGN.LEFT, font="Segoe UI"):
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


# ── Shared components ──────────────────────────────────────────────────

def _header_bar(slide, title, subtitle=""):
    _rect(slide, 0, 0, SW, I(0.74), T["primary_dk"])
    _tb(slide, title, I(0.4), I(0.1), I(7), I(0.35),
        sz=16, bold=True, color=WHITE, font="Segoe UI Semibold")
    if subtitle:
        _tb(slide, subtitle, I(0.4), I(0.42), I(8), I(0.28),
            sz=9, color=T["primary_lt"])

def _page_num(slide, num, total):
    _tb(slide, f"{num:02d} / {total:02d}",
        SW - I(0.8), SH - I(0.3), I(0.65), I(0.22),
        sz=8, bold=True, color=LIGHT_TEXT, align=PP_ALIGN.RIGHT)

def _source_bar(slide, text):
    _rrect(slide, I(0.4), SH - I(0.55), SW - I(0.8), I(0.4), T["primary_dk"], radius=0.04)
    _tb(slide, text, I(0.55), SH - I(0.5), SW - I(1.1), I(0.3),
        sz=8, color=WHITE)


# ── Content card ───────────────────────────────────────────────────────

def _content_card(slide, x, y, w, h, idx, title, desc=""):
    accents = _accents()
    ac = accents[idx % len(accents)]
    _rrect(slide, x, y, w, h, T["card_bg"], CARD_BORDER)
    # Icon
    icon_sz = I(0.38)
    _add_icon(slide, x + I(0.12), y + (h - icon_sz) // 2, icon_sz, ac)
    # Text
    tx = x + I(0.58)
    tw = w - I(0.7)
    if desc:
        _tb(slide, title, tx, y + I(0.06), tw, I(0.22), sz=11, bold=True, color=DARK)
        _tb(slide, desc, tx, y + I(0.28), tw, h - I(0.34), sz=9, color=MID)
    else:
        _tb(slide, title, tx, y + (h - I(0.25)) // 2, tw, I(0.25), sz=11, bold=True, color=DARK)


# ═══════════════════════════════════════════════════════════════════════
# SLIDE BUILDERS
# ═══════════════════════════════════════════════════════════════════════

def make_cover(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["cover_bg"])

    # Decorative circles
    _oval(slide, SW - I(1.5), I(0.3), I(2.2), T["primary"])
    _oval(slide, SW + I(0.3), I(1.5), I(1.5), T["primary_lt"])
    _oval(slide, I(-0.5), SH - I(0.8), I(0.8), T["primary_lt"])

    # Title
    _tb(slide, s["title"], I(0.7), I(1.0), I(7), I(1.3),
        sz=30, bold=True, color=WHITE, font="Segoe UI Black")

    # Decorative line
    _rect(slide, I(0.7), I(2.45), I(2.2), Pt(3), T["primary_lt"])

    # Subtitle
    if s.get("bullets"):
        sub = " · ".join(s["bullets"][:3])
        _tb(slide, sub, I(0.7), I(2.7), I(7), I(0.5), sz=11, color=T["primary_lt"])

    # Separator
    _rect(slide, 0, SH - I(0.5), SW, Pt(1), T["primary_lt"])


def make_section(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["cover_bg"])
    _oval(slide, SW // 2, I(1.0), I(2.5), T["primary"])
    _tb(slide, s["title"], I(0.5), I(1.5), SW - I(1.0), I(1.0),
        sz=26, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Segoe UI Black")
    _rect(slide, SW // 2 - I(1), I(2.7), I(2), Pt(3), T["primary_lt"])
    _page_num(slide, idx, total)


def make_bullets(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    bullets = s.get("bullets", [])
    if not bullets: return

    n = len(bullets)
    top = I(0.9)
    bot = SH - I(0.4)
    avail = bot - top

    if n >= 4:
        cols = 2
        col_w = (SW - I(1.0)) // 2
        card_h = min(avail // ((n + 1) // 2) - I(0.06), I(0.65))
        for i, b in enumerate(bullets[:10]):
            c = i % 2; r = i // 2
            x = I(0.35) + c * (col_w + I(0.15))
            y = top + r * (card_h + I(0.06))
            if y + card_h > bot: break
            _content_card(slide, x, y, col_w, card_h, i, b)
    else:
        card_h = min(avail // n - I(0.06), I(0.8))
        for i, b in enumerate(bullets):
            y = top + i * (card_h + I(0.06))
            if y + card_h > bot: break
            _content_card(slide, I(0.35), y, SW - I(0.7), card_h, i, b)
    _page_num(slide, idx, total)


def make_stats(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 4)
    gap = I(0.15)
    card_w = (SW - I(0.7) - gap * (n - 1)) // n
    sx = I(0.35)
    cy = I(0.9)
    card_h = SH - cy - I(0.65)
    accents = _accents()

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = sx + i * (card_w + gap)

        # Dark stat card (like co-work)
        _rrect(slide, x, cy, card_w, card_h, T["primary_dk"], radius=0.04)
        # Accent side bar
        _rect(slide, x + card_w - I(0.05), cy + I(0.1), I(0.05), card_h - I(0.2), ac)

        # Big value (white on dark)
        _tb(slide, item.get("value", ""),
            x + I(0.1), cy + I(0.25), card_w - I(0.2), I(0.55),
            sz=28, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Segoe UI Black")

        # Label (light on dark)
        _tb(slide, item.get("label", ""),
            x + I(0.1), cy + I(0.85), card_w - I(0.2), card_h - I(1.0),
            sz=9, color=T["primary_lt"], align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


def make_chart(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 6)
    max_val = max(item.get("value", 1) for item in items[:n]) or 1
    accents = _accents()

    # Chart card
    _rrect(slide, I(0.35), I(0.9), SW - I(0.7), SH - I(1.4), T["card_bg"], CARD_BORDER)

    chart_h = I(2.4)
    chart_top = I(1.2)
    bar_w = I(0.85)
    gap = I(0.3)
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
            sz=8, color=MID, align=PP_ALIGN.CENTER)
    _page_num(slide, idx, total)


def make_two_col(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    headers = s.get("headers", ["", ""])
    col1, col2 = s.get("col1", []), s.get("col2", [])
    gap = I(0.15)
    col_w = (SW - I(0.7) - gap) // 2
    accents = _accents()
    col_colors = [accents[0], accents[2]]  # primary vs accent2

    for ci, (items, ac) in enumerate(zip([col1, col2], col_colors)):
        sx = I(0.35) + ci * (col_w + gap)
        hdr_text = headers[ci] if ci < len(headers) else ""

        # Column header
        _rrect(slide, sx, I(0.9), col_w, I(0.32), ac, radius=0.08)
        _tb(slide, hdr_text, sx + I(0.1), I(0.92), col_w - I(0.2), I(0.25),
            sz=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

        for i, item in enumerate(items[:6]):
            y = I(1.32) + i * I(0.48)
            if y + I(0.42) > SH - I(0.4): break
            _rrect(slide, sx, y, col_w, I(0.42), T["card_bg"], CARD_BORDER)
            _add_icon(slide, sx + I(0.08), y + I(0.05), I(0.3), ac)
            _tb(slide, item, sx + I(0.45), y + I(0.06), col_w - I(0.55), I(0.3),
                sz=9, color=DARK)
    _page_num(slide, idx, total)


def make_timeline(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 5)
    gap = I(0.12)
    step_w = (SW - I(0.7) - gap * (n - 1)) // n
    sx = I(0.35)
    y = I(0.95)
    card_h = SH - y - I(0.6)
    accents = _accents()

    # Connector
    _rect(slide, sx, y + I(0.5), SW - I(0.7), Pt(2), T["primary_xl"])

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = sx + i * (step_w + gap)
        _rrect(slide, x, y, step_w, card_h, T["card_bg"], CARD_BORDER)
        _rect(slide, x, y, step_w, I(0.03), ac)
        # Number circle
        nsz = I(0.32)
        _oval(slide, x + step_w // 2, y + I(0.22) + nsz // 2, nsz // 2, ac)
        _tb(slide, str(i + 1), x + step_w // 2 - nsz // 2, y + I(0.22),
            nsz, nsz, sz=14, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("step", ""),
            x + I(0.06), y + I(0.58), step_w - I(0.12), I(0.3),
            sz=10, bold=True, color=ac, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("desc", ""),
            x + I(0.06), y + I(0.9), step_w - I(0.12), card_h - I(1.0),
            sz=8, color=MID, align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


def make_pillars(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 4)
    gap = I(0.12)
    col_w = (SW - I(0.7) - gap * (n - 1)) // n
    sx = I(0.35)
    y = I(0.9)
    card_h = SH - y - I(0.45)
    accents = _accents()

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = sx + i * (col_w + gap)
        _rrect(slide, x, y, col_w, card_h, T["card_bg"], CARD_BORDER)
        _rect(slide, x, y, col_w, I(0.03), ac)
        # Icon
        _add_icon(slide, x + (col_w - I(0.38)) // 2, y + I(0.1), I(0.38), ac)
        # Title
        _tb(slide, item.get("title", ""),
            x + I(0.06), y + I(0.55), col_w - I(0.12), I(0.28),
            sz=11, bold=True, color=ac, align=PP_ALIGN.CENTER)
        # Bullets
        for bi, b in enumerate(item.get("bullets", [])[:6]):
            by = y + I(0.9) + bi * I(0.4)
            if by + I(0.32) > y + card_h - I(0.05): break
            _oval(slide, x + I(0.15), by + I(0.08), Pt(3), ac)
            _tb(slide, b, x + I(0.28), by, col_w - I(0.35), I(0.32), sz=8, color=MID)
    _page_num(slide, idx, total)


def make_agenda(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return

    row_h = I(0.5)
    gap = I(0.05)
    accents = _accents()

    for i, item in enumerate(items[:8]):
        ac = accents[i % len(accents)]
        y = I(0.9) + i * (row_h + gap)
        if y + row_h > SH - I(0.35): break

        _rrect(slide, I(0.35), y, SW - I(0.7), row_h, T["card_bg"], CARD_BORDER)
        nsz = I(0.28)
        _oval(slide, I(0.58) + nsz // 2, y + row_h // 2, nsz // 2, ac)
        _tb(slide, item.get("num", str(i + 1)),
            I(0.58), y + (row_h - I(0.2)) // 2, nsz, I(0.2),
            sz=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("title", ""), I(0.98), y + I(0.04), I(3.5), I(0.2),
            sz=11, bold=True, color=DARK)
        _tb(slide, item.get("desc", ""), I(0.98), y + I(0.24), SW - I(1.5), I(0.2),
            sz=8, color=MID)
    _page_num(slide, idx, total)


def make_roles(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 3)
    gap = I(0.15)
    col_w = (SW - I(0.7) - gap * (n - 1)) // n
    sx = I(0.35)
    y = I(0.9)
    card_h = SH - y - I(0.45)
    accents = _accents()

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = sx + i * (col_w + gap)
        _rrect(slide, x, y, col_w, card_h, T["card_bg"], CARD_BORDER)
        _rect(slide, x, y, col_w, I(0.03), ac)
        # Avatar
        _add_icon(slide, x + (col_w - I(0.48)) // 2, y + I(0.1), I(0.48), ac, avatar=True)
        # Name
        _tb(slide, item.get("role", ""),
            x + I(0.05), y + I(0.65), col_w - I(0.1), I(0.22),
            sz=12, bold=True, color=ac, align=PP_ALIGN.CENTER)
        # Badge
        if item.get("type"):
            bw = min(col_w - I(0.3), I(1.8))
            _rrect(slide, x + (col_w - bw) // 2, y + I(0.9), bw, I(0.2), T["primary_xl"], radius=0.3)
            _tb(slide, item["type"],
                x + (col_w - bw) // 2, y + I(0.91), bw, I(0.18),
                sz=8, color=T["primary"], align=PP_ALIGN.CENTER)
        # Separator
        _rect(slide, x + I(0.15), y + I(1.15), col_w - I(0.3), Pt(1), CARD_BORDER)
        # Bullets
        for bi, b in enumerate(item.get("bullets", [])[:5]):
            by = y + I(1.25) + bi * I(0.38)
            if by + I(0.3) > y + card_h - I(0.05): break
            _oval(slide, x + I(0.15), by + I(0.08), Pt(3), ac)
            _tb(slide, b, x + I(0.28), by, col_w - I(0.35), I(0.3), sz=8, color=MID)

    _page_num(slide, idx, total)


def make_okr(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return
    accents = _accents()

    row_h = I(0.62)
    for i, item in enumerate(items[:5]):
        ac = accents[i % len(accents)]
        y = I(0.9) + i * (row_h + I(0.06))
        if y + row_h > SH - I(0.35): break
        _rrect(slide, I(0.35), y, SW - I(0.7), row_h, T["card_bg"], CARD_BORDER)
        _rect(slide, I(0.35), y + I(0.06), Pt(4), row_h - I(0.12), ac)
        _tb(slide, item.get("objective", ""),
            I(0.6), y + I(0.04), I(2.8), I(0.22), sz=10, bold=True, color=ac)
        for ki, kr in enumerate(item.get("krs", [])[:3]):
            kx = I(3.6) + ki * I(1.7)
            _tb(slide, f"✓ {kr}", kx, y + I(0.04), I(1.6), row_h - I(0.08), sz=8, color=MID)
    _page_num(slide, idx, total)


def make_principles(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["content_bg"])
    _header_bar(slide, s["title"])

    items = s.get("items", [])
    if not items: return

    cols = 2
    gap_x, gap_y = I(0.12), I(0.08)
    col_w = (SW - I(0.7) - gap_x) // 2
    card_h = I(0.68)

    for i, item in enumerate(items[:6]):
        c = i % cols; r = i // cols
        x = I(0.35) + c * (col_w + gap_x)
        y = I(0.9) + r * (card_h + gap_y)
        if y + card_h > SH - I(0.35): break
        _content_card(slide, x, y, col_w, card_h, i,
                      item.get("title", ""), item.get("desc", ""))
    _page_num(slide, idx, total)


def make_summary(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["cover_bg"])

    # Decorative
    _oval(slide, SW // 2, I(0.6), I(2.2), T["primary"])
    _oval(slide, I(0.3), SH - I(1.0), I(1.2), T["primary"])

    # Title
    _tb(slide, s["title"], I(0.5), I(0.6), SW - I(1.0), I(0.9),
        sz=22, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Segoe UI Black")
    _rect(slide, SW // 2 - I(0.8), I(1.55), I(1.6), Pt(3), T["primary_lt"])

    # Bullets on dark bg
    for i, b in enumerate(s.get("bullets", [])[:5]):
        y = I(1.8) + i * I(0.42)
        if y > SH - I(0.8): break
        _rrect(slide, I(0.8), y, SW - I(1.6), I(0.34), T["primary"], radius=0.04)
        _oval(slide, I(0.95), y + I(0.13), Pt(4), T["primary_lt"])
        _tb(slide, b, I(1.15), y + I(0.04), SW - I(2.1), I(0.26),
            sz=10, color=WHITE)

    _page_num(slide, idx, total)


# ═══════════════════════════════════════════════════════════════════════
LAYOUT_MAP = {
    "bullets": make_bullets, "stats": make_stats, "chart": make_chart,
    "two-col": make_two_col, "timeline": make_timeline, "pillars": make_pillars,
    "agenda": make_agenda, "roles": make_roles, "okr": make_okr,
    "principles": make_principles,
}

def generate(slides_json_str, output_path, theme_name="blue"):
    global T
    T = _resolve_theme(theme_name)

    slides = json.loads(slides_json_str)
    total = len(slides)
    prs = Presentation()
    prs.slide_width = SW
    prs.slide_height = SH

    for i, s in enumerate(slides):
        idx = i + 1
        layout = s.get("layout", "bullets")
        if i == 0:
            make_cover(prs, s, idx, total)
        elif i == total - 1:
            make_summary(prs, s, idx, total)
        elif layout in LAYOUT_MAP:
            LAYOUT_MAP[layout](prs, s, idx, total)
        else:
            make_bullets(prs, s, idx, total)
        if s.get("note"):
            prs.slides[-1].notes_slide.notes_text_frame.text = s["note"]

    prs.save(output_path)
    print(f"OK:{output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: generate_pptx.py <slides_json> <output_path> [theme]", file=sys.stderr)
        sys.exit(1)
    theme = sys.argv[3] if len(sys.argv) > 3 else "blue"
    generate(sys.argv[1], sys.argv[2], theme)
