## Shared character characteristics (issue #108).
##
## Every figure in the game — player team or enemy team — is the SAME class
## of character: identical health, movement and view parameters. Both
## Player.gd and Npc.gd load their stats from here so they can never drift
## apart again.

## Health: every figure starts at the same maximum health.
const MAX_HEALTH := 100

## Movement (issue #108: the AI moves just as fast as the player).
const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const GRAVITY := 1200.0

## Issue #641: the walkable-surface rule — a figure moves on any surface
## whose angle with the gravity vector (measured at the current point) is
## under 135°: floors, slopes, vertical walls and overhangs up to 45° past
## vertical; only steeper overhangs and flat ceilings stay unwalkable.
## Expressed the way CharacterBody2D consumes it — the largest angle
## between a surface normal and the frame's up that still counts as floor.
const FLOOR_MAX_ANGLE := PI * 0.75

## Issue #641: floor glue for walking DOWN an incline — at SPEED one
## physics tick (60 Hz) covers ~5.3 px, so the default 1 px snap cannot
## follow a steep surface and the figure would bounce between floor and
## free fall downhill. 20 px keeps it attached on slopes up to ~75°.
const FLOOR_SNAP_LENGTH := 20.0

## View/aim (issue #67/#66: both teams aim the same way).
const VIEW_SPEED := 2.2
const VIEW_MAX := 1.2

## Health bar geometry (identical for both teams).
const BAR_WIDTH := 64.0
const BAR_HEIGHT := 8.0

## Issue #598 render layers: the character's LINE (speech balloon)
## draws in front of EVERYTHING, the HP bar in front of everything
## EXCEPT the line. Both clear the highlight rings (z 50 — LevelItem,
## ProjectileBody), so no body, terrain or projectile can cover them.
## Single-sourced here so SpeechBubble, Player and Npc can never drift.
const LINE_Z := 100
const HP_Z := 90

## Issue #270: the figure's footprint — the square shape visual and the
## capsule are 64 px wide/tall, so ONE character width is 64 px. The level
## terrain rules are expressed as multiples of it.
const BODY_SIZE := 64.0
