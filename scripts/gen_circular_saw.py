#!/usr/bin/env python3
"""Generate the Forms cartoon CIRCULAR SAW held-weapon sprite (#680
part 4d, sub-issue #722 — Jackhammer & Circular Saw contact-weapon
migration).

Style: matches the rocket-launcher/shotgun/pistol cartoons and the
modular square character — bold dark-purple outline (31,20,41), flat
vivid fills, simple shading/highlight bands, slightly exaggerated
proportions. Authored at 16x and downscaled with LANCZOS to a clean 4x
texture (88x64 = 22x16 in-game px, sprite scaled 0.25).

The blade points +x (the aim direction of every held weapon): a
light-steel 8-tooth blade (the same star silhouette the thrown body's
code-drawn blade polygon spins, issue #570) with a dark hub, under a
dark-steel hood crescent, behind it the vivid power-tool-orange motor
with the top handle arch, the yellow switch and the flat steel shoe.
The old plain rectangle was 16x16; the drawn size grows to 22x16 for
the readable silhouette — nothing in the code reads the saw's size,
and the THROWN saw keeps its own code-drawn spinning blade (the saw
motion stays its animation).
"""
import math
from PIL import Image, ImageDraw

WORK_W, WORK_H = 352, 256          # 16x of 22x16
TEX_W, TEX_H = 88, 64              # 4x of 22x16
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
D = (74, 78, 94, 255)      # dark steel (hood, handle)
G = (150, 156, 172, 255)   # light steel (blade, shoe)
GH = (196, 200, 212, 255)  # steel highlight
M = (240, 120, 40, 255)    # power-tool orange (motor)
MH = (255, 176, 96, 255)   # motor highlight
MS = (196, 76, 22, 255)    # motor shade
Y = (255, 214, 51, 255)    # accent yellow (switch)
K = (24, 16, 33, 255)      # near-black openings

W_OUT = int(1.8 * S)        # bold outline width

BLADE_X, BLADE_Y = 3.5, 0.5  # blade centre (in-game coords)

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


def star(cx, cy, teeth, r_tip, r_root, fill, outline=False):
    """The 8-tooth blade star (mirrors ProjectileBody's blade polygon)."""
    pts = []
    for i in range(teeth * 2):
        a = math.tau * i / (teeth * 2)
        r = r_tip if i % 2 == 0 else r_root
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    poly(pts, fill, outline)


def arc_band(cx, cy, a0, a1, r_in, r_out, fill, outline=False):
    """Annular sector (the hood crescent) between two PIL angles."""
    pts = []
    steps = 14
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        pts.append((cx + math.cos(a) * r_out, cy + math.sin(a) * r_out))
    for i in range(steps + 1):
        a = a1 + (a0 - a1) * i / steps
        pts.append((cx + math.cos(a) * r_in, cy + math.sin(a) * r_in))
    poly(pts, fill, outline)


# ---- pass 1: silhouettes (bold outline behind, like the character body)
rr(-5.0, 4.2, 6.0, 5.2, 0.4, None, outline=True)              # shoe plate
rr(-7.0, -3.5, 0.5, 4.0, 1.0, None, outline=True)             # motor
rr(-6.5, -6.0, -2.5, -4.8, 0.6, None, outline=True)           # handle bar
rr(-5.8, -4.8, -4.8, -3.2, 0.3, None, outline=True)           # handle post (back)
rr(-3.6, -4.8, -2.6, -3.2, 0.3, None, outline=True)           # handle post (front)
star(BLADE_X, BLADE_Y, 8, 5.4, 4.1, None, outline=True)       # blade
arc_band(BLADE_X, BLADE_Y, math.radians(195), math.radians(325),
         4.2, 6.3, None, outline=True)                        # hood crescent

# ---- pass 2: fills
rr(-5.0, 4.2, 6.0, 5.2, 0.4, G)
rr(-7.0, -3.5, 0.5, 4.0, 1.0, M)
rr(-6.5, -6.0, -2.5, -4.8, 0.6, D)
rr(-5.8, -4.8, -4.8, -3.2, 0.3, D)
rr(-3.6, -4.8, -2.6, -3.2, 0.3, D)
star(BLADE_X, BLADE_Y, 8, 5.4, 4.1, G)
# the hood covers the blade's top teeth (a guard, drawn over the blade)
arc_band(BLADE_X, BLADE_Y, math.radians(195), math.radians(325),
         4.2, 6.3, D)

# ---- pass 3: shading / details
# motor: top highlight band + bottom shade sliver
rr(-6.4, -2.9, -0.1, -2.1, 0.7, MH)
rr(-6.4, 3.0, -0.1, 3.7, 0.6, MS)
# yellow switch dot near the handle post
circ(-5.6, -1.2, 0.55, Y)
# blade: dark hub + near-black axle + upper-left glint wedge
circ(BLADE_X, BLADE_Y, 1.3, D)
circ(BLADE_X, BLADE_Y, 0.5, K)
poly([(0.3, -0.6), (2.2, -2.6), (2.8, -2.0), (0.9, 0.0)], GH)
# shoe: front highlight sliver
rr(-4.6, 4.4, 5.6, 4.6, 0.2, GH)
# handle bar: highlight sliver
rr(-6.3, -5.9, -2.7, -5.6, 0.15, (110, 116, 134, 255))

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/circular_saw.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
