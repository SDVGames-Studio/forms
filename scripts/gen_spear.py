#!/usr/bin/env python3
"""Generate the Forms cartoon SPEAR held-weapon sprite (#680 part 4c,
sub-issue #721 — Spear, Baseball Bat & Shovel melee migration).

Style: matches the rocket-launcher/shotgun/pistol cartoons and the
modular square character — bold dark-purple outline (31,20,41), flat
vivid fills, simple shading/highlight bands, slightly exaggerated
proportions. Authored at 16x and downscaled with LANCZOS to a clean 4x
texture (160x32 = 40x8 in-game px, sprite scaled 0.25).

The spearhead points +x (the aim/muzzle direction of every held
weapon): a slender warm-wood shaft, a wrap near the grip, a steel
pommel, a dark socket collar and a light-steel leaf head with a top
glint. The drawn height grows to 8 px (from the old 4 px rectangle)
for a readable silhouette; WeaponVisuals keeps size.x EXACTLY 40
because the sweep hitbox reads HELD_STYLES[3]["size"].x.
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 640, 128          # 16x of 40x8
TEX_W, TEX_H = 160, 32             # 4x of 40x8
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
W = (171, 101, 48, 255)    # warm wood (shaft)
WH = (214, 150, 90, 255)   # wood highlight
WS = (128, 70, 30, 255)    # wood shade
D = (74, 78, 94, 255)      # dark steel (socket collar, pommel)
G = (150, 156, 172, 255)   # light steel (head)
GH = (196, 200, 212, 255)  # steel highlight (head glint)
L = (94, 62, 38, 255)      # dark leather (grip wrap)

W_OUT = int(1.8 * S)        # bold outline width

im = Image.new("RGBA", (WORK_W, WORK_H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)


def rr(x0, y0, x1, y1, rad, fill, outline=False):
    """Rounded rect in in-game coords; outline pass inflates by W_OUT."""
    px0, py0 = CX + x0 * S, CY + y0 * S
    px1, py1 = CX + x1 * S, CY + y1 * S
    r = rad * S
    if outline:
        d.rounded_rectangle([px0 - W_OUT, py0 - W_OUT, px1 + W_OUT, py1 + W_OUT],
                            radius=r + W_OUT, fill=O)
    else:
        d.rounded_rectangle([px0, py0, px1, py1], radius=r, fill=fill)


def circ(x, y, rad, fill, outline=False):
    r = rad * S
    if outline:
        d.ellipse([CX + x * S - r - W_OUT, CY + y * S - r - W_OUT,
                   CX + x * S + r + W_OUT, CY + y * S + r + W_OUT], fill=O)
    else:
        d.ellipse([CX + x * S - r, CY + y * S - r,
                   CX + x * S + r, CY + y * S + r], fill=fill)


def poly(pts, fill, outline=False):
    p = [(CX + x * S, CY + y * S) for x, y in pts]
    if outline:
        d.polygon(p, fill=O, outline=O, width=2 * W_OUT)
    else:
        d.polygon(p, fill=fill)


# ---- pass 1: silhouettes (bold outline behind, like the character body)
rr(-16.4, -1.1, 8.5, 1.1, 0.9, None, outline=True)          # shaft
poly([(8.2, -0.5), (10.8, -2.6), (14.0, -1.25), (17.2, 0.0),
      (14.0, 1.25), (10.8, 2.6), (8.2, 0.5)], None, outline=True)  # leaf head
rr(7.6, -1.7, 9.6, 1.7, 0.5, None, outline=True)            # socket collar
rr(-15.6, -1.5, -11.6, 1.5, 0.6, None, outline=True)        # grip wrap
circ(-16.2, 0.0, 1.0, None, outline=True)                   # pommel

# ---- pass 2: fills
rr(-16.4, -1.1, 8.5, 1.1, 0.9, W)
poly([(8.2, -0.5), (10.8, -2.6), (14.0, -1.25), (17.2, 0.0),
      (14.0, 1.25), (10.8, 2.6), (8.2, 0.5)], G)
rr(7.6, -1.7, 9.6, 1.7, 0.5, D)
rr(-15.6, -1.5, -11.6, 1.5, 0.6, L)
circ(-16.2, 0.0, 1.0, D)

# ---- pass 3: shading / highlights
# shaft: top highlight sliver + bottom shade sliver, full length
rr(-15.5, -1.05, 7.8, -0.45, 0.5, WH)
rr(-15.5, 0.45, 7.8, 1.05, 0.5, WS)
# head glint: bright band under the top edge of the leaf
poly([(9.2, -0.6), (11.2, -1.9), (13.0, -1.0), (15.6, -0.35),
      (12.8, -0.25), (9.2, -0.2)], GH)
# grip wrap: three darker cross strips
for x in (-14.6, -13.6, -12.6):
    rr(x - 0.25, -1.5, x + 0.25, 1.5, 0.25, (70, 46, 28, 255))
# socket collar highlight sliver
rr(7.8, -1.55, 9.4, -1.05, 0.4, (110, 116, 134, 255))

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/spear.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
