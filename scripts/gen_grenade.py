#!/usr/bin/env python3
"""Generate the Forms cartoon grenade sprite (#680 part 4a, issue #719).

Style: matches the rocket-launcher/shotgun prototypes and the modular
characters — bold dark-purple outline (31,20,41), flat vivid fills,
simple shading bands, slightly exaggerated proportions. Authored at
16x and downscaled with LANCZOS to a clean 4x texture (64x64 = 16x16
in-game px, sprite scaled 0.25).

Reads at gameplay scale as a round pineapple grenade: green body with
segment grooves, steel cap with collar, yellow pin ring. Used BOTH as
the held weapon (WeaponVisuals.STYLES) and as the thrown rigid body
(WeaponVisuals.PROJECTILE_SPRITES -> ProjectileBody).
"""
from PIL import Image, ImageDraw

WORK_W, WORK_H = 256, 256          # 16x of 16x16
TEX_W, TEX_H = 64, 64              # 4x of 16x16
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
GRN = (80, 178, 74, 255)   # grenade green (registry identity 0.3,0.7,0.3)
GRH = (146, 216, 118, 255) # green highlight
GRS = (44, 118, 40, 255)   # green shade
D = (74, 78, 94, 255)      # dark steel (cap)
G = (150, 156, 172, 255)   # light steel (collar)
GH = (196, 200, 212, 255)  # steel highlight
Y = (255, 214, 51, 255)    # accent yellow (pin ring)
K = (24, 16, 33, 255)      # near-black openings

W_OUT = int(1.8 * S)        # bold outline width

# in-game geometry (origin = sprite centre, y down). The bold outline
# inflates every shape by 1.75 in-game px, so all geometry stays within
# +/-6.25 of the centre to fill the 16x16 texture WITHOUT clipping.
BODY = (0.0, 1.7, 4.5)      # body circle: cx, cy, r
cap_x0, cap_y0, cap_x1, cap_y1 = -2.0, -6.1, 2.0, -2.9   # steel cap
COLLAR = (-2.6, -3.6, 2.6, -2.7)
PIN = (3.1, -4.8)           # pin ring centre

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


def arc(x, y, rad, start, end, fill, width):
    """Thick arc on a circle, in in-game coords."""
    r = rad * S
    d.arc([CX + x * S - r, CY + y * S - r, CX + x * S + r, CY + y * S + r],
          start=start, end=end, fill=fill, width=int(width * S))


# ---- pass 1: silhouette (bold outline behind, like the character body)
circ(BODY[0], BODY[1], BODY[2], None, outline=True)         # body
rr(cap_x0, cap_y0, cap_x1, cap_y1, 0.8, None, outline=True)  # cap
rr(COLLAR[0], COLLAR[1], COLLAR[2], COLLAR[3], 0.5, None, outline=True)
circ(PIN[0], PIN[1], 1.25, None, outline=True)             # pin ring

# ---- pass 2: fills
circ(BODY[0], BODY[1], BODY[2], GRN)                        # body
rr(cap_x0, cap_y0, cap_x1, cap_y1, 0.8, D)                 # cap
rr(COLLAR[0], COLLAR[1], COLLAR[2], COLLAR[3], 0.5, G)      # collar

# cap highlight band + fuse-hole slot (near-black)
rr(cap_x0 + 0.4, cap_y0 + 0.25, cap_x1 - 0.4, cap_y0 + 0.95, 0.4, GH)
rr(-0.55, -5.9, 0.55, -5.15, 0.25, K)

# body shading: bottom-right shade crescent + top-left highlight sliver
arc(BODY[0], BODY[1], BODY[2] - 0.35, 20, 115, GRS, 1.25)
arc(BODY[0], BODY[1], BODY[2] - 0.35, 200, 280, GRH, 0.95)

# pineapple segment grooves (subtle vertical pair + horizontal)
rr(-2.35, -0.9, -1.95, 3.6, 0.18, GRS)
rr(1.95, -0.9, 2.35, 3.6, 0.18, GRS)
rr(-3.2, 2.1, 3.2, 2.5, 0.18, GRS)

# pin ring: dark rim, yellow fill, dark inner rim, transparent hole
circ(PIN[0], PIN[1], 1.25, O)
circ(PIN[0], PIN[1], 0.95, Y)
circ(PIN[0], PIN[1], 0.58, O)
circ(PIN[0], PIN[1], 0.38, (0, 0, 0, 0))

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/grenade.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
