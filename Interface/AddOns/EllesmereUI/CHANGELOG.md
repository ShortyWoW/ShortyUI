# EllesmereUI

## [v8.3.2](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.3.2) (2026-06-28)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.3.1...v8.3.2) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.3.2  
- Merge pull request #479 from nulltyto/bugfix/ebon-might-icons  
    Fix CDM custom-shape display for fake-active overlays  
- Merge pull request #482 from smvoss/toggle-buff-glows-combat  
    Add combat-only option for CDM bar glows  
- Merge pull request #480 from Filpet96/feat/qol-hide-error-messages  
    Add Hide Error Messages quality-of-life option  
- Add combat-only option for CDM bar glows  
    Add an Only In Combat toggle to CDM bar glow assignments and gate  
    the runtime glow state on player combat. This lets a glow trigger  
    only while its aura condition matches and the player is in combat.  
    Also add the new UI label to the locale key list for translation  
    coverage.  
- Add Hide Error Messages quality-of-life option  
    Adds a "Hide Error Messages" toggle to the QoL Features tab that suppresses  
    the red UIErrorsFrame spam (e.g. "Not enough rage", "Ability is not ready  
    yet") while keeping a short whitelist of genuinely useful errors visible  
    (full bag, full quest log, group-finder/boot messages, pet/player dead,  
    pickpocket). Ping system errors are silenced too.  
    Off by default. The UIErrorsFrame OnEvent override is only installed while  
    the option is enabled and fully restored when disabled, so it costs nothing  
    for anyone who leaves it off.  
- Fix CDM custom-shape display for fake-active overlays  
    The CDM "fake active" overlay (Ebon Might and any spell given an Active  
    State duration) drew its own icon/swipe/glow on top of the real icon  
    without mirroring the icon's custom shape, breaking masking and several  
    related visuals. Fixes:  
    - Mask the overlay icon + swipe to the icon's custom shape; raise the  
      border above the overlay so the active swipe no longer covers it.  
    - Re-sync the overlay when its icon is restyled (border size / shape /  
      zoom change while the active window is open) instead of waiting for the  
      next trigger.  
    - Style the overlay's countdown number with the bar's Duration Text  
      settings (font / size / colour / offset / show toggle).  
    - Active Border now recolours custom-shape rings, on both the real path  
      and the fake-active overlay (previously square-borders only).  
    - Shape Glow masks to the shape on the overlay.  
    - Active glow restarts on colour/style change so live Glow Effect Color  
      edits take effect (previously never restarted while continuously active).  
    Regenerated Locales/\_keys.txt.  
- Merge pull request #478 from Filpet96/feat/cdm-custom-item-id  
    Add Custom Item ID tracking to Cooldown Manager  
- Merge branch 'main' into feat/cdm-custom-item-id  
- Add Custom Item ID tracking to Cooldown Manager  
    Adds a "Custom Item ID" option alongside "Custom Spell ID" in both the  
    buff-bar and CD/utility spell pickers, letting users track an arbitrary  
    item (e.g. a food/consumable) by its item ID. Items are stored as negative  
    markers (-itemID) and rendered through the existing item-preset path  
    (icon + item cooldown + bag count), so they behave the same as the built-in  
    potion/healthstone presets, including on buff bars.  
    Performance: the buff-bar item-injection pass is gated behind a set-once  
    ns.\_cdmAnyCustomItem flag (scanned from saved data at login, flipped live by  
    the picker), so it costs nothing for anyone who never adds a custom item. No  
    change to existing UI or behaviour unless a custom item is added.  
