local _, ns = ...

local palette = {
  ROGUE = { 0.90, 0.18, 0.20 },
  DRUID = { 0.98, 0.55, 0.18 },
  PALADIN = { 0.95, 0.90, 0.60 },
  MONK = { 0.71, 1.00, 0.92 },
  WARLOCK = { 0.63, 0.31, 0.78 },
  MAGE = { 0.42, 0.28, 0.98 },
  EVOKER = { 0.22, 0.88, 0.72 },
}

function ns.GetResourcePaletteColor(key)
  local color = key and palette[key] or nil
  if not color then
    return nil
  end

  return color[1], color[2], color[3]
end
