local _, ns = ...

local PT = Enum and Enum.PowerType or nil

ns.RegisterResourceModule("DRUID", ns.CreateSegmentResourceModule({
  token = "COMBO_POINTS",
  power_type = (PT and PT.ComboPoints) or 4,
  get_color = function()
    return ns.GetResourcePaletteColor("DRUID")
  end,
}))
