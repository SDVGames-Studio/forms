#!/usr/bin/env python3
"""Generate the Forms cartoon shotgun held-weapon sprite (#680 part 2).

Style: matches the rocket-launcher prototype and the modular square
character — bold dark-purple outline (31,20,41), flat vivid fills, simple
shading/highlight bands, slightly exaggerated proportions. Authored at
16x and downscaled with LANCZOS to a clean 4x texture (160x64 = 40x16
in-game px, sprite scaled 0.25).
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 640, 256          # 16x of 40x16
TEX_W, TEX_H = 160, 64             # 4x of 40x16
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
W = (171, 101, 48, 255)    # warm wood (stock, pump)
WH = (214, 150, 90, 255)   # wood highlight
WS = (128, 70, 30, 255)    # wood shade
D = (74, 78, 94, 255)      # dark steel (receiver, muzzle, guard)
G = (150, 156, 172, 255)   # light steel (barrel)
GH = (196, 200, 212, 255)  # steel highlight
Y = (255, 214, 51, 255)    # accent yellow (character body color)
Y2 = (226, 178, 32, 255)   # yellow shade
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
poly([(-17.5, -2.6), (-6.5, -3.5), (-6.5, 4.0), (-14.5, 5.4)], None, outline=True)  # stock
rr(-7.2, -4.4, -1.2, 3.6, 1.0, None, outline=True)        # receiver
rr(-1.2, -4.4, 13.8, -0.9, 1.0, None, outline=True)       # barrel
rr(13.8, -5.0, 17.2, -0.3, 0.9, None, outline=True)       # muzzle ring
rr(0.8, 0.4, 7.8, 3.2, 1.0, None, outline=True)           # pump grip
rr(-6.2, 4.2, -2.4, 5.6, 0.6, None, outline=True)         # trigger guard
circ(13.2, -5.2, 0.6, None, outline=True)                 # front sight

# ---- pass 2: fills
poly([(-17.5, -2.6), (-6.5, -3.5), (-6.5, 4.0), (-14.5, 5.4)], W)   # stock
rr(-7.2, -4.4, -1.2, 3.6, 1.0, D)                                   # receiver
rr(-1.2, -4.4, 13.8, -0.9, 1.0, G)                                  # barrel
rr(13.8, -5.0, 17.2, -0.3, 0.9, D)                                  # muzzle ring
rr(0.8, 0.4, 7.8, 3.2, 1.0, W)                                      # pump grip
rr(-6.2, 4.2, -2.4, 5.6, 0.6, D)                                    # trigger guard
circ(13.2, -5.2, 0.6, Y)                                            # front sight

# stock shading: darker lower half + top highlight sliver
poly([(-17.5, 0.5), (-6.5, 1.0), (-6.5, 4.0), (-14.5, 5.4)], WS)
poly([(-16.8, -2.4), (-7.0, -3.1), (-7.0, -2.4), (-16.0, -1.6)], WH)

# barrel shading: top highlight band + bottom shade band
rr(-0.7, -3.7, 13.3, -2.8, 0.7, GH)
rr(-0.7, -1.8, 13.3, -1.1, 0.5, D)

# pump ribs (wood shade)
rr(2.8, 0.6, 3.4, 3.0, 0.3, WS)
rr(5.2, 0.6, 5.8, 3.0, 0.3, WS)

# receiver ejection slot + muzzle opening (near-black)
rr(-4.8, -2.4, -2.6, -0.6, 0.5, K)
rr(16.6, -4.1, 17.5, -1.2, 0.6, K)

# yellow accent band ring near the muzzle (painted over the barrel)
rr(10.2, -4.4, 12.2, -0.9, 0.7, O, outline=True)
rr(10.2, -4.4, 12.2, -0.9, 0.7, Y)
rr(10.2, -2.6, 12.2, -0.9, 0.6, Y2)  # band lower shade

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/shotgun.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
