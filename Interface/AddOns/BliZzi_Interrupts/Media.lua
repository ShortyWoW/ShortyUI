--[[
    Media.lua - BliZzi_Interrupts
    Font and texture resolution.
    Uses LibSharedMedia-3.0 if available, with manual fallbacks.
]]

BIT = BIT or {}
BIT.Media = {}

local LOCALE_FONT_OVERRIDES = {
    ["koKR"] = "Fonts\\2002.TTF",
    ["zhCN"] = "Fonts\\ARKai_T.TTF",
    ["zhTW"] = "Fonts\\blei00d.TTF",
    ["ruRU"] = "Fonts\\FRIZQT___CYR.TTF",
}

-- Built-in WoW fonts (always available, no addon needed)
local BUILTIN_FONTS = {
    { name = "Friz Quadrata (Default)", path = "Fonts\\FRIZQT__.TTF"  },
    { name = "Arial Narrow",            path = "Fonts\\ARIALN.TTF"    },
    { name = "Skurri",                  path = "Fonts\\SKURRI.TTF"    },
    { name = "Morpheus",                path = "Fonts\\MORPHEUS.TTF"  },
}

-- Built-in WoW border textures (always available)
local BUILTIN_BORDERS = {
    { name = "None",              path = nil                                                   },
    { name = "Tooltip",           path = "Interface\\Tooltips\\UI-Tooltip-Border"             },
    { name = "Glow",              path = "Interface\\Glues\\Components\\GlueMenu-Border"      },
    { name = "Dialog",            path = "Interface\\DialogFrame\\UI-DialogBox-Border"        },
    { name = "Achievement",       path = "Interface\\AchievementFrame\\UI-Achievement-Border" },
}

-- Built-in WoW sounds (always available, no addon needed)
local BUILTIN_SOUNDS = {
    { name = "None"                                                                         },
    { name = "Raid Warning",  file = "Sound\\Interface\\RaidWarning.ogg"                  },
    { name = "Error",         file = "Sound\\Interface\\IfloopIsEnd.ogg"                  },
    { name = "Alarm",         file = "Sound\\Interface\\AlarmClockWarning1.ogg"           },
    { name = "Coin",          file = "Sound\\Spells\\SimonGame_Visual_CoinDing.ogg"       },
    { name = "Ping",          file = "Sound\\Doodad\\BellTollNight.ogg"                   },
}

-- Built-in WoW textures (always available)
local BUILTIN_TEXTURES = {
    { name = "Flat",               path = "Interface\\BUTTONS\\WHITE8X8"               },
    { name = "Blizzard (Default)", path = "Interface\\TargetingFrame\\UI-StatusBar"    },
    { name = "Blizzard Raid Bar",  path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"     },
}

------------------------------------------------------------
-- Existence checks (for non-LibSM paths)
------------------------------------------------------------
local _probeTex = nil
local _probeFS  = nil

local function GetProbeTex()
    if not _probeTex then
        _probeTex = UIParent:CreateTexture(nil, "ARTWORK")
        _probeTex:SetSize(64, 64)
        _probeTex:Hide()
    end
    return _probeTex
end

local function GetProbeFS()
    if not _probeFS then
        _probeFS = UIParent:CreateFontString(nil, "ARTWORK")
        _probeFS:Hide()
    end
    return _probeFS
end

local function TextureExists(path)
    if not path or path == "" then return false end
    local probe = GetProbeTex()
    probe:SetTexture(path)
    local loaded = probe:GetTexture()
    probe:SetTexture(nil)
    return loaded ~= nil and loaded ~= ""
end

local function FontExists(path)
    local probe = GetProbeFS()
    local ok = pcall(function() probe:SetFont(path, 12, "") end)
    if not ok then return false end
    local loadedPath = probe:GetFont()
    if not loadedPath then return false end
    local normLoaded = loadedPath:lower():gsub("\\", "/")
    local normTarget = path:lower():gsub("\\", "/")
    return normLoaded:find(normTarget:match("[^/]+$") or normTarget, 1, true) ~= nil
end

------------------------------------------------------------
-- Get LibSharedMedia if available
------------------------------------------------------------
local function GetLSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

------------------------------------------------------------
-- Build available font list
------------------------------------------------------------
function BIT.Media:GetAvailableFonts()
    local out = {}
    local seen = {}

    local lsm = GetLSM()
    if lsm then
        -- Get all fonts registered in LibSharedMedia
        local list = lsm:List("font")
        if list then
            table.sort(list)
            for _, name in ipairs(list) do
                local path = lsm:Fetch("font", name)
                if path and not seen[name] then
                    seen[name] = true
                    table.insert(out, { name = name, path = path })
                end
            end
        end
    end

    -- Always add built-ins if not already covered by LSM
    for _, e in ipairs(BUILTIN_FONTS) do
        if not seen[e.name] and FontExists(e.path) then
            seen[e.name] = true
            table.insert(out, { name = e.name, path = e.path })
        end
    end

    return out
end

------------------------------------------------------------
-- Build available texture list
------------------------------------------------------------
function BIT.Media:GetAvailableTextures()
    local out = {}
    local seen = {}

    local lsm = GetLSM()
    if lsm then
        local list = lsm:List("statusbar")
        if list then
            table.sort(list)
            for _, name in ipairs(list) do
                local path = lsm:Fetch("statusbar", name)
                if path and not seen[name] then
                    seen[name] = true
                    table.insert(out, { name = name, path = path })
                end
            end
        end
    end

    -- Always add built-ins
    for _, e in ipairs(BUILTIN_TEXTURES) do
        if not seen[e.name] then
            seen[e.name] = true
            table.insert(out, { name = e.name, path = e.path })
        end
    end

    return out
end

------------------------------------------------------------
-- Build available border list
------------------------------------------------------------
function BIT.Media:GetAvailableBorders()
    local out  = {}
    local seen = {}

    -- "None" always first
    table.insert(out, { name = "None", path = nil })
    seen["None"] = true

    local lsm = GetLSM()
    if lsm then
        local list = lsm:List("border")
        if list then
            table.sort(list)
            for _, name in ipairs(list) do
                local path = lsm:Fetch("border", name)
                if path and not seen[name] then
                    seen[name] = true
                    table.insert(out, { name = name, path = path })
                end
            end
        end
    end

    -- Built-in fallbacks
    for _, e in ipairs(BUILTIN_BORDERS) do
        if e.path and not seen[e.name] then
            seen[e.name] = true
            table.insert(out, { name = e.name, path = e.path })
        end
    end

    return out
end


function BIT.Media:Load()
    self.flatTexture = "Interface\\BUTTONS\\WHITE8X8"

    local db     = BIT.db
    -- Font outline: "NONE" maps to empty string for WoW SetFont API
    local outline = db and db.fontOutline or "OUTLINE"
    self.fontFlags = (outline == "NONE") and "" or outline
    local locale = GetLocale()
    local lsm    = GetLSM()

    -- ── Font ──────────────────────────────────────────────
    if db and db.fontPath and FontExists(db.fontPath) then
        -- User override saved and file is still accessible
        self.font     = db.fontPath
        self.fontName = db.fontName or "Custom"
    else
        if db and db.fontPath then
            -- Saved font path no longer valid (addon removed etc.) — clear and fall through to auto-detect
            db.fontPath = nil
            db.fontName = nil
        end
        if LOCALE_FONT_OVERRIDES[locale] then
            self.font     = LOCALE_FONT_OVERRIDES[locale]
            self.fontName = "Locale-" .. locale
        else
            -- Auto-detect via LSM first, then manual fallbacks
            self.font     = "Fonts\\FRIZQT__.TTF"
            self.fontName = "Friz Quadrata (Default)"

            if lsm then
                -- Prefer Naowh → PT Sans Narrow → Expressway in that order if registered
                local preferred = { "Naowh", "PT Sans Narrow", "Expressway" }
                for _, name in ipairs(preferred) do
                    if lsm:IsValid("font", name) then
                        self.font     = lsm:Fetch("font", name)
                        self.fontName = name
                        break
                    end
                end
            end
        end
    end

    -- ── Texture ───────────────────────────────────────────
    if db and db.barTexturePath then
        self.barTexture     = db.barTexturePath
        self.barTextureName = db.barTextureName or "Custom"
    else
        self.barTexture     = self.flatTexture
        self.barTextureName = "Flat"

        if lsm then
            local preferred = { "Naowh", "Norm", "Minimalist", "Aluminium" }
            for _, name in ipairs(preferred) do
                if lsm:IsValid("statusbar", name) then
                    self.barTexture     = lsm:Fetch("statusbar", name)
                    self.barTextureName = name
                    break
                end
            end
        end
    end
end

function BIT.Media:SetFont(fontString, size)
    local path = self.font
    -- safety: if font path is invalid, fall back to WoW default
    if path then
        local ok = pcall(function() fontString:SetFont(path, size, self.fontFlags or "OUTLINE") end)
        if ok and fontString:GetFont() then return end
    end
    -- fallback — guaranteed to work
    fontString:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
end

function BIT.Media:SetBarTexture(widget)
    local tex = self.barTexture or self.flatTexture
    if widget.SetStatusBarTexture then widget:SetStatusBarTexture(tex)
    elseif widget.SetTexture then widget:SetTexture(tex) end
end

------------------------------------------------------------
-- Build available sound list (LSM sounds + built-ins)
------------------------------------------------------------
function BIT.Media:GetAvailableSounds()
    local out  = {}
    local seen = {}
    local lsm  = GetLSM()
    if lsm then
        local list = lsm:List("sound")
        if list then
            table.sort(list)
            for _, name in ipairs(list) do
                local path = lsm:Fetch("sound", name)
                if path and not seen[name] then
                    seen[name] = true
                    out[#out + 1] = { name = name, file = path }
                end
            end
        end
    end
    for _, s in ipairs(BUILTIN_SOUNDS) do
        if not seen[s.name] then
            seen[s.name] = true
            out[#out + 1] = s
        end
    end
    return out
end

------------------------------------------------------------
-- Play a sound by name
------------------------------------------------------------
function BIT.Media:PlayKickSound(soundName)
    if not soundName or soundName == "None" then return end
    local lsm = GetLSM()
    if lsm then
        local path = lsm:Fetch("sound", soundName, true)
        if path then PlaySoundFile(path, "Master"); return end
    end
    for _, s in ipairs(BUILTIN_SOUNDS) do
        if s.name == soundName and s.file then
            PlaySoundFile(s.file, "Master")
            return
        end
    end
end
