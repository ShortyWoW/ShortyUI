local myname, ns = ...

local HandyNotes = LibStub("AceAddon-3.0"):GetAddon("HandyNotes")

local provider = {}
provider.data = {}

local highlights = {}
local routecache = {}
local already = {}

local function GetMainPoint(point, mapID)
    if point.route and ns.points[mapID][point.route] then
        point = ns.points[mapID][point.route]
    end
    if point._uiMapID ~= mapID then return end
    return point
end

function provider:OnRefresh()
    table.wipe(self.data)

    if HandyNotes.db.profile.enabledPlugins[myname:gsub("HandyNotes_", "")] == false or not HandyNotes.db.profile.enabled then
        return
    end

    if not ns.db.show_routes then return end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    if not ns.points[mapID] then return end

    for coord, point in pairs(ns.points[mapID]) do
        point = GetMainPoint(point, mapID)
        if point and not already[point] and point.routes and ns.should_show_point(coord, point, mapID, false) then
            already[point] = true
            for i, route in ipairs(point.routes) do
                if not routecache[route] then
                    routecache[route] = {
                        route = route,
                        point = point,
                        coord = coord,
                        mapID = mapID,
                    }
                end
                table.insert(self.data, routecache[route])
            end
        end
    end
    table.wipe(already)
end

function provider.OnPinReset(pin)
    pin.line = nil
    pin.routedata = nil
end

function provider:HandleData(routedata)
    local route = routedata.route
    local mapID = routedata.mapID
    local prevPin
    for _, coord in ipairs(route) do
        local pin, isNew = self:AcquirePin()
        pin:SetID(coord)
        pin:SetSize(1, 1) -- needs a size or the route can't connect
        if pin:SetPosition(mapID, HandyNotes:getXY(coord)) then
            pin.routedata = routedata
            pin:Show()
            if prevPin then
                local line = ns.MapSystem:AttachLine(prevPin, pin)
                line.baseThickness = line:GetThickness()
                -- line:SetColorTexture(route.r or 1, route.g or 1, route.b or 1, route.a or 0.6)
                line:SetVertexColor(route.r or 1, route.g or 1, route.b or 1, route.a or 0.6)
                if route.highlightOnly and not highlights[point] then
                    line:Hide()
                end
                pin.line = line
            end
            prevPin = pin
        end
    end
end

function provider:HighlightRoutes(point, state)
    for pin in self:EnumeratePins() do
        if pin.line and pin.routedata and pin.routedata.point == point then
            pin.line:SetThickness(pin.line.baseThickness * (state and 1.5 or 1))
            if pin.routedata.route.highlightOnly then
                pin.line:SetShown(state)
            end
        end
    end
end

provider.Proxy = {
    Enter = function(self, _, point, mapID, coord)
        point = GetMainPoint(point, mapID)
        if point then
            if highlights[point] then return end
            self:HighlightRoutes(point, true)
        end
    end,
    Leave = function(self, _, point, mapID, coord)
        point = GetMainPoint(point, mapID)
        if point then
            if highlights[point] then return end
            self:HighlightRoutes(point, false)
        end
    end,
    Click = function(self, _, point, mapID, coord)
        point = GetMainPoint(point, mapID)
        if point then
            highlights[point] = not highlights[point]
            self:HighlightRoutes(point, highlights[point])
        end
    end,
}

ns.MapSystem:AddProvider(provider)
