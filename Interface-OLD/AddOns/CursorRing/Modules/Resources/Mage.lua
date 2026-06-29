local _, ns = ...

local PT = Enum and Enum.PowerType or nil

ns.RegisterResourceModule("MAGE", ns.CreateSegmentResourceModule({
  token = "ARCANE_CHARGES",
  power_type = (PT and PT.ArcaneCharges) or 16,
  use_unmodified = true,
  get_color = function()
    return ns.GetResourcePaletteColor("MAGE")
  end,
}))
