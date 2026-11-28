#!/usr/bin/env python3
"""Generate the Forms cartoon BASEBALL BAT held-weapon sprite (#680
part 4c, sub-issue #721 — Spear, Baseball Bat & Shovel melee migration).

Style: matches the rocket-launcher/shotgun/pistol cartoons and the
modular square character — bold dark-purple outline (31,20,41), flat
vivid fills, simple shading/highlight bands, slightly exaggerated
proportions. Authored at 16x and downscaled with LANCZOS to a clean 4x
texture (128x40 = 32x10 in-game px, sprite scaled 0.25).

The barrel points +x (the aim direction of every held weapon): honey
wood with a top highlight and bottom shade that follow the taper, a
dark taped grip and a round knob. The swing corridor stays the fixed
BAT_RANGE constant in Weapon.gd, so the size change is visual only.
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 512, 160          # 16x of 32x10
TEX_W, TEX_H = 128, 40             # 4x of 32x10
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
W = (198, 128, 58, 255)    # honey wood (body)
WH = (232, 178, 110, 255)  # wood highlight
WS = (150, 90, 34, 255)    # wood shade
L = (94, 62, 38, 255)      # dark tape (grip)

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


# The bat's tapered silhouette: thin handle at the grip (left, -x),
# swelling through the middle into the fat barrel with a rounded tip.
# Top edge points, then the mirrored bottom edge, then the knob.
BAT = [(-11.6, -0.9), (-3.0, -1.3), (3.0, -2.6), (8.0, -3.4),
       (12.4, -3.3), (13.8, -1.9), (14.2, 0.0),
       (13.8, 1.9), (12.4, 3.3), (8.0, 3.4), (3.0, 2.6),
       (-3.0, 1.3), (-11.6, 0.9)]

# ---- pass 1: silhouettes (bold outline behind, like the character body)
poly(BAT, None, outline=True)                              # tapered body
circ(-11.9, 0.0, 1.4, None, outline=True)                  # knob
rr(-10.6, -1.45, -6.4, 1.45, 0.5, None, outline=True)      # taped grip

# ---- pass 2: fills
poly(BAT, W)
circ(-11.9, 0.0, 1.4, W)
rr(-10.6, -1.45, -6.4, 1.45, 0.5, L)

# ---- pass 3: shading / highlights
# top highlight band following the taper (the whole bat reads round)
TOP = [(-11.0, -0.55), (-3.0, -1.0), (3.0, -2.25), (8.0, -3.05),
       (12.4, -2.95), (13.4, -1.5)]
poly(TOP + [(x, y + 0.85) for x, y in reversed(TOP)], WH)
# bottom shade band, mirrored and thinner
BOT = [(-11.0, 0.55), (-3.0, 1.0), (3.0, 2.25), (8.0, 3.05),
       (12.4, 2.95), (13.4, 1.5)]
poly(BOT + [(x, y - 0.7) for x, y in reversed(BOT)], WS)
# knob highlight sliver
circ(-12.2, -0.4, 0.7, WH)
# tape cross strips (three darker wraps)
for x in (-9.7, -8.6, -7.5):
    rr(x - 0.25, -1.45, x + 0.25, 1.45, 0.25, (70, 46, 28, 255))

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/baseball_bat.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
