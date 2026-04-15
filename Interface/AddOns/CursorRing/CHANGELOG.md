# CursorRing Changelog

## 1.7.1
- Added various performance optimizations to reduce Cursor Ring's CPU usage during normal cursor movement and trail handling.
- Fixed the settings panel so Cursor Ring's options render reliably when selected from the Blizzard Settings UI.
- Reworked trail preset handling and kept the built-in preset list focused on Blizzard glows, with `Challenge Metal Glow` and `Selected Pet Glow` available from the dropdown.
- Switched Cursor Ring's settings dropdowns back to `UIDropDownMenu` to avoid retail `Blizzard_Menu` taint errors from the addon options panel.

## 1.7
- Updated GCD cooldown rendering on modern clients to use Blizzard's duration-object cooldown APIs and `isActive` handling, avoiding the protected/secret cooldown configuration paths affected by Blizzard's newer API security changes while keeping legacy fallbacks for older clients.
- Added the current cursor trail implementation with independent glow, ribbon, and particle layers that can be enabled together, plus per-layer color mode and custom color controls.
- Added shared trail tuning controls for performance testing, including trail alpha, size, length, sample rate, movement threshold, segment count, ribbon width, head scale, and particle pool/burst/spread/speed/size.
- Standardized the trail texture on Blizzard's `Challenge Metal Glow` asset and removed the asset selector from the settings UI.

## 1.6.5
- Updated GCD cooldown rendering on modern clients to use Blizzard's duration-object cooldown APIs instead of passing spell cooldown values directly into `Cooldown:SetCooldown`.
- Added compatibility guards so Cursor Ring keeps the numeric cooldown fallback only on older clients that do not expose the newer duration-object APIs.
- Avoided the new protected cooldown configuration paths introduced by Blizzard's live hotfix, preventing secret-value errors from the main cursor ring cooldown swipe.

## 1.6.4
- Updated the shared launcher/minimap integration to use the new LibDBIcon-backed shared launcher behavior.
- Added launcher override controls so a chosen Kagrok addon can supply the shared launcher icon, tooltip, and primary click action.
- Kept launcher override behavior from reshuffling the addon list order in the shared settings panel.

## 1.6.3
- Added independent thickness controls for each ring type:
  - main ring thickness
  - cast ring thickness
  - secondary resource ring thickness
- Added a `Ring margin` control and reworked ring layout spacing so cast/resource rings are solved outward by geometry and maintain separation from inner rings as thickness changes.
- Updated defaults for the new spacing controls:
  - cast ring thickness default: `25`
  - secondary resource ring thickness default: `15`
  - ring margin default: `2`
- Added new localization keys for the added settings labels and synchronized locale key sets.

## 1.6.2
- Added MoP Classic safety fallbacks for modern-only spellcast/power events so unsupported events no longer break addon load.
- Hardened cooldown method calls with compatibility guards for clients missing newer `Cooldown` APIs (`SetHideCountdownNumbers`, swipe styling methods, and 3-arg `SetCooldown` behavior).
- Updated shared launcher template fallback behavior for older settings APIs:
  - only uses settings subcategories when `Settings.RegisterCanvasLayoutSubcategory` is available
  - falls back to standalone addon categories when subcategories are unavailable
  - adds safe frame creation fallback when `BackdropTemplate` is unavailable

## 1.6.1
- Added per-addon `Show Minimap button` settings to Cursor Ring so its shared minimap entry can be hidden without affecting other Kagrok addons.
- Added a shared launcher-stack visibility toggle to `Kagrok's Addons` and a matching `Hide minimap button` action at the bottom of the launcher `Shared` section.
- Fixed shared settings registration timing so Cursor Ring and ACA both appear reliably under the shared `Kagrok's Addons` settings tree after login.
- Fixed Cursor Ring settings refresh timing so the options page now reflects saved values immediately after reload instead of waiting for a control interaction.

## 1.6
- Integrated the shared developer info panel and shared minimap launcher templates under `Templates/` for reuse across addons.
- Moved shared template media into `Templates/Media/...` and updated the source templates to use the same addon-local layout by default.
- Added launcher menu toggles for `Main Ring`, `Cast Bar`, and `2nd Resource`, while keeping `Developer Info` as a deduped shared launcher entry.
- Lowered Cursor Ring + launcher priority to `20` so utility addons sort later in the shared launcher.
- Refined shared launcher menu behavior so smaller addon sets expand without a scrollbar, and the scrollbar only appears once `5` or more addons are present.
- Moved settings access into a single shared launcher `Open settings` entry so duplicate per-addon settings lines no longer appear in the minimap menu.
- Updated the shared `Kagrok's Addons` settings hub to use the same section widths and structured card rows as the addon-specific settings pages.
- Updated shared launcher settings behavior so `Open settings` opens `Kagrok's Addons` when multiple Kagrok addons expose settings pages, and opens the addon page directly when only one settings page exists.

## 1.5
- Reworked secondary resources into class-specific modules that only load the implementation relevant to the current class.
- Added class/resource-specific colors and curved segment rendering for secondary resource rings, including dynamic max-resource updates.
- Rebuilt Death Knight rune handling with dedicated rune-state logic, continuous recharge updates, and DK-specific alpha-pop refill behavior.
- Added ring priority layout so the main ring stays centered, the cast ring takes the first outer slot, and the resource ring nests outside it.
- Reworked the GCD swipe to use native cooldown timing with ring-shaped swipe textures, avoiding secret-value taint while keeping the swipe on the main ring.
- Added support for modern empower/charge casts on the cast ring, including empower events, stage indicators, and staged tier coloring with hold-at-max accenting.
- Added per-class secondary resource palette overrides and improved full-state visibility while allowing DK runes to opt out of washout-style highlighting.

## 1.4.1
- Removed global `seterrorhandler` override from options code.
- Removed global AceGUI `SetText` monkey patching from options code.
- Added targeted AceConfig tooltip compatibility fix for current `GameTooltip:SetText` argument order.
- Reduced hot-path cursor update work by only re-anchoring when cursor position or offsets change.
- Refactored GCD swipe mask updates to cached/dirty-driven behavior instead of frequent full region traversal.
- Added texture sampling hardening for ring/spinner/mask/swipe textures:
  - disables snap-to-pixel-grid where available
  - sets texel snapping bias to `0` where available
  - uses trilinear sampling where supported in texture assignment calls
- Migrated ring and mask paths to BLP assets:
  - `Media/Solid.blp`
  - `Media/SolidInverseMask.blp`

## 1.4
- Higher resolution texture pipeline for the ring and mask.
- Removed legacy texture selection and standardized on custom texture + mask workflow.
- Added manual `Ring Thickness` control driven by mask scaling.
- Size control now uses percent values instead of raw radius values.
- Offset ranges adjusted for more granular control (`-100` to `100` for horizontal and vertical).
- New gradient defaults to make first-time selection visibly different:
  - Gradient angle default is `315`.
  - Gradient colors default to white/black.
