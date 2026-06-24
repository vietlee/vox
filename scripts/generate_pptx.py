#!/usr/bin/env python3
"""
Generate a professional PPTX matching cowork quality level.
Usage: python3 generate_pptx.py <slides_json> <output_path> [theme]
"""
import sys, json, math, io, tempfile, os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.chart import XL_CHART_TYPE
from pptx.chart.data import CategoryChartData
from PIL import Image, ImageDraw

SW = 9144000   # 10.00"
SH = 5143500   # 5.625"

def I(inches):
    return int(inches * 914400)

THEMES = {
    "green": {
        "cover_bg":   (0x1B, 0x43, 0x32),
        "primary_dk": (0x1B, 0x43, 0x32),
        "primary":    (0x2D, 0x6A, 0x4F),
        "primary_lt": (0x74, 0xC6, 0x9D),
        "primary_xl": (0xD8, 0xF3, 0xDC),
        "accent":     (0xE8, 0x60, 0x2C),
        "accent3":    (0x40, 0x91, 0x6C),
        "accent4":    (0x52, 0xB7, 0x88),
        "content_bg": (0xF4, 0xF6, 0xFB),
        "card_bgs":   [(0xE8,0xF8,0xF1),(0xEA,0xF2,0xFF),(0xF1,0xEC,0xFE),(0xFF,0xF6,0xE5)],
        "card_icons": [(0x10,0xB9,0x81),(0x2E,0x5B,0xFF),(0x8B,0x5C,0xF6),(0xF5,0x9E,0x0B)],
    },
    "blue": {
        "cover_bg":   (0x1E, 0x3A, 0x5F),
        "primary_dk": (0x1E, 0x3A, 0x5F),
        "primary":    (0x3B, 0x82, 0xF6),
        "primary_lt": (0x93, 0xC5, 0xFD),
        "primary_xl": (0xDB, 0xEA, 0xFE),
        "accent":     (0xF5, 0x9E, 0x0B),
        "accent3":    (0x06, 0xB6, 0xD4),
        "accent4":    (0x60, 0xA5, 0xFA),
        "content_bg": (0xF4, 0xF6, 0xFB),
        "card_bgs":   [(0xEA,0xF2,0xFF),(0xE8,0xF8,0xF1),(0xF1,0xEC,0xFE),(0xFF,0xF6,0xE5)],
        "card_icons": [(0x2E,0x5B,0xFF),(0x10,0xB9,0x81),(0x8B,0x5C,0xF6),(0xF5,0x9E,0x0B)],
    },
    "purple": {
        "cover_bg":   (0x31, 0x30, 0x8C),
        "primary_dk": (0x31, 0x30, 0x8C),
        "primary":    (0x7C, 0x3A, 0xED),
        "primary_lt": (0xC4, 0xB5, 0xFD),
        "primary_xl": (0xED, 0xE9, 0xFE),
        "accent":     (0xEC, 0x48, 0x99),
        "accent3":    (0x8B, 0x5C, 0xF6),
        "accent4":    (0xA7, 0x8B, 0xFA),
        "content_bg": (0xF4, 0xF6, 0xFB),
        "card_bgs":   [(0xF1,0xEC,0xFE),(0xEA,0xF2,0xFF),(0xFD,0xEC,0xEC),(0xFF,0xF6,0xE5)],
        "card_icons": [(0x8B,0x5C,0xF6),(0x2E,0x5B,0xFF),(0xEF,0x44,0x44),(0xF5,0x9E,0x0B)],
    },
    "red": {
        "cover_bg":   (0x7F, 0x1D, 0x1D),
        "primary_dk": (0x7F, 0x1D, 0x1D),
        "primary":    (0xDC, 0x26, 0x26),
        "primary_lt": (0xFC, 0xA5, 0xA5),
        "primary_xl": (0xFE, 0xE2, 0xE2),
        "accent":     (0xF5, 0x9E, 0x0B),
        "accent3":    (0xEF, 0x44, 0x44),
        "accent4":    (0xF8, 0x71, 0x71),
        "content_bg": (0xF4, 0xF6, 0xFB),
        "card_bgs":   [(0xFD,0xEC,0xEC),(0xEA,0xF2,0xFF),(0xFF,0xF6,0xE5),(0xE8,0xF8,0xF1)],
        "card_icons": [(0xEF,0x44,0x44),(0x2E,0x5B,0xFF),(0xF5,0x9E,0x0B),(0x10,0xB9,0x81)],
    },
    "teal": {
        "cover_bg":   (0x13, 0x47, 0x4E),
        "primary_dk": (0x13, 0x47, 0x4E),
        "primary":    (0x0D, 0x94, 0x88),
        "primary_lt": (0x5E, 0xEA, 0xD4),
        "primary_xl": (0xCC, 0xFB, 0xF1),
        "accent":     (0xF5, 0x9E, 0x0B),
        "accent3":    (0x14, 0xB8, 0xA6),
        "accent4":    (0x2D, 0xD4, 0xBF),
        "content_bg": (0xF4, 0xF6, 0xFB),
        "card_bgs":   [(0xE8,0xF8,0xF1),(0xEA,0xF2,0xFF),(0xF1,0xEC,0xFE),(0xFF,0xF6,0xE5)],
        "card_icons": [(0x10,0xB9,0x81),(0x2E,0x5B,0xFF),(0x8B,0x5C,0xF6),(0xF5,0x9E,0x0B)],
    },
    "amber": {
        "cover_bg":   (0x78, 0x35, 0x0F),
        "primary_dk": (0x78, 0x35, 0x0F),
        "primary":    (0xD9, 0x77, 0x06),
        "primary_lt": (0xFC, 0xD3, 0x4D),
        "primary_xl": (0xFE, 0xF3, 0xC7),
        "accent":     (0xEF, 0x44, 0x44),
        "accent3":    (0xF5, 0x9E, 0x0B),
        "accent4":    (0xFB, 0xBF, 0x24),
        "content_bg": (0xF4, 0xF6, 0xFB),
        "card_bgs":   [(0xFF,0xF6,0xE5),(0xEA,0xF2,0xFF),(0xE8,0xF8,0xF1),(0xF1,0xEC,0xFE)],
        "card_icons": [(0xF5,0x9E,0x0B),(0x2E,0x5B,0xFF),(0x10,0xB9,0x81),(0x8B,0x5C,0xF6)],
    },
    "slate": {
        "cover_bg":   (0x1E, 0x29, 0x3B),
        "primary_dk": (0x1E, 0x29, 0x3B),
        "primary":    (0x47, 0x55, 0x69),
        "primary_lt": (0x94, 0xA3, 0xB8),
        "primary_xl": (0xE2, 0xE8, 0xF0),
        "accent":     (0x3B, 0x82, 0xF6),
        "accent3":    (0x64, 0x74, 0x8B),
        "accent4":    (0x94, 0xA3, 0xB8),
        "content_bg": (0xF4, 0xF6, 0xFB),
        "card_bgs":   [(0xEA,0xF2,0xFF),(0xE8,0xF8,0xF1),(0xF1,0xEC,0xFE),(0xFF,0xF6,0xE5)],
        "card_icons": [(0x2E,0x5B,0xFF),(0x10,0xB9,0x81),(0x8B,0x5C,0xF6),(0xF5,0x9E,0x0B)],
    },
}

T = None
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
DARK  = RGBColor(0x1F, 0x2A, 0x44)
MID   = RGBColor(0x5B, 0x64, 0x78)

LM = I(0.60)
CW = SW - LM * 2   # 8.80"

def _rgb(tup):
    return RGBColor(*tup)

def _resolve_theme(name):
    raw = THEMES.get(name, THEMES["blue"])
    resolved = {}
    for k, v in raw.items():
        if isinstance(v, tuple):
            resolved[k] = _rgb(v)
        elif isinstance(v, list) and v and isinstance(v[0], tuple):
            resolved[k] = [_rgb(c) for c in v]
        else:
            resolved[k] = v
    return resolved

def _accents():
    return T.get("card_icons", [T["primary_dk"], T["primary"], T["accent"], T["accent3"]])

def _card_bgs():
    return T.get("card_bgs", [T["primary_xl"], T["primary_xl"], T["primary_xl"], T["primary_xl"]])

# ── Icon system ──────────────────────────────────────────────────────
_icon_cache = {}
_ICONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")
_ICON_NAMES = [
    "search", "filter", "store", "check", "clock", "person", "people",
    "rocket", "code", "chart", "money", "percent", "megaphone", "crown",
    "lightbulb", "shield", "star", "heart", "globe", "target",
    "handshake", "leaf", "phone", "truck", "default"
]

_ICON_KEYWORDS = {
    "search": ["tìm", "tìm kiếm", "search", "khó tìm", "lọc", "phát hiện"],
    "filter": ["bộ lọc", "filter", "phân loại", "sàng lọc"],
    "store": ["cửa hàng", "store", "shop", "restaurant"],
    "check": ["kiểm", "xác minh", "verify", "đạt chuẩn", "chất lượng", "đảm bảo"],
    "clock": ["thời gian", "phút", "giờ", "time"],
    "person": ["người", "khách", "user", "cá nhân", "founder", "CEO"],
    "people": ["cộng đồng", "nhóm", "team", "đội", "community", "người dùng"],
    "rocket": ["tăng trưởng", "phát triển", "growth", "launch", "mở rộng", "scale"],
    "code": ["công nghệ", "tech", "AI", "app", "ứng dụng", "phần mềm", "platform"],
    "chart": ["doanh thu", "revenue", "số liệu", "KPI", "metric", "thống kê"],
    "money": ["vốn", "đầu tư", "tiền", "USD", "fund", "tài chính", "chi phí", "hoa hồng", "doanh thu", "revenue", "phí"],
    "percent": ["tỷ lệ", "%", "phần trăm", "rate", "margin", "lợi nhuận"],
    "megaphone": ["marketing", "quảng cáo", "truyền thông", "ads", "kênh"],
    "crown": ["premium", "VIP", "cao cấp", "hàng đầu", "leader", "dẫn đầu"],
    "lightbulb": ["giải pháp", "ý tưởng", "idea", "solution", "sáng tạo", "đổi mới"],
    "shield": ["bảo vệ", "an toàn", "security", "trust", "uy tín", "tin cậy"],
    "star": ["đánh giá", "review", "rating", "chất lượng", "nổi bật"],
    "heart": ["yêu thích", "sức khỏe", "health", "thuần chay", "vegan"],
    "globe": ["thị trường", "quốc tế", "global", "thế giới", "khu vực"],
    "target": ["mục tiêu", "target", "chiến lược", "strategy", "định hướng"],
    "handshake": ["đối tác", "partner", "hợp tác", "B2B", "liên kết", "đồng hành"],
    "leaf": ["xanh", "green", "eco", "bền vững", "organic", "thuần chay", "chay"],
    "phone": ["mobile", "điện thoại", "app", "đặt hàng", "order"],
    "truck": ["giao hàng", "delivery", "vận chuyển", "logistics", "ship", "nhanh", "30 phút"],
}

def _pick_icon(text, icon_hint=None):
    if icon_hint and icon_hint in _ICON_NAMES:
        return icon_hint
    text_lower = text.lower()
    best, best_score = "default", 0
    for icon_name, keywords in _ICON_KEYWORDS.items():
        score = sum(len(kw) for kw in keywords if kw.lower() in text_lower)
        if score > best_score:
            best, best_score = icon_name, score
    return best

def _load_icon_png(icon_name, size=120):
    key = ("icon_file", icon_name, size)
    if key in _icon_cache:
        return _icon_cache[key]
    path = os.path.join(_ICONS_DIR, f"{icon_name}.png")
    if not os.path.exists(path):
        path = os.path.join(_ICONS_DIR, "default.png")
    img = Image.open(path).resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    _icon_cache[key] = buf.getvalue()
    return _icon_cache[key]

def _add_icon(slide, left, top, size, rgb_color, icon_name="default", avatar=False):
    if avatar:
        icon_name = "person"
    png = _load_icon_png(icon_name, size=256)
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp.write(png); tmp.close()
    pic = slide.shapes.add_picture(tmp.name, left, top, size, size)
    os.unlink(tmp.name)
    return pic

# ── Shape helpers ─────────────────────────────────────────────────────

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
    s = _shape(slide, MSO_SHAPE.ROUNDED_RECTANGLE, l, t, w, h, fill or WHITE, line)
    s.adjustments[0] = radius
    return s

def _oval(slide, cx, cy, r, fill):
    return _shape(slide, MSO_SHAPE.OVAL, cx-r, cy-r, r*2, r*2, fill)

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

def _tb2(slide, lines_data, l, t, w, h, align=PP_ALIGN.LEFT, font="Calibri"):
    """Multi-line text box: lines_data = [(text, sz, bold, color), ...]"""
    s = _shape(slide, MSO_SHAPE.RECTANGLE, l, t, w, h)
    s.fill.background()
    tf = s.text_frame; tf.word_wrap = True
    tf.margin_left = Pt(2); tf.margin_right = Pt(2)
    tf.margin_top = Pt(1); tf.margin_bottom = Pt(1)
    for i, (text, sz, bold, color) in enumerate(lines_data):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_before = Pt(0); p.space_after = Pt(2)
        r = p.add_run(); r.text = text
        r.font.size = Pt(sz); r.font.bold = bold; r.font.color.rgb = color; r.font.name = font
    return s

def _bg(slide, color):
    f = slide.background.fill; f.solid(); f.fore_color.rgb = color

# ── Content slide header ──────────────────────────────────────────────

def _style(s, key, default=None):
    return s.get("style", {}).get(key, default)

def _setup_content_slide(prs, s):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    is_dark = _style(s, "bg") == "dark"
    _bg(slide, T["cover_bg"] if is_dark else T["content_bg"])

    cat = _style(s, "category", "")
    if is_dark:
        if cat:
            _tb(slide, cat, LM, I(0.42), CW, I(0.35), sz=12, bold=True, color=T["primary_lt"], font="Calibri")
        _tb(slide, s["title"], LM, I(0.78), CW, I(0.70), sz=26, bold=True, color=WHITE, font="Calibri")
    else:
        if cat:
            _tb(slide, cat.upper(), I(0.00), I(0.35), SW, I(0.30), sz=12, bold=True, color=_accents()[0], font="Calibri", align=PP_ALIGN.CENTER)
        _tb(slide, s["title"], I(0.00), I(0.68), SW, I(0.55), sz=22, bold=True, color=DARK, font="Calibri", align=PP_ALIGN.CENTER)

    note = s.get("note", "")
    footer = s.get("footer", "")
    if note:
        _insight_bar(slide, note)
        if footer:
            _tb(slide, footer, LM, SH - I(0.35), I(8.0), I(0.25), sz=8, color=MID)
    elif footer:
        _tb(slide, footer, LM, SH - I(0.35), I(8.0), I(0.30), sz=9, color=MID)
    return slide, I(1.70)

def _page_num(slide, num, total):
    _tb(slide, f"{num:02d} / {total:02d}",
        SW - I(1.0), SH - I(0.30), I(0.90), I(0.25),
        sz=9, color=MID, align=PP_ALIGN.RIGHT)

def _insight_bar(slide, text):
    """RAPID-style: pastel bar at bottom with insight text"""
    bar_bg = _card_bgs()[0] if _card_bgs() else T["primary_xl"]
    _rrect(slide, LM, I(4.45), CW, I(0.68), bar_bg, radius=0.06)
    _tb(slide, text, LM + I(0.25), I(4.45), CW - I(0.50), I(0.68),
        sz=11, bold=True, color=DARK, font="Calibri")

# ── Chart helpers ─────────────────────────────────────────────────────

def _add_line_chart(slide, items, left, top, width, height):
    chart_data = CategoryChartData()
    chart_data.categories = [it.get("label", "") for it in items]
    chart_data.add_series("Data", [it.get("value", 0) for it in items])
    cf = slide.shapes.add_chart(XL_CHART_TYPE.LINE_MARKERS, left, top, width, height, chart_data)
    chart = cf.chart
    chart.has_legend = False
    chart.has_title = False
    series = chart.plots[0].series[0]
    series.format.line.color.rgb = T["primary"]
    series.format.line.width = Pt(2.5)
    series.marker.style = 8  # circle
    series.marker.size = 8
    series.marker.format.fill.solid()
    series.marker.format.fill.fore_color.rgb = T["primary"]
    val_axis = chart.value_axis
    val_axis.visible = False
    val_axis.has_title = False
    val_axis.major_gridlines.format.line.color.rgb = RGBColor(0xE0, 0xE0, 0xE0)
    val_axis.major_gridlines.format.line.width = Pt(0.5)
    cat_axis = chart.category_axis
    cat_axis.tick_labels.font.size = Pt(9)
    cat_axis.tick_labels.font.color.rgb = MID
    cat_axis.format.line.fill.background()
    cat_axis.major_tick_mark = 2
    series.has_data_labels = True
    dl = series.data_labels
    dl.font.size = Pt(10)
    dl.font.bold = True
    dl.font.color.rgb = T["primary_dk"]
    dl.number_format = '#,##0'
    return cf

def _add_bar_chart(slide, items, left, top, width, height, accents):
    chart_data = CategoryChartData()
    chart_data.categories = [it.get("label", "") for it in items]
    chart_data.add_series("Data", [it.get("value", 0) for it in items])
    cf = slide.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, left, top, width, height, chart_data)
    chart = cf.chart
    chart.has_legend = False
    chart.has_title = False
    plot = chart.plots[0]
    plot.gap_width = 80
    for i, pt in enumerate(plot.series[0].points):
        pt.format.fill.solid()
        pt.format.fill.fore_color.rgb = accents[i % len(accents)]
    chart.value_axis.visible = False
    chart.value_axis.has_title = False
    chart.value_axis.major_gridlines.format.line.fill.background()
    cat_axis = chart.category_axis
    cat_axis.tick_labels.font.size = Pt(9)
    cat_axis.tick_labels.font.color.rgb = MID
    cat_axis.format.line.fill.background()
    cat_axis.major_tick_mark = 2
    plot.series[0].has_data_labels = True
    dl = plot.series[0].data_labels
    dl.font.size = Pt(11); dl.font.bold = True; dl.font.color.rgb = T["primary_dk"]
    dl.number_format = '#,##0'
    return cf

def _add_donut_chart(slide, labels, values, left, top, width, height, accents):
    chart_data = CategoryChartData()
    chart_data.categories = labels
    chart_data.add_series("Data", values)
    cf = slide.shapes.add_chart(XL_CHART_TYPE.DOUGHNUT, left, top, width, height, chart_data)
    chart = cf.chart
    chart.has_legend = False
    chart.has_title = False
    for i, pt in enumerate(chart.plots[0].series[0].points):
        pt.format.fill.solid()
        pt.format.fill.fore_color.rgb = accents[i % len(accents)]
    return cf

# ═══════════════════════════════════════════════════════════════════════
# SLIDE BUILDERS — matching cowork layout patterns
# ═══════════════════════════════════════════════════════════════════════

def make_cover(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    is_dark = _style(s, "bg", "dark") == "dark"
    _bg(slide, T["cover_bg"] if is_dark else T["content_bg"])

    # Decorative circles (cowork cover exact: 7.40,-1.60 r2.60 and 8.60,3.00 r1.50)
    if is_dark:
        _oval(slide, I(10.00), I(1.00), I(2.60), T["primary"])
        _oval(slide, I(10.10), I(4.50), I(1.50), T["primary_dk"])

    # Logo: rounded-rect (cowork: 0.70,0.65 0.90x0.90)
    logo_bg = T["primary_lt"] if is_dark else T["primary_xl"]
    _rrect(slide, I(0.70), I(0.65), I(0.90), I(0.90), logo_bg, radius=0.15)
    _add_icon(slide, I(0.92), I(0.87), I(0.46), T["primary_dk"])

    cat = _style(s, "category", "")
    if cat:
        _tb(slide, cat, I(0.70), I(1.75), I(2.0), I(0.35),
            sz=12, bold=True, color=T["accent"])

    title_color = WHITE if is_dark else T["primary_dk"]
    title_y = I(2.05) if cat else I(1.75)
    _tb(slide, s["title"], I(0.65), title_y, I(8.50), I(1.30),
        sz=56, bold=True, color=title_color, font="Calibri")

    sub_color = T["primary_xl"] if is_dark else MID
    if s.get("subtitle"):
        _tb(slide, s["subtitle"], I(0.68), I(3.25), I(7.20), I(0.60),
            sz=18, color=sub_color)

    if s.get("bullets"):
        # Vertical bar + bullet text (cowork style)
        bar_color = WHITE if is_dark else T["primary_dk"]
        _rect(slide, I(0.70), I(4.55), Pt(3), I(0.40), bar_color)
        s_tf = _shape(slide, MSO_SHAPE.RECTANGLE, I(0.90), I(4.55), I(6.0), I(0.40))
        s_tf.fill.background(); s_tf.line.fill.background()
        tf = s_tf.text_frame; tf.word_wrap = True
        tf.margin_left = Pt(2); tf.margin_right = Pt(2)
        tf.margin_top = Pt(1); tf.margin_bottom = Pt(1)
        p = tf.paragraphs[0]; p.alignment = PP_ALIGN.LEFT
        p.space_before = Pt(0); p.space_after = Pt(0)
        for bi, bt in enumerate(s["bullets"][:3]):
            if bi > 0:
                r = p.add_run(); r.text = "   ·   "
                r.font.size = Pt(13); r.font.color.rgb = T["primary_xl"] if is_dark else MID; r.font.name = "Calibri"
            r = p.add_run(); r.text = bt
            r.font.size = Pt(13); r.font.name = "Calibri"
            r.font.bold = (bi == 0)
            r.font.color.rgb = WHITE if is_dark else T["primary_dk"]

    if s.get("footer"):
        _tb(slide, s["footer"], I(0.65), SH - I(0.48), I(7.0), I(0.30),
            sz=10, color=T["primary_lt"] if is_dark else MID)


def make_section(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["cover_bg"])
    _tb(slide, s["title"], I(0.5), I(1.3), SW - I(1.0), I(1.2),
        sz=30, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Calibri")
    if s.get("subtitle"):
        _tb(slide, s["subtitle"], I(0.8), I(2.9), SW - I(1.6), I(0.4),
            sz=12, color=T["primary_lt"], align=PP_ALIGN.CENTER)
    _page_num(slide, idx, total)


def make_bullets(prs, s, idx, total):
    """Cowork style: icon + title + desc directly on slide, NO card borders.
    3 items → 3-column. 4 items → 2x2 grid. ≥5 → stacked list."""
    slide, top = _setup_content_slide(prs, s)
    b_items = s.get("bullet_items", [])
    bullets = s.get("bullets", [])
    if not bullets and not b_items:
        _page_num(slide, idx, total); return

    n = len(b_items) if b_items else len(bullets)
    accents = _accents()
    bot = SH - I(0.50)

    if b_items and n == 3:
        # RAPID-style: pastel card bg + centered icon circle + title + desc
        gap = I(0.30)
        col_w = I(2.80)
        card_top = top + I(0.10)
        has_note = bool(s.get("note"))
        card_h = I(2.10) if has_note else I(2.55)
        icon_circle = I(0.60)
        icon_sz = I(0.30)
        cbgs = _card_bgs()
        for i, it in enumerate(b_items[:3]):
            ac = accents[i % len(accents)]
            bg = cbgs[i % len(cbgs)]
            x = LM + i * (col_w + gap)
            _rrect(slide, x, card_top, col_w, card_h, bg, radius=0.06)
            # Centered icon circle
            cx_icon = x + col_w // 2
            _oval(slide, cx_icon, card_top + I(0.20) + icon_circle//2, icon_circle//2, ac)
            title_text = it.get("title", "")
            ic = _pick_icon(title_text + " " + it.get("desc", ""), it.get("icon"))
            _add_icon(slide, cx_icon - icon_sz//2, card_top + I(0.20) + (icon_circle - icon_sz)//2, icon_sz, WHITE, icon_name=ic)
            # Title centered under icon
            tx = x + I(0.20)
            tw = col_w - I(0.40)
            t_top = I(0.95)
            _tb(slide, title_text, tx, card_top + t_top, tw, I(0.40),
                sz=13, bold=True, color=DARK, font="Calibri", align=PP_ALIGN.CENTER)
            if it.get("desc"):
                d_top = t_top + I(0.40)
                d_h = card_h - d_top - I(0.10)
                if d_h > I(0.15):
                    _tb(slide, it["desc"], tx, card_top + d_top, tw, d_h,
                        sz=10, color=MID, font="Calibri", align=PP_ALIGN.CENTER)

    elif b_items and n >= 2:
        # Stacked list with icon circle left
        icon_circle = I(0.50)
        icon_sz = I(0.26)
        has_note = bool(s.get("note"))
        list_bot = I(4.35) if has_note else bot
        avail = list_bot - top - I(0.15)
        row_h = min(I(0.85), avail // min(n, 6))
        list_top = top + I(0.15)
        tx = LM + I(0.75)
        content_w = I(7.80)
        for i, it in enumerate(b_items[:6]):
            ac = accents[i % len(accents)]
            y = list_top + i * row_h
            if y + I(0.50) > list_bot: break
            _oval(slide, LM + icon_circle//2, y + I(0.05) + icon_circle//2, icon_circle//2, ac)
            ic = _pick_icon(it.get("title","") + " " + it.get("desc",""), it.get("icon"))
            _add_icon(slide, LM + (icon_circle - icon_sz)//2, y + I(0.05) + (icon_circle - icon_sz)//2, icon_sz, WHITE, icon_name=ic)
            _tb(slide, it.get("title", ""), tx, y, I(7.50), I(0.30),
                sz=13, bold=True, color=DARK, font="Calibri")
            if it.get("desc"):
                _tb(slide, it["desc"], tx, y + I(0.30), content_w, I(0.45),
                    sz=10, color=MID, font="Calibri")
    else:
        # Simple bullets without desc — 3-column or stacked
        if n <= 3:
            gap = I(0.20)
            col_w = (CW - gap * (n - 1)) // n
            icon_sz = I(0.33)
            for i, b in enumerate(bullets[:n]):
                ac = accents[i % len(accents)]
                x = LM + I(0.25) + i * (col_w + gap)
                _add_icon(slide, x + I(0.16), top + I(0.56), icon_sz, ac, icon_name=_pick_icon(b))
                _tb(slide, b, x, top + I(1.15), col_w - I(0.50), I(0.55),
                    sz=14.5, bold=True, color=T["primary_dk"], font="Calibri")
        else:
            row_h = I(0.65)
            for i, b in enumerate(bullets[:8]):
                ac = accents[i % len(accents)]
                y = top + i * row_h
                if y + I(0.50) > bot: break
                icon_sz = I(0.26)
                _add_icon(slide, LM + I(0.16), y + I(0.10), icon_sz, ac, icon_name=_pick_icon(b))
                _tb(slide, b, LM + I(0.65), y + I(0.05), CW - I(0.80), I(0.50),
                    sz=13, bold=True, color=T["primary_dk"], font="Calibri")

    # Source bar if subtitle contains data
    if s.get("subtitle") and any(c.isdigit() for c in s.get("subtitle", "")):
        _insight_bar(slide, s["subtitle"])

    _page_num(slide, idx, total)


def make_stats(prs, s, idx, total):
    """Cowork slide 5 style: stats on left (dark cards) + optional chart on right."""
    slide, top_y = _setup_content_slide(prs, s)
    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 4)
    accents = _accents()

    # Check if we have chart data embedded
    chart_data = s.get("chart_items", [])
    has_chart = len(chart_data) >= 3

    if has_chart:
        stat_w = I(2.90)
        gap_y = I(0.15)
        has_note = bool(s.get("note"))
        card_h = I(1.20) if has_note else I(1.50)
        val_sz = 28 if has_note else 34
        val_top = I(0.10) if has_note else I(0.18)
        val_h = I(0.55) if has_note else I(0.75)
        lbl_top = I(0.65) if has_note else I(0.95)
        lbl_h = I(0.50) if has_note else I(0.50)
        for i, item in enumerate(items[:2]):
            ac = accents[i % len(accents)]
            cy = top_y + i * (card_h + gap_y)
            _rrect(slide, LM, cy, stat_w, card_h, T["primary_dk"], radius=0.05)
            _rect(slide, LM, cy, I(0.09), card_h, ac)
            _tb(slide, item.get("value", ""),
                LM + I(0.30), cy + val_top, stat_w - I(0.50), val_h,
                sz=val_sz, bold=True, color=WHITE, font="Calibri")
            _tb(slide, item.get("label", ""),
                LM + I(0.30), cy + lbl_top, stat_w - I(0.50), lbl_h,
                sz=10 if has_note else 11, color=T["primary_xl"])

        # Chart on right
        chart_items_parsed = []
        for it in chart_data:
            v = it.get("value", 0)
            if isinstance(v, str):
                v = int(''.join(c for c in v if c.isdigit()) or '0')
            chart_items_parsed.append({"label": it.get("label", ""), "value": v})

        chart_label = s.get("chart_label", "")
        if chart_label:
            _tb(slide, chart_label, I(3.85), top_y - I(0.15), I(5.60), I(0.30),
                sz=11, bold=True, color=T["primary_dk"])

        chart_h = I(2.05) if s.get("note") else I(2.95)
        _add_line_chart(slide, chart_items_parsed,
                        I(3.75), top_y + I(0.20), I(5.65), chart_h)
    else:
        # Standard stats layout
        if n <= 2:
            card_w = I(2.90)
            card_h = I(1.50)
            for i, item in enumerate(items[:n]):
                ac = accents[i % len(accents)]
                cy = top_y + i * (card_h + I(0.15))
                _rrect(slide, LM, cy, card_w, card_h, T["primary_dk"], radius=0.05)
                _rect(slide, LM, cy, I(0.09), card_h, ac)
                _tb(slide, item.get("value", ""),
                    LM + I(0.30), cy + I(0.18), card_w - I(0.50), I(0.75),
                    sz=34, bold=True, color=WHITE, font="Calibri")
                _tb(slide, item.get("label", ""),
                    LM + I(0.30), cy + I(0.95), card_w - I(0.50), I(0.50),
                    sz=11, color=T["primary_xl"])
        elif n == 3:
            # 3 stats in a row — wider cards
            gap = I(0.15)
            card_w = (CW - gap * 2) // 3
            card_h = I(1.50)
            for i, item in enumerate(items[:3]):
                ac = accents[i % len(accents)]
                x = LM + i * (card_w + gap)
                _rrect(slide, x, top_y, card_w, card_h, T["primary_dk"], radius=0.05)
                _rect(slide, x, top_y, I(0.09), card_h, ac)
                val = item.get("value", "")
                vsz = 28 if len(val) > 6 else 34
                _tb(slide, val,
                    x + I(0.20), top_y + I(0.10), card_w - I(0.40), I(0.65),
                    sz=vsz, bold=True, color=WHITE, font="Calibri")
                _tb(slide, item.get("label", ""),
                    x + I(0.20), top_y + I(0.80), card_w - I(0.40), I(0.60),
                    sz=10, color=T["primary_xl"])
        else:
            # 4+ stats → 2x2 grid
            gap_x, gap_y = I(0.15), I(0.15)
            card_w = (CW - gap_x) // 2
            card_h = I(1.35)
            for i, item in enumerate(items[:4]):
                ac = accents[i % len(accents)]
                c, r = i % 2, i // 2
                x = LM + c * (card_w + gap_x)
                cy = top_y + r * (card_h + gap_y)
                _rrect(slide, x, cy, card_w, card_h, T["primary_dk"], radius=0.05)
                _rect(slide, x, cy, I(0.09), card_h, ac)
                val = item.get("value", "")
                vsz = 28 if len(val) > 6 else 34
                _tb(slide, val,
                    x + I(0.25), cy + I(0.10), card_w - I(0.45), I(0.65),
                    sz=vsz, bold=True, color=WHITE, font="Calibri")
                _tb(slide, item.get("label", ""),
                    x + I(0.25), cy + I(0.80), card_w - I(0.45), I(0.50),
                    sz=10, color=T["primary_xl"])

    # Insight bar at bottom if available
    if s.get("insight"):
        _insight_bar(slide, s["insight"])

    _page_num(slide, idx, total)


def make_chart(prs, s, idx, total):
    """Bar or line chart. chart_type in style: 'line' or 'bar' (default bar)."""
    slide, top_y = _setup_content_slide(prs, s)
    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    chart_items = []
    for it in items[:8]:
        v = it.get("value", 0)
        if isinstance(v, str):
            v = int(''.join(c for c in v if c.isdigit()) or '0')
        chart_items.append({"label": it.get("label", ""), "value": v})

    chart_type = _style(s, "chart_type", "bar")
    avail_h = SH - top_y - I(0.55)

    if chart_type == "line":
        _add_line_chart(slide, chart_items, LM, top_y, CW, avail_h)
    else:
        _add_bar_chart(slide, chart_items, LM, top_y, CW, avail_h, _accents())

    _page_num(slide, idx, total)


def make_donut(prs, s, idx, total):
    """Cowork slide 7: donut chart left + legend items right."""
    slide, top_y = _setup_content_slide(prs, s)
    bot = SH - I(0.55)
    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 6)
    has_note = bool(s.get("note"))
    accents = _accents()
    labels = [it.get("label", "") for it in items[:n]]
    values = []
    for it in items[:n]:
        v = it.get("value", 0)
        if isinstance(v, str):
            v = int(''.join(c for c in v if c.isdigit()) or '0')
        values.append(v)

    total_val = sum(values) or 1

    # Donut on left — shrink when insight bar present
    chart_h = I(2.50) if has_note else I(3.60)
    _add_donut_chart(slide, labels, values, I(0.50), top_y - I(0.10), I(4.50), chart_h, accents)

    # Center text in donut
    center_text = s.get("center_text", "")
    center_sub = s.get("center_sub", "")
    if center_text:
        ct_y = I(2.40) if has_note else I(2.85)
        _tb2(slide, [
            (center_text, 18, True, T["primary_dk"]),
            (center_sub, 18, True, T["primary_dk"]),
        ], I(1.85), ct_y, I(1.80), I(1.10), align=PP_ALIGN.CENTER)

    # Legend items on right — dynamic spacing, respect insight bar
    legend_x = I(5.35)
    legend_y_start = top_y - I(0.05)
    has_note = bool(s.get("note"))
    legend_bot = I(4.35) if has_note else bot
    avail_h = legend_bot - legend_y_start
    item_h = min(I(0.82), avail_h // n) if n else I(0.82)
    icon_circle = I(0.50)
    icon_sz = I(0.26)
    legend_sz = 11.5 if n <= 4 else 10

    for i, it in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        y = legend_y_start + i * item_h
        if y + I(0.50) > legend_bot:
            break
        _oval(slide, legend_x + icon_circle//2, y + I(0.10) + icon_circle//2, icon_circle//2, ac)
        _add_icon(slide, legend_x + (icon_circle - icon_sz)//2, y + I(0.10) + (icon_circle - icon_sz)//2, icon_sz, WHITE, icon_name=_pick_icon(it.get("label","")))
        pct = round(values[i] / total_val * 100) if total_val else 0
        detail = it.get("detail", "")
        _tb2(slide, [
            (it.get("label", ""), legend_sz, True, T["primary_dk"]),
            (f"{pct}%  ·  {detail}" if detail else f"{pct}%", legend_sz, False, MID),
        ], legend_x + I(0.65), y, I(3.40), I(0.60))

    _page_num(slide, idx, total)


def make_two_col(prs, s, idx, total):
    """Two-column comparison: icon-left items, no card borders."""
    slide, top_y = _setup_content_slide(prs, s)
    col1, col2 = s.get("col1", []), s.get("col2", [])
    accents = _accents()
    gap_x = I(0.30)
    col_w = (CW - gap_x) // 2
    row_h = I(0.85)

    for ci, items in enumerate([col1, col2]):
        for i, item in enumerate(items[:5]):
            ac = accents[(ci * 5 + i) % len(accents)]
            x = LM + I(0.15) + ci * (col_w + gap_x)
            y = top_y + i * row_h
            if y + I(0.70) > SH - I(0.45): break
            icon_sz = I(0.26)
            _add_icon(slide, x, y + I(0.12), icon_sz, ac, icon_name=_pick_icon(item))
            _tb(slide, item, x + I(0.50), y + I(0.06), col_w - I(0.80), I(0.65),
                sz=12, bold=True, color=T["primary_dk"], font="Calibri")

    _page_num(slide, idx, total)


def make_timeline(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)
    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 5)
    gap = I(0.12)
    step_w = (CW - gap * (n - 1)) // n
    accents = _accents()
    card_h = I(2.50)

    _rect(slide, LM, top_y + I(0.50), CW, Pt(2), T["primary_xl"])

    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = LM + i * (step_w + gap)
        _rrect(slide, x, top_y, step_w, card_h, WHITE, radius=0.04)
        _rect(slide, x, top_y, step_w, I(0.04), ac)
        nsz = I(0.32)
        _oval(slide, x + step_w//2, top_y + I(0.22) + nsz//2, nsz//2, ac)
        _tb(slide, str(i+1), x + step_w//2 - nsz//2, top_y + I(0.22),
            nsz, nsz, sz=14, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("step", ""),
            x + I(0.08), top_y + I(0.58), step_w - I(0.16), I(0.35),
            sz=11, bold=True, color=ac, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("desc", ""),
            x + I(0.08), top_y + I(0.95), step_w - I(0.16), card_h - I(1.05),
            sz=9, color=DARK, align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


def make_pillars(prs, s, idx, total):
    """Cowork slide 4: 2x2 grid cards with icon + title + desc."""
    slide, top_y = _setup_content_slide(prs, s)
    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    n = min(len(items), 4)
    accents = _accents()
    top_y = top_y - I(0.05)
    gap_x = I(0.30)
    gap_y = I(0.20)
    cols = 2 if n >= 2 else 1
    rows = (n + cols - 1) // cols
    col_w = I(4.35)
    card_h = I(2.80) if rows == 1 else I(1.55)
    icon_circle = I(0.60)
    icon_sz = I(0.30)

    cbgs = _card_bgs()
    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        bg = cbgs[i % len(cbgs)]
        c, r = i % cols, i // cols
        x = LM + c * (col_w + gap_x)
        y = top_y + r * (card_h + gap_y)
        _rrect(slide, x, y, col_w, card_h, bg, radius=0.06)
        _oval(slide, x + I(0.22) + icon_circle//2, y + I(0.22) + icon_circle//2, icon_circle//2, ac)
        ic = _pick_icon(item.get("title","") + " " + " ".join(item.get("bullets",[])), item.get("icon"))
        _add_icon(slide, x + I(0.22) + (icon_circle - icon_sz)//2, y + I(0.22) + (icon_circle - icon_sz)//2, icon_sz, WHITE, icon_name=ic)
        tx = x + I(0.95)
        tw = I(3.20)
        _tb(slide, item.get("title", ""), tx, y + I(0.18), tw, I(0.40),
            sz=13, bold=True, color=DARK, font="Calibri")
        desc = " ".join(item.get("bullets", [])[:3])
        if desc:
            d_h = card_h - I(0.68)
            _tb(slide, desc, tx, y + I(0.58), tw, d_h,
                sz=10, color=MID, font="Calibri")
    _page_num(slide, idx, total)


def make_agenda(prs, s, idx, total):
    slide, top_y = _setup_content_slide(prs, s)
    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    accents = _accents()
    row_h = I(0.55)
    gap = I(0.08)

    for i, item in enumerate(items[:8]):
        ac = accents[i % len(accents)]
        y = top_y + i * (row_h + gap)
        if y + row_h > SH - I(0.40): break
        _rrect(slide, LM, y, CW, row_h, WHITE, radius=0.04)
        nsz = I(0.30)
        _oval(slide, LM + I(0.20) + nsz//2, y + row_h//2, nsz//2, ac)
        _tb(slide, item.get("num", str(i+1)),
            LM + I(0.20), y + (row_h - I(0.22))//2, nsz, I(0.22),
            sz=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _tb(slide, item.get("title", ""), LM + I(0.60), y + I(0.06), I(3.5), I(0.24),
            sz=12, bold=True, color=T["primary_dk"], font="Calibri")
        _tb(slide, item.get("desc", ""), LM + I(0.60), y + I(0.30), CW - I(0.80), I(0.22),
            sz=9, color=MID)
    _page_num(slide, idx, total)


def make_roles(prs, s, idx, total):
    """Cowork slide 6: 3 team columns with avatar, name, role badge, bio text."""
    slide, top_y = _setup_content_slide(prs, s)
    items = s.get("items", [])
    if not items: _page_num(slide, idx, total); return

    top_y = top_y + I(0.05)
    n = min(len(items), 3)
    gap = I(0.15)
    col_w = I(2.80)
    accents = _accents()

    card_h = I(3.35)
    for i, item in enumerate(items[:n]):
        ac = accents[i % len(accents)]
        x = LM + i * (col_w + gap)
        cx = x + col_w // 2

        _rrect(slide, x, top_y, col_w, card_h, WHITE, radius=0.04)
        _rect(slide, x, top_y, col_w, I(0.08), ac)

        avatar_circle = I(1.00)
        avatar_sz = I(0.54)
        _oval(slide, cx, top_y + I(0.35) + avatar_circle//2, avatar_circle//2, T["primary_xl"])
        _add_icon(slide, cx - avatar_sz//2, top_y + I(0.35) + (avatar_circle - avatar_sz)//2, avatar_sz, T["primary_dk"], avatar=True)

        name_y = top_y + I(1.55)
        _tb(slide, item.get("role", ""),
            x + I(0.15), name_y, col_w - I(0.30), I(0.40),
            sz=14.5, bold=True, color=T["primary_dk"], align=PP_ALIGN.CENTER, font="Calibri")

        # Role badge
        if item.get("type"):
            _tb(slide, item["type"],
                x + I(0.15), name_y + I(0.38), col_w - I(0.30), I(0.30),
                sz=11, bold=True, color=T["accent"], align=PP_ALIGN.CENTER)

        # Divider line
        div_w = I(0.70)
        _rect(slide, cx - div_w//2, name_y + I(0.75), div_w, Pt(1), T["primary_xl"])

        # Bio (bullets joined as paragraph)
        bio_y = name_y + I(0.88)
        bio_text = " ".join(item.get("bullets", [])[:3])
        if bio_text:
            _tb(slide, bio_text,
                x + I(0.22), bio_y, col_w - I(0.44), I(0.90),
                sz=10, color=DARK, align=PP_ALIGN.CENTER)

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
        _rrect(slide, LM, y, CW, row_h, WHITE, radius=0.04)
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
    gap_x, gap_y = I(0.15), I(0.12)
    col_w = (CW - gap_x) // 2
    card_h = I(0.85)
    accents = _accents()

    for i, item in enumerate(items[:6]):
        ac = accents[i % len(accents)]
        c, r = i % cols, i // cols
        x = LM + c * (col_w + gap_x)
        y = top_y + r * (card_h + gap_y)
        if y + card_h > SH - I(0.40): break
        # Icon-left card without border
        icon_sz = I(0.30)
        _add_icon(slide, x + I(0.12), y + I(0.12), icon_sz, ac, icon_name=_pick_icon(item.get("title","") if isinstance(item, dict) else str(item)))
        tx = x + I(0.55)
        tw = col_w - I(0.70)
        _tb(slide, item.get("title", ""), tx, y + I(0.05), tw, I(0.28),
            sz=13, bold=True, color=T["primary_dk"], font="Calibri")
        if item.get("desc"):
            _tb(slide, item["desc"], tx, y + I(0.35), tw, card_h - I(0.40),
                sz=10, color=DARK)
    _page_num(slide, idx, total)


def make_summary(prs, s, idx, total):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(slide, T["cover_bg"])

    # Decorative circles (cowork style)
    _oval(slide, I(0.70), I(5.10), I(2.50), T["primary"])
    _oval(slide, I(9.70), I(0.30), I(1.70), T["primary_dk"])

    # Logo centered (rounded-rect like cowork slide 8)
    _rrect(slide, SW//2 - I(0.45), I(0.55), I(0.90), I(0.90), T["primary"], radius=0.15)
    _add_icon(slide, SW//2 - I(0.23), I(0.77), I(0.46), T["primary_lt"])

    _tb(slide, s["title"], I(0.80), I(1.70), SW - I(1.60), I(1.30),
        sz=28, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Calibri")

    if s.get("bullets"):
        cta = s["bullets"][0] if s["bullets"] else ""
        if cta:
            btn_w = I(5.10)
            _rrect(slide, SW//2 - btn_w//2, I(3.15), btn_w, I(0.70), T["accent"], radius=0.08)
            _tb(slide, cta, SW//2 - btn_w//2, I(3.15), btn_w, I(0.70),
                sz=16, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font="Calibri")

        contact_parts = s["bullets"][1:4]
        if contact_parts:
            _tb(slide, "   |   ".join(contact_parts),
                I(0.80), I(4.35), SW - I(1.60), I(0.40),
                sz=13, color=T["primary_xl"], align=PP_ALIGN.CENTER)

    if s.get("footer"):
        _tb(slide, s["footer"], I(0.80), I(4.85), SW - I(1.60), I(0.40),
            sz=12, color=T["primary_lt"], align=PP_ALIGN.CENTER)

    _page_num(slide, idx, total)


# ═══════════════════════════════════════════════════════════════════════
LAYOUT_MAP = {
    "bullets": make_bullets, "stats": make_stats, "chart": make_chart,
    "donut": make_donut,
    "two-col": make_two_col, "timeline": make_timeline, "pillars": make_pillars,
    "agenda": make_agenda, "roles": make_roles, "okr": make_okr,
    "principles": make_principles,
}

def _embed_images(slide, s, image_map):
    if not image_map or not s.get("bullets"): return
    new_bullets = []
    for b in s["bullets"]:
        text = b if isinstance(b, str) else (b.get("text", "") if isinstance(b, dict) else str(b))
        if text.strip().startswith("IMAGE:"):
            key = text.strip().split(":", 1)[1].strip()
            img_path = image_map.get(key)
            if img_path and os.path.exists(img_path):
                try: slide.shapes.add_picture(img_path, I(1), I(2), I(4), I(2.5))
                except: new_bullets.append(b)
            else: new_bullets.append(b)
        else: new_bullets.append(b)
    s["bullets"] = new_bullets


def generate(slides_json_str, output_path, theme_name="blue", image_paths=None):
    global T
    T = _resolve_theme(theme_name)

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
    if not s.get("_images"): return
    for img_key in s["_images"]:
        img_path = image_map.get(img_key)
        if img_path and os.path.exists(img_path):
            try: slide.shapes.add_picture(img_path, I(5), I(1.5), I(3.5), I(3))
            except: pass


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
