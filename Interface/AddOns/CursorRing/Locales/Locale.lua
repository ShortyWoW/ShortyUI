local addon_name, ns = ...

local active_locale = (type(GetLocale) == "function" and GetLocale()) or "enUS"
local default_locale = {}
local selected_locale = {}

setmetatable(selected_locale, {
  __index = function(_, key)
    local value = default_locale[key]
    if value ~= nil then
      return value
    end
    return key
  end,
})

ns._locale_code = active_locale
ns._locale_default = default_locale
ns._locale_selected = selected_locale
ns.L = selected_locale

function ns.NewLocale(locale, is_default)
  if type(locale) ~= "string" or locale == "" then
    return nil
  end
  if is_default == true or locale == "enUS" then
    return default_locale
  end
  if locale == active_locale then
    return selected_locale
  end
  return nil
end
