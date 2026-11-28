#!/usr/bin/env python3
"""Generate the Forms cartoon mine sprite (#680 part 4a, issue #719).

Style: matches the rocket-launcher/shotgun/grenade prototypes and the
modular characters — bold dark-purple outline (31,20,41), flat fills,
subtle shading. Authored at 16x and downscaled with LANCZOS to a clean
4x texture (72x72 = 18x18 in-game px, sprite scaled 0.25).

A naval contact mine: dark navy hull (the registry identity color
0.22,0.24,0.3 — the dormant mine stays stealthy, #717) with EIGHT
steel studs around the whole rim, so the silhouette reads as a mine at
ANY rotation — the thrown body tumbles and the placed one comes to
rest at arbitrary angles on arbitrary slopes. Used BOTH as the held
weapon (WeaponVisuals.STYLES) and as the thrown/placed rigid body
(WeaponVisuals.PROJECTILE_SPRITES -> ProjectileBody); the armed fuse
blink tints the whole sprite red through modulate.
"""
from PIL import Image, ImageDraw
import math

WORK_W, WORK_H = 288, 288          # 16x of 18x18
TEX_W, TEX_H = 72, 72              # 4x of 18x18
S = 16.0                            # work px per in-game px
CX, CY = WORK_W / 2, WORK_H / 2

O = (31, 20, 41, 255)      # outline dark purple (character outline color)
NV = (56, 61, 77, 255)     # navy hull (registry identity 0.22,0.24,0.3)
NVH = (96, 104, 128, 255)  # navy highlight
NVS = (36, 40, 52, 255)    # navy shade
ST = (110, 118, 142, 255)  # stud steel
STH = (150, 156, 172, 255) # stud steel highlight

W_OUT = int(1.8 * S)        # bold outline width

# in-game geometry (origin = sprite centre)
BODY_R = 5.6               # hull radius
STUD_R0 = 4.2              # stud base centre radius
STUD_R1 = 7.1              # stud tip radius (tip+outline stays inside +/-9)
STUD_HALF = 1.25           # stud base half width
STUD_TIP_FROM = 0.55       # fraction along the stud where the light tip starts

im = Image.new("RGBA", (WORK_W, WORK_H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)


def circ(x, y, rad, fill, outline=False):
    r = rad * S
    if outline:
        d.ellipse([CX + x * S - r - W_OUT, CY + y * S - r - W_OUT,
                   CX + x * S + r + W_OUT, CY + y * S + r + W_OUT], fill=O)
    else:
        d.ellipse([CX + x * S - r, CY + y * S - r,
                   CX + x * S + r, CY + y * S + r], fill=fill)


def arc(x, y, rad, start, end, fill, width):
    r = rad * S
    d.arc([CX + x * S - r, CY + y * S - r, CX + x * S + r, CY + y * S + r],
          start=start, end=end, fill=fill, width=int(width * S))


def stud_pts(angle: float, r_base: float, r_tip: float, half: float = STUD_HALF):
    """Triangle points of one stud at `angle` (rad): base pair at r_base
    plus the tip at r_tip, in in-game coords."""
    ca, sa = math.cos(angle), math.sin(angle)
    pa, pb = -sa, ca
    b1 = (ca * r_base - pa * half, sa * r_base - pb * half)
    b2 = (ca * r_base + pa * half, sa * r_base + pb * half)
    tip = (ca * r_tip, sa * r_tip)
    return [b1, tip, b2]


def poly(pts, fill, outline=False):
    p = [(CX + x * S, CY + y * S) for x, y in pts]
    if outline:
        d.polygon(p, fill=O, outline=O, width=2 * W_OUT)
    else:
        d.polygon(p, fill=fill)


angles = [math.radians(45 * k) for k in range(8)]

# ---- pass 1: silhouette (bold outline behind — hull + all 8 studs).
# PIL's polygon outline stroke barely reaches OUTWARD, so each stud's
# bold rim is a manually inflated O triangle (the hull's ellipse
# outline inflates by itself).
circ(0.0, 0.0, BODY_R, None, outline=True)
for a in angles:
    poly(stud_pts(a, STUD_R0 - 0.6, STUD_R1 + 1.3, STUD_HALF + 1.0), O)

# ---- pass 2: fills — studs first, hull painted over their bases
for a in angles:
    poly(stud_pts(a, STUD_R0, STUD_R1), ST)
    # light steel tip: the outer part of the same triangle
    r_tip_start = STUD_R0 + STUD_TIP_FROM * (STUD_R1 - STUD_R0)
    poly(stud_pts(a, r_tip_start, STUD_R1), STH)
circ(0.0, 0.0, BODY_R, NV)

# hull shading: bottom-right shade crescent + top-left highlight sliver
arc(0.0, 0.0, BODY_R - 0.35, 10, 105, NVS, 1.3)
arc(0.0, 0.0, BODY_R - 0.35, 190, 275, NVH, 1.0)

tex = im.resize((TEX_W, TEX_H), Image.LANCZOS)
tex.save("assets/weapons/mine.png")

# quick structural report
bbox = tex.getbbox()
print("texture", tex.size, "bbox", bbox)
