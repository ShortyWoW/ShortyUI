-- BliZzi Interrupts — Locale bootstrap
-- Creates BIT.Locales (one table per language) and BIT.L (active strings).
-- BIT:ApplyLocale() is called after SavedVars are loaded so the user's
-- language override (BIT.db.language) is respected.

BIT.Locales = {}
BIT.L       = {}

-- Fallback metatable: unknown keys return the key itself, never nil
setmetatable(BIT.L, {
    __index = function(_, key) return key end
})

function BIT:ApplyLocale()
    local lang = (self.db and self.db.language)
    -- "auto" or nil -> derive from client locale
    if not lang or lang == "auto" then
        local c = GetLocale()  -- e.g. "deDE", "frFR", "esES", "esMX", "enUS", "enGB"
        if     c == "deDE"              then lang = "deDE"
        elseif c == "frFR"              then lang = "frFR"
        elseif c == "esES" or c == "esMX" then lang = "esES"
        elseif c == "ruRU"              then lang = "ruRU"
        else                                 lang = "enUS"
        end
    end
    -- Start from enUS as base, then overwrite with chosen lang
    local base = BIT.Locales["enUS"] or {}
    for k, v in pairs(base) do BIT.L[k] = v end
    if lang ~= "enUS" then
        local overlay = BIT.Locales[lang] or {}
        for k, v in pairs(overlay) do BIT.L[k] = v end
    end
end
