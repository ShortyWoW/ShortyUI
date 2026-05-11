local addonName, addon = ...

addon.changelogs = {
    ["2.8.0"] = {
        "|cFF999999New Features|r",
        "|cFF87e6e8Waypoint Triggers|r - Waypoints can now auto-advance using triggers instead of zone discovery messages. Triggers guide routing between discovery node paths, allowing segments to transition on gameplay events. Five types: proximity, zone change, buff gained/lost, spell cast, and vehicle enter/exit.",
        "|cFF87e6e8Conditional Routing|r - Segment routes can include conditional entries that evaluate player state (achievement, faction, level, class, quest) to determine which segments appear. Supports compound conditions with all/any logic.",
        "|cFF87e6e8Switch Branching|r - Multi-way branching with first-match-wins evaluation. Switch cases can resolve to a single route or expand into multiple routes, eliminating the need for wrapper segments.",
        "|cFF87e6e8Waypoint Actions|r - Waypoints can display an action button above the note frame that executes a macro when clicked (e.g., Exit Vehicle).",
        "|cFF87e6e8Coordinate-Optional Waypoints|r - Trigger waypoints can omit map coordinates. They appear in the segment list but skip map pins and overlay dots.",
        "|cFF87e6e8Route Editor|r - Triggers, actions, conditionals, and switch branches can all be created and edited in the route editor. Switch case routes are drillable, with each case navigable and reorderable like any segment.",
        "|cFF999999Improvements|r",
        "|cFF87e6e8Map Overlay|r - World map and minimap overlays now only display waypoints from the current segment.",
        "|cFF87e6e8Route Display|r - Removed the note column from the segment waypoint list. Trigger and action indicators shown inline on waypoint rows.",
        "|cFF87e6e8Orphan Detection|r - Routes referenced by any conditional branch are excluded from the top-level menu regardless of current evaluation.",
    },
    ["2.7.2"] = {
        "|cFF999999New Features|r",
        "|cFF87e6e8Guides|r - Added a Guides tab with articles on skyriding leveling basics, advanced skyriding techniques, and lorewalking. An Addon Information section provides explanation of features, commands, and other information.",
        "|cFF87e6e8Change Log Viewer|r - Version History is now accessible from the Guides tab. When a new version is detected, the addon opens directly to the version history page.",
        "|cFF999999Improvements|r",
        "|cFF87e6e8Route Migration|r - Routes are now automatically migrated to the latest version on addon update.",
        "|cFF87e6e8UX Improvements|r - Changes to many things including row highlighting, consistent label colours, improved button spacing, and refined route browser navigation.",
        "|cFF999999Route Changes|r",
        "|cFF87e6e8Eastern Kingdoms|r - Corrected coordinates for Okril'lon Hold.",
    },
    ["2.7.0"] = {
        "|cFF999999Improvements|r",
        "|cFF87e6e8Midnight Routes|r - Default routes have been updated for Midnight and replaced with 10-90 routes for both Horde and Alliance factions.",
        "|cFF87e6e8Minimap Overlay|r - The minimap overlay now draws a line from the player to the current waypoint instead of rendering the previous waypoint and connecting it to the current one.",
    }
}

