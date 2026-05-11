local addonName, addon = ...

addon.segment = { waypoints = {}}
addon.waypoint = { index = nil, arrow = nil }

function addon:GetCharacterID()
    local playerName, realm = UnitName("player")
    if not realm then
        realm = GetRealmName()
    end
    return playerName .. "-" .. realm
end

function addon:SaveProgress()
    if not addon.active or not addon.segment.route or not addon.waypoint.index then
        return
    end

    if not addon.data.progress then
        addon.data.progress = {}
    end

    local charID = addon:GetCharacterID()
    local leafName = addon.active.path[#addon.active.path]
    local discoveries = {}
    for i, wp in ipairs(addon.segment.route) do
        discoveries[i] = wp.discovered
    end

    addon.data.progress[charID] = {
        activePath = addon.active.path,
        segmentDiscoveries = discoveries,
        waypointIndex = addon.waypoint.index,
        runIndex = #addon.data.runs,
        routeVersion = #(addon.data.routes[leafName] and addon.data.routes[leafName].route or {}),
    }
end

function addon:ClearProgress()
    if addon.data.progress then
        local charID = addon:GetCharacterID()
        addon.data.progress[charID] = nil
    end
end

function addon:ResumeProgress()
    if not addon.data.progress then return false end

    local charID = addon:GetCharacterID()
    local saved = addon.data.progress[charID]
    if not saved then return false end

    local rootName = saved.activePath[1]
    if not addon.menu[rootName] then
        addon.data.progress[charID] = nil
        return false
    end

    local leafName = saved.activePath[#saved.activePath]
    local routeData = addon.data.routes[leafName]
    if not routeData or not routeData.route then
        addon.data.progress[charID] = nil
        return false
    end

    if #routeData.route ~= saved.routeVersion then
        addon.data.progress[charID] = nil
        return false
    end

    local current = addon.menu[rootName]
    for i = 2, #saved.activePath do
        local found = false
        if current.children then
            for _, child in ipairs(current.children) do
                if child.name == saved.activePath[i] then
                    current = child
                    found = true
                    break
                end
            end
        end
        if not found then
            addon.data.progress[charID] = nil
            return false
        end
    end

    addon.active = current
    addon.segment = addon:LoadWaypoints(leafName)

    for i, discovered in ipairs(saved.segmentDiscoveries) do
        if addon.segment.route[i] then
            addon.segment.route[i].discovered = discovered
        end
    end

    addon.waypoint.index = saved.waypointIndex
    if addon.waypoint.index > #addon.segment.route then
        addon.waypoint.index = #addon.segment.route
    end

    if saved.runIndex and saved.runIndex > 0 and saved.runIndex <= #addon.data.runs then
        addon.ui.LogFrame.selection.view_active:Enable()
        addon.ui.LogFrame:ShowActiveRun()
    else
        addon:StartNewRun()
    end

    addon:UpdateWaypointArrow()
    addon.ui:Refresh()

    return true
end

function addon:UpdateActive(item)
    addon.active = addon:FindFirstLeaf(item)
    addon.segment = addon:LoadWaypoints(addon.active.path[#addon.active.path])
    addon.waypoint.index = 1

    if addon.segment.route[addon.waypoint.index] == nil then
        addon:RunCompleted(addon.active.path[1])
        addon:ClearActive()
        return
    end

    addon:UpdateWaypointArrow()

    addon.ui:Refresh()
    addon:SaveProgress()
end

function addon:ClearActive()
    addon:DeactivateTrigger()
    addon:ClearProgress()
    addon.active = nil
    addon.segment = { waypoints = {} }
    addon.waypoint.index = nil
    addon.ui.LogFrame.selection.view_active:Disable()

    addon.ui:Refresh()
    addon:RefreshWorldMapOverlay()
    addon:RefreshMinimapOverlay()
end

function addon:FindNextLeaf(menu, path)
    if not menu or not path or #path < 2 then
        return nil
    end

    local indices = {}
    local current = menu
    
    for i = 2, #path do
        if not current.children then
            return nil
        end
        
        local found = false
        for j, item in ipairs(current.children) do
            if item.name == path[i] then
                table.insert(indices, j)
                current = item
                found = true
                break
            end
        end
        
        if not found then
            return nil
        end
    end
    
    local workingIndices = {unpack(indices)}
    local depth = #workingIndices
    
    current = menu
    for i = 1, depth - 1 do
        if not current.children or not current.children[workingIndices[i]] then
            return nil
        end
        current = current.children[workingIndices[i]]
    end
    
    while depth > 0 do
        if current.children and workingIndices[depth] < #current.children then
            workingIndices[depth] = workingIndices[depth] + 1
            
            current = menu
            for i = 1, depth - 1 do
                current = current.children[workingIndices[i]]
            end
            
            current = current.children[workingIndices[depth]]
            while current.children and #current.children > 0 do
                current = current.children[1]
            end
            
            return current
        else
            depth = depth - 1
            if depth > 0 then
                current = menu
                for i = 1, depth - 1 do
                    current = current.children[workingIndices[i]]
                end
            end
        end
    end
    
    return nil
end

function addon:FindPreviousLeaf(menu, path)
    if not menu or not path or #path < 2 then
        return nil
    end

    local indices = {}
    local current = menu

    for i = 2, #path do
        if not current.children then
            return nil
        end

        local found = false
        for j, item in ipairs(current.children) do
            if item.name == path[i] then
                table.insert(indices, j)
                current = item
                found = true
                break
            end
        end

        if not found then
            return nil
        end
    end

    local workingIndices = {unpack(indices)}
    local depth = #workingIndices

    current = menu
    for i = 1, depth - 1 do
        if not current.children or not current.children[workingIndices[i]] then
            return nil
        end
        current = current.children[workingIndices[i]]
    end

    while depth > 0 do
        if current.children and workingIndices[depth] > 1 then
            workingIndices[depth] = workingIndices[depth] - 1

            current = menu
            for i = 1, depth - 1 do
                current = current.children[workingIndices[i]]
            end

            current = current.children[workingIndices[depth]]
            while current.children and #current.children > 0 do
                current = current.children[#current.children]
            end

            return current
        else
            depth = depth - 1
            if depth > 0 then
                current = menu
                for i = 1, depth - 1 do
                    current = current.children[workingIndices[i]]
                end
            end
        end
    end

    return nil
end

function addon:GetAllLeaves(node)
    local leaves = {}
    local function collect(n)
        if not n.children or #n.children == 0 then
            leaves[#leaves + 1] = n
        else
            for _, child in ipairs(n.children) do
                collect(child)
            end
        end
    end
    collect(node)
    return leaves
end

function addon:JumpToSegment(leaf)
    if not leaf then return end
    addon.active = leaf
    local section = leaf.path[#leaf.path]
    addon.segment = addon:LoadWaypoints(section)
    addon.waypoint.index = 1
    addon:Announce("New Chapter", addon.data.routes[section].display or section)
    addon:UpdateWaypointArrow()
    addon.ui:Refresh()
    addon:SaveProgress()
end

function addon:JumpToNextSegment()
    if not addon.active then return end
    addon:JumpToSegment(addon:FindNextLeaf(addon.menu[addon.active.path[1]], addon.active.path))
end

function addon:JumpToPreviousSegment()
    if not addon.active then return end
    addon:JumpToSegment(addon:FindPreviousLeaf(addon.menu[addon.active.path[1]], addon.active.path))
end

function addon:DetermineNextWaypoint()
    if not addon.segment.route then return end
    while (addon.segment.route[addon.waypoint.index].discovered)
    do
        if addon.waypoint.index < #addon.segment.route then
            addon.waypoint.index = addon.waypoint.index + 1
            addon:UpdateWaypointArrow()
        else
            local routeName = addon.data.routes[addon.active.path[1]].display or addon.active.path[1]
            addon.active = addon:FindNextLeaf(addon.menu[addon.active.path[1]], addon.active.path)
            if addon.active then
                local section = addon.active.path[#addon.active.path]
                addon:Announce("New Chapter", addon.data.routes[section].display or section)
                addon.segment = addon:LoadWaypoints(section)
                addon.waypoint.index = 1
                addon:SaveProgress()
                break
            else
                addon:RunCompleted(routeName)
                addon:ClearActive()
                break
            end
        end
    end
    addon:UpdateWaypointArrow()
    addon:SaveProgress()
end

function addon:LoadWaypoints(name)
    local segment = addon.data.routes[name]
    local newSegment = {
        map = segment.map,
        route = {}
    }

    for i, waypoint in ipairs(segment.route) do
        newSegment.route[#newSegment.route + 1] = {
            discovered = false,
            data = waypoint
        }
    end

    addon.ui.SegmentFrame.abandon:Enable()
    addon.ui.SegmentFrame.skip:Enable()
    addon.ui.SegmentFrame.next:Enable()

    return newSegment
end

local function GetTopLevelMap(startingMapID)
    local mapInfo = C_Map.GetMapInfo(startingMapID)
    
    while mapInfo and mapInfo.parentMapID do
        local newMapInfo = C_Map.GetMapInfo(mapInfo.parentMapID)
        if newMapInfo then 
            for _, name in ipairs({ "Azeroth", "Cosmic" }) do
                if newMapInfo.name == name then
                    return mapInfo
                end
            end
            mapInfo = newMapInfo
        else
            return mapInfo
        end
    end
    
    return mapInfo
end

function addon:ClearTomTomWaypoints()
    if not TomTom or not TomTom.waypoints then return end
    local toRemove = {}
    for mapId, waypoints in pairs(TomTom.waypoints) do
        for key, uid in pairs(waypoints) do
            if type(uid) == "table" and uid.from == "Dystinct Earthen Skyriding" then
                toRemove[#toRemove + 1] = uid
            end
        end
    end
    for _, uid in ipairs(toRemove) do
        TomTom:RemoveWaypoint(uid)
    end
end

function addon:ShouldUseTomTom()
    if not TomTom then return false end
    local setting = addon.data.waypoints and addon.data.waypoints.tomtom or "auto"
    if setting == "disable" then return false end
    return true
end

function addon:ShouldUsePins()
    local setting = addon.data.waypoints and addon.data.waypoints.pins or "auto"
    if setting == "enable" then return true end
    if setting == "disable" then return false end
    if not addon:ShouldUseTomTom() then return true end
    return C_AddOns.IsAddOnLoaded("WaypointUI")
end

function addon:UpdateWaypointArrow()
    if addon.waypoint.arrow and TomTom then
        TomTom:RemoveWaypoint(addon.waypoint.arrow)
        addon.waypoint.arrow = nil
    end
    if WaypointUIAPI and WaypointUIAPI.Navigation then
        WaypointUIAPI.Navigation.ClearUserNavigation()
    end
    C_Map.ClearUserWaypoint()
    C_SuperTrack.SetSuperTrackedUserWaypoint(false)

    if addon.waypoint.index then
        local waypoint = addon.segment.route[addon.waypoint.index].data
        local note = waypoint.note
        local hasAction = waypoint.action and waypoint.action.macro
        addon.note_active = (note and note ~= "") or hasAction
        local mapID = tonumber(waypoint.map) or tonumber(addon.segment.map) or nil

        if mapID then
            local waypointContinentMap = GetTopLevelMap(mapID)
            local playerMapID = C_Map.GetBestMapForUnit("player")
            local currentContinentMap = playerMapID and GetTopLevelMap(playerMapID)
            local waypointContinent = waypointContinentMap and waypointContinentMap.name
            local currentContinent = currentContinentMap and currentContinentMap.name
            local segment = addon.data.routes[addon.active.path[#addon.active.path]]

            local wx = (tonumber(waypoint.x) or 0) / 100
            local wy = (tonumber(waypoint.y) or 0) / 100

            if addon:ShouldUseTomTom() then
                addon.waypoint.arrow = TomTom:AddWaypoint(mapID, wx, wy, { title = addon:LocalizedString(waypoint.name), cleardistance = 0, from = "Dystinct Earthen Skyriding" })
            end

            if addon:ShouldUsePins() then
                local point = UiMapPoint.CreateFromCoordinates(mapID, wx, wy)
                C_Map.SetUserWaypoint(point)
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            else
                C_Timer.After(0, function()
                    if not addon:ShouldUsePins() then
                        C_Map.ClearUserWaypoint()
                        C_SuperTrack.SetSuperTrackedUserWaypoint(false)
                        if WaypointUIAPI and WaypointUIAPI.Navigation then
                            WaypointUIAPI.Navigation.ClearUserNavigation()
                        end
                    end
                end)
            end

            if waypointContinent == currentContinent then
                if addon.note_active then
                    addon:UpdateNote(note)
                else
                    addon.ui.NoteFrame:Hide()
                end
            else
                addon.note_active = true
                addon:UpdateNote(addon.note_active and note ~= "" and note or segment.note or "This route continues in |cff3dff7e" .. waypointContinent .. "|r.")
                addon.ui.NoteFrame:SetShown(addon.data.note.visible)
            end
        else
            -- No map position — show note if present, otherwise hide
            if addon.note_active then
                addon:UpdateNote(note)
            else
                addon.ui.NoteFrame:Hide()
            end
        end
    else
        addon.note_active = false
        addon.ui.NoteFrame:Hide()
    end

    addon:UpdateNoteAction(addon.waypoint.index and addon.segment.route[addon.waypoint.index] and addon.segment.route[addon.waypoint.index].data.action or nil)
    addon:ActivateTrigger()
    addon:RefreshWorldMapOverlay()
    addon:RefreshMinimapOverlay()
end