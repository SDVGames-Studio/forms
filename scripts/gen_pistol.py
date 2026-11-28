#!/usr/bin/env python3
"""Generate the Forms cartoon PISTOL held-weapon sprite (#680 part 4b,
sub-issue #720 — Pistol & Railgun arsenal migration).

Style: matches the rocket-launcher/shotgun cartoons and the modular
square character — bold dark-purple outline (31,20,41), flat vivid
fills, simple shading/highlight bands, slightly exaggerated
proportions. Authored at 16x and downscaled with LANCZOS to a clean 4x
texture (96x64 = 24x16 in-game px, sprite scaled 0.25).
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 384, 256          # 16x of 24x16
TEX_W, TEX_H = 96, 64              # 4x of 24x16
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
W = (171, 101, 48, 255)    # warm wood (grip)
WH = (214, 150, 90, 255)   # wood highlight
WS = (128, 70, 30, 255)    # wood shade
D = (74, 78, 94, 255)      # dark steel (slide, hammer, guard)
G = (150, 156, 172, 255)   # light steel (frame)
GH = (196, 200, 212, 255)  # steel highlight
Y = (255, 214, 51, 255)    # accent yellow (sight, trigger)
K = (24, 16, 33, 255)      # near-black openings

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
rr(-7.0, -5.4, 8.4, -1.8, 1.0, None, outline=True)        # slide
rr(8.4, -5.0, 10.2, -2.2, 0.7, None, outline=True)        # muzzle ring
rr(-7.0, -1.8, 4.2, 0.0, 0.6, None, outline=True)         # frame
poly([(-2.6, -0.6), (1.4, -0.6), (-0.6, 4.2), (-4.4, 4.2)], None, outline=True)  # grip
rr(0.6, 0.6, 4.0, 3.4, 0.7, None, outline=True)           # trigger guard
rr(-8.8, -5.0, -7.2, -2.8, 0.5, None, outline=True)       # hammer
circ(7.2, -5.75, 0.45, None, outline=True)                # front sight

# ---- pass 2: fills
rr(-7.0, -5.4, 8.4, -1.8, 1.0, D)                                   # slide
rr(8.4, -5.0, 10.2, -2.2, 0.7, D)                                   # muzzle ring
rr(-7.0, -1.8, 4.2, 0.0, 0.6, G)                                    # frame
poly([(-2.6, -0.6), (1.4, -0.6), (-0.6, 4.2), (-4.4, 4.2)], W)      # grip
rr(0.6, 0.6, 4.0, 3.4, 0.7, D)                                      # trigger guard
rr(-8.8, -5.0, -7.2, -2.8, 0.5, D)                                  # hammer
circ(7.2, -5.75, 0.45, Y)                                           # front sight

# slide shading: top highlight band + bottom shade sliver
rr(-6.4, -4.9, 7.8, -4.2, 0.7, GH)
rr(-6.4, -2.9, 7.8, -2.3, 0.6, K)

# ejection port + muzzle opening (near-black)
rr(-4.6, -4.7, -2.4, -3.0, 0.4, K)
rr(9.4, -4.3, 10.2, -2.9, 0.4, K)

# frame shade strip under the slide
rr(-6.4, -0.8, 3.6, -0.3, 0.5, D)

# grip shading: darker lower part + top highlight sliver
poly([(-4.4, 1.8), (-1.2, 1.8), (-0.6, 4.2), (-4.4, 4.2)], WS)
poly([(-2.2, -0.3), (1.1, -0.3), (0.8, 0.7), (-1.9, 0.7)], WH)

# trigger (accent yellow, inside the guard, no outline)
poly([(1.9, 1.2), (2.7, 1.2), (2.3, 2.6)], Y)

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/pistol.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
