local addonName, addon = ...

function addon:FindWaypointIndex(name)
    if not addon.segment.route then return nil end
    for index, waypoint in ipairs(addon.segment.route) do
        if not waypoint.discovered then
            if addon:LocalizedString(name):gsub("Die ", ""):gsub("Les ", "") == addon:LocalizedString(waypoint.data.name):gsub("Die ", ""):gsub("Les ", "") then
                return index
            end
        end
    end
    return nil
end

function addon:HandleChatMsgSystem(msg)
    local pattern = ERR_ZONE_EXPLORED_XP:gsub("1%$", ""):gsub("2%$", ""):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    local _, _, zone = string.find(msg, pattern)
    if zone then
        local index = addon:FindWaypointIndex(addon:LocalizedString(zone))
        addon:RecordEvent(zone, index)
        if index ~= nil then
            addon.segment.route[index].discovered = true
        end
        if index == addon.waypoint.index then
            addon:DetermineNextWaypoint()
            addon:UpdateWaypointArrow()
        else
            addon:RefreshWorldMapOverlay()
            addon:RefreshMinimapOverlay()
        end
        addon.ui.SegmentFrame:Refresh()
        addon.ui.LogFrame:LoadRun(addon.ui.LogFrame.viewer.run or #addon.data.runs)
        addon:SaveProgress()
    end
end

function addon:StartNewRun()
    local charID = addon:GetCharacterID()
    local playerClass, _ = UnitClass("player")

    local route = addon.active and addon.active.path[1] or nil
    addon.data.runs[#addon.data.runs + 1] = {
        discoveries = {},
        route = route and (addon.data.routes[route].display or route) or "No Route",
        character = charID,
        class = playerClass,
        date = date("%Y-%m-%d", time())
    }

    addon.ui.LogFrame.selection.view_active:Enable()
    addon.ui.LogFrame:ShowActiveRun()
    addon.ui.SettingsFrame:Refresh()
    addon:SaveProgress()
end

function addon:RecordEvent(name, index)
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")

    local status
    if index == nil then
        status = "new"
    elseif index == addon.waypoint.index then
        status = "ok"
    else
        status = "unexpected"
    end

    if #addon.data.runs == 0 then
        addon:StartNewRun()
    end

    local run = addon.data.runs[#addon.data.runs]
    run.discoveries[#run.discoveries + 1] = {
        name = name,
        mapID = mapID,
        zoneName = GetRealZoneText(),
        timestamp = time(),
        experience = UnitXP("player"),
        level = UnitLevel("player"),
        segment = (addon:LocalizedString(addon.active and addon.active.path[#addon.active.path])) or "",
        x = math.floor(pos.x * 10000) / 100,
        y = math.floor(pos.y * 10000) / 100,
        status = status
    }
    
    addon.ui.LogFrame:Refresh()
end