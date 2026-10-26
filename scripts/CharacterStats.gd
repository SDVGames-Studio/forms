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

## View/aim (issue #67/#66: both teams aim the same way).
const VIEW_SPEED := 2.2
const VIEW_MAX := 1.2

## Health bar geometry (identical for both teams).
const BAR_WIDTH := 64.0
const BAR_HEIGHT := 8.0
