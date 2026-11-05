# Forms — Game Design Rules

Rules the owner (IlinyhGleb) has established through issue decisions and
comments, as implemented on `dev`. Each rule cites the issue(s) that
define it. When rules evolved, the most recent decision wins; known
successions are noted inline. Reference point for the whole game:
**Worms: Armageddon**.

## 1. Turns and match flow

1. Forms is a **turn-based team game**: teams act in a fixed alternating
   order (#33, #65); a wrong turn order is a bug (#191).
2. The **default turn time is 15 seconds** (#253); turn time is a
   per-level parameter configurable in the level config menu (#192).
3. A turn does **not** end while any explosion or activated mine is still
   resolving — the next turn begins only after every effect finished
   (#119, #244, #312).
4. Weapons have per-turn shot counts: shotgun 2, spear 2, rocket/grenade/
   mine 1 (#101, #114).
5. **Tab skips the turn** (#102).
6. The player may **not switch characters after moving or aiming** —
   control switching locks in for the rest of the member's turn (#104).
7. Switching members uses the Switch tool: arm it, then commit the use
   on action (N/P are the shortcuts, next/previous) (#170, #215, #306).
8. A character can never **move another character** during its move —
   figures do not push each other (#144).
9. Win conditions are explicit: a team is out when all its figures are
   dead; **mutual destruction is a DRAW** (#151); the game must never
   lock after a win (#222).
10. Figures are steady — no gliding/inertia walking (#39, #58).

## 2. Grounds and terrain geometry

1. Two ground types: **indestructible** and **destructible** (#236).
2. Indestructible ground is at least **7 character widths thick** —
   thinner authored slabs extend downward to the minimum (#270).
3. Indestructible ground always has **rounded corners**, minimum radius
   **3 character widths** (#270).
4. Separated indestructible grounds keep a minimum distance of
   **8 character widths** horizontally (#270; supersedes the 6-width rule
   of #258) and a safe minimum **vertical** gap — the owner rejected a
   too-small vertical distance in #258's rework.
5. A figure **always stands on the ground, even upside down**: its
   bottom faces the ground surface along the local gravity direction
   (#270 owner comment, #275).
6. Destructible ground is destroyed **precisely**: an explosion with a
   circular radius removes exactly that circle from the terrain, not
   rough squares (#270 owner comment, #299 — "no, it is still too
   rough").
7. The Rock tool **creates** destructible ground precisely (exact chord
   strips; never overlapping indestructible ground or figures) (#227,
   #234, #324).
8. Different grounds never overlap each other (#296).
9. Levels contain substantial destructible ground around the
   indestructible skeleton (#225); the campaign levels were reworked to
   these geometry rules (#190, #258, #270; circular arena level #250).

## 3. Gravity

1. Gravity is a **per-level vector field**: straight down in classic
   levels, radially toward the circle center in the circular arena
   (Level5) (#279, #293).
2. Figures **align with gravity** — bottom toward the ground, wherever
   gravity pulls (#270 owner comment, #275).
3. Projectiles obey level gravity: grenades arc under it (#216) and
   rockets have weight — they keep their launch speed but bend into an
   arc (#245).
4. A debug overlay can visualize the gravity vector field (#290).

## 4. Weapons

1. Five standard weapons: **Shotgun, Rocket, Grenade, Spear, Mine**
   (#49, #246) — all rendered held in-hand in front of the figure
   (#68, #282).
2. Fixed damage (surfaced in the inventory hints, #271): shotgun 5×6,
   rocket 35, grenade 40, spear 25, mine 40.
3. **Friendly fire is on** — blasts damage every figure in range,
   including the shooter's team (#57).
4. **One weapon per character per turn**: after the first shot the
   character's weapon choice is locked until its team's next turn
   (#116, #131 — the owner verified the lock twice; reworked per-
   character, not per-team, in #143).
5. Teams have **per-team use budgets: 5 uses of each weapon and tool**;
   the **spear is unlimited**; the remaining count shows at the
   bottom-right corner of each inventory slot (#305).
6. A weapon/tool with **zero uses left cannot be taken in-hands**
   (#327).
7. The **spear attacks along its axis**: the in-hand spear rotates with
   aiming, thrusts fast in the aiming direction and returns slowly —
   no second projectile appears (#133 owner comments); it damages along
   the entire swept path (#257).
8. **Mines**: the activation radius is doubled (#262); a mine has HP
   and can be destroyed (#281); once activated, the turn waits until it
   explodes (#312).
9. The **jackhammer** damages characters and carves destructible
   ground; its tunnel is at least as wide as the drilling figure (#307
   owner comment, #313).
10. The aiming view/arrow direction must match the character's facing
    (#277, #298).
11. The shot-power indicator renders at the aiming figure, not at a
    screen-fixed spot (#322).

## 5. Tools

1. Four tools: **Switch, Teleport, Shield, Rock** (#170, #227).
2. **Tool or weapon per character per turn — never both** (#207); each
   tool is usable once per turn per character, quotas reset on the
   team's next turn (#170).
3. Tools and weapons share **one unified inventory panel** (#179) laid
   out as a slot table with shape icons (#64); weapons on keys 1–5,
   tools on keys 5–8, mine on key 9 (#246, #179).
4. **Switch** hands control to the next/previous team member; blocked
   after the member moved or aimed (#104, #170, #215, #306).
5. **Teleport** moves the member to the next left-clicked point —
   destinations buried inside ground are rejected (#328).
6. **Shield** blocks exactly **one** attack and is consumed by the
   block (#255).
7. **Rock** is aimed and charged like a grenade, then crumbles into
   destructible ground where it rests (#234), never covering
   indestructible ground or figures (#227), with precise placement
   (#324).

## 6. Teams and figures

1. Teams have distinct **colors**; every member wears its team's color
   (#60, #163, #167).
2. Every figure has a visible **name and health bar** (#61) that reacts
   to damage immediately (#97).
3. **0 HP is death**: the flag stays, the figure disappears, no
   heal-back (#181).
4. Player figures are fully damageable — no invulnerability (#99,
   #161); explosions visibly affect them (#186).
5. Default teams use distinct shape sets; a figure renders exactly
   **one** shape at a time (#226 owner comment, #178).
6. Teams are customizable: member shapes, colors, size, AI skill and
   friendly-fire toggle (#169, #180); the team menu uses team
   dropdowns with a 3-member default cap (#208).
7. Figures are the geometric shapes the game is named for — triangle,
   square, circle, … — one team, one shape language.

## 7. Computer opponents (AI)

1. AI difficulty is a **per-team skill setting** (0–100) (#180).
2. AI **sees enemy figures anywhere in the level** — no distance cutoff
   (#308); standing still because the enemy is far away is a bug.
3. AI **aims before shooting** — ballistic lobs land on the target, it
   does not shoot blind or through teammates (#99, #147).
4. AI fights **all enemy teams**, not only the player's (#228).
5. Smarter AI uses tools situationally: a badly hurt figure spends its
   tool; a near threat raises the shield (#120, #221).
6. AI obeys the same per-turn constraints as the player (weapon lock,
   tool-or-weapon, quotas) (#143, #207).

## 8. Camera and HUD

1. An OSD shows the **current character's health** and text hints about
   what the player should do now (#76, #109, #87).
2. **Zoom with the mouse wheel** (#233).
3. **Free spectator camera via mouse is always available** — during
   enemy turns too, not only between turns (#126, #212).
4. An **additional camera type** is switchable in game (#289).
5. The camera must never block the view after a match ends (#280);
   zoom errors are bugs (#63).
6. Inventory slots show **hover hints**: item name plus damage for
   weapons (#271) and the team's remaining use count (#305).
7. **Name and HP labels align with the current coordinate system** —
   on rotated gravity levels they follow the figure's frame, not the
   screen (#311 owner comment).
8. Turn description text states clearly whose turn it is (#165).

## 9. Menus and navigation

1. Menu tree: Main → Levels → Level config → game; Settings (with Team
   setup and Hotkeys) (#32, #137, #31, #175).
2. **Escape is the cancel button in every menu** — Back on every
   screen, abort-rebind on the hotkeys screen, quits on the root main
   menu, toggles the pause menu in game (#303, #254).
3. The in-game menu (pause) only exists **inside levels** (#211); in-
   game UI never appears on menu screens (#174).
4. The in-game settings menu has the **same content as the main-menu
   settings**, rendered over a **shadowed (dimmed) live game
   background**; the main-menu version has no shadow (#304 owner
   comment).
5. **Hotkeys are rebindable** in settings and persist across restarts;
   Escape always cancels a rebinding listen (#294).
6. The level config menu before each level sets team size, enemy count
   and turn time (#137, #192).

## 10. Mobile / touch

1. Touch devices get **on-screen controls** for movement and actions
   (#69, #78).
2. The mobile inventory is the **centered ~2× layout**, toggled by a
   corner button (#125, #129).
3. The mobile version must not crash at start (#141 — open at the time
   of writing).

---

Grounded in issues #1–#332 as of 2026-11-05. When a new owner decision
conflicts with anything above, the newer decision rules — update this
file with it.
