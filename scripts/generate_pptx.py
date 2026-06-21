#!/usr/bin/env python3
"""
Generate a professional PPTX from slide JSON.
Usage: python3 generate_pptx.py <slides_json> <output_path>
slides_json: JSON string of [{title, bullets, note}, ...]
"""
import sys, json
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches, Pt

# ── Theme ────────────────────────────────────────────────────────────────────
DARK_BG      = RGBColor(0x0F, 0x17, 0x2A)   # slate-950
ACCENT       = RGBColor(0x81, 0x8C, 0xF8)   # indigo-400
ACCENT_ALT   = [
    RGBColor(0x38, 0xBD, 0xF8),  # sky-400
    RGBColor(0x34, 0xD3, 0x99),  # emerald-400
    RGBColor(0xFB, 0x92, 0x3C),  # orange-400
    RGBColor(0xF4, 0x72, 0xB6),  # pink-400
    RGBColor(0xA7, 0x8B, 0xFA),  # violet-400
]
WHITE        = RGBColor(0xFF, 0xFF, 0xFF)
LIGHT_GRAY   = RGBColor(0xCB, 0xD5, 0xE1)  # slate-300
DARK_CARD    = RGBColor(0x1E, 0x29, 0x3B)  # slate-800

W = Inches(13.33)   # 16:9 widescreen
H = Inches(7.5)


def rgb_hex(rgb):
    return "#{:02X}{:02X}{:02X}".format(rgb[0], rgb[1], rgb[2])


def set_bg(slide, color):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color


def add_text_box(slide, text, left, top, width, height,
                 font_size=18, bold=False, color=WHITE,
                 align=PP_ALIGN.LEFT, italic=False):
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    run.font.size = Pt(font_size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    return txBox


def add_accent_bar(slide, color, top_offset=Inches(0.55)):
    """Thin horizontal bar below header."""
    bar = slide.shapes.add_shape(
        1,  # MSO_SHAPE_TYPE.RECTANGLE
        Inches(0), top_offset, W, Pt(3)
    )
    bar.fill.solid()
    bar.fill.fore_color.rgb = color
    bar.line.fill.background()


def add_bullet_card(slide, bullets, left, top, width, height, accent_color):
    """Dark card with bullet points."""
    card = slide.shapes.add_shape(1, left, top, width, height)
    card.fill.solid()
    card.fill.fore_color.rgb = DARK_CARD
    card.line.color.rgb = accent_color
    card.line.width = Pt(1)

    tf = card.text_frame
    tf.word_wrap = True
    tf.margin_left  = Inches(0.2)
    tf.margin_top   = Inches(0.15)
    tf.margin_right = Inches(0.2)

    for i, bullet in enumerate(bullets):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_before = Pt(6)
        # bullet dot
        dot = p.add_run()
        dot.text = "● "
        dot.font.size = Pt(11)
        dot.font.color.rgb = accent_color
        dot.font.bold = True
        # text
        run = p.add_run()
        run.text = bullet
        run.font.size = Pt(14)
        run.font.color.rgb = LIGHT_GRAY


def make_cover(prs, slide_data, idx):
    """Title slide (first slide)."""
    layout = prs.slide_layouts[6]  # blank
    slide = prs.slides.add_slide(layout)
    set_bg(slide, DARK_BG)

    color = ACCENT

    # Top accent bar
    bar = slide.shapes.add_shape(1, Inches(0), Inches(0), W, Inches(0.08))
    bar.fill.solid(); bar.fill.fore_color.rgb = color; bar.line.fill.background()

    # Bottom accent bar
    bar2 = slide.shapes.add_shape(1, Inches(0), H - Inches(0.08), W, Inches(0.08))
    bar2.fill.solid(); bar2.fill.fore_color.rgb = color; bar2.line.fill.background()

    # Big vertical accent strip left
    strip = slide.shapes.add_shape(1, Inches(0), Inches(0.08), Inches(0.25), H - Inches(0.16))
    strip.fill.solid(); strip.fill.fore_color.rgb = color; strip.line.fill.background()

    # Title
    add_text_box(slide, slide_data["title"],
                 Inches(1), Inches(2.2), Inches(11.3), Inches(2),
                 font_size=40, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

    # Subtitle bullets (if any)
    if slide_data.get("bullets"):
        subtitle = " · ".join(slide_data["bullets"])
        add_text_box(slide, subtitle,
                     Inches(1.5), Inches(4.4), Inches(10), Inches(1),
                     font_size=18, color=LIGHT_GRAY, align=PP_ALIGN.CENTER, italic=True)

    # Slide number badge
    add_text_box(slide, "01",
                 W - Inches(1.2), H - Inches(0.7), Inches(0.8), Inches(0.5),
                 font_size=12, color=color, align=PP_ALIGN.RIGHT)


def make_content_slide(prs, slide_data, idx, total):
    """Standard content slide."""
    layout = prs.slide_layouts[6]
    slide = prs.slides.add_slide(layout)
    set_bg(slide, DARK_BG)

    color = ACCENT_ALT[(idx - 1) % len(ACCENT_ALT)]

    # Header background strip
    hdr = slide.shapes.add_shape(1, Inches(0), Inches(0), W, Inches(1.1))
    hdr.fill.solid(); hdr.fill.fore_color.rgb = DARK_CARD; hdr.line.fill.background()

    # Header accent bar
    add_accent_bar(slide, color, Inches(1.1))

    # Slide number left in header
    add_text_box(slide, f"{idx:02d} / {total:02d}",
                 Inches(0.3), Inches(0.25), Inches(1.5), Inches(0.6),
                 font_size=11, color=color, bold=True)

    # Title
    add_text_box(slide, slide_data["title"],
                 Inches(2), Inches(0.18), Inches(10.5), Inches(0.75),
                 font_size=22, bold=True, color=WHITE)

    # Bullets
    bullets = slide_data.get("bullets", [])
    if bullets:
        add_bullet_card(slide, bullets,
                        Inches(0.4), Inches(1.4),
                        Inches(12.5), Inches(5.5), color)

    # Speaker note
    if slide_data.get("note"):
        notes_slide = slide.notes_slide
        tf = notes_slide.notes_text_frame
        tf.text = slide_data["note"]


def make_summary_slide(prs, slide_data, idx, total):
    """Last / summary slide."""
    layout = prs.slide_layouts[6]
    slide = prs.slides.add_slide(layout)
    set_bg(slide, DARK_BG)

    color = ACCENT

    bar = slide.shapes.add_shape(1, Inches(0), Inches(0), W, Inches(0.08))
    bar.fill.solid(); bar.fill.fore_color.rgb = color; bar.line.fill.background()

    add_text_box(slide, slide_data["title"],
                 Inches(1), Inches(1.8), Inches(11.3), Inches(1.2),
                 font_size=30, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

    bullets = slide_data.get("bullets", [])
    if bullets:
        add_bullet_card(slide, bullets,
                        Inches(1.5), Inches(3.2),
                        Inches(10.3), Inches(3.5), color)

    add_text_box(slide, f"{idx:02d} / {total:02d}",
                 W - Inches(1.2), H - Inches(0.7), Inches(0.8), Inches(0.5),
                 font_size=12, color=color, align=PP_ALIGN.RIGHT)


def generate(slides_json_str, output_path):
    slides = json.loads(slides_json_str)
    total  = len(slides)

    prs = Presentation()
    prs.slide_width  = W
    prs.slide_height = H

    for i, s in enumerate(slides):
        if i == 0:
            make_cover(prs, s, i + 1)
        elif i == total - 1:
            make_summary_slide(prs, s, i + 1, total)
        else:
            make_content_slide(prs, s, i + 1, total)

    prs.save(output_path)
    print(f"OK:{output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: generate_pptx.py <slides_json> <output_path>", file=sys.stderr)
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
