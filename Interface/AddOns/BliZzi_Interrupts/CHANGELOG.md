# BliZzi Interrupts 3.3.10

## Border rendering fixed
- **The bar border now wraps the bar cleanly from the outside** instead of being drawn inward and eating pixels off the icon and bar content. Previous builds used Blizzard's default backdrop which draws the edge texture inside the frame — at larger border sizes this made the bar look squished and the icon look chopped.
- **Icon and bar keep their full size.** The border overlay now extends outward around the frame so nothing inside gets compressed.
- **Built-in border selection refreshed.** The old list had a couple of textures that Blizzard's backdrop system can't render correctly (they collapsed into plain dark rectangles, making every option look identical). The list now only contains edge textures that actually work, plus a clean `Solid` option:
  - `Solid` — flat colored border, fully driven by the Border Color picker
  - `Tooltip (thin)` — classic thin tooltip rim
  - `Dialog (wooden)` — heavy wooden dialog-box frame
  - `Achievement Wood` — ornate achievement wood border
  - `Achievement Gold` — gold filigree achievement border
  - `Tutorial` — dotted tutorial frame
- **Border size slider is respected 1:1.** Pick the thickness you want; nothing is silently clamped.

## Settings page fixed
- **Interrupts page shows mode-correct options from the first open.** Previously, the first time you opened the Interrupts tab only the Display Mode dropdown was visible — you had to change the dropdown once for the other mode-specific options (Lock Position, Grow Upward, Icon Position, Bar Fill Direction, Sort Order for Bars; or the attached-display options for Attached mode) to appear. They now render immediately with the correct set for your current mode.
- **Collapsing and re-expanding the Display Mode section restores the correct options.** Before, re-opening a collapsed section would leave the mode-specific widgets hidden until you flipped the dropdown; now the section's visibility rules are re-applied when you expand it.
- **Attached Display is part of the Display Mode section.** No separate second section header — Bars options and Attached options both live under Display Mode and swap automatically based on the selected mode.

## New: Name color
- **Player-name color is now customizable.** Under *Colors → Name Color* you can either set a custom RGB color for the player names in the interrupt tracker bars, or enable *Use Class Colors (Names)* so each name takes the color of that player's class (Mage blue, Hunter green, …).
- The color picker hides itself while class colors are active — only the relevant control is visible at any time.
- Changes apply live, no `/reload` needed.

---

# BliZzi Interrupts 3.3.9

## Display mode cleanup & settings restructure
- **Icon Only Mode removed.** The compact horizontal icon strip conflicted visually and behaviourally with the new *Attached to Unit Frames* mode introduced in 3.3.8. The attached display is a strictly better replacement — each player gets their own icon at their unit frame, with cooldown sweep and counter text.
- **Settings page reorganized.** All display-scoped options now live under *Interrupts → Display Mode*, and the section adapts to the selected mode:
  - **Bars / Window** mode shows: Lock Position, Grow Upward, Icon Position, Bar Fill Mode, Sort Order.
  - **Attached to Unit Frames** mode shows: the full *Attached Display* block (Frame Provider, Attach Position, Offset X/Y, Icon Size, Counter Text Size, Desaturate on Cooldown, Show Own Icon on Player Frame).
  - Options not relevant to the current mode collapse to zero height — no empty sections, no clutter.
- **Live preview.** Switching the Display Mode dropdown re-layouts the settings page immediately; no `/reload` required to see mode-specific options appear or disappear.

## Solo Mode + Attached display
- **Solo Mode now respects Attached mode.** Previously Solo Mode only hid party bars in the classic window — attached party icons stayed visible. Both renderers now honor the toggle identically, and flipping Solo Mode updates the attached icons live.

## Internal
- `LayoutWidgets` now supports `_dynamic` section headers, so hiding a section also collapses all its children to zero height without needing a page rebuild. Used by the new Display Mode grouping above.

---

# BliZzi Interrupts 3.3.8

## New display mode: Attached to Unit Frames
- **Interrupt tracker can now attach icons directly to party unit frames** instead of showing a standalone bars window. Each party member gets exactly one icon — their class/spec interrupt spell — anchored next to their frame, with a cooldown sweep and countdown text.
- Shared frame-provider detection with Party CDs: Blizzard, ElvUI, Cell, Grid2 and Danders/D4 are auto-detected (or can be pinned explicitly).
- Settings under *Interrupts → Attached Display*:
  - Display Mode: `Bars / Window` (classic) or `Attached to Unit Frames`
  - Attach Position: Left / Right / Top / Bottom
  - Offset X / Y (-100 to 100 px)
  - Icon Size (12–64 px)
  - Counter Text Size (6–28 px)
  - Desaturate on Cooldown (toggle)
  - Show Own Icon on Player Frame (toggle)
- The classic bars window is hidden automatically while Attached Mode is active; switching back brings it right back. Settings panel always previews the bars window when open so layout tweaks stay visible.

---

# BliZzi Interrupts 3.3.7

## WoW 12.0.5 compatibility

### Party-kick detection rebuild
- **`UNIT_SPELLCAST_SUCCEEDED` no longer fires for party members in 12.0.5**, which broke the old cast↔interrupt correlation for teammate kicks. `COMBAT_LOG_EVENT_UNFILTERED` registration is also protected for this addon (triggers `ADDON_ACTION_FORBIDDEN`), so both traditional cast sources are unavailable.
- **New heuristic attribution** on `UNIT_SPELLCAST_INTERRUPTED` (mob-side still fires). When a nameplate cast gets interrupted we pick the responsible party member using a tiered signal, strongest first:
  1. Exactly one party member targets the interrupted mob → that one.
  2. Multiple targeting candidates → the closest to the mob.
  3. Exactly one in-range (≤35 yd) off-CD candidate → that one.
  4. Multiple in-range → the closest.
  5. Exactly one off-CD candidate overall → solo attribution.
- **Distance filter** uses `UnitPosition(nameplate)` vs. `UnitPosition(partyN)` in the same instance map. Unknown distance is tolerated (candidate passes through instead of being rejected).
- **Own-kick protection**: if the local player's target matches the interrupted mob and a pending kick marker is fresh (<300 ms), party attribution is skipped so the own-player `_playerFrame` path keeps the credit.

### Party-defensive detection (SyncCD) rebuild
- **Aura scan rewritten as single-pass** `GetUnitAuras(unit, "HELPFUL")` with per-instance `IsAuraFilteredOutByInstanceID` probes for `BIG_DEFENSIVE`, `EXTERNAL_DEFENSIVE`, `IMPORTANT`, `RAID_IN_COMBAT`. The previous combined filter strings `HELPFUL|BIG_DEFENSIVE` etc. return empty arrays on party units in 12.0.5.
- **Self-cast Cast-evidence relaxation.** Party casts can no longer produce Cast evidence. For self-cast (non-external) rules the aura itself now substitutes for Cast, gated to:
  - exact spellId match (unambiguous), OR
  - stripped spellId plus flag-signature + duration match (±1.5 s incl. talent mods).
- **Table-form evidence** like `{"Cast","UnitFlags"}` (Dispersion, Ice Block, AMS, …) is handled by the same relaxation: only the `Cast` slot is substituted, all other required items must be genuinely present.
- **Icon-file-ID fallback** for stripped spellIds. A per-class `icon → spellID` map is built from the rule table; the aura's icon is laundered through the taint helpers and looked up when direct spellId extraction fails. Class-scoped to avoid cross-class collisions.
- **Duration capture** from aura data (taint-safe via pcall + slider-laundering fallback) feeds the ambiguous-match duration gate.
- **Taint-safe ingest** across the scan: `ad.spellId`, `ad.icon` and `ad.duration` are all treated as potentially-secret values; every comparison and table-index is pcall-wrapped so one tainted aura can no longer abort the entire scan loop.

### Data fix
- **Mistweaver Monk (spec 270) marked `noKick=true`.** MW cannot cast Spear Hand Strike — the previous entry silently registered the icon for healer Monks whenever `UnitGroupRolesAssigned` returned anything other than `HEALER` (manual group, role-detection race, etc.). All registration paths (auto-by-class, LibSpec comm, spec-switch-via-cast) now correctly classify MW as no-interrupt.

---

# BliZzi Interrupts 3.3.6

## New Feature: Smart Misdirect (Hunter / Rogue)
- Optional extra feature that automatically re-targets **Misdirection** (Hunter) or **Tricks of the Trade** (Rogue) to the most useful target. Off by default; enable it on the new **Smart Misdirect** sidebar tab (visible only for eligible classes).
- **Priority order:** manual override → focus → tanks → own pet (Hunter only).
- **Tank selection methods:**
  - *By Role* — every group member flagged TANK.
  - *Role + Main Tank* — TANK role plus `MAINTANK` raid assignments.
  - *Main Tank first* — `MAINTANK` assignments first, then role-TANKs.
  - *Main Tank only* — strictly `MAINTANK`-flagged players.
- **Manual override** field for pinning a specific player (with optional realm for cross-realm). Clears automatically when you leave the group.
- **Focus priority toggle** — focus target wins over tanks when set to a party/raid member.
- **Pet fallback** (Hunter only) — uses your own pet if no other valid target exists. Tricks of the Trade cannot target the caster's pet, so the option is hidden for Rogues.
- **Chat announcer** prints the current target (or "no valid target") on change. Suppressed while mounted and in BG / Arena to avoid spam.
- **Create / Update Macro** button in the settings creates a per-character WoW macro (`SmartMD` / `SmartTotT`) that drives two hidden secure action buttons. Drag the macro onto your action bar — one click always casts at the correct target.
- Built on two `SecureActionButtonTemplate` buttons so the reassignment is fully blizzard-safe. The buttons defer every attribute change until combat ends (required for secure frames in 12.x).
- Events wired: `PLAYER_FOCUS_CHANGED`, `GROUP_ROSTER_UPDATE`, `GROUP_LEFT`, `PLAYER_ROLES_ASSIGNED`, `ROLE_CHANGED_INFORM`, `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_REGEN_ENABLED`, `PLAYER_ENTERING_WORLD`. Non-eligible classes never register any of them.
- Locale coverage: `en_US`, `de_DE`, `es_ES`, `fr_FR`, `ru_RU`, `tlh_TLH`.

## Feign Death Fixes (own player)
- **Glow no longer gets stuck** after Feign Death is cancelled early. Previously the 6-minute buff timer kept the glow active even though the buff was already gone, because the aura is not part of the tracked-category scan that normally clears the glow at buff expiry.
- **Cooldown now starts when the buff ends**, not when the spell is cast. Feign Death is almost always cancelled early (damage taken, manual cancel, or out-of-combat), so starting the 30 s CD at cast time showed the wrong remaining time.
- **Two independent buff-end signals** now clear the glow (whichever fires first wins):
  - `UNIT_AURA` observes the FD aura transitioning from present → absent. This is the primary path — it also fires for early cancels (damage during the 0.5 s cast-to-FD latency) and manual `/cancelaura`, neither of which triggers `UNIT_FLAGS`.
  - `UNIT_FLAGS` observes `UnitIsFeignDeath` flipping true → false, as a second safety net.
- **Self-cancel check in `UpdateIcon` got a fallback path.** The `C_UnitAuras.GetAuraDataBySpellID` call can throw `table index is secret` in 12.x when it hits a tainted aura; the throw was silently swallowed by pcall and the glow never cleared. The check now falls back to enumerating via `GetUnitAuras` so the self-cancel still works under taint.
- Party members already behaved correctly; only the own-player path was affected.

## Icon Display
- **CD swipe and timer text are now hidden while the glow is active.** Showing both at once is misleading — the defensive is still up, so there is no meaningful CD to display yet. The CD appears the moment the glow ends.

## Flicker Fixes
- **No more icon flicker on `SPELLS_CHANGED` noise events.** The event fires for many reasons unrelated to talents (glyph swap, shapeshift, sometimes transiently after casts). Previously every fire bumped the internal talent version, which tore down and recreated all icons. Now the rebuild only triggers when the active talent set or full talent list actually changed.
- **Rows in the Window view are no longer hidden-then-shown on every rebuild.** Rebuild triggers like incoming HELLO broadcasts used to hide every row at the start and show them again at the end — one frame of invisibility visible as a blink. Only rows for players who left the group now get hidden.
- **Icon diff on row/bar rebuilds.** When the spell list truly changes (spec switch, talent change), only icons for removed spells get hidden and only icons for newly added spells get created. Icons for spells that are in both the old and new list are reused and just repositioned — no flash from a fresh texture load.
- **Attached bars reuse their frame across rebuilds.** Only a parent-unit-frame swap (caused by switching unit-frame addons) forces a fresh frame; all other changes (layout, offsets, size, talents) update the existing frame in place.

## Custom Name System
- **Custom name is now per-character by default.** Every character can have its own nickname that gets broadcast to the group.
- **Added a global nickname with an override toggle.** Enabling *Use Global Nickname* makes every character use the same name — useful if you want all your alts to show up under one name.
- **Legacy account-wide custom name migrates automatically** into the per-character slot on first login.
- Locale coverage: `en_US`, `de_DE`, `es_ES`, `fr_FR`, `ru_RU`, `tlh_TLH`.

## Error Fixes
- **Fixed `ADDON_ACTION_BLOCKED` on `Button:SetPropagateMouseClicks()`** (reported 112x). The call was firing during bar rebuilds that occasionally happened in combat, which is forbidden for protected frame methods in 12.x. Both call sites now guard with `InCombatLockdown()` and defer the call to `PLAYER_REGEN_ENABLED` (combat exit) if needed.

## Events / Internal
- New DevLog lines: `[FD]` for own-player Feign Death cast, buff-end via `UNIT_AURA`, and buff-end via `UNIT_FLAGS`.
