local ADDON_NAME = ...
local SF = {}
_G.ShortyFalls = SF

-- =======================================================
-- ShortyFalls (TicTac UI style)
--  * Uses UI-RaidTargetingIcons + texcoords (reliable)
--  * Simple 5 horizontal cells
--  * Left click assigns 1..5 order
--  * Right click ANY cell resets ALL
--  * /sfalls show|hide|lock|unlock|clear
-- =======================================================

-- -------------------------------------------------------
-- Config (match TicTac look)
-- -------------------------------------------------------
local CELL_SIZE = 44
local CELL_GAP  = 6
local PAD_X     = 12
local PAD_Y     = 12

-- Icon order:
-- Moon, Diamond, Cross, Triangle, T
local ICON_ORDER = { 5, 3, 7, 4, "T" }

-- -------------------------------------------------------
-- SavedVariables
-- -------------------------------------------------------
local function DB()
  if not ShortyFallsDB then ShortyFallsDB = {} end
  if ShortyFallsDB.locked == nil then
    ShortyFallsDB.locked = true
  end
  if not ShortyFallsDB.assign then ShortyFallsDB.assign = {} end
  if not ShortyFallsDB.used then ShortyFallsDB.used = {} end
  return ShortyFallsDB
end

-- -------------------------------------------------------
-- Raid icon helper: UI-RaidTargetingIcons + texcoords
-- -------------------------------------------------------
local RAID_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RAID_TEXCOORDS = {
  [1] = {0.00, 0.25, 0.00, 0.25}, -- Star
  [2] = {0.25, 0.50, 0.00, 0.25}, -- Circle
  [3] = {0.50, 0.75, 0.00, 0.25}, -- Diamond
  [4] = {0.75, 1.00, 0.00, 0.25}, -- Triangle
  [5] = {0.00, 0.25, 0.25, 0.50}, -- Moon
  [6] = {0.25, 0.50, 0.25, 0.50}, -- Square
  [7] = {0.50, 0.75, 0.25, 0.50}, -- Cross
  [8] = {0.75, 1.00, 0.25, 0.50}, -- Skull
}

local function ApplyRaidIcon(tex, iconIndex)
  if not tex or not iconIndex then return end
  local tc = RAID_TEXCOORDS[iconIndex]
  tex:SetTexture(RAID_TEX)
  if tc then
    tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
  else
    tex:SetTexCoord(0, 1, 0, 1)
  end
end

-- -------------------------------------------------------
-- UI state
-- -------------------------------------------------------
local frame
local cells = {}

local function SavePosition()
  local db = DB()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePosition()
  local db = DB()
  if db.pos and db.pos.point and db.pos.relPoint and db.pos.x and db.pos.y then
    frame:ClearAllPoints()
    frame:SetPoint(db.pos.point, UIParent, db.pos.relPoint, db.pos.x, db.pos.y)
  else
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
end

local function ApplyLockState()
  local db = DB()
  if db.locked then
    frame:RegisterForDrag()
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
  else
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
  end
end

-- -------------------------------------------------------
-- Assignment logic
-- -------------------------------------------------------
local function ResetAll()
  local db = DB()
  wipe(db.assign)
  wipe(db.used)
  for i = 1, #cells do
    cells[i].num:SetText("")
  end
end

local function GetNextNumber()
  local db = DB()
  for n = 1, 5 do
    if not db.used[n] then
      return n
    end
  end
end

local function ApplyFromDB()
  local db = DB()
  for i = 1, #cells do
    local n = db.assign[i]
    cells[i].num:SetText(n and tostring(n) or "")
  end
end

local function Assign(cellIndex)
  local db = DB()
  if db.assign[cellIndex] then return end

  local n = GetNextNumber()
  if not n then return end

  db.assign[cellIndex] = n
  db.used[n] = true
  cells[cellIndex].num:SetText(tostring(n))
end

-- -------------------------------------------------------
-- Build UI
-- -------------------------------------------------------
local function BuildUI()
  if frame then return end
  DB()

  local totalW = (PAD_X * 2) + (CELL_SIZE * 5) + (CELL_GAP * 4)
  local totalH = (PAD_Y * 2) + CELL_SIZE + 26

  frame = CreateFrame("Frame", "ShortyFallsFrame", UIParent, "BackdropTemplate")
  frame:SetSize(totalW, totalH)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(0, 0, 0, 0.35)
  frame:SetBackdropBorderColor(1, 1, 1, 0.25)
  frame:SetClampedToScreen(true)

  frame:EnableMouse(true)
  frame:SetMovable(true)

  local fontPath = (GameFontNormal and select(1, GameFontNormal:GetFont()))
    or (STANDARD_TEXT_FONT)
    or "Fonts\\FRIZQT__.TTF"

  for i = 1, 5 do
    local cell = CreateFrame("Button", nil, frame, "BackdropTemplate")
    cell:SetSize(CELL_SIZE, CELL_SIZE)

    local x = PAD_X + (i - 1) * (CELL_SIZE + CELL_GAP)
    local y = -PAD_Y - 22
    cell:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)

    cell:SetBackdrop({
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1,
    })
    cell:SetBackdropBorderColor(1, 1, 1, 0.25)

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(cell)
    cell.bg:SetColorTexture(1, 1, 1, 0.10)

    -- Icon or fancy T
    local iconSpec = ICON_ORDER[i]
    if iconSpec == "T" then
    --   cell.tGlow = cell:CreateTexture(nil, "BORDER")
    --   cell.tGlow:SetPoint("CENTER", cell, "CENTER", 0, 0)
    --   cell.tGlow:SetSize(CELL_SIZE + 18, CELL_SIZE + 18)
    --   cell.tGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    --   cell.tGlow:SetVertexColor(0.10, 0.65, 1.00, 0.18)

      cell.icon = cell:CreateFontString(nil, "OVERLAY")
      cell.icon:SetPoint("CENTER", cell, "CENTER", 0, -1)
      cell.icon:SetJustifyH("CENTER")
      cell.icon:SetJustifyV("MIDDLE")
      cell.icon:SetFont(fontPath, 34, "THICKOUTLINE")
      cell.icon:SetText("T")
      cell.icon:SetTextColor(0.10, 0.70, 1.00, 1)
      cell.icon:SetShadowColor(0, 0, 0, 1)
      cell.icon:SetShadowOffset(1, -1)
    else
      cell.icon = cell:CreateTexture(nil, "OVERLAY")
      cell.icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
      cell.icon:SetSize(CELL_SIZE - 10, CELL_SIZE - 10)
      cell.icon:SetAlpha(1)
      ApplyRaidIcon(cell.icon, iconSpec)
    end

    -- Number above
    cell.num = cell:CreateFontString(nil, "OVERLAY")
    cell.num:SetPoint("BOTTOM", cell, "TOP", 0, 6)
    cell.num:SetJustifyH("CENTER")
    cell.num:SetTextColor(1, 1, 1, 1)
    cell.num:SetFont(fontPath, 28, "OUTLINE")
    cell.num:SetShadowColor(0, 0, 0, 1)
    cell.num:SetShadowOffset(0, 0)
    cell.num:SetText("")

    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
        ResetAll()
        return
      end
      Assign(i)
    end)

    cells[i] = cell
  end

  RestorePosition()
  ApplyLockState()
  ApplyFromDB()
  frame:Show()
end

BuildUI()

-- -------------------------------------------------------
-- Slash commands
-- -------------------------------------------------------
SLASH_SHORTYFALLS1 = "/sfalls"
SlashCmdList["SHORTYFALLS"] = function(msg)
  msg = (msg or ""):lower()

  if msg == "show" then
    if frame then frame:Show() end
    print("|cff66ccffShortyFalls|r: shown.")
    return
  end

  if msg == "hide" then
    if frame then frame:Hide() end
    print("|cff66ccffShortyFalls|r: hidden.")
    return
  end

  if msg == "lock" then
    local db = DB()
    db.locked = true
    ApplyLockState()
    print("|cff66ccffShortyFalls|r: frame is now |cffff0000LOCKED|r.")
    return
  end

  if msg == "unlock" then
    local db = DB()
    db.locked = false
    ApplyLockState()
    print("|cff66ccffShortyFalls|r: frame is now |cff00ff00UNLOCKED|r (drag to move).")
    return
  end

  if msg == "clear" or msg == "reset" then
    ResetAll()
    print("|cff66ccffShortyFalls|r: cleared.")
    return
  end

  print("|cff66ccffShortyFalls|r commands:")
  print("  /sfalls show")
  print("  /sfalls hide")
  print("  /sfalls lock")
  print("  /sfalls unlock")
  print("  /sfalls clear")
end