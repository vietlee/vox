#!/usr/bin/env python3
"""
Generate a professional PPTX from slide JSON.
Usage: python3 generate_pptx.py <slides_json> <output_path>
"""
import sys, json, math, io, tempfile, os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from PIL import Image, ImageDraw

# ── Dimensions (standard widescreen 16:9) ─────────────────────────────
SW = 9144000   # 10 inches
SH = 5143500   # ~5.63 inches

def I(inches):
    return int(inches * 914400)

# ── Colors ─────────────────────────────────────────────────────────────
C_PRIMARY    = RGBColor(0x4F, 0x46, 0xE5)
C_PRIMARY_DK = RGBColor(0x31, 0x30, 0x8C)
C_PRIMARY_LT = RGBColor(0xE8, 0xEB, 0xFF)
C_PRIMARY_XL = RGBColor(0xF0, 0xF0, 0xFF)
WHITE        = RGBColor(0xFF, 0xFF, 0xFF)
DARK         = RGBColor(0x1E, 0x29, 0x3B)
MID          = RGBColor(0x47, 0x55, 0x69)
LIGHT_TEXT   = RGBColor(0x94, 0xA3, 0xB8)
CARD_BORDER  = RGBColor(0xE2, 0xE8, 0xF0)
BG_GRAY      = RGBColor(0xF8, 0xFA, 0xFC)

ACCENTS = [
    RGBColor(0x4F, 0x46, 0xE5),  # indigo
    RGBColor(0x06, 0xB6, 0xD4),  # teal
    RGBColor(0x10, 0xB9, 0x81),  # green
    RGBColor(0xF5, 0x9E, 0x0B),  # amber
    RGBColor(0xEF, 0x44, 0x44),  # red
    RGBColor(0x8B, 0x5C, 0xF6),  # violet
    RGBColor(0x38, 0xBD, 0xF8),  # sky
]

ACCENT_LIGHT = [
    RGBColor(0xE8, 0xEB, 0xFF),
    RGBColor(0xE0, 0xF7, 0xFA),
    RGBColor(0xD1, 0xFA, 0xE5),
    RGBColor(0xFE, 0xF3, 0xC7),
    RGBColor(0xFE, 0xE2, 0xE2),
    RGBColor(0xED, 0xE9, 0xFE),
    RGBColor(0xE0, 0xF2, 0xFE),
]

# ── Icon generation (PNG via Pillow) ───────────────────────────────────
_icon_cache = {}

def _make_icon_png(accent_rgb, size=120):
    """Create a simple circular icon PNG with inner shape."""
    key = (accent_rgb[0], accent_rgb[1], accent_rgb[2], size)
    if key in _icon_cache:
        return _icon_cache[key]

    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    r, g, b = accent_rgb
    # Outer circle
    draw.ellipse([0, 0, size-1, size-1], fill=(r, g, b, 255))
    # Inner white circle
    m = size // 4
    draw.ellipse([m, m, size-m-1, size-m-1], fill=(255, 255, 255, 255))
    # Center dot
    m2 = size * 3 // 8
    draw.ellipse([m2, m2, size-m2-1, size-m2-1], fill=(r, g, b, 255))

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    _icon_cache[key] = buf.getvalue()
    return _icon_cache[key]


def _make_avatar_png(accent_rgb, size=120):
    """Create an avatar-style circular icon."""
    key = ("avatar", accent_rgb[0], accent_rgb[1], accent_rgb[2], size)
    if key in _icon_cache:
        return _icon_cache[key]

    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    r, g, b = accent_rgb
    # Circle bg
    draw.ellipse([0, 0, size-1, size-1], fill=(r, g, b, 255))
    # Head
    hx, hy = size // 2, size * 5 // 14
    hr = size // 7
    draw.ellipse([hx-hr, hy-hr, hx+hr, hy+hr], fill=(255, 255, 255, 255))
    # Shoulders
    sw = size // 3
    sh = size // 5
    sy = size * 9 // 14
    draw.ellipse([hx-sw, sy, hx+sw, sy+sh*2], fill=(255, 255, 255, 255))

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    _icon_cache[key] = buf.getvalue()
    return _icon_cache[key]


def _add_icon(slide, left, top, size, accent_rgb, avatar=False):
    """Embed a PNG icon into the slide."""
    png_data = _make_avatar_png(accent_rgb, 120) if avatar else _make_icon_png(accent_rgb, 120)
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp.write(png_data)
    tmp.close()
    pic = slide.shapes.add_picture(tmp.name, left, top, size, size)
    os.unlink(tmp.name)
    return pic


# ── Shape helpers ──────────────────────────────────────────────────────

def _shape(slide, stype, l, t, w, h, fill=None, line=None):
    s = slide.shapes.add_shape(stype, l, t, w, h)
    if fill:
        s.fill.solid(); s.fill.fore_color.rgb = fill
    else:
        s.fill.background()
    if line:
        s.line.color.rgb = line; s.line.width = Pt(0.75)
    else:
        s.line.fill.background()
    return s

def _rect(slide, l, t, w, h, fill, line=None):
    return _shape(slide, MSO_SHAPE.RECTANGLE, l, t, w, h, fill, line)

def _rrect(slide, l, t, w, h, fill=WHITE, line=CARD_BORDER, radius=0.06):
    s = _shape(slide, MSO_SHAPE.ROUNDED_RECTANGLE, l, t, w, h, fill, line)
    s.adjustments[0] = radius
    return s

def _oval(slide, cx, cy, r, fill):
    return _shape(slide, MSO_SHAPE.OVAL, cx - r, cy - r, r*2, r*2, fill)

def _tb(slide, text, l, t, w, h, sz=12, bold=False, color=DARK, align=PP_ALIGN.LEFT, font="Segoe UI"):
    """Add text via a shape (not textbox) — cleaner editing in PowerPoint."""
    s = _shape(slide, MSO_SHAPE.RECTANGLE, l, t, w, h)
    s.fill.background()
    tf = s.text_frame
    tf.word_wrap = True
    tf.margin_left = Pt(2); tf.margin_right = Pt(2)
    tf.margin_top = Pt(1); tf.margin_bottom = Pt(1)
    p = tf.paragraphs[0]
    p.alignment = align
    p.space_before = Pt(0); p.space_after = Pt(0)
    r = p.add_run()
    r.text = text
    r.font.size = Pt(sz); r.font.bold = bold; r.font.color.rgb = color; r.font.name = font
    return s

def _tb_multi(slide, lines, l, t, w, h, font="Segoe UI"):
    """Multi-line text shape: list of (text, size, bold, color)."""
    s = _shape(slide, MSO_SHAPE.RECTANGLE, l, t, w, h)
    s.fill.background()
    tf = s.text_frame
    tf.word_wrap = True
    tf.margin_left = Pt(4); tf.margin_right = Pt(4)
    tf.margin_top = Pt(2); tf.margin_bottom = Pt(2)
    for i, (text, sz, bold, color) in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_before = Pt(2); p.space_after = Pt(1)
        r = p.add_run()
        r.text = text
        r.font.size = Pt(sz); r.font.bold = bold; r.font.color.rgb = color; r.font.name = font
    return s


def _bg_white(slide):
    f = slide.background.fill; f.solid(); f.fore_color.rgb = WHITE

def _bg_gray(slide):
    f = slide.background.fill; f.solid(); f.fore_color.rgb = BG_GRAY


# ── Shared components ──────────────────────────────────────────────────

def _header_bar(slide, title, subtitle=""):
    """Dark header bar with title + subtitle."""
    _rect(slide, 0, 0, SW, I(0.04), C_PRIMARY)
    _rect(slide, 0, I(0.04), SW, I(0.7), C_PRIMARY_DK)
    _tb(slide, title, I(0.4), I(0.1), I(7), I(0.35),
        sz=16, bold=True, color=WHITE, font="Segoe UI Semibold")
    if subtitle:
        _tb(slide, subtitle, I(0.4), I(0.42), I(8), I(0.28),
            sz=9, color=RGBColor(0xC7, 0xD2, 0xFE))

def _page_num(slide, num, total):
    _tb(slide, f"{num:02d} / {total:02d}",
        SW - I(0.8), SH - I(0.35), I(0.65), I(0.25),
        sz=8, bold=True, color=LIGHT_TEXT, align=PP_ALIGN.RIGHT)

def _source_note(slide, text):
    bar = _rrect(slide, I(0.4), SH - I(0.55), SW - I(0.8), I(0.4), C_PRIMARY_XL, line=None)
    _tb(slide, text, I(0.55), SH - I(0.5), SW - I(1.1), I(0.3),
        sz=8, color=C_PRIMARY)


# ── Content card (icon + title + description) ─────────────────────────

def _content_card(slide, x, y, w, h, accent_idx, title, desc=""):
    """Card matching co-work style: rounded rect + embedded icon + title + description."""
    ac = ACCENTS[accent_idx % len(ACCENTS)]
    ac_lt = ACCENT_LIGHT[accent_idx % len(ACCENT_LIGHT)]
    ac_rgb = (ac.red if hasattr(ac, 'red') else int(str(ac)[:2], 16),
              ac.green if hasattr(ac, 'green') else int(str(ac)[2:4], 16),
              ac.blue if hasattr(ac, 'blue') else int(str(ac)[4:6], 16))
    # Parse RGB from RGBColor
    s = str(ac)
    ac_rgb = (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))

    # Card
    _rrect(slide, x, y, w, h, WHITE, CARD_BORDER)

    # Icon
    icon_sz = I(0.38)
    icon_x = x + I(0.15)
    icon_y = y + (h - icon_sz) // 2
    _add_icon(slide, icon_x, icon_y, icon_sz, ac_rgb)

    # Title
    tx = x + I(0.62)
    tw = w - I(0.77)
    if desc:
        _tb(slide, title, tx, y + I(0.08), tw, I(0.25),
            sz=11, bold=True, color=DARK)
        _tb(slide, desc, tx, y + I(0.32), tw, h - I(0.4),
            sz=9, color=MID)
    else:
        _tb(slide, title, tx, y + (h - I(0.3)) // 2, tw, I(0.3),
            sz=11, bold=True, color=DARK)


# ═══════════════════════════════════════════════════════════════════════
# SLIDE BUILDERS
# ═══════════════════════════════════════════════════════════════════════

def make_cover(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_white(slide)

    # Decorative circles
    _oval(slide, SW - I(1.2), I(0.5), I(1.8), C_PRIMARY_XL)
    _oval(slide, SW - I(0.1), I(-0.4), I(1.0), C_PRIMARY_LT)
    _oval(slide, I(-0.8), SH - I(1.5), I(1.2), C_PRIMARY_XL)

    # Left accent stripe
    _rect(slide, 0, 0, I(0.15), SH, C_PRIMARY)
    # Top/bottom lines
    _rect(slide, I(0.15), 0, SW, I(0.03), C_PRIMARY)
    _rect(slide, 0, SH - I(0.03), SW, I(0.03), C_PRIMARY)

    # Title
    _tb(slide, s["title"], I(0.8), I(1.2), I(7.5), I(1.2),
        sz=28, bold=True, color=C_PRIMARY_DK, font="Segoe UI Black")

    # Decorative line
    _rect(slide, I(0.8), I(2.5), I(2.2), Pt(3), C_PRIMARY)

    # Subtitle from bullets
    if s.get("bullets"):
        sub = " · ".join(s["bullets"][:3])
        _tb(slide, sub, I(0.8), I(2.75), I(7.5), I(0.5),
            sz=11, color=MID)

    # Bottom info bar
    if s.get("note"):
        _rrect(slide, I(0.35), SH - I(0.65), SW - I(0.7), I(0.4), C_PRIMARY_XL, line=None)
        _tb(slide, s["note"], I(0.5), SH - I(0.6), SW - I(1.0), I(0.3),
            sz=9, color=C_PRIMARY)


def make_section(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_white(slide)
    _rect(slide, 0, 0, SW, I(0.03), C_PRIMARY)
    _oval(slide, SW // 2, I(1.2), I(2.5), C_PRIMARY_XL)
    _tb(slide, s["title"], I(0.5), I(1.5), SW - I(1.0), I(1.0),
        sz=26, bold=True, color=C_PRIMARY_DK, align=PP_ALIGN.CENTER, font="Segoe UI Black")
    _rect(slide, SW // 2 - I(1), I(2.7), I(2), Pt(3), C_PRIMARY)
    if s.get("note"):
        _tb(slide, s["note"], I(1), I(3.0), SW - I(2), I(0.4),
            sz=10, color=MID, align=PP_ALIGN.CENTER)
    _page_num(slide, idx, total)


def make_bullets(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    bullets = s.get("bullets", [])
    if not bullets: return

    n = len(bullets)
    content_top = I(0.95)
    avail_h = SH - content_top - I(0.45)

    if n >= 4:
        cols = 2
        col_w = (SW - I(1.1)) // 2
        card_h = min(avail_h // ((n + 1) // 2) - I(0.08), I(0.72))
        for i, b in enumerate(bullets[:10]):
            c = i % 2
            r = i // 2
            x = I(0.35) + c * (col_w + I(0.2))
            y = content_top + r * (card_h + I(0.08))
            if y + card_h > SH - I(0.4): break
            _content_card(slide, x, y, col_w, card_h, i, b)
    else:
        card_h = min(avail_h // n - I(0.08), I(0.85))
        for i, b in enumerate(bullets):
            y = content_top + i * (card_h + I(0.08))
            if y + card_h > SH - I(0.4): break
            _content_card(slide, I(0.35), y, SW - I(0.7), card_h, i, b)

    _page_num(slide, idx, total)


def make_stats(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 4)
    gap = I(0.2)
    card_w = (SW - I(0.7) - gap * (n - 1)) // n
    start_x = I(0.35)
    cy = I(0.95)
    card_h = SH - cy - I(0.55)

    for i, item in enumerate(items[:n]):
        ac = ACCENTS[i % len(ACCENTS)]
        s_ac = str(ac)
        ac_rgb = (int(s_ac[0:2], 16), int(s_ac[2:4], 16), int(s_ac[4:6], 16))
        x = start_x + i * (card_w + gap)

        # Card
        _rrect(slide, x, cy, card_w, card_h, WHITE, CARD_BORDER)
        # Top accent
        _rect(slide, x, cy, card_w, I(0.04), ac)

        # Icon
        icon_sz = I(0.4)
        _add_icon(slide, x + (card_w - icon_sz) // 2, cy + I(0.18), icon_sz, ac_rgb)

        # Big value
        _tb(slide, item.get("value", ""),
            x + I(0.08), cy + I(0.7), card_w - I(0.16), I(0.55),
            sz=28, bold=True, color=ac, align=PP_ALIGN.CENTER, font="Segoe UI Black")

        # Divider
        _rect(slide, x + card_w // 4, cy + I(1.3), card_w // 2, Pt(2), ac)

        # Label
        _tb(slide, item.get("label", ""),
            x + I(0.1), cy + I(1.45), card_w - I(0.2), card_h - I(1.6),
            sz=9, color=MID, align=PP_ALIGN.CENTER)

    if s.get("note"):
        _source_note(slide, s["note"])
    _page_num(slide, idx, total)


def make_chart(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 6)
    max_val = max(item.get("value", 1) for item in items[:n]) or 1

    # Chart card
    _rrect(slide, I(0.35), I(0.95), SW - I(0.7), SH - I(1.5), WHITE, CARD_BORDER)

    chart_h = I(2.6)
    chart_top = I(1.3)
    bar_w = I(0.9)
    gap = I(0.35)
    total_w = n * bar_w + (n - 1) * gap
    start_x = (SW - total_w) // 2

    for i, item in enumerate(items[:n]):
        ac = ACCENTS[i % len(ACCENTS)]
        val = item.get("value", 0)
        pct = val / max_val if max_val else 0
        bar_h = max(int(chart_h * pct), I(0.15))
        x = start_x + i * (bar_w + gap)
        y_bar = chart_top + chart_h - bar_h

        _rrect(slide, x, y_bar, bar_w, bar_h, ac, radius=0.08)
        _tb(slide, str(val), x, y_bar - I(0.25), bar_w, I(0.22),
            sz=11, bold=True, color=ac, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("label", ""),
            x - I(0.1), chart_top + chart_h + I(0.1), bar_w + I(0.2), I(0.4),
            sz=8, color=MID, align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


def make_two_col(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    headers = s.get("headers", ["", ""])
    col1 = s.get("col1", [])
    col2 = s.get("col2", [])
    gap = I(0.2)
    col_w = (SW - I(0.7) - gap) // 2
    positions = [
        (I(0.35), ACCENTS[4]),   # red
        (I(0.35) + col_w + gap, ACCENTS[2]),  # green
    ]

    for ci, (items, (sx, ac)) in enumerate(zip([col1, col2], positions)):
        hdr_text = headers[ci] if ci < len(headers) else ""
        s_ac = str(ac)
        ac_rgb = (int(s_ac[0:2], 16), int(s_ac[2:4], 16), int(s_ac[4:6], 16))

        # Column header
        hdr = _rrect(slide, sx, I(0.95), col_w, I(0.35), ac, line=None, radius=0.1)
        _tb(slide, hdr_text, sx + I(0.1), I(0.97), col_w - I(0.2), I(0.28),
            sz=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

        # Items
        for i, item in enumerate(items[:6]):
            y = I(1.4) + i * I(0.52)
            if y + I(0.45) > SH - I(0.4): break
            _rrect(slide, sx, y, col_w, I(0.45), WHITE, CARD_BORDER)

            # Icon
            _add_icon(slide, sx + I(0.1), y + I(0.06), I(0.32), ac_rgb)

            _tb(slide, item, sx + I(0.5), y + I(0.06), col_w - I(0.6), I(0.33),
                sz=9, color=DARK)

    _page_num(slide, idx, total)


def make_timeline(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 5)
    gap = I(0.15)
    step_w = (SW - I(0.7) - gap * (n - 1)) // n
    start_x = I(0.35)
    y = I(1.05)
    card_h = SH - y - I(0.55)

    # Connector line
    line_y = y + I(0.55)
    _rect(slide, start_x, line_y, SW - I(0.7), Pt(2), C_PRIMARY_LT)

    for i, item in enumerate(items[:n]):
        ac = ACCENTS[i % len(ACCENTS)]
        s_ac = str(ac)
        ac_rgb = (int(s_ac[0:2], 16), int(s_ac[2:4], 16), int(s_ac[4:6], 16))
        x = start_x + i * (step_w + gap)

        # Card
        _rrect(slide, x, y, step_w, card_h, WHITE, CARD_BORDER)
        _rect(slide, x, y, step_w, I(0.03), ac)

        # Number circle
        num_sz = I(0.35)
        num_x = x + (step_w - num_sz) // 2
        num_y = y + I(0.12)
        _oval(slide, num_x + num_sz // 2, num_y + num_sz // 2, num_sz // 2, ac)
        _tb(slide, str(i + 1), num_x, num_y + I(0.02), num_sz, I(0.25),
            sz=14, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

        # Step name
        _tb(slide, item.get("step", ""),
            x + I(0.08), y + I(0.55), step_w - I(0.16), I(0.35),
            sz=10, bold=True, color=ac, align=PP_ALIGN.CENTER)

        # Description
        _tb(slide, item.get("desc", ""),
            x + I(0.08), y + I(0.95), step_w - I(0.16), card_h - I(1.1),
            sz=8, color=MID, align=PP_ALIGN.CENTER)

    if s.get("note"):
        _source_note(slide, s["note"])
    _page_num(slide, idx, total)


def make_pillars(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 4)
    gap = I(0.15)
    col_w = (SW - I(0.7) - gap * (n - 1)) // n
    start_x = I(0.35)
    y = I(0.95)
    card_h = SH - y - I(0.5)

    for i, item in enumerate(items[:n]):
        ac = ACCENTS[i % len(ACCENTS)]
        s_ac = str(ac)
        ac_rgb = (int(s_ac[0:2], 16), int(s_ac[2:4], 16), int(s_ac[4:6], 16))
        x = start_x + i * (col_w + gap)

        # Card
        _rrect(slide, x, y, col_w, card_h, WHITE, CARD_BORDER)
        _rect(slide, x, y, col_w, I(0.03), ac)

        # Icon
        icon_sz = I(0.4)
        _add_icon(slide, x + (col_w - icon_sz) // 2, y + I(0.12), icon_sz, ac_rgb)

        # Title
        _tb(slide, item.get("title", ""),
            x + I(0.08), y + I(0.6), col_w - I(0.16), I(0.3),
            sz=11, bold=True, color=ac, align=PP_ALIGN.CENTER)

        # Bullets
        bullets = item.get("bullets", [])
        for bi, b in enumerate(bullets[:6]):
            by = y + I(1.0) + bi * I(0.42)
            if by + I(0.35) > y + card_h - I(0.08): break
            # Bullet dot
            dot_y = by + I(0.08)
            _oval(slide, x + I(0.18), dot_y, Pt(3), ac)
            _tb(slide, b, x + I(0.32), by, col_w - I(0.4), I(0.35),
                sz=8, color=MID)

    _page_num(slide, idx, total)


def make_agenda(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    row_h = I(0.55)
    gap = I(0.06)

    for i, item in enumerate(items[:8]):
        ac = ACCENTS[i % len(ACCENTS)]
        s_ac = str(ac)
        ac_rgb = (int(s_ac[0:2], 16), int(s_ac[2:4], 16), int(s_ac[4:6], 16))
        y = I(0.95) + i * (row_h + gap)
        if y + row_h > SH - I(0.4): break

        # Row card
        _rrect(slide, I(0.35), y, SW - I(0.7), row_h, WHITE, CARD_BORDER)

        # Number circle
        num_sz = I(0.3)
        _oval(slide, I(0.6) + num_sz // 2, y + row_h // 2, num_sz // 2, ac)
        _tb(slide, item.get("num", str(i + 1)),
            I(0.6), y + (row_h - I(0.22)) // 2, num_sz, I(0.22),
            sz=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

        # Title + desc
        _tb(slide, item.get("title", ""),
            I(1.05), y + I(0.04), I(3.5), I(0.22),
            sz=11, bold=True, color=DARK)
        _tb(slide, item.get("desc", ""),
            I(1.05), y + I(0.26), SW - I(1.5), I(0.22),
            sz=8, color=MID)

    _page_num(slide, idx, total)


def make_roles(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    n = min(len(items), 3)
    gap = I(0.2)
    col_w = (SW - I(0.7) - gap * (n - 1)) // n
    start_x = I(0.35)
    y = I(0.95)
    card_h = SH - y - I(0.5)

    for i, item in enumerate(items[:n]):
        ac = ACCENTS[i % len(ACCENTS)]
        s_ac = str(ac)
        ac_rgb = (int(s_ac[0:2], 16), int(s_ac[2:4], 16), int(s_ac[4:6], 16))
        x = start_x + i * (col_w + gap)

        # Card
        _rrect(slide, x, y, col_w, card_h, WHITE, CARD_BORDER)
        _rect(slide, x, y, col_w, I(0.04), ac)

        # Avatar
        av_sz = I(0.55)
        _add_icon(slide, x + (col_w - av_sz) // 2, y + I(0.12), av_sz, ac_rgb, avatar=True)

        # Name
        _tb(slide, item.get("role", ""),
            x + I(0.05), y + I(0.75), col_w - I(0.1), I(0.25),
            sz=12, bold=True, color=ac, align=PP_ALIGN.CENTER)

        # Type badge
        if item.get("type"):
            badge_w = min(col_w - I(0.3), I(2.0))
            _rrect(slide, x + (col_w - badge_w) // 2, y + I(1.02),
                   badge_w, I(0.22), C_PRIMARY_XL, line=None, radius=0.3)
            _tb(slide, item["type"],
                x + (col_w - badge_w) // 2, y + I(1.04), badge_w, I(0.18),
                sz=8, color=C_PRIMARY, align=PP_ALIGN.CENTER)

        # Separator
        _rect(slide, x + I(0.2), y + I(1.32), col_w - I(0.4), Pt(1), CARD_BORDER)

        # Bullets
        bullets = item.get("bullets", [])
        for bi, b in enumerate(bullets[:5]):
            by = y + I(1.45) + bi * I(0.42)
            if by + I(0.35) > y + card_h - I(0.08): break
            _oval(slide, x + I(0.18), by + I(0.08), Pt(3), ac)
            _tb(slide, b, x + I(0.32), by, col_w - I(0.4), I(0.35),
                sz=8, color=MID)

    if s.get("note"):
        _source_note(slide, s["note"])
    _page_num(slide, idx, total)


def make_okr(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    row_h = I(0.7)
    for i, item in enumerate(items[:5]):
        ac = ACCENTS[i % len(ACCENTS)]
        y = I(0.95) + i * (row_h + I(0.08))
        if y + row_h > SH - I(0.4): break

        _rrect(slide, I(0.35), y, SW - I(0.7), row_h, WHITE, CARD_BORDER)
        _rect(slide, I(0.35), y + I(0.08), Pt(4), row_h - I(0.16), ac)

        _tb(slide, item.get("objective", ""),
            I(0.65), y + I(0.05), I(3), I(0.25),
            sz=10, bold=True, color=ac)

        krs = item.get("krs", [])
        for ki, kr in enumerate(krs[:3]):
            kx = I(3.8) + ki * I(1.8)
            _tb(slide, f"✓ {kr}", kx, y + I(0.05), I(1.7), row_h - I(0.1),
                sz=8, color=MID)

    _page_num(slide, idx, total)


def make_principles(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_gray(slide)
    _header_bar(slide, s["title"], s.get("note", ""))

    items = s.get("items", [])
    if not items: return

    cols = 2
    gap_x = I(0.15)
    gap_y = I(0.1)
    col_w = (SW - I(0.7) - gap_x) // 2
    card_h = I(0.75)

    for i, item in enumerate(items[:6]):
        c = i % cols
        r = i // cols
        x = I(0.35) + c * (col_w + gap_x)
        y = I(0.95) + r * (card_h + gap_y)
        if y + card_h > SH - I(0.4): break

        _content_card(slide, x, y, col_w, card_h, i,
                      item.get("title", ""), item.get("desc", ""))

    _page_num(slide, idx, total)


def make_summary(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg_white(slide)

    # Decorative
    _oval(slide, SW // 2, I(0.8), I(2.2), C_PRIMARY_XL)
    _oval(slide, I(0.5), SH - I(1.2), I(1.3), C_PRIMARY_XL)

    _rect(slide, 0, 0, SW, I(0.03), C_PRIMARY)
    _rect(slide, 0, SH - I(0.03), SW, I(0.03), C_PRIMARY)

    # Title
    _tb(slide, s["title"], I(0.5), I(0.8), SW - I(1.0), I(0.8),
        sz=22, bold=True, color=C_PRIMARY_DK, align=PP_ALIGN.CENTER, font="Segoe UI Black")

    _rect(slide, SW // 2 - I(0.8), I(1.7), I(1.6), Pt(3), C_PRIMARY)

    # Accent bullets
    bullets = s.get("bullets", [])
    for i, b in enumerate(bullets[:5]):
        y = I(2.0) + i * I(0.45)
        if y > SH - I(1.0): break
        _rrect(slide, I(1.0), y, SW - I(2.0), I(0.36), C_PRIMARY_XL, line=None)
        _oval(slide, I(1.15), y + I(0.14), Pt(4), C_PRIMARY)
        _tb(slide, b, I(1.35), y + I(0.04), SW - I(2.5), I(0.28),
            sz=10, color=C_PRIMARY)

    if s.get("note"):
        _tb(slide, s["note"], I(1), SH - I(0.65), SW - I(2), I(0.35),
            sz=9, color=MID, align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


# ═══════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════

LAYOUT_MAP = {
    "bullets": make_bullets, "stats": make_stats, "chart": make_chart,
    "two-col": make_two_col, "timeline": make_timeline, "pillars": make_pillars,
    "agenda": make_agenda, "roles": make_roles, "okr": make_okr,
    "principles": make_principles,
}

def generate(slides_json_str, output_path):
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
        print("Usage: generate_pptx.py <slides_json> <output_path>", file=sys.stderr)
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
