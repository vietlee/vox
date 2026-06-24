#!/usr/bin/env python3
"""Generate Material-style icon PNGs for PPTX slides.
Each icon is a white silhouette on transparent background, 256x256."""

from PIL import Image, ImageDraw
import os, math

SZ = 256
OUT = os.path.join(os.path.dirname(__file__), "icons")
os.makedirs(OUT, exist_ok=True)

def save(name, img):
    img.save(os.path.join(OUT, f"{name}.png"))
    print(f"  {name}.png")

def new():
    return Image.new("RGBA", (SZ, SZ), (0,0,0,0)), None

def draw(img):
    return ImageDraw.Draw(img)

C = (255,255,255,255)  # white fill

# ── search (magnifying glass) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
# Circle
cx, cy, r = 105, 100, 60
for t in range(-8, 9):
    d.ellipse([cx-r+t, cy-r, cx+r+t, cy+r], outline=C, width=22)
# Handle
d.line([155, 150, 210, 210], fill=C, width=26)
d.ellipse([cx-r+10, cy-r+10, cx+r-10, cy+r-10], fill=(0,0,0,0))
save("search", img)

# ── filter (funnel) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.polygon([(40,45),(216,45),(148,135),(148,200),(108,220),(108,135)], fill=C)
save("filter", img)

# ── store (storefront) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.rounded_rectangle([35,40,221,100], radius=20, fill=C)
# Awning scallops
for i in range(3):
    cx = 75 + i*53
    d.ellipse([cx-28, 85, cx+28, 130], fill=C)
d.rectangle([45,125,211,215], fill=C)
d.rectangle([60,140,130,215], fill=(0,0,0,0))  # door cutout
save("store", img)

# ── check (checkmark in circle) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([20,20,236,236], fill=C)
d.line([80,130, 115,170, 180,90], fill=(0,0,0,255), width=22, joint="curve")
save("check", img)

# ── clock ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([20,20,236,236], fill=C)
d.ellipse([40,40,216,216], fill=(0,0,0,0))
d.line([128,128, 128,65], fill=C, width=16)
d.line([128,128, 175,128], fill=C, width=16)
d.ellipse([118,118,138,138], fill=C)
save("clock", img)

# ── person ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([90,25,166,101], fill=C)  # head
d.ellipse([55,115,201,260], fill=C)  # body
save("person", img)

# ── people (group) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([85,20,155,90], fill=C)
d.ellipse([50,100,190,250], fill=C)
d.ellipse([160,35,215,85], fill=C)
d.ellipse([140,95,235,220], fill=C)
save("people", img)

# ── rocket ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
# Body
pts = [(128,25),(170,100),(170,180),(128,200),(86,180),(86,100)]
d.polygon(pts, fill=C)
# Nose
d.ellipse([100,20,156,80], fill=C)
# Window
d.ellipse([112,85,144,117], fill=(0,0,0,0))
# Fins
d.polygon([(86,145),(50,190),(86,180)], fill=C)
d.polygon([(170,145),(206,190),(170,180)], fill=C)
# Flame
d.polygon([(110,195),(128,235),(146,195)], fill=C)
save("rocket", img)

# ── code (brackets </>) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.line([95,55, 55,128, 95,201], fill=C, width=22, joint="curve")
d.line([161,55, 201,128, 161,201], fill=C, width=22, joint="curve")
d.line([140,40, 116,216], fill=C, width=16)
save("code", img)

# ── chart (bar chart) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.rounded_rectangle([40,140,85,220], radius=8, fill=C)
d.rounded_rectangle([100,90,145,220], radius=8, fill=C)
d.rounded_rectangle([160,45,205,220], radius=8, fill=C)
save("chart", img)

# ── money (dollar/coin) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([30,30,226,226], fill=C)
d.ellipse([50,50,206,206], fill=(0,0,0,0))
d.line([128,55, 128,200], fill=C, width=14)
d.arc([88,65,168,145], 180, 0, fill=C, width=14)
d.arc([88,110,168,190], 0, 180, fill=C, width=14)
save("money", img)

# ── percent ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([50,40,110,100], fill=C)
d.ellipse([146,156,206,216], fill=C)
d.line([190,40, 66,216], fill=C, width=24)
save("percent", img)

# ── megaphone ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.polygon([(60,90),(60,170),(160,210),(160,50)], fill=C)
d.rounded_rectangle([35,85,65,175], radius=10, fill=C)
d.ellipse([155,60,215,120], fill=C)
save("megaphone", img)

# ── crown ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.polygon([(40,180),(55,80),(100,130),(128,55),(156,130),(201,80),(216,180)], fill=C)
d.rounded_rectangle([38,180,218,210], radius=8, fill=C)
save("crown", img)

# ── lightbulb ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([65,25,191,160], fill=C)
d.rounded_rectangle([95,140,161,200], radius=5, fill=C)
d.line([95,170,161,170], fill=(0,0,0,0), width=6)
d.line([95,185,161,185], fill=(0,0,0,0), width=6)
d.rounded_rectangle([100,195,156,215], radius=8, fill=C)
save("lightbulb", img)

# ── shield ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.polygon([(128,25),(210,65),(210,145),(128,235),(46,145),(46,65)], fill=C)
d.line([95,128, 118,155, 168,100], fill=(0,0,0,255), width=18, joint="curve")
save("shield", img)

# ── star ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
pts = []
for i in range(5):
    a = math.radians(i * 72 - 90)
    pts.append((128 + 100*math.cos(a), 128 + 100*math.sin(a)))
    a2 = math.radians(i * 72 - 90 + 36)
    pts.append((128 + 45*math.cos(a2), 128 + 45*math.sin(a2)))
d.polygon(pts, fill=C)
save("star", img)

# ── heart ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([40,50,140,140], fill=C)
d.ellipse([116,50,216,140], fill=C)
d.polygon([(45,115),(128,220),(211,115)], fill=C)
save("heart", img)

# ── globe ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([25,25,231,231], fill=C)
d.ellipse([45,45,211,211], fill=(0,0,0,0))
d.ellipse([85,25,171,231], outline=C, width=10)
d.line([25,128,231,128], fill=C, width=10)
d.line([128,25,128,231], fill=C, width=4)
save("globe", img)

# ── target ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([25,25,231,231], fill=C)
d.ellipse([45,45,211,211], fill=(0,0,0,0))
d.ellipse([75,75,181,181], fill=C)
d.ellipse([95,95,161,161], fill=(0,0,0,0))
d.ellipse([112,112,144,144], fill=C)
save("target", img)

# ── handshake ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.rounded_rectangle([30,90,115,150], radius=10, fill=C)
d.rounded_rectangle([141,90,226,150], radius=10, fill=C)
d.polygon([(90,120),(128,85),(166,120),(128,155)], fill=C)
save("handshake", img)

# ── leaf (eco/green) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.pieslice([40,30,250,220], 150, 330, fill=C)
d.arc([40,30,250,220], 150, 330, fill=C, width=3)
d.line([80,190, 128,128], fill=(0,0,0,0), width=8)
save("leaf", img)

# ── phone ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.rounded_rectangle([80,20,176,236], radius=18, fill=C)
d.rectangle([88,45,168,195], fill=(0,0,0,0))
d.ellipse([118,205,138,225], fill=(0,0,0,0))
save("phone", img)

# ── truck (delivery) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.rounded_rectangle([25,80,165,185], radius=10, fill=C)
d.polygon([(165,100),(220,100),(235,145),(235,185),(165,185)], fill=C)
d.ellipse([55,170,95,210], fill=C)
d.ellipse([55,170,95,210], fill=(0,0,0,0))
d.ellipse([63,178,87,202], fill=C)
d.ellipse([190,170,230,210], fill=C)
d.ellipse([190,170,230,210], fill=(0,0,0,0))
d.ellipse([198,178,222,202], fill=C)
save("truck", img)

# ── default (circle dot) ──
img = Image.new("RGBA", (SZ,SZ), (0,0,0,0))
d = draw(img)
d.ellipse([30,30,226,226], fill=C)
d.ellipse([65,65,191,191], fill=(0,0,0,0))
d.ellipse([95,95,161,161], fill=C)
save("default", img)

print(f"\nDone: {len(os.listdir(OUT))} icons in {OUT}")
