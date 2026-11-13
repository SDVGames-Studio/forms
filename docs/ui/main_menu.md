# Forms — Main Menu UI Specification

**Status:** Approved for architecture review  
**Project:** Forms  
**Engine:** Godot 4.x  
**Visual direction:** Dark minimalist / geometric  
**Implementation:** Native Godot UI

---

## 1. Game identity

Forms is a 2D side-view, turn-based team deathmatch game inspired by Worms Armageddon.

Instead of worms, the characters are geometric shapes called Forms. The game introduces modern gameplay mechanics, including custom gravity fields.

The menu should communicate three qualities:

- Tactical gameplay.
- Geometric visual identity.
- Modern minimalist presentation.

The interface must have its own identity. It must not look like a direct copy of Worms Armageddon or a generic sci-fi game menu.

## 2. Design principles

1. **Minimalism:** Avoid unnecessary decorative elements.
2. **Readability:** Menu options must be immediately recognizable.
3. **Consistency:** Use consistent typography, colors, spacing, and interaction states.
4. **Responsiveness:** Support different resolutions and aspect ratios.
5. **Functionality:** All visible menu controls must work.
6. **Separation:** Menu UI must remain independent of the gameplay HUD and gameplay state.
7. **Reusability:** Prefer existing project functionality and reusable UI components over duplicate implementations.

## 3. Visual style

### 3.1 Color palette

Initial proposed palette:

| Element | Color |
|---|---|
| Main background | `#17191F` |
| Secondary background | `#292D38` |
| Primary text | `#E8E8ED` |
| Secondary text | `#777D8B` |
| Accent | `#A78BFA` |
| Divider / border | `#343943` |

The palette may be refined during implementation, but the overall appearance must remain dark and restrained.

Use the accent color for selected, focused, and interactive elements. Avoid using it excessively.

### 3.2 Typography

- Use a clean, modern sans-serif font.
- The game title must be visually dominant.
- Menu options should be easy to read.
- Use consistent font sizes and weights across screens.
- Avoid decorative or handwritten fonts.

### 3.3 Background

The main menu background must be completely static.

Proposed visual concept:

- Dark graphite background.
- A small composition of geometric shapes representing Forms.
- Subtle lighting and shadows.
- A restrained visual reference to gravity distortion, such as a curved or distorted geometric arrangement.
- No animation, particle effects, or moving objects.

The background should not compete with menu controls.

Do not reuse existing game assets unless they are suitable for this visual direction. The current visual assets are not approved as the basis for the new menu.

The background must be replaceable independently of menu logic.

## 4. Main menu

### 4.1 Layout

Use an asymmetric composition:

- Game title and subtitle on the left.
- Main navigation options on the right.
- Static geometric composition integrated into the background.
- Small footer at the bottom.

The layout must adapt to different screen sizes without overlapping or clipping.

### 4.2 Branding

Display:

**FORMS**

Subtitle:

**TACTICAL TURN-BASED COMBAT**

Optional footer text:

- A BATTLE OF SHAPES
- SDVGAMES
- Game version

### 4.3 Main menu options

The main menu must contain exactly four primary options:

1. NEW GAME
2. LEVEL EDITOR
3. SETTINGS
4. QUIT

Do not display Level Selection or Continue on the main menu.

### 4.4 Button behavior

- **New Game:** Opens the existing level selection flow.
- **Level Editor:** Opens the level editor screen (issue #464).
- **Settings:** Opens the Settings screen.
- **Quit:** Requests application exit.

Buttons must have visible normal, hover, pressed, and focused states.

Keyboard and controller navigation must be supported through Godot's focus system.

## 5. New Game flow

The existing project already implements the following flow:

`Main → LevelsMenu → LevelConfigMenu → Gameplay`

Reuse this flow.

Requirements:

- Rename the main menu's Play option to New Game.
- New Game opens the existing `LevelsMenu`.
- Preserve the existing level selection and level configuration behavior.
- Preserve the existing game initialization logic.
- Provide a way to return to the main menu.
- Do not introduce another level selection implementation.

Level Selection must only be accessible through the New Game flow.

## 6. Settings

The Settings screen must contain four categories:

1. Teams Customization
2. Controls
3. Graphics
4. Audio

Each category must open its corresponding settings screen.

### 6.1 Teams Customization

Reuse the existing `TeamMenu`.

Preserve existing functionality, including:

- Team configuration.
- Shape selection.
- Color selection.
- Existing skill and friendly-fire settings.
- Existing persistence through `GameConfig`.

Do not invent additional team properties without approval.

### 6.2 Controls

Reuse the existing `HotkeysMenu`.

Preserve:

- Existing input actions.
- Key rebinding functionality.
- Existing hotkey persistence.
- Existing keyboard navigation and cancellation behavior.

Do not remove or rename gameplay input actions without approval.

### 6.3 Graphics

The project currently does not have a dedicated graphics settings screen.

Implement a new Graphics settings screen.

Initially investigate these settings:

- Display mode: fullscreen / windowed.
- Resolution.
- VSync.

Requirements:

- Inspect the existing Godot display configuration before implementation.
- Only expose settings that can actually be applied.
- Persist user-selected settings.
- Apply settings immediately where safe.
- Provide sensible defaults.
- Avoid introducing unnecessary graphics options.
- Ensure the UI remains usable after changing resolution or display mode.

If a setting cannot be implemented reliably, report the limitation instead of exposing a nonfunctional control.

### 6.4 Settings navigation

- Settings opens the Settings screen.
- Teams Customization opens the existing TeamMenu.
- Controls opens the existing HotkeysMenu.
- Graphics opens the new Graphics settings screen.
- Audio opens the audio settings screen.
- Every settings screen must provide a way to return to Settings.
- Settings must provide a way to return to the main menu.

### 6.5 In-game settings consistency

The project already has an in-game settings overlay implemented through `InGameMenu` and the existing settings functionality.

Preserve this behavior.

Do not create a third independent implementation of settings.

Where practical, share UI components and settings logic between the main menu and in-game settings overlay. Ensure that settings changed in either location remain consistent.

Do not modify the pause-menu behavior unnecessarily.

### 6.6 Audio

The audio settings screen (issue #472) exposes one volume slider per audio bus of the project's `default_bus_layout.tres`:

- Master volume.
- Music volume.
- SFX volume.

Requirements:

- Persist user-selected volumes in `settings.cfg`.
- Apply changes immediately through `AudioServer` bus volumes.
- 0% is silence (the -80 dB hard-mute floor).
- Sensible defaults keep today's authored mix (Master 100%, Music 50%, SFX 100%).
- The category stays available on touch devices.

## 7. Navigation and state management

Implement menu navigation using the existing project architecture.

The project currently uses direct:

`get_tree().change_scene_to_file()`

Continue using this approach. Do not introduce a scene manager or navigation framework as part of this task.

Requirements:

- Every screen has a clear navigation path back.
- Opening a submenu does not create duplicate menu instances.
- Returning to a previous screen preserves appropriate UI state where practical.
- Opening the main menu does not accidentally start or reset gameplay.
- The gameplay HUD remains hidden while navigating menus.
- Menu navigation does not modify gameplay state unless the user explicitly starts a game.
- Preserve existing Escape-key navigation behavior.

Inspect the existing autoloads and gameplay-state checks before making changes.

## 8. Godot implementation requirements

Use native Godot UI nodes:

- `Control`
- `Container`
- `Button`
- `Label`
- `ColorRect`
- Other appropriate built-in UI nodes.

Prefer reusable scenes and components.

Use anchors, containers, and size flags instead of hardcoded screen coordinates wherever possible.

Keep visual styling reusable through Godot Theme resources or shared style resources.

Avoid external UI frameworks and unnecessary plugins.

### 8.1 Existing architecture to preserve

The current project contains:

- `Main.tscn` and `Main.gd` — main menu.
- `LevelsMenu` — level selection.
- `LevelConfigMenu` — level configuration.
- `SettingsMenu` — settings navigation.
- `TeamMenu` — team customization.
- `HotkeysMenu` — controls configuration.
- `InGameMenu` — in-game pause and settings overlay.
- `GameConfig.gd` — persistent game and settings configuration.

The project also has gameplay HUD autoloads, including `WeaponInventory`, `OSD`, `InGameMenu`, and `TouchControls`.

Preserve their existing responsibilities and gameplay-state gating.

Do not re-parent gameplay HUD elements into menu scenes.

### 8.2 Expected changes

Expected changes include:

- Updating the existing main menu layout and styling.
- Updating main menu labels and navigation.
- Updating the existing Settings screen layout and styling.
- Adding a Graphics settings screen and the necessary settings persistence.
- Reusing existing TeamMenu and HotkeysMenu.
- Updating shared settings UI components if needed to keep the main menu and in-game settings consistent.
- Adding or updating UI tests where appropriate.

The exact file structure must be determined after inspecting the existing project.

## 9. Mobile compatibility

The project has existing mobile-specific UI behavior.

Preserve existing mobile conventions, including touch controls and mobile HUD layouts.

The new menu must remain usable on supported mobile screen sizes.

Do not assume that a desktop-oriented layout will work on mobile. Adapt the composition where necessary while preserving the visual identity.

## 10. Game design constraints

The implementation must respect `GAME_DESIGN_RULES.md` and `AGENTS.md`.

In particular:

- The in-game interface must not appear in the main menu.
- Menu screens must not accidentally initialize gameplay.
- Starting a new game must follow existing game initialization rules.
- The menu must not introduce changes to gameplay mechanics.
- Each level must continue to initialize its gameplay state according to existing requirements.

If an existing requirement conflicts with this specification, stop and request clarification rather than silently changing it.

## 11. Acceptance criteria

### Main menu

- [ ] Main menu displays the Forms title and subtitle.
- [ ] Background is completely static.
- [ ] Main menu contains exactly New Game, Level Editor, Settings, and Quit.
- [ ] No gameplay HUD is visible.
- [ ] All four options work.
- [ ] Visual style follows the approved dark minimalist direction.

### New Game

- [ ] New Game opens the existing LevelsMenu.
- [ ] Existing level configuration flow remains functional.
- [ ] Level Selection is accessible only through this flow.
- [ ] Navigation back to the main menu works.

### Settings

- [ ] Settings opens the Settings screen.
- [ ] Teams Customization opens the existing TeamMenu.
- [ ] Controls opens the existing HotkeysMenu.
- [ ] Graphics opens the new Graphics settings screen.
- [ ] Functional graphics settings are available.
- [ ] Settings persist correctly.
- [ ] Main menu and in-game settings remain consistent.

### Interaction

- [ ] Mouse interaction works.
- [ ] Keyboard navigation works.
- [ ] Focus states are visible.
- [ ] Controller navigation works through Godot's UI focus system.
- [ ] Existing Escape-key behavior is preserved.

### Technical

- [ ] UI scales correctly at supported resolutions.
- [ ] No overlapping or clipped controls.
- [ ] No runtime errors during menu navigation.
- [ ] Gameplay HUD remains separate from menu UI.
- [ ] Existing gameplay functionality is not broken.
- [ ] Mobile UI conventions are preserved.

## 12. Implementation workflow

Before changing code:

1. Read `AGENTS.md`, `GAME_DESIGN_RULES.md`, and this specification.
2. Inspect the existing main menu, settings screens, scene transitions, autoloads, and game state.
3. Identify which existing scenes and scripts will be reused.
4. Identify all new scenes, scripts, and resources.
5. Report the proposed implementation architecture and any risks.
6. Wait for owner approval before implementation.

After approval:

1. Implement the main menu visual redesign.
2. Implement the Settings screen redesign.
3. Implement the Graphics settings screen.
4. Reuse existing New Game, TeamMenu, and HotkeysMenu functionality.
5. Verify consistency with in-game settings.
6. Test menu navigation, display settings, and input.
7. Test multiple resolutions and supported mobile layouts.
8. Verify that gameplay behavior remains unchanged.

Do not commit directly to `dev` or `main`.

Work on a feature branch and open a pull request into `dev`.

The pull request description must include:

- Summary of implemented screens.
- List of changed files.
- Tests performed and their results.
- Screenshots of the implemented UI.
- Any incomplete functionality or assumptions.

---

**Design approval note:** The colors, typography, layout, and background composition are approved as the initial direction. They may be refined during implementation, but changes to menu structure, gameplay behavior, or existing game mechanics require owner approval.
