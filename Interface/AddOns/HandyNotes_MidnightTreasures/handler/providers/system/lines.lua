local myname, ns = ...

local lineParent = CreateFrame('Frame', nil, WorldMapFrame:GetCanvas())
lineParent:SetAllPoints()
lineParent:SetFrameStrata("MEDIUM")
-- lineParent:SetFrameLevel(2200) -- need to set it high so lines render above the canvas and pois
lineParent:SetFrameLevel(ns.MapSystem.GetWorldMapFrameLevelByType("PIN_FRAME_LEVEL_AREA_POI") - 2)

local linePool = CreateUnsecuredObjectPool(function()
    local line = lineParent:CreateLine()
    -- line:SetColorTexture is an option here...
    if ns.CLASSIC then
        -- self.Line:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Line")
        line:SetAtlas("_UI-Taxi-Line-horizontal")
    else
        line:SetAtlas("_AnimaChannel-Channel-Line-horizontal")
    end
    return line
end, function(_, line)
    line:SetVertexColor(1, 1, 1, 1)
    line:Hide()
end)

function ns.MapSystem:AttachLine(source, destination)
    local line = linePool:Acquire()
    line:SetStartPoint('CENTER', source)
    line:SetEndPoint('CENTER', destination)
    line:SetThickness(1 / WorldMapFrame:GetCanvasScale() * 35)
    line:Show()
    return line
end

function ns.MapSystem:EnumerateLines()
    return linePool:EnumerateActive()
end

function ns.MapSystem:ReleaseLines()
    linePool:ReleaseAll()
end

function ns.MapSystem:ReleaseLine(line)
    lineParent:Release(line)
end
