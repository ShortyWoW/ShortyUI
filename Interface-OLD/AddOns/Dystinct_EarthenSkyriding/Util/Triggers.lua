local addonName, addon = ...

local activeTrigger = nil -- "proximity" | "zone" | "buff" | nil
local triggerFrame = nil
local PROXIMITY_DEFAULT_RADIUS = 25
local PROXIMITY_INTERVAL = 0.2

-- Cached waypoint world position for proximity checks (avoid recomputing each frame)
local cachedWpWorldX, cachedWpWorldY, cachedWpContinent
local cachedRadius
local elapsed = 0

---------------------------------------------------------------------------
-- Shared advancement helper
---------------------------------------------------------------------------

local function TriggerDiscovery()
    local wpIndex = addon.waypoint.index
    if not wpIndex or not addon.segment.route or not addon.segment.route[wpIndex] then return end
    addon.segment.route[wpIndex].discovered = true
    addon:DetermineNextWaypoint()
    addon:UpdateWaypointArrow()
    addon.ui.SegmentFrame:Refresh()
    addon:SaveProgress()
end

---------------------------------------------------------------------------
-- Proximity trigger
---------------------------------------------------------------------------

local function CheckProximity()
    local playerMapID = C_Map.GetBestMapForUnit("player")
    if not playerMapID then return end

    local playerPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    if not playerPos then return end

    local playerContinent, playerWorld = C_Map.GetWorldPosFromMapPos(playerMapID, playerPos)
    if not playerContinent or not playerWorld then return end

    -- Must be on the same continent
    if playerContinent ~= cachedWpContinent then return end

    local dx = playerWorld.x - cachedWpWorldX
    local dy = playerWorld.y - cachedWpWorldY
    local distSq = dx * dx + dy * dy

    if distSq <= cachedRadius * cachedRadius then
        TriggerDiscovery()
    end
end

local function OnProximityUpdate(self, dt)
    elapsed = elapsed + dt
    if elapsed < PROXIMITY_INTERVAL then return end
    elapsed = 0
    CheckProximity()
end

local function ActivateProximity(trigger, waypoint)
    local mapID = tonumber(waypoint.map)
    if not mapID then return false end

    local wpX = (tonumber(waypoint.x) or 0) / 100
    local wpY = (tonumber(waypoint.y) or 0) / 100

    local continent, worldPos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(wpX, wpY))
    if not continent or not worldPos then return false end

    cachedWpWorldX = worldPos.x
    cachedWpWorldY = worldPos.y
    cachedWpContinent = continent
    cachedRadius = trigger.radius or PROXIMITY_DEFAULT_RADIUS
    elapsed = 0

    if not triggerFrame then
        triggerFrame = CreateFrame("Frame")
    end
    triggerFrame:SetScript("OnUpdate", OnProximityUpdate)
    triggerFrame:Show()

    activeTrigger = "proximity"
    return true
end

---------------------------------------------------------------------------
-- Zone trigger
---------------------------------------------------------------------------

local function ActivateZone()
    activeTrigger = "zone"
    return true
end

function addon:CheckZoneTrigger()
    if activeTrigger ~= "zone" then return false end
    if not addon.waypoint.index or not addon.segment.route then return false end

    local wp = addon.segment.route[addon.waypoint.index]
    if not wp then return false end

    local trigger = wp.data.trigger
    local targetMapID = tonumber(trigger and trigger.map or wp.data.map)
    if not targetMapID then return false end

    local playerMapID = C_Map.GetBestMapForUnit("player")
    if not playerMapID then return false end

    -- Direct match
    if playerMapID == targetMapID then
        TriggerDiscovery()
        return true
    end

    -- Walk up parent hierarchy for sub-zone matching
    local info = C_Map.GetMapInfo(playerMapID)
    while info and info.parentMapID do
        if info.parentMapID == targetMapID then
            TriggerDiscovery()
            return true
        end
        info = C_Map.GetMapInfo(info.parentMapID)
    end

    return false
end

---------------------------------------------------------------------------
-- Buff trigger
---------------------------------------------------------------------------

local function OnBuffEvent(self, event, unit)
    if event ~= "UNIT_AURA" or unit ~= "player" then return end
    if activeTrigger ~= "buff" then return end
    if not addon.waypoint.index or not addon.segment.route then return end

    local wp = addon.segment.route[addon.waypoint.index]
    if not wp or not wp.data.trigger then return end

    local trigger = wp.data.trigger
    local spellId = trigger.spellId
    if not spellId then return end

    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
    local hasAura = aura ~= nil
    local wantGained = trigger.gained ~= false -- default true

    if hasAura == wantGained then
        TriggerDiscovery()
    end
end

local function ActivateBuff(trigger)
    if not trigger.spellId then return false end

    if not triggerFrame then
        triggerFrame = CreateFrame("Frame")
    end
    triggerFrame:SetScript("OnUpdate", nil)
    triggerFrame:SetScript("OnEvent", OnBuffEvent)
    triggerFrame:RegisterEvent("UNIT_AURA")
    triggerFrame:Show()

    activeTrigger = "buff"
    return true
end

---------------------------------------------------------------------------
-- Cast trigger
---------------------------------------------------------------------------

local function OnCastEvent(self, event, unit, _, spellId)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end
    if activeTrigger ~= "cast" then return end
    if not addon.waypoint.index or not addon.segment.route then return end

    local wp = addon.segment.route[addon.waypoint.index]
    if not wp or not wp.data.trigger then return end

    if spellId == wp.data.trigger.spellId then
        TriggerDiscovery()
    end
end

local function ActivateCast(trigger)
    if not trigger.spellId then return false end

    if not triggerFrame then
        triggerFrame = CreateFrame("Frame")
    end
    triggerFrame:SetScript("OnUpdate", nil)
    triggerFrame:SetScript("OnEvent", OnCastEvent)
    triggerFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    triggerFrame:Show()

    activeTrigger = "cast"
    return true
end

---------------------------------------------------------------------------
-- Vehicle trigger
---------------------------------------------------------------------------

local function OnVehicleEvent(self, event, unit)
    if unit ~= "player" then return end
    if activeTrigger ~= "vehicle" then return end

    local wp = addon.segment.route[addon.waypoint.index]
    if not wp or not wp.data.trigger then return end

    local wantEntered = wp.data.trigger.entered ~= false -- default true
    local entered = (event == "UNIT_ENTERED_VEHICLE")

    if entered == wantEntered then
        TriggerDiscovery()
    end
end

local function ActivateVehicle(trigger)
    if not triggerFrame then
        triggerFrame = CreateFrame("Frame")
    end
    triggerFrame:SetScript("OnUpdate", nil)
    triggerFrame:SetScript("OnEvent", OnVehicleEvent)
    triggerFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    triggerFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    triggerFrame:Show()

    activeTrigger = "vehicle"
    return true
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function addon:DeactivateTrigger()
    if triggerFrame then
        triggerFrame:SetScript("OnUpdate", nil)
        triggerFrame:SetScript("OnEvent", nil)
        triggerFrame:UnregisterAllEvents()
        triggerFrame:Hide()
    end
    activeTrigger = nil
    cachedWpWorldX = nil
    cachedWpWorldY = nil
    cachedWpContinent = nil
end

function addon:ActivateTrigger()
    addon:DeactivateTrigger()

    if not addon.waypoint.index or not addon.segment.route then return end

    local wp = addon.segment.route[addon.waypoint.index]
    if not wp or not wp.data.trigger then return end

    local trigger = wp.data.trigger
    local triggerType = trigger.type

    if triggerType == "proximity" then
        ActivateProximity(trigger, wp.data)
    elseif triggerType == "zone" then
        ActivateZone()
    elseif triggerType == "buff" then
        ActivateBuff(trigger)
    elseif triggerType == "cast" then
        ActivateCast(trigger)
    elseif triggerType == "vehicle" then
        ActivateVehicle(trigger)
    end
end

---------------------------------------------------------------------------
-- Condition evaluator (used by ProcessRoutes for conditional segments)
---------------------------------------------------------------------------

function addon:EvaluateCondition(cond)
    if not cond or not cond.type then return false end

    local condType = cond.type

    if condType == "achievement" then
        local _, _, _, completed = GetAchievementInfo(cond.id)
        return completed == true

    elseif condType == "faction" then
        return UnitFactionGroup("player") == cond.faction

    elseif condType == "level" then
        return UnitLevel("player") >= (cond.level or 0)

    elseif condType == "class" then
        local _, classToken = UnitClass("player")
        return classToken == cond.class

    elseif condType == "quest" then
        return C_QuestLog.IsQuestFlaggedCompleted(cond.id)

    elseif condType == "all" then
        for _, sub in ipairs(cond.conditions) do
            if not addon:EvaluateCondition(sub) then return false end
        end
        return true

    elseif condType == "any" then
        for _, sub in ipairs(cond.conditions) do
            if addon:EvaluateCondition(sub) then return true end
        end
        return false
    end

    return false
end
