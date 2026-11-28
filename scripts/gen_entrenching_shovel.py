#!/usr/bin/env python3
"""Generate the Forms cartoon ENTRENCHING SHOVEL held-weapon sprite
(#680 part 4c, sub-issue #721 — Spear, Baseball Bat & Shovel melee
migration).

Style: matches the rocket-launcher/shotgun/pistol cartoons and the
modular square character — bold dark-purple outline (31,20,41), flat
vivid fills, simple shading/highlight bands, slightly exaggerated
proportions. Authored at 16x and downscaled with LANCZOS to a clean 4x
texture (104x48 = 26x12 in-game px, sprite scaled 0.25).

The blade points +x (the aim direction of every held weapon): a warm
wood T-grip, a steel tube shaft with a collar, and the wide stamped
spade blade with a top glint and a center rib. The dig corridor stays
the fixed SHOVEL_RANGE constant in Weapon.gd, so the size change is
visual only.
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 416, 192          # 16x of 26x12
TEX_W, TEX_H = 104, 48             # 4x of 26x12
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
W = (171, 101, 48, 255)    # warm wood (T-grip)
WH = (214, 150, 90, 255)   # wood highlight
WS = (128, 70, 30, 255)    # wood shade
D = (74, 78, 94, 255)      # dark steel (shaft shade, collar, rib)
G = (150, 156, 172, 255)   # light steel (shaft, blade)
GH = (196, 200, 212, 255)  # steel highlight (blade glint)

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


def poly(pts, fill, outline=False):
    p = [(CX + x * S, CY + y * S) for x, y in pts]
    if outline:
        d.polygon(p, fill=O, outline=O, width=2 * W_OUT)
    else:
        d.polygon(p, fill=fill)


# The spade blade: narrow at the socket, flaring to the full width,
# then sweeping to the rounded point.
BLADE = [(1.5, -1.9), (6.5, -4.3), (9.5, -3.9), (11.2, 0.0),
         (9.5, 3.9), (6.5, 4.3), (1.5, 1.9)]

# ---- pass 1: silhouettes (bold outline behind, like the character body)
poly(BLADE, None, outline=True)                            # spade blade
rr(-8.8, -1.0, 2.0, 1.0, 0.5, None, outline=True)          # steel shaft
rr(0.8, -2.2, 2.6, 2.2, 0.5, None, outline=True)           # socket collar
rr(-10.2, -3.0, -8.4, 3.0, 0.9, None, outline=True)        # T-grip bar

# ---- pass 2: fills
poly(BLADE, G)
rr(-8.8, -1.0, 2.0, 1.0, 0.5, G)
rr(0.8, -2.2, 2.6, 2.2, 0.5, D)
rr(-10.2, -3.0, -8.4, 3.0, 0.9, W)

# ---- pass 3: shading / highlights
# blade glint: bright band under the blade's top edge
TOP = [(1.8, -1.7), (6.5, -3.95), (10.0, -3.35), (10.8, -0.8)]
poly(TOP + [(x, y + 0.8) for x, y in reversed(TOP)], GH)
# blade center rib (the stamped stiffener), narrowing to the point
poly([(1.8, -0.55), (7.0, -0.35), (10.3, -0.2), (10.6, 0.0),
      (10.3, 0.2), (7.0, 0.35), (1.8, 0.55)], D)
# shaft: top highlight sliver + bottom shade sliver
rr(-8.6, -0.95, 1.8, -0.45, 0.4, GH)
rr(-8.6, 0.45, 1.8, 0.95, 0.4, D)
# T-grip: top highlight sliver + bottom shade sliver
rr(-9.8, -2.95, -8.6, -2.1, 0.5, WH)
rr(-9.8, 2.1, -8.6, 2.95, 0.5, WS)

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/entrenching_shovel.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
