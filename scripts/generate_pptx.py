#!/usr/bin/env python3
"""
Generate a professional PPTX from slide JSON.
Usage: python3 generate_pptx.py <slides_json> <output_path>

Inspired by corporate presentation style: white backgrounds, colored accent shapes,
icon placeholders, multi-column card layouts, professional typography.
"""
import sys, json, math
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

# ── Dimensions (standard 16:9) ──────────────────────────────────────────
W = Inches(13.33)
H = Inches(7.5)

# ── Color Palettes ──────────────────────────────────────────────────────
PALETTES = [
    {   # Indigo/Purple (default)
        "primary":   RGBColor(0x4F, 0x46, 0xE5),
        "primary_l": RGBColor(0xE0, 0xE7, 0xFF),
        "accent1":   RGBColor(0x06, 0xB6, 0xD4),
        "accent2":   RGBColor(0x10, 0xB9, 0x81),
        "accent3":   RGBColor(0xF5, 0x9E, 0x0B),
        "accent4":   RGBColor(0xEF, 0x44, 0x44),
        "accent5":   RGBColor(0x8B, 0x5C, 0xF6),
        "header_bg": RGBColor(0x31, 0x30, 0x8C),
    },
    {   # Teal/Cyan
        "primary":   RGBColor(0x0D, 0x94, 0x88),
        "primary_l": RGBColor(0xCC, 0xFB, 0xF1),
        "accent1":   RGBColor(0x64, 0x74, 0x8B),
        "accent2":   RGBColor(0xF5, 0x9E, 0x0B),
        "accent3":   RGBColor(0xEF, 0x44, 0x44),
        "accent4":   RGBColor(0x8B, 0x5C, 0xF6),
        "accent5":   RGBColor(0x06, 0xB6, 0xD4),
        "header_bg": RGBColor(0x11, 0x50, 0x4A),
    },
]

WHITE      = RGBColor(0xFF, 0xFF, 0xFF)
NEAR_WHITE = RGBColor(0xF8, 0xFA, 0xFC)
DARK_TEXT   = RGBColor(0x1E, 0x29, 0x3B)
MID_TEXT    = RGBColor(0x47, 0x55, 0x69)
LIGHT_TEXT  = RGBColor(0x94, 0xA3, 0xB8)
CARD_BG     = RGBColor(0xF1, 0xF5, 0xF9)
CARD_BORDER = RGBColor(0xE2, 0xE8, 0xF0)

# Icon symbols for different contexts
ICONS = ["📋", "🎯", "💡", "📊", "🔧", "🚀", "⚡", "🏆", "📈", "✅",
         "🔍", "💼", "🌐", "🎓", "📱", "🛡️", "⭐", "🔄", "📌", "🎯"]


def get_palette(idx=0):
    return PALETTES[idx % len(PALETTES)]


def set_bg_white(slide):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = WHITE


def set_bg_light(slide):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = NEAR_WHITE


def add_rounded_rect(slide, left, top, width, height, fill_color, line_color=None, corner_radius=Inches(0.15)):
    shape = slide.shapes.add_shape(
        MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill_color
    if line_color:
        shape.line.color.rgb = line_color
        shape.line.width = Pt(1)
    else:
        shape.line.fill.background()
    # Adjust corner radius
    shape.adjustments[0] = 0.06
    return shape


def add_rect(slide, left, top, width, height, fill_color, line_color=None):
    shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill_color
    if line_color:
        shape.line.color.rgb = line_color
        shape.line.width = Pt(1)
    else:
        shape.line.fill.background()
    return shape


def add_circle(slide, left, top, size, fill_color):
    shape = slide.shapes.add_shape(MSO_SHAPE.OVAL, left, top, size, size)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill_color
    shape.line.fill.background()
    return shape


def add_text(slide, text, left, top, width, height,
             font_size=14, bold=False, color=DARK_TEXT,
             align=PP_ALIGN.LEFT, italic=False, font_name="Segoe UI"):
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = align
    p.space_before = Pt(0)
    p.space_after = Pt(0)
    run = p.add_run()
    run.text = text
    run.font.size = Pt(font_size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    run.font.name = font_name
    return txBox


def add_rich_text_in_shape(shape, lines, font_size=12, color=MID_TEXT, line_spacing=Pt(6), bullet_color=None):
    """Add multiple lines of text into an existing shape's text frame."""
    tf = shape.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.2)
    tf.margin_right = Inches(0.2)
    tf.margin_top = Inches(0.15)
    tf.margin_bottom = Inches(0.1)

    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_before = line_spacing
        p.space_after = Pt(2)
        if bullet_color:
            dot = p.add_run()
            dot.text = "●  "
            dot.font.size = Pt(8)
            dot.font.color.rgb = bullet_color
        run = p.add_run()
        run.text = line
        run.font.size = Pt(font_size)
        run.font.color.rgb = color
        run.font.name = "Segoe UI"


def add_header_bar(slide, pal, title, subtitle="", slide_num="", total=""):
    """Standard content slide header: colored top bar + title + subtitle."""
    # Top colored bar
    add_rect(slide, Inches(0), Inches(0), W, Inches(0.06), pal["primary"])

    # Header background
    add_rect(slide, Inches(0), Inches(0.06), W, Inches(0.94), pal["header_bg"])

    # Title text
    add_text(slide, title,
             Inches(0.6), Inches(0.18), Inches(10.5), Inches(0.65),
             font_size=22, bold=True, color=WHITE)

    # Slide number badge
    if slide_num:
        num_text = f"{slide_num}"
        add_text(slide, num_text,
                 W - Inches(1.2), Inches(0.25), Inches(0.8), Inches(0.5),
                 font_size=11, color=RGBColor(0xA5, 0xB4, 0xFC), align=PP_ALIGN.RIGHT)

    # Subtitle
    if subtitle:
        add_text(slide, subtitle,
                 Inches(0.6), Inches(0.62), Inches(10), Inches(0.35),
                 font_size=12, color=RGBColor(0xA5, 0xB4, 0xFC), italic=True)


def add_footer(slide, pal, page_num, total):
    """Subtle footer with page number."""
    add_rect(slide, Inches(0), H - Inches(0.35), W, Inches(0.35), pal["primary_l"])
    add_text(slide, f"{page_num} / {total}",
             W - Inches(1.5), H - Inches(0.32), Inches(1.2), Inches(0.3),
             font_size=9, color=pal["primary"], align=PP_ALIGN.RIGHT, bold=True)


# ═══════════════════════════════════════════════════════════════════════
# SLIDE BUILDERS
# ═══════════════════════════════════════════════════════════════════════

def make_cover(prs, s, idx, total, pal):
    """Title/cover slide with large centered text."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_white(slide)

    # Full-width colored band
    add_rect(slide, Inches(0), Inches(0), W, Inches(0.08), pal["primary"])
    add_rect(slide, Inches(0), H - Inches(0.08), W, Inches(0.08), pal["primary"])

    # Left accent stripe
    add_rect(slide, Inches(0), Inches(0.08), Inches(0.3), H - Inches(0.16), pal["primary"])

    # Decorative circle top-right
    add_circle(slide, W - Inches(2.5), Inches(0.5), Inches(1.5), pal["primary_l"])

    # Title
    add_text(slide, s["title"],
             Inches(1.2), Inches(2.0), Inches(10.5), Inches(1.8),
             font_size=40, bold=True, color=pal["header_bg"], align=PP_ALIGN.LEFT,
             font_name="Segoe UI Black")

    # Subtitle line
    if s.get("bullets"):
        sub = " · ".join(s["bullets"][:3])
        add_text(slide, sub,
                 Inches(1.2), Inches(4.0), Inches(10), Inches(0.8),
                 font_size=16, color=MID_TEXT, italic=True)

    # Bottom info bar
    bar = add_rounded_rect(slide, Inches(0.6), H - Inches(1.0), Inches(10), Inches(0.45),
                           pal["primary_l"])
    add_rich_text_in_shape(bar, [s.get("note", "")], font_size=11, color=pal["primary"])


def make_section_divider(prs, s, idx, total, pal):
    """Section title slide - large centered text like '1. EXECUTIVE SUMMARY'."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_white(slide)

    # Accent bar top
    add_rect(slide, Inches(0), Inches(0), W, Inches(0.06), pal["primary"])

    # Large centered title
    add_text(slide, s["title"],
             Inches(1), Inches(2.5), Inches(11.3), Inches(2),
             font_size=36, bold=True, color=pal["header_bg"], align=PP_ALIGN.CENTER,
             font_name="Segoe UI Black")

    # Decorative line under title
    add_rect(slide, Inches(5.5), Inches(4.3), Inches(2.3), Pt(4), pal["primary"])

    if s.get("note"):
        add_text(slide, s["note"],
                 Inches(2), Inches(4.8), Inches(9.3), Inches(0.6),
                 font_size=14, color=MID_TEXT, align=PP_ALIGN.CENTER, italic=True)

    add_footer(slide, pal, idx, total)


def make_bullets_slide(prs, s, idx, total, pal):
    """Content slide with bullet points in cards."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    subtitle = s.get("note", "")
    add_header_bar(slide, pal, s["title"], subtitle, str(idx), str(total))

    bullets = s.get("bullets", [])
    if not bullets:
        return

    # Layout: bullets in 2 columns of cards
    cols = 2 if len(bullets) >= 4 else 1
    col_w = Inches(5.8) if cols == 2 else Inches(12)
    start_y = Inches(1.3)
    card_h = Inches(0.7)
    gap = Inches(0.12)
    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"], pal["accent4"], pal["accent5"]]

    for i, bullet in enumerate(bullets):
        col = i % cols if cols == 2 else 0
        row = i // cols if cols == 2 else i
        x = Inches(0.5) + col * (col_w + Inches(0.4))
        y = start_y + row * (card_h + gap)

        if y + card_h > H - Inches(0.5):
            break

        ac = accents[i % len(accents)]

        # Card background
        card = add_rounded_rect(slide, x, y, col_w, card_h, WHITE, CARD_BORDER)

        # Left accent stripe on card
        add_rect(slide, x, y + Inches(0.08), Pt(5), card_h - Inches(0.16), ac)

        # Icon circle
        add_circle(slide, x + Inches(0.25), y + Inches(0.12), Inches(0.45), pal["primary_l"])
        add_text(slide, ICONS[i % len(ICONS)],
                 x + Inches(0.27), y + Inches(0.12), Inches(0.45), Inches(0.45),
                 font_size=14, align=PP_ALIGN.CENTER)

        # Bullet text
        add_text(slide, bullet,
                 x + Inches(0.85), y + Inches(0.12), col_w - Inches(1.1), card_h - Inches(0.2),
                 font_size=13, color=DARK_TEXT)

    add_footer(slide, pal, idx, total)


def make_stats_slide(prs, s, idx, total, pal):
    """KPI / stats cards in a row."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    n = min(len(items), 4)
    card_w = Inches(2.8)
    total_w = n * card_w + (n - 1) * Inches(0.3)
    start_x = (Emu(W.emu) - Emu(total_w.emu if hasattr(total_w, 'emu') else int(total_w))) // 2
    # Recalculate properly
    gap = Inches(0.3)
    total_width = n * card_w.emu + (n - 1) * gap.emu
    start_x = (W.emu - total_width) // 2

    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"]]

    for i, item in enumerate(items[:n]):
        x = start_x + i * (card_w.emu + gap.emu)
        y = Inches(2.0)
        ac = accents[i % len(accents)]

        # Card
        card = add_rounded_rect(slide, x, y, card_w, Inches(3.5), WHITE, CARD_BORDER)

        # Top colored bar inside card
        add_rect(slide, x, y, card_w, Inches(0.06), ac)

        # Big number
        add_text(slide, item.get("value", ""),
                 x, y + Inches(0.5), card_w, Inches(1.2),
                 font_size=42, bold=True, color=ac, align=PP_ALIGN.CENTER,
                 font_name="Segoe UI Black")

        # Label
        add_text(slide, item.get("label", ""),
                 x + Inches(0.2), y + Inches(1.8), card_w - Inches(0.4), Inches(1.2),
                 font_size=13, color=MID_TEXT, align=PP_ALIGN.CENTER)

    add_footer(slide, pal, idx, total)


def make_chart_slide(prs, s, idx, total, pal):
    """Bar chart built from shapes."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    n = min(len(items), 6)
    max_val = max(item.get("value", 1) for item in items[:n]) or 1
    chart_h = Inches(4.0)
    chart_y = Inches(2.2)
    bar_w = Inches(1.2)
    gap = Inches(0.5)
    total_width = n * bar_w.emu + (n - 1) * gap.emu
    start_x = (W.emu - total_width) // 2

    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"], pal["accent4"], pal["accent5"]]

    # Chart area background
    add_rounded_rect(slide, Inches(0.6), Inches(1.5), Inches(12.1), Inches(5.5), WHITE, CARD_BORDER)

    for i, item in enumerate(items[:n]):
        val = item.get("value", 0)
        pct = val / max_val
        bar_h_emu = int(chart_h.emu * pct)
        x = start_x + i * (bar_w.emu + gap.emu)
        y_bar = chart_y.emu + chart_h.emu - bar_h_emu
        ac = accents[i % len(accents)]

        # Bar
        bar = add_rounded_rect(slide, x, y_bar, bar_w, bar_h_emu, ac)
        bar.adjustments[0] = 0.08

        # Value on top of bar
        add_text(slide, str(val),
                 x, y_bar - Inches(0.35), bar_w, Inches(0.3),
                 font_size=16, bold=True, color=ac, align=PP_ALIGN.CENTER)

        # Label below bar
        add_text(slide, item.get("label", ""),
                 x - Inches(0.15), chart_y.emu + chart_h.emu + Inches(0.15).emu, bar_w + Inches(0.3), Inches(0.5),
                 font_size=11, color=MID_TEXT, align=PP_ALIGN.CENTER)

    add_footer(slide, pal, idx, total)


def make_two_col_slide(prs, s, idx, total, pal):
    """Two-column comparison slide."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    headers = s.get("headers", ["", ""])
    col1 = s.get("col1", [])
    col2 = s.get("col2", [])

    col_w = Inches(5.8)
    left1 = Inches(0.5)
    left2 = Inches(7.0)
    top = Inches(1.3)
    hdr_h = Inches(0.55)

    # Column headers
    for ci, (header, x, ac) in enumerate([
        (headers[0] if len(headers) > 0 else "", left1, pal["accent4"]),
        (headers[1] if len(headers) > 1 else "", left2, pal["accent2"])
    ]):
        hdr_card = add_rounded_rect(slide, x, top, col_w, hdr_h, ac)
        hdr_card.adjustments[0] = 0.12
        add_text(slide, header,
                 x + Inches(0.2), top + Inches(0.08), col_w - Inches(0.4), Inches(0.4),
                 font_size=14, bold=True, color=WHITE)

    # Column items
    for ci, (items, x, ac) in enumerate([
        (col1, left1, pal["accent4"]),
        (col2, left2, pal["accent2"])
    ]):
        for i, item in enumerate(items):
            y = top + hdr_h + Inches(0.15) + i * Inches(0.7)
            if y + Inches(0.6) > H - Inches(0.5):
                break
            card = add_rounded_rect(slide, x, y, col_w, Inches(0.6), WHITE, CARD_BORDER)
            add_rect(slide, x, y + Inches(0.08), Pt(4), Inches(0.44), ac)
            add_text(slide, item,
                     x + Inches(0.25), y + Inches(0.1), col_w - Inches(0.5), Inches(0.4),
                     font_size=12, color=DARK_TEXT)

    add_footer(slide, pal, idx, total)


def make_timeline_slide(prs, s, idx, total, pal):
    """Timeline / process steps."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    n = min(len(items), 5)
    step_w = Inches(2.2)
    gap = Inches(0.3)
    total_width = n * step_w.emu + (n - 1) * gap.emu
    start_x = (W.emu - total_width) // 2
    y = Inches(2.0)
    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"], pal["accent4"]]

    for i, item in enumerate(items[:n]):
        x = start_x + i * (step_w.emu + gap.emu)
        ac = accents[i % len(accents)]

        # Step card
        card = add_rounded_rect(slide, x, y, step_w, Inches(4.2), WHITE, CARD_BORDER)

        # Top colored section
        add_rect(slide, x, y, step_w, Inches(0.06), ac)

        # Number circle
        circ = add_circle(slide, x + step_w.emu // 2 - Inches(0.35).emu, y + Inches(0.3),
                          Inches(0.7), ac)
        add_text(slide, str(i + 1),
                 x + step_w.emu // 2 - Inches(0.35).emu, y + Inches(0.35),
                 Inches(0.7), Inches(0.6),
                 font_size=22, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

        # Step name
        add_text(slide, item.get("step", ""),
                 x + Inches(0.15), y + Inches(1.2), step_w - Inches(0.3), Inches(0.5),
                 font_size=14, bold=True, color=DARK_TEXT, align=PP_ALIGN.CENTER)

        # Description
        add_text(slide, item.get("desc", ""),
                 x + Inches(0.15), y + Inches(1.75), step_w - Inches(0.3), Inches(2.0),
                 font_size=11, color=MID_TEXT, align=PP_ALIGN.CENTER)

        # Arrow between steps
        if i < n - 1:
            arrow_x = x + step_w.emu + gap.emu // 4
            add_text(slide, "→",
                     arrow_x, y + Inches(1.0), Inches(0.3), Inches(0.5),
                     font_size=20, color=LIGHT_TEXT, align=PP_ALIGN.CENTER)

    add_footer(slide, pal, idx, total)


def make_pillars_slide(prs, s, idx, total, pal):
    """3-4 pillar cards side by side with bullet points."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    n = min(len(items), 4)
    col_w = Inches(2.8) if n >= 4 else Inches(3.5) if n == 3 else Inches(5.5)
    gap = Inches(0.3)
    total_width = n * col_w.emu + (n - 1) * gap.emu
    start_x = (W.emu - total_width) // 2
    y = Inches(1.5)
    card_h = Inches(5.0)
    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"]]

    for i, item in enumerate(items[:n]):
        x = start_x + i * (col_w.emu + gap.emu)
        ac = accents[i % len(accents)]

        # Card
        card = add_rounded_rect(slide, x, y, col_w, card_h, WHITE, CARD_BORDER)

        # Top accent bar
        add_rect(slide, x, y, col_w, Inches(0.06), ac)

        # Icon circle
        circ_x = x + col_w.emu // 2 - Inches(0.3).emu
        add_circle(slide, circ_x, y + Inches(0.3), Inches(0.6), pal["primary_l"])
        add_text(slide, ICONS[i % len(ICONS)],
                 circ_x, y + Inches(0.3), Inches(0.6), Inches(0.6),
                 font_size=18, align=PP_ALIGN.CENTER)

        # Pillar title
        add_text(slide, item.get("title", ""),
                 x + Inches(0.15), y + Inches(1.1), col_w - Inches(0.3), Inches(0.5),
                 font_size=14, bold=True, color=ac, align=PP_ALIGN.CENTER)

        # Bullet points
        bullets = item.get("bullets", [])
        for bi, b in enumerate(bullets[:5]):
            by = y + Inches(1.7) + bi * Inches(0.55)
            if by + Inches(0.4) > y + card_h:
                break
            add_text(slide, f"●  {b}",
                     x + Inches(0.2), by, col_w - Inches(0.4), Inches(0.5),
                     font_size=11, color=MID_TEXT)

    add_footer(slide, pal, idx, total)


def make_agenda_slide(prs, s, idx, total, pal):
    """Agenda / table of contents."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    start_y = Inches(1.4)
    row_h = Inches(0.72)
    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"],
               pal["accent4"], pal["accent5"], pal["primary"], pal["accent1"]]

    for i, item in enumerate(items[:8]):
        y = start_y + i * (row_h + Inches(0.08))
        if y + row_h > H - Inches(0.5):
            break
        ac = accents[i % len(accents)]

        # Row card
        card = add_rounded_rect(slide, Inches(0.6), y, Inches(12), row_h, WHITE, CARD_BORDER)

        # Number circle
        add_circle(slide, Inches(0.9), y + Inches(0.1), Inches(0.5), ac)
        add_text(slide, item.get("num", str(i + 1)),
                 Inches(0.9), y + Inches(0.1), Inches(0.5), Inches(0.5),
                 font_size=14, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

        # Title
        add_text(slide, item.get("title", ""),
                 Inches(1.7), y + Inches(0.08), Inches(4), Inches(0.35),
                 font_size=15, bold=True, color=DARK_TEXT)

        # Description
        add_text(slide, item.get("desc", ""),
                 Inches(1.7), y + Inches(0.38), Inches(9), Inches(0.3),
                 font_size=11, color=MID_TEXT)

    add_footer(slide, pal, idx, total)


def make_roles_slide(prs, s, idx, total, pal):
    """Roles / team structure slide."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    n = min(len(items), 3)
    col_w = Inches(3.8) if n == 3 else Inches(5.5)
    gap = Inches(0.35)
    total_width = n * col_w.emu + (n - 1) * gap.emu
    start_x = (W.emu - total_width) // 2
    y = Inches(1.5)
    card_h = Inches(5.2)
    accents = [pal["primary"], pal["accent1"], pal["accent2"]]

    for i, item in enumerate(items[:n]):
        x = start_x + i * (col_w.emu + gap.emu)
        ac = accents[i % len(accents)]

        # Card
        add_rounded_rect(slide, x, y, col_w, card_h, WHITE, CARD_BORDER)
        add_rect(slide, x, y, col_w, Inches(0.06), ac)

        # Role icon
        circ_x = x + col_w.emu // 2 - Inches(0.35).emu
        add_circle(slide, circ_x, y + Inches(0.25), Inches(0.7), ac)
        add_text(slide, ICONS[(i + 5) % len(ICONS)],
                 circ_x, y + Inches(0.28), Inches(0.7), Inches(0.7),
                 font_size=20, align=PP_ALIGN.CENTER)

        # Role name
        add_text(slide, item.get("role", ""),
                 x + Inches(0.1), y + Inches(1.1), col_w - Inches(0.2), Inches(0.45),
                 font_size=16, bold=True, color=ac, align=PP_ALIGN.CENTER)

        # Type badge
        if item.get("type"):
            badge = add_rounded_rect(slide,
                                     x + col_w.emu // 2 - Inches(1.2).emu, y + Inches(1.55),
                                     Inches(2.4), Inches(0.35), pal["primary_l"])
            add_text(slide, item["type"],
                     x + col_w.emu // 2 - Inches(1.1).emu, y + Inches(1.58),
                     Inches(2.2), Inches(0.3),
                     font_size=10, color=pal["primary"], align=PP_ALIGN.CENTER, italic=True)

        # Responsibilities
        bullets = item.get("bullets", [])
        for bi, b in enumerate(bullets[:5]):
            by = y + Inches(2.1) + bi * Inches(0.55)
            if by + Inches(0.4) > y + card_h:
                break
            add_text(slide, f"●  {b}",
                     x + Inches(0.2), by, col_w - Inches(0.4), Inches(0.5),
                     font_size=11, color=MID_TEXT)

    add_footer(slide, pal, idx, total)


def make_okr_slide(prs, s, idx, total, pal):
    """OKR / objectives and key results."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    start_y = Inches(1.4)
    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"], pal["accent4"]]

    for i, item in enumerate(items[:5]):
        ac = accents[i % len(accents)]
        y = start_y + i * Inches(1.1)
        if y + Inches(0.95) > H - Inches(0.5):
            break

        # Row card
        add_rounded_rect(slide, Inches(0.5), y, Inches(12.3), Inches(0.95), WHITE, CARD_BORDER)
        add_rect(slide, Inches(0.5), y + Inches(0.1), Pt(5), Inches(0.75), ac)

        # Objective
        add_text(slide, item.get("objective", ""),
                 Inches(0.85), y + Inches(0.08), Inches(3.5), Inches(0.4),
                 font_size=14, bold=True, color=ac)

        # Key Results
        krs = item.get("krs", [])
        for ki, kr in enumerate(krs[:3]):
            kx = Inches(4.5) + ki * Inches(2.7)
            add_text(slide, f"✓  {kr}",
                     kx, y + Inches(0.1), Inches(2.6), Inches(0.7),
                     font_size=10, color=MID_TEXT)

    add_footer(slide, pal, idx, total)


def make_principles_slide(prs, s, idx, total, pal):
    """Principles / values grid."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_light(slide)

    add_header_bar(slide, pal, s["title"], s.get("note", ""), str(idx), str(total))

    items = s.get("items", [])
    if not items:
        return

    cols = 2
    col_w = Inches(5.8)
    card_h = Inches(1.3)
    gap_x = Inches(0.5)
    gap_y = Inches(0.15)
    start_y = Inches(1.4)
    accents = [pal["primary"], pal["accent1"], pal["accent2"], pal["accent3"], pal["accent4"], pal["accent5"]]

    for i, item in enumerate(items[:6]):
        col = i % cols
        row = i // cols
        x = Inches(0.5) + col * (col_w + gap_x)
        y = start_y + row * (card_h + gap_y)
        ac = accents[i % len(accents)]

        if y + card_h > H - Inches(0.5):
            break

        # Card
        add_rounded_rect(slide, x, y, col_w, card_h, WHITE, CARD_BORDER)
        add_rect(slide, x, y + Inches(0.12), Pt(5), card_h - Inches(0.24), ac)

        # Icon
        add_circle(slide, x + Inches(0.2), y + Inches(0.2), Inches(0.5), pal["primary_l"])
        add_text(slide, ICONS[i % len(ICONS)],
                 x + Inches(0.22), y + Inches(0.22), Inches(0.5), Inches(0.5),
                 font_size=14, align=PP_ALIGN.CENTER)

        # Title
        add_text(slide, item.get("title", ""),
                 x + Inches(0.85), y + Inches(0.12), col_w - Inches(1.1), Inches(0.35),
                 font_size=14, bold=True, color=ac)

        # Description
        add_text(slide, item.get("desc", ""),
                 x + Inches(0.85), y + Inches(0.5), col_w - Inches(1.1), Inches(0.7),
                 font_size=11, color=MID_TEXT)

    add_footer(slide, pal, idx, total)


def make_summary_slide(prs, s, idx, total, pal):
    """Summary / closing slide."""
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg_white(slide)

    # Top and bottom bars
    add_rect(slide, Inches(0), Inches(0), W, Inches(0.08), pal["primary"])
    add_rect(slide, Inches(0), H - Inches(0.08), W, Inches(0.08), pal["primary"])

    # Centered title
    add_text(slide, s["title"],
             Inches(1), Inches(1.5), Inches(11.3), Inches(1.2),
             font_size=32, bold=True, color=pal["header_bg"], align=PP_ALIGN.CENTER,
             font_name="Segoe UI Black")

    # Decorative line
    add_rect(slide, Inches(5.5), Inches(2.8), Inches(2.3), Pt(4), pal["primary"])

    # Summary bullets
    bullets = s.get("bullets", [])
    if bullets:
        for i, b in enumerate(bullets):
            y = Inches(3.3) + i * Inches(0.65)
            if y > H - Inches(1.2):
                break

            add_rounded_rect(slide, Inches(1.5), y, Inches(10.3), Inches(0.55), pal["primary_l"])
            add_text(slide, f"●  {b}",
                     Inches(1.8), y + Inches(0.08), Inches(9.5), Inches(0.4),
                     font_size=13, color=pal["primary"])

    # Note
    if s.get("note"):
        add_text(slide, s["note"],
                 Inches(2), H - Inches(1.3), Inches(9.3), Inches(0.5),
                 font_size=12, color=MID_TEXT, align=PP_ALIGN.CENTER, italic=True)

    add_footer(slide, pal, idx, total)


# ═══════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════

LAYOUT_MAP = {
    "bullets":    make_bullets_slide,
    "stats":      make_stats_slide,
    "chart":      make_chart_slide,
    "two-col":    make_two_col_slide,
    "timeline":   make_timeline_slide,
    "pillars":    make_pillars_slide,
    "agenda":     make_agenda_slide,
    "roles":      make_roles_slide,
    "okr":        make_okr_slide,
    "principles": make_principles_slide,
}


def generate(slides_json_str, output_path):
    slides = json.loads(slides_json_str)
    total = len(slides)
    pal = get_palette(0)

    prs = Presentation()
    prs.slide_width = W
    prs.slide_height = H

    for i, s in enumerate(slides):
        idx = i + 1
        layout = s.get("layout", "bullets")

        if i == 0:
            make_cover(prs, s, idx, total, pal)
        elif i == total - 1:
            make_summary_slide(prs, s, idx, total, pal)
        elif layout in LAYOUT_MAP:
            LAYOUT_MAP[layout](prs, s, idx, total, pal)
        else:
            make_bullets_slide(prs, s, idx, total, pal)

        # Speaker notes
        if s.get("note"):
            slide = prs.slides[-1]
            notes = slide.notes_slide
            notes.notes_text_frame.text = s["note"]

    prs.save(output_path)
    print(f"OK:{output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: generate_pptx.py <slides_json> <output_path>", file=sys.stderr)
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
