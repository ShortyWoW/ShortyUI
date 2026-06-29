local _, ns = ...

local PT = Enum and Enum.PowerType or nil
local UnitPartialPower = UnitPartialPower
local UnitPower = UnitPower

local function GetEssenceValue(power_type, max_value)
  local current = UnitPower and UnitPower("player", power_type) or 0
  local partial = 0

  if UnitPartialPower and current < max_value then
    partial = (UnitPartialPower("player", power_type) or 0) / 1000
  end

  return current + partial
end

ns.RegisterResourceModule("EVOKER", ns.CreateSegmentResourceModule({
  token = "ESSENCE",
  power_type = (PT and PT.Essence) or 19,
  get_current = GetEssenceValue,
  get_color = function()
    return ns.GetResourcePaletteColor("EVOKER")
  end,
  needs_continuous_update = function(current, max_value)
    return current > 0 and current < max_value
  end,
}))
