local _, ns = ...

local C_SpecializationInfo = C_SpecializationInfo
local Enum = Enum
local GetNumRunes = GetNumRunes
local GetRuneCooldown = GetRuneCooldown
local GetTime = GetTime
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local math_floor = math.floor

local DEFAULT_RUNE_COUNT = 6

local function Clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function GetRuneReadyColor()
  local spec_index = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization() or nil
  if spec_index == 1 then
    return 0.85, 0.18, 0.22
  elseif spec_index == 2 then
    return 0.24, 0.82, 0.98
  elseif spec_index == 3 then
    return 0.18, 0.80, 0.30
  end
  return 0.72, 0.72, 0.72
end

local module = {}

local function BuildFallbackState(rune_power_type, explicit_count)
  local max_value = explicit_count or (UnitPowerMax and UnitPowerMax("player", rune_power_type)) or 0
  if not max_value or max_value <= 0 then
    max_value = DEFAULT_RUNE_COUNT
  end

  local current = UnitPower and UnitPower("player", rune_power_type) or 0
  local ready = math_floor((tonumber(current) or 0) + 0.5)
  local values = {}
  for i = 1, max_value do
    values[i] = i <= ready and 1 or 0
  end

  local r, g, b = GetRuneReadyColor()
  return {
    kind = "segments",
    token = "RUNES",
    powerType = rune_power_type,
    count = max_value,
    values = values,
    color = { r, g, b },
    options = {
      rechargeVisual = "alpha_pop",
      suppressFullChargeHighlight = true,
    },
    hasValue = ready > 0,
    needsContinuousUpdate = ready < max_value,
  }
end

function module:BuildState()
  local rune_power_type = (Enum and Enum.PowerType and Enum.PowerType.Runes) or 5

  if not GetRuneCooldown then
    return BuildFallbackState(rune_power_type)
  end

  local rune_count = DEFAULT_RUNE_COUNT
  if GetNumRunes then
    local api_count = GetNumRunes() or 0
    if api_count > 0 then
      rune_count = api_count
    end
  end

  local max_value = UnitPowerMax and UnitPowerMax("player", rune_power_type) or 0
  if max_value and max_value > rune_count then
    rune_count = max_value
  end
  if rune_count <= 0 then
    return BuildFallbackState(rune_power_type)
  end

  local now = GetTime()
  local ready_count = 0
  local rune_states = {}
  local saw_rune_data = false

  for rune_index = 1, rune_count do
    local start, duration, rune_ready = GetRuneCooldown(rune_index)
    local progress = 0
    local state_rank = 1

    if rune_ready then
      saw_rune_data = true
      state_rank = 4
      progress = 1
      ready_count = ready_count + 1
    elseif start and duration and duration > 0 then
      saw_rune_data = true
      progress = Clamp01((now - start) / duration)
      local cooldown_ending_start_time = (start + duration) - 0.67
      if now >= cooldown_ending_start_time then
        state_rank = 3
      else
        state_rank = 2
      end
    end

    rune_states[rune_index] = {
      progress = progress,
      stateRank = state_rank,
      start = start or 0,
      runeIndex = rune_index,
    }
  end

  if not saw_rune_data then
    return BuildFallbackState(rune_power_type, rune_count)
  end

  table.sort(rune_states, function(a, b)
    if a.stateRank ~= b.stateRank then
      return a.stateRank > b.stateRank
    end
    if a.start ~= b.start then
      return a.start < b.start
    end
    return a.runeIndex > b.runeIndex
  end)

  local values = {}
  local needs_continuous_update = ready_count < rune_count
  for i = 1, rune_count do
    values[i] = rune_states[i].progress
  end

  local r, g, b = GetRuneReadyColor()
  return {
    kind = "segments",
    token = "RUNES",
    powerType = rune_power_type,
    count = rune_count,
    values = values,
    color = { r, g, b },
    options = {
      rechargeVisual = "alpha_pop",
      suppressFullChargeHighlight = true,
    },
    hasValue = ready_count > 0,
    needsContinuousUpdate = needs_continuous_update,
  }
end

ns.RegisterResourceModule("DEATHKNIGHT", module)
