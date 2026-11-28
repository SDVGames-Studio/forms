#!/usr/bin/env python3
"""Generate the Forms cartoon RAILGUN held-weapon sprite (#680 part 4b,
sub-issue #720 — Pistol & Railgun arsenal migration).

Style: matches the rocket-launcher/shotgun cartoons and the modular
square character — bold dark-purple outline (31,20,41), flat vivid
fills, simple shading/highlight bands. The silhouette is the weapon's
own physics: TWIN RAILS with a dark energy channel between them, three
charged coil rings, a glowing cyan core window and a muzzle glow — the
same icy-cyan family as the #359 rainbow-to-white beam. Authored at
16x and downscaled with LANCZOS to a clean 4x texture (192x64 = 48x16
in-game px, sprite scaled 0.25).
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 768, 256          # 16x of 48x16
TEX_W, TEX_H = 192, 64             # 4x of 48x16
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
W = (171, 101, 48, 255)    # warm wood (stock, grip)
WH = (214, 150, 90, 255)   # wood highlight
WS = (128, 70, 30, 255)    # wood shade
D = (74, 78, 94, 255)      # dark steel (receiver trim, muzzle clamp)
G = (150, 156, 172, 255)   # light steel (receiver, rails)
GH = (196, 200, 212, 255)  # steel highlight
Y = (255, 214, 51, 255)    # accent yellow (coil rings)
Y2 = (226, 178, 32, 255)   # yellow shade
K = (24, 16, 33, 255)      # near-black energy channel
C = (77, 191, 255, 255)    # cyan energy (core window, channel shimmer)
CW = (230, 248, 255, 255)  # white-hot core

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
poly([(-22.2, -2.6), (-16.0, -4.0), (-16.0, 4.0), (-22.2, 2.6)], None, outline=True)  # stock
rr(-16.0, -4.6, -3.0, 4.6, 1.2, None, outline=True)       # receiver
rr(-3.0, -5.4, 18.0, -2.6, 0.5, None, outline=True)       # upper rail
rr(-3.0, -0.8, 18.0, 1.8, 0.5, None, outline=True)        # lower rail
rr(-3.0, -2.6, 18.0, -0.8, 0.3, None, outline=True)       # energy channel
rr(18.0, -5.2, 21.6, 2.2, 0.6, None, outline=True)        # muzzle clamp
poly([(-11.6, 4.6), (-7.6, 4.6), (-8.6, 6.2), (-12.6, 6.2)], None, outline=True)  # grip
for x0, x1 in [(1.0, 3.2), (8.0, 10.2), (15.0, 17.2)]:    # coil rings
    rr(x0, -5.8, x1, 2.6, 0.6, None, outline=True)
rr(-13.0, -1.9, -6.0, 1.9, 0.9, None, outline=True)       # core window
circ(20.2, -1.7, 1.0, None, outline=True)                 # muzzle glow

# ---- pass 2: fills
poly([(-22.2, -2.6), (-16.0, -4.0), (-16.0, 4.0), (-22.2, 2.6)], W)  # stock
rr(-16.0, -4.6, -3.0, 4.6, 1.2, G)                                  # receiver
rr(-3.0, -5.4, 18.0, -2.6, 0.5, G)                                  # upper rail
rr(-3.0, -0.8, 18.0, 1.8, 0.5, G)                                   # lower rail
rr(-3.0, -2.6, 18.0, -0.8, 0.3, K)                                  # energy channel
rr(18.0, -5.2, 21.6, 2.2, 0.6, D)                                   # muzzle clamp
poly([(-11.6, 4.6), (-7.6, 4.6), (-8.6, 6.2), (-12.6, 6.2)], W)      # grip
for x0, x1 in [(1.0, 3.2), (8.0, 10.2), (15.0, 17.2)]:    # coil rings
    rr(x0, -5.8, x1, 2.6, 0.6, Y)
rr(-13.0, -1.9, -6.0, 1.9, 0.9, C)                                  # core window
circ(20.2, -1.7, 1.0, C)                                            # muzzle glow

# stock shading: top highlight sliver + bottom shade half
poly([(-22.2, -2.6), (-16.0, -4.0), (-16.0, -3.0), (-21.4, -1.9)], WH)
poly([(-22.2, 2.6), (-16.0, 4.0), (-16.0, 0.8), (-21.6, 0.2)], WS)

# receiver shading: top highlight band + bottom shade band
rr(-15.4, -4.0, -3.6, -3.0, 0.8, GH)
rr(-15.4, 2.4, -3.6, 4.0, 0.8, D)

# rail shading: each rail gets a top highlight and a bottom shade band
rr(-2.4, -5.1, 17.4, -4.2, 0.4, GH)
rr(-2.4, -3.5, 17.4, -2.8, 0.4, D)
rr(-2.4, -0.6, 17.4, 0.3, 0.4, GH)
rr(-2.4, 0.9, 17.4, 1.6, 0.4, D)

# channel shimmer: a thin cyan strip inside the dark lane
rr(-2.0, -1.85, 16.0, -1.55, 0.2, C)

# core window: white-hot inner core
rr(-11.5, -1.0, -9.5, 1.0, 0.6, CW)

# coil ring shading: lower part of each ring
for x0, x1 in [(1.0, 3.2), (8.0, 10.2), (15.0, 17.2)]:
    rr(x0 + 0.4, 0.5, x1 - 0.4, 2.3, 0.5, Y2)

# muzzle clamp highlight + glow core
rr(18.4, -4.6, 20.6, -3.8, 0.4, GH)
circ(20.2, -1.7, 0.5, CW)

# grip shading: darker lower part + top highlight sliver
poly([(-11.9, 5.2), (-8.9, 5.2), (-8.7, 6.2), (-12.5, 6.2)], WS)
poly([(-11.2, 4.6), (-8.0, 4.6), (-8.1, 5.1), (-11.0, 5.1)], WH)

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/railgun.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
