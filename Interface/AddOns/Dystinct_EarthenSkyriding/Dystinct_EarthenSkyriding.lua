local addonName, addon = ...

local LibDeflate
local LibSerialize
local LibBabble

addon.importExportEnabled = false

addon.Localized = {}

function addon:Localize()
    if not LibStub then
        return
    end
    
    if not LibBabble then
        LibBabble = LibStub("LibBabble-SubZone-3.0", true)
        if LibBabble then
            addon.Localized = LibBabble and LibBabble:GetUnstrictLookupTable()
        end
    end
end

function addon:LocalizedString(string)
    return addon.Localized[string] or string
end

function addon:CheckLibraries()
    if not LibSerialize then
        LibSerialize = _G.LibSerialize
    end

    if not LibDeflate then
        LibDeflate = _G.LibDeflate
    end
    
    local hasLibs = LibDeflate and LibSerialize
    if hasLibs and not addon.importExportEnabled then
        addon.importExportEnabled = true
    end
end

function addon:AdjustProgressRunIndices(removedIndex)
    if not PersistentData.progress then return end
    for charID, saved in pairs(PersistentData.progress) do
        if saved.runIndex then
            if saved.runIndex == removedIndex then
                saved.runIndex = nil
            elseif saved.runIndex > removedIndex then
                saved.runIndex = saved.runIndex - 1
            end
        end
    end
end

function addon:Initialize()
    addon:Localize()
    addon:CheckLibraries()

    if not PersistentData then
        PersistentData = {
            routes = addon:DefaultRoutes(),
            runs = {},
            note = { visible = true, anchor = "CENTER", relative = "TOP", x = 0, y = -300 },
            announcement = { anchor = "TOP", relative = "TOP", x = 0, y = -25 },
            progress = {},
            minimap = { angle = 225 },
            waypoints = { tomtom = "auto", pins = "auto", mapOverlay = true }
        }
    else
        if not PersistentData.progress then
            PersistentData.progress = {}
        end
        if not PersistentData.minimap then
            PersistentData.minimap = { angle = 225 }
        end
        if not PersistentData.waypoints then
            PersistentData.waypoints = { tomtom = "auto", pins = "auto", mapOverlay = true }
        end
        if PersistentData.waypoints.mapOverlay == nil then
            PersistentData.waypoints.mapOverlay = true
        end

        for i = #PersistentData.runs, 1, -1 do
            if #PersistentData.runs[i].discoveries == 0 then
                addon:AdjustProgressRunIndices(i)
                table.remove(PersistentData.runs, i)
            end
        end
    end
    addon.data = PersistentData

    local currentVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
    if addon.data.version ~= currentVersion then
        addon:RunMigrations(addon.data.version)
        addon.data.version = currentVersion
    end

    addon.menu = addon.processRoutes(addon.data.routes)

    addon.ui:Initialize()

    addon:InitializeMinimap()
    addon:InitializeWorldMapOverlay()
    addon:InitializeMinimapOverlay()

    addon:ClearTomTomWaypoints()

    if addon:ResumeProgress() then
        addon.ui:Show()
    end
end

local function SlashCommandHandler(msg)
    msg = msg:lower()
    if msg == "show" or msg == "" then
        addon.ui:Show()
    elseif msg == "hide" then
        addon.ui:Hide()
    elseif msg == "reset" then
        addon.ui:SetUserPlaced(false)
        addon.ui:ClearAllPoints()
        addon.ui:SetPoint("CENTER", UIParent, "CENTER")
        addon.ui:Show()
    elseif msg == "minimap" then
        addon.data.minimap.hidden = not addon.data.minimap.hidden
        addon.minimapButton:SetShown(not addon.data.minimap.hidden)
        addon.ui.SettingsFrame:Refresh()
    elseif msg == "help" then
        print("Dystinct Earthen Skyriding Commands")
        print("  /dyses - Toggle window")
        print("  /dyses show - Show window")
        print("  /dyses hide - Hide window")
        print("  /dyses reset - Reset window position")
        print("  /dyses minimap - Toggle minimap button")
        print("  /dyses help - Show this help message")
    else
        addon.ui:SetShown(not addon.ui:IsShown())
    end
end

SLASH_DYSES1 = "/dyses"
SlashCmdList["DYSES"] = SlashCommandHandler

BINDING_NAME_DYSES_MARK_DISCOVERED = "Mark Node Discovered"
BINDING_NAME_DYSES_GO_PREVIOUS = "Restore Previous Node"
BINDING_NAME_DYSES_NEXT_SEGMENT = "Next Segment"
BINDING_NAME_DYSES_PREV_SEGMENT = "Previous Segment"

function DysES_MarkCurrentDiscovered()
    if not addon.active or not addon.segment.route or not addon.waypoint.index then return end
    addon.segment.route[addon.waypoint.index].discovered = true
    addon:DetermineNextWaypoint()
    addon.ui.SegmentFrame:Refresh()
end

function DysES_GoToPreviousNode()
    if not addon.active or not addon.segment.route or not addon.waypoint.index then return end
    if addon.waypoint.index > 1 then
        addon.segment.route[addon.waypoint.index - 1].discovered = false
        addon.waypoint.index = addon.waypoint.index - 1
    else
        local prevLeaf = addon:FindPreviousLeaf(addon.menu[addon.active.path[1]], addon.active.path)
        if not prevLeaf then return end
        local section = prevLeaf.path[#prevLeaf.path]
        addon.active = prevLeaf
        addon.segment = addon:LoadWaypoints(section)
        addon.waypoint.index = #addon.segment.route
        addon.segment.route[addon.waypoint.index].discovered = false
    end
    addon:UpdateWaypointArrow()
    addon.ui.SegmentFrame:Refresh()
    addon:SaveProgress()
end

function DysES_NextSegment()
    if not addon.active then return end
    addon:JumpToNextSegment()
end

function DysES_PreviousSegment()
    if not addon.active then return end
    addon:JumpToPreviousSegment()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        addon:HandleChatMsgSystem(...)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if not addon:CheckZoneTrigger() then
            addon:UpdateWaypointArrow()
        end
    elseif event == "ADDON_LOADED" then
        if ... == addonName then
            addon:Initialize()
        end
    end
end)