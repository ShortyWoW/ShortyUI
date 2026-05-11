local addonName, addon = ...

local DOT_SIZE = 5
local DOT_SIZE_CURRENT = 7
local LINE_THICKNESS = 1
local STROKE_SIZE = 1

local COLOR_CURRENT  = { 0.5, 1.0, 0.0, 1.0 }
local COLOR_UPCOMING = { 1.0, 1.0, 1.0, 1.0 }
local COLOR_LINE        = { 1.0, 1.0, 1.0, 0.7 }
local COLOR_LINE_STROKE = { 0.0, 0.0, 0.0, 0.5 }
local COLOR_PREVIOUS    = { 0.5, 0.5, 0.5, 0.4 }
local LINE_STROKE_EXTRA = 1
local DOT_MIN_SIZE = 2
local DOT_MAX_SIZE = 12

local DOT_TEMPLATE_WM  = "DysESWorldMapDotTemplate"
local LINE_TEMPLATE_WM = "DysESWorldMapLineTemplate"
local DOT_TEMPLATE_ZM  = "DysESZoneMapDotTemplate"
local LINE_TEMPLATE_ZM = "DysESZoneMapLineTemplate"

local LINE_TEXTURE = "Interface\\AddOns\\Dystinct_EarthenSkyriding\\Textures\\line"
local LINEFACTOR   = 128 / 122
local LINEFACTOR_2 = LINEFACTOR / 2

-- Tooltip handlers
local function DotOnEnter(self)
    if not self.waypointData then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon:LocalizedString(self.waypointData.name), 1, 1, 1)
    if self.waypointData.note and self.waypointData.note ~= "" then
        GameTooltip:AddLine(self.waypointData.note, 1, 0.82, 0, true)
    end
    if self.waypointIndex == addon.waypoint.index then
        GameTooltip:AddLine("Current waypoint", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function DotOnLeave(self)
    GameTooltip:Hide()
end

-- Dot pin mixin
local dotMixin = CreateFromMixins(MapCanvasPinMixin)
dotMixin.SetPassThroughButtons = function() end

function dotMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetIgnoreGlobalPinScale(true)
end

function dotMixin:ApplyScaledSize()
    if not self.baseSize then return end
    local map = self:GetMap()
    local canvasW = map:DenormalizeHorizontalSize(1.0)
    local frameW = map:GetWidth()
    if frameW == 0 then return end
    -- Partial normalization: power < 1 keeps dots slightly larger on smaller maps
    local canvasScale = (canvasW / frameW) ^ 0.4
    local size = self.baseSize * canvasScale
    size = math.max(4 * canvasScale, math.min(24 * canvasScale, size))
    self:SetSize(size, size)
end

function dotMixin:OnCanvasSizeChanged()
    self:ApplyScaledSize()
end

function dotMixin:OnAcquired(wpInfo)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetPosition(wpInfo.x, wpInfo.y)
    self.baseSize = wpInfo.size
    self.pinScale = wpInfo.scale or 1
    self:ApplyScaledSize()

    if not self.texture then
        self.bg = self:CreateTexture(nil, "ARTWORK")
        self.bg:SetPoint("TOPLEFT", self, "TOPLEFT", -STROKE_SIZE, STROKE_SIZE)
        self.bg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", STROKE_SIZE, -STROKE_SIZE)
        self.bg:SetColorTexture(0, 0, 0, 1)

        self.bgMask = self:CreateMaskTexture()
        self.bgMask:SetAllPoints(self.bg)
        self.bgMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        self.bg:AddMaskTexture(self.bgMask)

        self.texture = self:CreateTexture(nil, "OVERLAY")
        self.texture:SetAllPoints(self)
        self.texture:SetColorTexture(1, 1, 1, 1)

        self.mask = self:CreateMaskTexture()
        self.mask:SetAllPoints(self.texture)
        self.mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        self.texture:AddMaskTexture(self.mask)
    end

    self.texture:SetVertexColor(wpInfo.color[1], wpInfo.color[2], wpInfo.color[3], wpInfo.color[4])
    self.bg:SetAlpha(wpInfo.color[4])

    self.waypointData = wpInfo.data
    self.waypointIndex = wpInfo.index

    self:EnableMouse(true)
    self:SetScript("OnEnter", DotOnEnter)
    self:SetScript("OnLeave", DotOnLeave)
end

function dotMixin:OnReleased()
    self.waypointData = nil
    self.waypointIndex = nil
end

-- Line canvas pin mixin (single pin covering the entire map, holds all line textures)
local lineCanvasMixin = CreateFromMixins(MapCanvasPinMixin)
lineCanvasMixin.SetPassThroughButtons = function() end

function lineCanvasMixin:OnLoad()
    self:SetIgnoreGlobalPinScale(true)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
end

function lineCanvasMixin:OnAcquired()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    self:SetPosition(0.5, 0.5)
    self:EnableMouse(false)
    self:SetSize(self:GetMap():DenormalizeHorizontalSize(1.0),
                 self:GetMap():DenormalizeVerticalSize(1.0))
end

function lineCanvasMixin:OnCanvasSizeChanged()
    self:SetSize(self:GetMap():DenormalizeHorizontalSize(1.0),
                 self:GetMap():DenormalizeVerticalSize(1.0))
end

function lineCanvasMixin:OnReleased()
    self:ReleaseLines()
end

function lineCanvasMixin:ReleaseLines()
    if not self.activeLines then return end
    if not self.linePool then self.linePool = {} end
    for i = #self.activeLines, 1, -1 do
        local tex = self.activeLines[i]
        tex:Hide()
        self.linePool[#self.linePool + 1] = tex
        self.activeLines[i] = nil
    end
end

function lineCanvasMixin:DrawLine(sx, sy, ex, ey, w, color, layer)
    if not self.linePool then self.linePool = {} end
    if not self.activeLines then self.activeLines = {} end

    layer = layer or "OVERLAY"
    local T = tremove(self.linePool) or self:CreateTexture(nil, layer)
    T:SetTexture(LINE_TEXTURE)
    T:SetTexelSnappingBias(0)
    T:SetSnapToPixelGrid(false)
    T:SetDrawLayer(layer)
    T:SetVertexColor(color[1], color[2], color[3], color[4])

    local dx, dy = ex - sx, ey - sy
    local l = (dx * dx + dy * dy) ^ 0.5

    if l == 0 then T:Hide() return end

    local cx, cy = (sx + ex) / 2, (sy + ey) / 2

    -- Normalize direction
    if dx < 0 then
        dx, dy = -dx, -dy
    end

    -- Sin and Cosine of rotation
    local s, c = -dy / l, dx / l
    local sc = s * c

    -- Calculate bounding box and texture coordinates (two branches based on dy sign)
    local Bwid, Bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy
    if dy >= 0 then
        Bwid = ((l * c) - (w * s)) * LINEFACTOR_2
        Bhgt = ((w * c) - (l * s)) * LINEFACTOR_2
        BLx, BLy, BRy = (w / l) * sc, s * s, (l / w) * sc
        BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx
        TRy = BRx
    else
        Bwid = ((l * c) + (w * s)) * LINEFACTOR_2
        Bhgt = ((w * c) + (l * s)) * LINEFACTOR_2
        BLx, BLy, BRx = s * s, -(l / w) * sc, 1 + (w / l) * sc
        BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy
        TRx = TLy
    end

    T:ClearAllPoints()
    T:SetTexCoord(TLx, TLy, BLx, BLy, TRx, TRy, BRx, BRy)
    T:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", cx - Bwid, cy - Bhgt)
    T:SetPoint("TOPRIGHT",   self, "BOTTOMLEFT", cx + Bwid, cy + Bhgt)
    T:Show()

    self.activeLines[#self.activeLines + 1] = T
end

-- Shared data provider mixin (used by both world map and zone map providers)
local overlayProviderMixin = {}

function overlayProviderMixin:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(self.lineTemplate)
    self:GetMap():RemoveAllPinsByTemplate(self.dotTemplate)
end

-- Convert a waypoint's zone coordinates to the current map's coordinate space
-- GetWorldPosFromMapPos returns Vector2D where .x = north-south, .y = east-west
-- Map coordinates are: x = east-west (left-right), y = north-south (top-bottom)
-- So world .y -> map x, world .x -> map y
local function ProjectToMap(wpMapID, wpX, wpY, currentMapID, mapContinent, mapTopLeft, mapWorldSize)
    if wpMapID == currentMapID then
        return wpX, wpY
    end

    local wpContinent, wpWorldPos = C_Map.GetWorldPosFromMapPos(wpMapID, CreateVector2D(wpX, wpY))
    if not wpContinent or wpContinent ~= mapContinent then return nil, nil end

    local x = (wpWorldPos.y - mapTopLeft.y) / mapWorldSize.y
    local y = (wpWorldPos.x - mapTopLeft.x) / mapWorldSize.x

    return x, y
end

-- Recursively collect all leaf waypoints from a route hierarchy into a flat ordered list
function addon:CollectLeafWaypoints(routeName, result)
    local route = addon.data.routes[routeName]
    if not route then return end
    if route.class == "path" then
        for i, wp in ipairs(route.route) do
            result[#result + 1] = {
                segmentName = routeName,
                wpIndex = i,
                data = wp,
            }
        end
    elseif route.class == "segment" then
        local resolved = addon:ResolveRouteList(route.route)
        for _, childName in ipairs(resolved) do
            addon:CollectLeafWaypoints(childName, result)
        end
    end
end

function overlayProviderMixin:RefreshAllData(fromOnShow)
    self:RemoveAllData()

    if not addon.data or not addon.data.waypoints.mapOverlay then return end
    if not addon.segment or not addon.segment.route or not addon.waypoint.index then return end
    if not addon.active or not addon.active.path or #addon.active.path == 0 then return end

    local currentMapID = self:GetMap():GetMapID()
    if not currentMapID then return end

    -- Get current map's world bounds for cross-map coordinate projection
    local mapContinent, mapTopLeft = C_Map.GetWorldPosFromMapPos(currentMapID, CreateVector2D(0, 0))
    local _, mapBotRight = C_Map.GetWorldPosFromMapPos(currentMapID, CreateVector2D(1, 1))
    if not mapContinent or not mapTopLeft or not mapBotRight then return end

    local mapWorldSize = CreateVector2D(mapBotRight.x - mapTopLeft.x, mapBotRight.y - mapTopLeft.y)
    if mapWorldSize.x == 0 or mapWorldSize.y == 0 then return end

    -- Collect waypoints from the current leaf segment only
    local currentLeafName = addon.active.path[#addon.active.path]

    local allWaypoints = {}
    addon:CollectLeafWaypoints(currentLeafName, allWaypoints)

    -- Find the flat index of the single previous waypoint (one before current)
    local previousFlatIdx = nil
    for flatIdx, wp in ipairs(allWaypoints) do
        if wp.wpIndex == addon.waypoint.index then
            break
        end
        previousFlatIdx = flatIdx
    end

    -- Project waypoints: skip all past except the single most-recent previous
    local pastCurrentWaypoint = false
    local scale = self.scale or 1
    local projected = {}
    for flatIdx, wp in ipairs(allWaypoints) do
        local isCurrentWp = wp.wpIndex == addon.waypoint.index

        -- Only include: the single previous waypoint, the current, and all upcoming
        if pastCurrentWaypoint or flatIdx == previousFlatIdx or isCurrentWp then
            local wpMapID = tonumber(wp.data.map)
            if wpMapID then
                local wpX = (tonumber(wp.data.x) or 0) / 100
                local wpY = (tonumber(wp.data.y) or 0) / 100

                local x, y = ProjectToMap(wpMapID, wpX, wpY, currentMapID, mapContinent, mapTopLeft, mapWorldSize)
                if x and y then
                    local onMap = x >= -0.02 and x <= 1.02 and y >= -0.02 and y <= 1.02

                    -- Check if this upcoming waypoint was already discovered out of order
                    local isDiscovered = addon.segment.route[wp.wpIndex]
                        and addon.segment.route[wp.wpIndex].discovered

                    local color, size, lineSkip
                    if isCurrentWp then
                        color = COLOR_CURRENT
                        size = DOT_SIZE_CURRENT
                        pastCurrentWaypoint = true
                    elseif pastCurrentWaypoint and isDiscovered then
                        color = COLOR_PREVIOUS
                        size = DOT_SIZE
                        lineSkip = true
                    elseif pastCurrentWaypoint then
                        color = COLOR_UPCOMING
                        size = DOT_SIZE
                    else
                        color = COLOR_PREVIOUS
                        size = DOT_SIZE
                    end

                    projected[#projected + 1] = {
                        flatIdx = flatIdx,
                        data = wp.data,
                        x = x,
                        y = y,
                        color = color,
                        size = size * scale,
                        onMap = onMap,
                        index = wp.wpIndex,
                        lineSkip = lineSkip,
                        scale = scale,
                    }
                end
            end
        end
    end

    -- Mark which projected waypoints to include (on-map + neighbors for line continuity)
    local included = {}
    for idx, p in ipairs(projected) do
        if p.onMap then
            included[idx] = true
            if idx > 1 then included[idx - 1] = true end
            if idx < #projected then included[idx + 1] = true end
        end
    end

    -- Build final waypoint list
    local mapWaypoints = {}
    for idx, p in ipairs(projected) do
        if included[idx] then
            mapWaypoints[#mapWaypoints + 1] = p
        end
    end

    if #mapWaypoints == 0 then return end

    -- Build line pairs (skip discovered upcoming waypoints, connect directly between non-skipped)
    local linePairs = {}
    local lastLineWp = nil
    local lastFlatIdx = nil

    for _, wp in ipairs(mapWaypoints) do
        if lastFlatIdx and wp.flatIdx ~= lastFlatIdx + 1 then
            lastLineWp = nil -- segment boundary, break the chain
        end
        lastFlatIdx = wp.flatIdx

        if not wp.lineSkip then
            if lastLineWp then
                linePairs[#linePairs + 1] = { lastLineWp, wp }
            end
            lastLineWp = wp
        end
    end

    -- Draw lines
    if #linePairs > 0 then
        local linePin = self:GetMap():AcquirePin(self.lineTemplate)
        linePin:ReleaseLines()

        -- Partial normalization: power < 1 keeps lines slightly larger on smaller maps
        local canvasW = self:GetMap():DenormalizeHorizontalSize(1.0)
        local frameW = self:GetMap():GetWidth()
        local canvasScale = (frameW > 0) and ((canvasW / frameW) ^ 0.4) or 1

        local fw, fh = linePin:GetSize()
        -- Stroke pass (wider, dark, behind)
        for _, pair in ipairs(linePairs) do
            linePin:DrawLine(
                pair[1].x * fw, (1 - pair[1].y) * fh,
                pair[2].x * fw, (1 - pair[2].y) * fh,
                (LINE_THICKNESS + LINE_STROKE_EXTRA) * scale * canvasScale, COLOR_LINE_STROKE, "ARTWORK"
            )
        end
        -- Main line pass (on top)
        for _, pair in ipairs(linePairs) do
            linePin:DrawLine(
                pair[1].x * fw, (1 - pair[1].y) * fh,
                pair[2].x * fw, (1 - pair[2].y) * fh,
                LINE_THICKNESS * scale * canvasScale, COLOR_LINE, "OVERLAY"
            )
        end
    end

    -- Acquire dot pins (only for on-map waypoints)
    for _, wp in ipairs(mapWaypoints) do
        if wp.onMap then
            self:GetMap():AcquirePin(self.dotTemplate, wp)
        end
    end
end

-- Create provider instances for each map frame
local worldMapProvider = CreateFromMixins(MapCanvasDataProviderMixin, overlayProviderMixin)
worldMapProvider.dotTemplate = DOT_TEMPLATE_WM
worldMapProvider.lineTemplate = LINE_TEMPLATE_WM
worldMapProvider.scale = 1.2

local zoneMapProvider = CreateFromMixins(MapCanvasDataProviderMixin, overlayProviderMixin)
zoneMapProvider.dotTemplate = DOT_TEMPLATE_ZM
zoneMapProvider.lineTemplate = LINE_TEMPLATE_ZM
zoneMapProvider.scale = 1.4

-- Registration
local worldMapRegistered = false
local zoneMapRegistered = false

local function CreatePinPool(mapFrame, templateName, mixin)
    local pool
    if CreateUnsecuredRegionPoolInstance then
        pool = CreateUnsecuredRegionPoolInstance(templateName)
    else
        pool = CreateFramePool("FRAME")
    end

    local canvas = mapFrame:GetCanvas()
    pool.parent = canvas
    pool.createFunc = function()
        local frame = CreateFrame("Frame", nil, canvas)
        frame:SetSize(1, 1)
        return Mixin(frame, mixin)
    end
    pool.resetFunc = function(p, pin)
        pin:Hide()
        pin:ClearAllPoints()
        pin:OnReleased()
        pin.pinTemplate = nil
        pin.owningMap = nil
    end
    pool.creationFunc = pool.createFunc
    pool.resetterFunc = pool.resetFunc

    return pool
end

local function RegisterOnMap(mapFrame, prov)
    mapFrame.pinPools[prov.dotTemplate] = CreatePinPool(mapFrame, prov.dotTemplate, dotMixin)
    mapFrame.pinPools[prov.lineTemplate] = CreatePinPool(mapFrame, prov.lineTemplate, lineCanvasMixin)
    mapFrame:AddDataProvider(prov)

    if mapFrame:IsShown() then
        prov:RefreshAllData()
    end
end

function addon:InitializeWorldMapOverlay()
    if WorldMapFrame and not worldMapRegistered then
        RegisterOnMap(WorldMapFrame, worldMapProvider)
        worldMapRegistered = true
    end
    if not worldMapRegistered then
        if EventUtil and EventUtil.ContinueOnAddOnLoaded then
            EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
                if not worldMapRegistered then
                    RegisterOnMap(WorldMapFrame, worldMapProvider)
                    worldMapRegistered = true
                end
            end)
        end
    end

    if BattlefieldMapFrame and not zoneMapRegistered then
        RegisterOnMap(BattlefieldMapFrame, zoneMapProvider)
        zoneMapRegistered = true
    end
    if not zoneMapRegistered then
        if EventUtil and EventUtil.ContinueOnAddOnLoaded then
            EventUtil.ContinueOnAddOnLoaded("Blizzard_BattlefieldMap", function()
                if BattlefieldMapFrame and not zoneMapRegistered then
                    RegisterOnMap(BattlefieldMapFrame, zoneMapProvider)
                    zoneMapRegistered = true
                end
            end)
        end
    end
end

function addon:RefreshWorldMapOverlay()
    if worldMapRegistered and WorldMapFrame:IsShown() then
        worldMapProvider:RefreshAllData()
    end
    if zoneMapRegistered and BattlefieldMapFrame and BattlefieldMapFrame:IsShown() then
        zoneMapProvider:RefreshAllData()
    end
end
