local _, ns = ...

local PT = Enum and Enum.PowerType or nil

ns.RegisterResourceModule("MONK", ns.CreateSegmentResourceModule({
  token = "CHI",
  power_type = (PT and PT.Chi) or 12,
  get_color = function()
    return ns.GetResourcePaletteColor("MONK")
  end,
}))
