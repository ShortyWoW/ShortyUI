-- ShortyTalents.lua (core)
-- Config rules are stored by SAVED configID (per-spec), not by name (robust against duplicate names).

local ADDON_NAME = ...
local ST = _G.ShortyTalents or {}
_G.ShortyTalents = ST

ST.ADDON_NAME = ADDON_NAME
ST.VERSION = ST.VERSION or "0.0.0"

local frame = CreateFrame("Frame")

ST.ACTIVITIES = {
  "Delves",
  "Dungeons",
  "Mythic+",
  "Raiding",
  "BGs",
  "Arena",
}

-- =========================
-- Debug
-- =========================
ST.debug = ST.debug or false

local function dprint(...)
  if not ST.debug then return end
  print("|cff66ccff[ST DEBUG]|r", ...)
end

-- Cache last known saved loadout per spec (Blizzard can return nil during TRAIT_CONFIG_UPDATED)
local lastKnownSavedIDBySpec = lastKnownSavedIDBySpec or {}

local function DumpSavedConfigsForSpec(specID)
  if not specID or not C_ClassTalents.GetConfigIDsBySpecID then return {} end
  local ids = C_ClassTalents.GetConfigIDsBySpecID(specID)
  if type(ids) ~= "table" then return {} end

  local out = {}
  for _, id in ipairs(ids) do
    local info = C_Traits.GetConfigInfo(id)
    out[#out+1] = { id = id, name = (info and info.name) or "?" }
  end

  table.sort(out, function(a, b)
    if a.name == b.name then return a.id < b.id end
    return a.name < b.name
  end)

  return out
end

local function DumpAllowedSet(allowedSet)
  local out = {}
  if type(allowedSet) ~= "table" then return out end
  for id, v in pairs(allowedSet) do
    if v == true then
      local info = C_Traits.GetConfigInfo(id)
      out[#out+1] = { id = id, name = (info and info.name) or "?" }
    end
  end

  table.sort(out, function(a, b)
    if a.name == b.name then return a.id < b.id end
    return a.name < b.name
  end)

  return out
end

-- -----------------------------
-- DB
-- -----------------------------
local lastKnownSavedConfigID, lastKnownSavedName = nil, nil
local function EnsureDB()
  ShortyTalentsDB = ShortyTalentsDB or {}
  ShortyTalentsDB.spec = ShortyTalentsDB.spec or {} -- keyed by specID number
end

local function EnsureSpecDB(specID)
  if not specID then return nil end

  local specDB = ShortyTalentsDB.spec[specID]
  if not specDB then
    specDB = {
      -- allowed[activity] is a SET of configIDs: allowed[activity][configID] = true
      allowed = {},
      raid = { bossAllowedByNPCID = {} }, -- bossAllowedByNPCID[npcID][configID] = true
    }
    for _, activity in ipairs(ST.ACTIVITIES) do
      specDB.allowed[activity] = {}
    end
    ShortyTalentsDB.spec[specID] = specDB
  else
    specDB.allowed = specDB.allowed or {}
    for _, activity in ipairs(ST.ACTIVITIES) do
      specDB.allowed[activity] = specDB.allowed[activity] or {}
    end
    specDB.raid = specDB.raid or { bossAllowedByNPCID = {} }
    specDB.raid.bossAllowedByNPCID = specDB.raid.bossAllowedByNPCID or {}
  end

  return specDB
end

-- -----------------------------
-- Spec + selected saved config
-- -----------------------------
local function GetCurrentSpecID()
  local specIndex = GetSpecialization()
  if not specIndex then return nil end
  local specID = select(1, GetSpecializationInfo(specIndex))
  if not specID or specID == 0 then return nil end
  return specID
end

-- Returns config name (string) or nil
local function GetConfigName(configID)
  if not configID then return nil end
  local info = C_Traits.GetConfigInfo(configID)
  return info and info.name or nil
end

-- Returns:
--   configID, displayName, isSaved, usedSaved
-- isSaved=true when active configID is one of the spec's SAVED loadouts.
-- We intentionally rely on the ACTIVE config (not "last selected saved") because Blizzard may return nil for
-- GetLastSelectedSavedConfigID even when the UI shows a named loadout.
local function GetCurrentLoadout()
  local specID = GetCurrentSpecID()
  if not specID then return nil, nil, false, false end

  local activeID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or nil
  if not activeID then return nil, nil, false, false end

  -- Prefer Blizzard's "last selected saved loadout" when available.
  -- This matches the configIDs you pick in Options and avoids false Starter/Unsaved warnings
  -- when the active configID is a different internal ID.
  local lastSavedID = C_ClassTalents.GetLastSelectedSavedConfigID and C_ClassTalents.GetLastSelectedSavedConfigID(specID) or nil
  if lastSavedID and lastSavedID > 0 then
    return lastSavedID, (GetConfigName(lastSavedID) or "Unknown"), true, true
  end

  local name = GetConfigName(activeID)

  -- Determine whether this active config is one of the spec's saved configs
  local isSaved = false
  if C_ClassTalents.GetConfigIDsBySpecID then
    local ids = C_ClassTalents.GetConfigIDsBySpecID(specID)
    if type(ids) == "table" then
      for _, id in ipairs(ids) do
        if id == activeID then
          isSaved = true
          break
        end
      end
    end
  end

  return activeID, name, isSaved, false
end

-- -----------------------------
-- Activity detection
-- -----------------------------
local function GetCurrentActivity()
  if C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress() then
    return "Delves"
  end

  if C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
    return "Mythic+"
  end

  local inInstance, instanceType = IsInInstance()
  if not inInstance then return nil end

  if instanceType == "raid" then return "Raiding" end
  if instanceType == "party" then return "Dungeons" end
  if instanceType == "pvp" then return "BGs" end
  if instanceType == "arena" then return "Arena" end

  return nil
end

-- -----------------------------
-- Warning throttle
-- -----------------------------
local lastWarnKey, lastWarnAt = nil, 0
local function CanWarn(key, cooldownSec)
  cooldownSec = cooldownSec or 6
  local now = GetTime()
  if key == lastWarnKey and (now - lastWarnAt) < cooldownSec then
    return false
  end
  lastWarnKey = key
  lastWarnAt = now
  return true
end

-- -----------------------------
-- Public warning API (Warning.lua provides ST.ShowWarning)
-- -----------------------------
function ST:Warn(activity, loadoutName, detail)
  local key = (activity or "?") .. "|" .. (loadoutName or "?") .. "|" .. (detail or "")
  if not CanWarn(key, 6) then return end

  if ST.ShowWarning then
    ST.ShowWarning(activity, loadoutName, detail)
  else
    print(string.format("|cffff5555ShortyTalents WARNING|r: %s | %s %s",
      tostring(activity),
      tostring(loadoutName),
      detail and ("(" .. detail .. ")") or ""
    ))
  end
end

-- -----------------------------
-- Core check (configID-based)
-- -----------------------------
local function IsAllowedID(allowedSet, configID)
  return allowedSet and configID and allowedSet[configID] == true
end

local function CheckTalentsNow(reason)
  local activity = GetCurrentActivity()
  if not activity then
    dprint("No activity detected. reason=", reason)
    return
  end

  local inInst, instType = IsInInstance()
  dprint("CheckTalentsNow", "reason=", reason, "activity=", activity, "IsInInstance=", inInst, "instanceType=", instType)

  local specID = GetCurrentSpecID()
  if not specID then
    dprint("No specID; abort.")
    return
  end

  local _, specName = GetSpecializationInfoByID(specID)
  dprint("specID=", specID, "specName=", specName or "?")

  EnsureDB()
  local specDB = EnsureSpecDB(specID)
  if not specDB then
    dprint("No specDB; abort.")
    return
  end

  local activeID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or nil
  local activeName = activeID and ((C_Traits.GetConfigInfo(activeID) or {}).name) or nil
  local lastSavedID = C_ClassTalents.GetLastSelectedSavedConfigID and C_ClassTalents.GetLastSelectedSavedConfigID(specID) or nil
  local lastSavedName = (lastSavedID and lastSavedID > 0) and ((C_Traits.GetConfigInfo(lastSavedID) or {}).name) or nil

  -- Cache/restore last known saved loadout. Blizzard may report nil during TRAIT_CONFIG_UPDATED.
  if lastSavedID and lastSavedID > 0 then
    lastKnownSavedIDBySpec[specID] = lastSavedID
  else
    local cached = lastKnownSavedIDBySpec[specID]
    if cached and cached > 0 then
      dprint("lastSelectedSavedID is nil; using cached savedID=", cached)
      lastSavedID = cached
      lastSavedName = ((C_Traits.GetConfigInfo(lastSavedID) or {}).name) or lastSavedName
    elseif reason == "talents_updated" then
      -- Avoid false positives during talent update before saved selection is available.
      dprint("talents_updated with no lastSelectedSavedID yet; skipping warning this tick.")
      return
    end
  end

  dprint("activeID=", activeID or "nil", "activeName=", activeName or "nil")
  dprint("lastSelectedSavedID=", lastSavedID or "nil", "lastSelectedSavedName=", lastSavedName or "nil")

  local savedList = DumpSavedConfigsForSpec(specID)
  if #savedList == 0 then
    dprint("Saved configs list is EMPTY for this spec.")
  else
    dprint("Saved configs for spec:")
    for _, it in ipairs(savedList) do
      dprint(" -", it.name, "(ID:", tostring(it.id) .. ")")
    end
  end

  local selectedID, selectedName, isSaved, usedSaved = GetCurrentLoadout()
  if not selectedID then
    dprint("WARNING PATH: selectedID nil -> Unknown Loadout")
    ST:Warn(activity, "Unknown Loadout", reason)
    return
  end

  local allowedSet = specDB.allowed[activity]

  local allowedDump = DumpAllowedSet(allowedSet)
  dprint("Allowed set for activity:", activity, "count=", tostring(#allowedDump))
  for _, it in ipairs(allowedDump) do
    dprint(" *", it.name, "(ID:", tostring(it.id) .. ")")
  end
  if not allowedSet or not next(allowedSet) then
    dprint("No rules configured for this activity; no warning.")
    return
  end

  -- If rules exist but player isn't on a saved loadout, warn clearly.
  -- Only call it Starter/Unsaved when we did NOT have a lastSelectedSavedID to use.
  if (not isSaved) and (not usedSaved) then
    ST:Warn(activity, "Starter/Unsaved Build", reason)
    return
  end

  if not IsAllowedID(allowedSet, selectedID) then
    dprint("WARNING PATH: config not allowed for activity")
    ST:Warn(activity, selectedName or ("ConfigID " .. tostring(selectedID)), reason)
  end

  dprint("OK: config allowed; no warning.")
end

ST.CheckTalentsNow = CheckTalentsNow

-- -----------------------------
-- Scheduled check (debounce to avoid race conditions)
-- -----------------------------
local pendingTimer = nil
local pendingReason = nil

local function ScheduleCheck(reason, delay)
  delay = delay or 0.10
  pendingReason = reason

  if pendingTimer then
    pendingTimer:Cancel()
    pendingTimer = nil
  end

  pendingTimer = C_Timer.NewTimer(delay, function()
    pendingTimer = nil
    CheckTalentsNow(pendingReason or "scheduled")
  end)
end

-- -----------------------------
-- Slash command
-- -----------------------------
SLASH_SHORTYTALENTS1 = "/stalent"
SLASH_SHORTYTALENTS2 = "/stalents"

SlashCmdList.SHORTYTALENTS = function(msg)
  msg = msg and msg:match("^%s*(.-)%s*$") or ""

  if msg == "debug" or msg:match("^debug%s") then
    local arg = msg:match("^debug%s+(%S+)")
    if arg == "on" then
      ST.debug = true
    elseif arg == "off" then
      ST.debug = false
    else
      ST.debug = not ST.debug
    end
    print(string.format("|cff66ccffShortyTalents|r: Debug %s", ST.debug and "ENABLED" or "DISABLED"))
    ScheduleCheck("slash_debug", 0.01)
    return
  end

  if msg == "check" then
    ScheduleCheck("slash", 0.01)
    return
  end

  local activity = GetCurrentActivity() or "None"
  local specID = GetCurrentSpecID()
  local id, name, isSaved = GetCurrentLoadout()
  print(string.format("|cff66ccffShortyTalents|r: Activity=%s, SpecID=%s, Selected=%s (%s) Saved=%s",
    tostring(activity),
    tostring(specID),
    tostring(name or "None"),
    tostring(id or "NoID"),
    tostring(isSaved)
  ))

  if ST.OpenOptions then
    ST:OpenOptions()
  else
    print("|cff66ccffShortyTalents|r: Options UI not loaded yet (Options.lua will provide it).")
    print("|cff66ccffShortyTalents|r: Tip: /stalent check to force a check now.")
  end
end

-- -----------------------------
-- Events
-- -----------------------------
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end
    EnsureDB()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    ScheduleCheck("entering_world", 0.10)
    return
  end

  if event == "ZONE_CHANGED_NEW_AREA" then
    ScheduleCheck("zone_changed", 0.10)
    return
  end

  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    local unit = ...
    if unit == "player" then
      ScheduleCheck("spec_changed", 0.10)
    end
    return
  end

  if event == "CHALLENGE_MODE_START" then
    ScheduleCheck("mplus_start", 0.10)
    return
  end

  if event == "ENCOUNTER_END" then
    ScheduleCheck("encounter_end", 0.10)
    return
  end

  if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
    ScheduleCheck("talents_updated", 0.10)
    return
  end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")