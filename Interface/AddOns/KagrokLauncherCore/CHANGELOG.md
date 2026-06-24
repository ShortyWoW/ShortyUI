# Kagrok Launcher Core Changelog

## 1.1.0
- Changed addon settings integration so Kagrok addon pages stay top-level in the AddOns list by default, with an option in the shared hub to sublist individual addons under `Kagrok's Addons` when preferred.
- Added reload-required messaging for settings placement changes so users know when a `/reload` is needed before the AddOns list updates.
- Made addon titles in the shared settings hub behave like settings links, including underline styling and hover tooltips that jump directly to the selected addon's settings page.
- Added tooltips for the drag handle and launcher override controls to explain shared minimap ordering and default-launcher behavior.
- Refined the shared settings layout with better row alignment, wrapped description text, and other list readability polish while keeping the current shared minimap implementation.

## 1.0.3
- Added drag-and-drop reordering to the shared `Registered Addons` list with a six-dot grip handle on each row.
- Made the shared launcher list update live while dragging so rows slide into place before drop.
- Saved the reordered list back into launcher priority overrides so the launcher menu and settings order stay in sync.

## 1.0.2
- Made addon names in the shared `Kagrok's Addons` settings hub clickable so they open the selected addon's specific settings panel.
- Kept the per-row launcher override button separate from the new direct settings shortcut.

## 1.0.1
- Reworked the shared launcher popup menu to use multiple columns when several addons are present, avoiding the old single-column scrollbar in normal multi-addon setups.

## 1.0.0
- Initial release of the standalone shared launcher core addon.
- Centralized the shared minimap launcher, settings hub, and developer info modules for Kagrok addons.
