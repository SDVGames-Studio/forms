#!/usr/bin/env python3
"""Generate the Forms cartoon rocket-launcher held-weapon sprite (#680).

Style: matches the modular square character — bold dark-purple outline
(31,20,41), flat vivid fills, simple shading/highlight bands, slightly
exaggerated proportions. Authored at 16x and downscaled with LANCZOS to
a clean 4x texture (208x80 = 52x20 in-game px, sprite scaled 0.25).
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 832, 320          # 16x of 52x20
TEX_W, TEX_H = 208, 80             # 4x of 52x20
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
R = (232, 92, 40, 255)     # tube red-orange (rocket weapon color)
H = (255, 160, 95, 255)    # tube highlight
SH = (168, 48, 24, 255)    # tube shadow
D = (74, 78, 94, 255)      # dark steel (grip, sight, muzzle hole)
G = (150, 156, 172, 255)   # light steel (muzzle, exhaust bell)
Y = (255, 214, 51, 255)    # accent yellow (character body color)
Y2 = (226, 178, 32, 255)   # yellow shade

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
rr(-20, -4.5, 18, 4.5, 2, None, outline=True)          # main tube
poly([(-19, -4.5), (-23, -6.2), (-23, 6.2), (-19, 4.5)], None, outline=True)  # exhaust bell
rr(18, -6.5, 23.5, 6.5, 2.5, None, outline=True)       # muzzle
rr(-3, -7.5, 2, -4.0, 1.2, None, outline=True)         # top sight
rr(-8, 3.8, -2.5, 8.3, 1.2, None, outline=True)        # grip

# ---- pass 2: fills
poly([(-19, -4.5), (-23, -6.2), (-23, 6.2), (-19, 4.5)], G)   # exhaust bell
rr(-20, -4.5, 18, 4.5, 2, R)                                   # tube
rr(18, -6.5, 23.5, 6.5, 2.5, G)                                # muzzle
rr(-3, -7.5, 2, -4.0, 1.2, D)                                  # sight
rr(-8, 3.8, -2.5, 8.3, 1.2, D)                                 # grip

# tube shading + highlight (inside the tube)
rr(-18.5, -3.6, 16.5, -1.9, 1.4, H)
rr(-18.5, 1.9, 16.5, 3.6, 1.4, SH)

# yellow band ring near the muzzle (painted over the tube)
rr(7.5, -4.5, 11.5, 4.5, 1.2, O, outline=True)
rr(7.5, -4.5, 11.5, 4.5, 1.2, Y)
rr(7.5, 2.4, 11.5, 4.5, 1.2, Y2)  # band lower shade

# exhaust opening (dark) + muzzle face hole
rr(-23.4, -5.4, -21.6, 5.4, 1.0, (24, 16, 33, 255))
rr(21.4, -4.9, 23.2, 4.9, 1.0, (24, 16, 33, 255))
# rocket warhead tip peeking from the muzzle
circ(21.2, 0, 1.6, Y)
circ(20.9, -0.4, 0.5, (255, 240, 170, 255))

# sight yellow dot
circ(-0.5, -5.75, 0.85, Y)

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/rocket_launcher.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
