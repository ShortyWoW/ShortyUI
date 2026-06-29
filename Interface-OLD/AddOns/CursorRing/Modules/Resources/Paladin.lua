local _, ns = ...

local PT = Enum and Enum.PowerType or nil

ns.RegisterResourceModule("PALADIN", ns.CreateSegmentResourceModule({
  token = "HOLY_POWER",
  power_type = (PT and PT.HolyPower) or 9,
  get_color = function()
    return ns.GetResourcePaletteColor("PALADIN")
  end,
}))
