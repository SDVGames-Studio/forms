#!/usr/bin/env python3
"""Generate the Forms cartoon JACKHAMMER held-weapon sprite (#680 part
4d, sub-issue #722 — Jackhammer & Circular Saw contact-weapon
migration).

Style: matches the rocket-launcher/shotgun/pistol cartoons and the
modular square character — bold dark-purple outline (31,20,41), flat
vivid fills, simple shading/highlight bands, slightly exaggerated
proportions. Authored at 16x and downscaled with LANCZOS to a clean 4x
texture (104x72 = 26x18 in-game px, sprite scaled 0.25).

The bit points +x (the aim/muzzle direction of every held weapon): a
chunky dark-steel motor with a bold yellow hazard stripe at the front,
a D-handle arch with an exhaust stub behind it, a warm-wood lower
grip, and the long light-steel bit with spiral flight stripes meeting
the chuck collar. The old plain rectangle was 10x18; the drawn size
grows to 26x18 for the readable drill silhouette — nothing in the
code reads the jackhammer's size (only the spear's size.x feeds a
hitbox), and the drill shake keeps riding the shared held-visual
offsets (issue #307).
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 416, 288          # 16x of 26x18
TEX_W, TEX_H = 104, 72             # 4x of 26x18
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
D = (74, 78, 94, 255)      # dark steel (motor, chuck, handles)
G = (150, 156, 172, 255)   # light steel (bit, exhaust)
GH = (196, 200, 212, 255)  # steel highlight
Y = (255, 214, 51, 255)    # accent yellow (hazard stripe)
W = (171, 101, 48, 255)    # warm wood (lower grip)
WH = (214, 150, 90, 255)   # wood highlight
WS = (128, 70, 30, 255)    # wood shade
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
rr(-9.5, -4.6, 1.6, 2.4, 1.2, None, outline=True)            # motor body
rr(-8.0, -6.6, -3.0, -5.4, 0.6, None, outline=True)          # handle bar
rr(-7.3, -5.8, -6.1, -4.2, 0.3, None, outline=True)          # handle post (back)
rr(-4.2, -5.8, -3.0, -4.2, 0.3, None, outline=True)          # handle post (front)
rr(-9.4, -6.2, -8.2, -4.0, 0.4, None, outline=True)          # exhaust stub
rr(-9.3, 2.4, -6.2, 5.6, 0.9, None, outline=True)            # lower grip
rr(1.6, -2.8, 3.8, 2.8, 0.5, None, outline=True)             # chuck collar
poly([(3.8, -2.2), (10.0, -0.3), (10.0, 0.3), (3.8, 2.2)], None, outline=True)  # bit

# ---- pass 2: fills
rr(-9.5, -4.6, 1.6, 2.4, 1.2, D)
rr(-8.0, -6.6, -3.0, -5.4, 0.6, D)
rr(-7.3, -5.8, -6.1, -4.2, 0.3, D)
rr(-4.2, -5.8, -3.0, -4.2, 0.3, D)
rr(-9.4, -6.2, -8.2, -4.0, 0.4, G)
rr(-9.3, 2.4, -6.2, 5.6, 0.9, W)
rr(1.6, -2.8, 3.8, 2.8, 0.5, D)
poly([(3.8, -2.2), (10.0, -0.3), (10.0, 0.3), (3.8, 2.2)], G)

# ---- pass 3: shading / details
# motor: top highlight band + bottom shade sliver + yellow hazard stripe
rr(-8.9, -4.0, 1.0, -3.2, 0.8, GH)
rr(-8.9, 1.6, 1.0, 2.2, 0.6, K)
rr(-0.5, -4.0, 1.4, 1.8, 0.5, Y)
# chuck: two light steel rings
rr(2.0, -2.6, 2.5, 2.6, 0.3, G)
rr(3.0, -2.6, 3.5, 2.6, 0.3, G)
# bit: spiral flight stripes (tapering with the bit) + top glint sliver
for x, frac in ((4.7, 0.145), (6.0, 0.355), (7.3, 0.564)):
    h = 2.2 - 1.9 * frac
    poly([(x, -h * 0.85), (x + 0.5, -h * 0.85),
          (x + 0.5, h * 0.85), (x, h * 0.85)], (100, 105, 122, 255))
poly([(3.9, -2.1), (7.2, -1.1), (7.2, -0.7), (3.9, -1.7)], GH)
# exhaust: near-black opening dot on top
rr(-9.2, -6.1, -8.4, -5.5, 0.3, K)
# lower grip: wood wrap strips + highlight sliver
rr(-8.6, 2.6, -8.2, 5.4, 0.2, WS)
rr(-7.4, 2.6, -7.0, 5.4, 0.2, WS)
rr(-9.1, 2.7, -8.9, 5.3, 0.1, WH)
# handle bar: highlight sliver
rr(-7.8, -6.5, -3.2, -6.2, 0.15, GH)

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/jackhammer.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
