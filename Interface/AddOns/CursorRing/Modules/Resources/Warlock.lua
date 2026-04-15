local _, ns = ...

local PT = Enum and Enum.PowerType or nil
local C_SpecializationInfo = C_SpecializationInfo
local GetSpecializationInfo = GetSpecializationInfo
local UnitPower = UnitPower
local UnitPowerDisplayMod = UnitPowerDisplayMod
local math_floor = math.floor

local SPEC_ID_WARLOCK_DESTRUCTION = 267

local function GetShardPower(power_type)
  if not UnitPower then
    return 0
  end

  local raw_power = UnitPower("player", power_type, true) or 0
  local display_mod = UnitPowerDisplayMod and UnitPowerDisplayMod(power_type) or 0
  local shard_power = display_mod ~= 0 and (raw_power / display_mod) or 0

  local spec_index = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization() or nil
  local spec_id = spec_index and GetSpecializationInfo and select(1, GetSpecializationInfo(spec_index)) or nil
  if spec_id ~= SPEC_ID_WARLOCK_DESTRUCTION then
    shard_power = math_floor(shard_power)
  end

  return shard_power
end

ns.RegisterResourceModule("WARLOCK", ns.CreateSegmentResourceModule({
  token = "SOUL_SHARDS",
  power_type = (PT and PT.SoulShards) or 7,
  get_current = GetShardPower,
  get_color = function()
    return ns.GetResourcePaletteColor("WARLOCK")
  end,
  needs_continuous_update = function(current, max_value)
    return current > 0 and current < max_value and current ~= math_floor(current)
  end,
}))
