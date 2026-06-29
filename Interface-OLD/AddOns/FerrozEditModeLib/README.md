# FerrozEditModeLib

A lightweight World of Warcraft library designed to simplify handling UI elements within the modern Edit Mode system.

## Overview

This library provides a standardized way to register frames with the Blizzard Edit Mode system, allowing for custom addons to persist positions, scales, and layouts alongside native UI elements.

## Installation

### For Developers (Standalone)
1. Download or clone this repository into your `Interface/AddOns/` folder.
2. Ensure the folder is named `FerrozEditModeLib`.

### As a Dependency
Add the following line to your addon's `.toc` file to ensure the library loads first:

```
## RequiredDeps: FerrozEditModeLib
```

## Usage

In your addon code, call the `Register` method. This handles the Blizzard Edit Mode registration and hooks your custom functions for entering and exiting Edit Mode.

```lua
-- Example: Registering BattleRezTracker
if FerrozEditModeLib then
    FerrozEditModeLib:Register(
        <ADDON>Frame, -- The frame to be managed
        <ADDON>_Settings,          -- Your addon's settings table (for position/scale by layout)
        {height=DEFAULT_HEIGHT,width=DEFAULT_WIDTH},-- a table that has defaults
    )
end
```
