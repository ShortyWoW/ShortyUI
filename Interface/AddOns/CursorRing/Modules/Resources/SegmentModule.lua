local _, ns = ...

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

local function Clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

function ns.CreateSegmentResourceModule(config)
  config = config or {}

  local module = {}

  function module:BuildState()
    local power_type = config.power_type
    if config.get_power_type then
      power_type = config.get_power_type()
    end

    if power_type == nil then
      return nil
    end

    if config.is_available and not config.is_available(power_type) then
      return nil
    end

    local max_value
    if config.get_max_value then
      max_value = config.get_max_value(power_type)
    else
      max_value = UnitPowerMax and UnitPowerMax("player", power_type) or 0
    end

    if not max_value or max_value <= 0 then
      return nil
    end

    local current
    if config.get_current then
      current = config.get_current(power_type, max_value)
    else
      current = UnitPower and UnitPower("player", power_type, config.use_unmodified == true) or 0
    end

    current = tonumber(current) or 0

    local values = {}
    local needs_continuous_update = false
    for i = 1, max_value do
      local progress
      if config.get_segment_progress then
        progress = config.get_segment_progress(current, i, max_value, power_type)
      else
        progress = Clamp01(current - (i - 1))
      end

      progress = Clamp01(tonumber(progress) or 0)
      values[i] = progress

      if progress > 0 and progress < 1 then
        needs_continuous_update = true
      end
    end

    if config.needs_continuous_update then
      needs_continuous_update = not not config.needs_continuous_update(current, max_value, values, power_type)
    end

    local state = {
      kind = "segments",
      token = config.token,
      powerType = power_type,
      count = max_value,
      values = values,
      hasValue = config.has_value and config.has_value(current, max_value, values, power_type) or current > 0,
      needsContinuousUpdate = needs_continuous_update,
    }

    if config.get_color then
      local r, g, b = config.get_color(current, max_value, values, power_type)
      if r and g and b then
        state.color = { r, g, b }
      end
    end

    return state
  end

  return module
end
