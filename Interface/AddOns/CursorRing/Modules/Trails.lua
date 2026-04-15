local addonName, ns = ...
local L = ns.L or {}

local function T(key)
  local value = L[key]
  if value == nil or value == "" then
    return key
  end
  return value
end

local CreateFrame = CreateFrame
local UIParent = UIParent
local math = math
local random = math.random
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local atan = math.atan
local pi = math.pi
local max = math.max
local min = math.min
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

local function Clamp(value, min_value, max_value)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function Clamp01(value)
  return Clamp(tonumber(value) or 0, 0, 1)
end

local function atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end
  if x > 0 then
    return atan(y / x)
  elseif x < 0 then
    return atan(y / x) + (y >= 0 and pi or -pi)
  elseif y > 0 then
    return pi * 0.5
  elseif y < 0 then
    return -pi * 0.5
  end
  return 0
end

local function applyTextureSampling(texture)
  if not texture then return end
  if texture.SetTexelSnappingBias then
    texture:SetTexelSnappingBias(0)
  end
  if texture.SetSnapToPixelGrid then
    texture:SetSnapToPixelGrid(false)
  end
end

local function setTextureSmooth(texture, path)
  if not (texture and path) then return end
  local ok = pcall(texture.SetTexture, texture, path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
  if not ok then
    texture:SetTexture(path)
  end
  applyTextureSampling(texture)
end

local TRAIL_ASSET_GROUPS = {
  {
    text = T("Blizzard Glows"),
    items = {
      { key = "metalglow", text = T("Challenge Metal Glow"), path = "Interface\\Challenges\\challenges-metalglow.blp", width = 256, height = 256, scale = 1.5 },
      { key = "petglow", text = T("Selected Pet Glow"), path = "Interface\\PETBATTLES\\PetBattle-SelectedPetGlow.blp", width = 256, height = 256 },
    },
  },
}

local TRAIL_ASSETS = {}

do
  for _, group in ipairs(TRAIL_ASSET_GROUPS) do
    for _, asset in ipairs(group.items or {}) do
      TRAIL_ASSETS[asset.key] = asset
    end
  end
end

local function get_trail_asset(asset_key)
  return TRAIL_ASSETS[asset_key or ""] or TRAIL_ASSETS.metalglow
end

ns.NormalizeTrailAssetKey = function(asset_key)
  return get_trail_asset(asset_key).key
end

ns.TrailModeChoices = {
  { value = "sprites", text = T("Glow sprites") },
  { value = "ribbon", text = T("Ribbon") },
  { value = "hybrid", text = T("Hybrid") },
  { value = "particles", text = T("Particles") },
}

ns.TrailColorModeChoices = {
  { value = "ring", text = T("Match ring") },
  { value = "custom", text = T("Custom color") },
}

ns.TrailBlendModeChoices = {
  { value = "ADD", text = T("Additive") },
  { value = "BLEND", text = T("Blend") },
}

do
  local asset_choices = {}
  for group_index, group in ipairs(TRAIL_ASSET_GROUPS) do
    local group_choice = {
      text = group.text,
      items = {},
    }
    for item_index, asset in ipairs(group.items or {}) do
      group_choice.items[item_index] = {
        value = asset.key,
        text = asset.text,
      }
    end
    asset_choices[group_index] = group_choice
  end
  ns.TrailAssetChoices = asset_choices
end

local function hide_texture_pool(pool)
  for i = 1, #pool do
    pool[i]:Hide()
  end
end

local function clear_array(list)
  for i = #list, 1, -1 do
    list[i] = nil
  end
end

local function ensure_texture_pool(parent, pool, count, layer)
  if #pool >= count then
    return
  end
  for i = #pool + 1, count do
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    applyTextureSampling(texture)
    texture:Hide()
    pool[i] = texture
  end
end

local function ensure_particle_pool(parent, pool, count, layer)
  if #pool >= count then
    return
  end
  for i = #pool + 1, count do
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    applyTextureSampling(texture)
    texture:Hide()
    pool[i] = {
      texture = texture,
      active = false,
      x = 0,
      y = 0,
      vx = 0,
      vy = 0,
      age = 0,
      life = 0,
      size = 0,
    }
  end
end

local function apply_trail_asset(texture, config)
  if not texture then
    return
  end

  if texture._trailAssetPath ~= config.asset_path then
    setTextureSmooth(texture, config.asset_path)
    texture._trailAssetPath = config.asset_path
  end

  local tex_coords = config.asset_tex_coords or { 0, 1, 0, 1 }
  if texture._trailTexCoord1 ~= tex_coords[1]
    or texture._trailTexCoord2 ~= tex_coords[2]
    or texture._trailTexCoord3 ~= tex_coords[3]
    or texture._trailTexCoord4 ~= tex_coords[4] then
    texture:SetTexCoord(tex_coords[1], tex_coords[2], tex_coords[3], tex_coords[4])
    texture._trailTexCoord1 = tex_coords[1]
    texture._trailTexCoord2 = tex_coords[2]
    texture._trailTexCoord3 = tex_coords[3]
    texture._trailTexCoord4 = tex_coords[4]
  end
end

function ns.CreateTrailSystem(anchor_frame, helpers)
  if type(anchor_frame) ~= "table" then
    return nil
  end

  local trail_frame = CreateFrame("Frame", nil, UIParent)
  trail_frame:SetAllPoints(UIParent)
  trail_frame:SetFrameStrata(anchor_frame:GetFrameStrata() or "TOOLTIP")
  trail_frame:SetFrameLevel(max((anchor_frame:GetFrameLevel() or 1) - 1, 1))
  trail_frame:Hide()

  local system = {
    frame = trail_frame,
    helpers = helpers or {},
    sprite_pool = {},
    ribbon_pool = {},
    particle_pool = {},
    history = {},
    sample_accumulator = 0,
    particle_cursor = 1,
    last_sample_x = nil,
    last_sample_y = nil,
    last_signature = nil,
    was_active = false,
  }

  function system:GetConfig()
    local cdb = CursorRingCharDB or ns.charDefaults or {}
    local asset_data = get_trail_asset(cdb.trailAsset)
    local aspect = 1
    if tonumber(asset_data.width) and tonumber(asset_data.height) and tonumber(asset_data.height) ~= 0 then
      aspect = tonumber(asset_data.width) / tonumber(asset_data.height)
    end

    local blend_mode = cdb.trailBlendMode or "ADD"
    if blend_mode ~= "ADD" and blend_mode ~= "BLEND" then
      blend_mode = "ADD"
    end

    local legacy_style = cdb.trailStyle or "sprites"
    if legacy_style ~= "sprites" and legacy_style ~= "ribbon" and legacy_style ~= "hybrid" and legacy_style ~= "particles" then
      legacy_style = "sprites"
    end

    local legacy_color_mode = cdb.trailColorMode or "ring"
    if legacy_color_mode ~= "ring" and legacy_color_mode ~= "custom" then
      legacy_color_mode = "ring"
    end
    local legacy_custom = cdb.trailCustomColor or { r = 1, g = 1, b = 1 }

    local function get_layer_enabled(key, fallback)
      local value = cdb[key]
      if value == nil then
        return fallback
      end
      return value == true
    end

    local function get_layer_color_mode(key)
      local value = cdb[key]
      if value ~= "ring" and value ~= "custom" then
        value = legacy_color_mode
      end
      if value ~= "ring" and value ~= "custom" then
        value = "ring"
      end
      return value
    end

    local function get_layer_custom_color(key)
      local color = cdb[key]
      if type(color) ~= "table" then
        color = legacy_custom
      end
      return {
        r = color.r or 1,
        g = color.g or 1,
        b = color.b or 1,
      }
    end

    local glow_enabled = get_layer_enabled("trailGlowEnabled", (legacy_style == "sprites" or legacy_style == "hybrid"))
    local ribbon_enabled = get_layer_enabled("trailRibbonEnabled", (legacy_style == "ribbon" or legacy_style == "hybrid"))
    local particle_enabled = get_layer_enabled("trailParticleEnabled", (legacy_style == "particles"))
    local any_layer_enabled = glow_enabled or ribbon_enabled or particle_enabled

    local segment_count = Clamp(math.floor(tonumber(cdb.trailSegments) or 8), 2, 24)
    local particle_count = Clamp(math.floor(tonumber(cdb.trailParticleCount) or 20), 4, 64)

    return {
      enabled = (cdb.trailEnabled == true) and any_layer_enabled,
      asset = asset_data.key,
      asset_path = asset_data.path,
      asset_scale = Clamp(tonumber(asset_data.scale) or 1, 0.1, 4),
      asset_aspect = Clamp(aspect, 0.1, 4),
      asset_tex_coords = asset_data.tex_coords,
      blend_mode = blend_mode,
      glow = {
        enabled = glow_enabled,
        color_mode = get_layer_color_mode("trailGlowColorMode"),
        custom = get_layer_custom_color("trailGlowCustomColor"),
      },
      ribbon = {
        enabled = ribbon_enabled,
        color_mode = get_layer_color_mode("trailRibbonColorMode"),
        custom = get_layer_custom_color("trailRibbonCustomColor"),
      },
      particles = {
        enabled = particle_enabled,
        color_mode = get_layer_color_mode("trailParticleColorMode"),
        custom = get_layer_custom_color("trailParticleCustomColor"),
      },
      alpha = Clamp01((tonumber(cdb.trailAlpha) or 60) / 100),
      size = Clamp(math.floor(tonumber(cdb.trailSize) or 24), 4, 96),
      length = Clamp(math.floor(tonumber(cdb.trailLength) or 320), 60, 1400) / 1000,
      segment_count = segment_count,
      sample_rate = Clamp(math.floor(tonumber(cdb.trailSampleRate) or 36), 10, 90),
      min_distance = Clamp(math.floor(tonumber(cdb.trailMinDistance) or 6), 0, 40),
      ribbon_width = Clamp(math.floor(tonumber(cdb.trailRibbonWidth) or 18), 2, 72),
      head_scale = Clamp(math.floor(tonumber(cdb.trailHeadScale) or 120), 50, 220) / 100,
      particle_count = particle_count,
      particle_burst = Clamp(math.floor(tonumber(cdb.trailParticleBurst) or 2), 1, 6),
      particle_spread = Clamp(math.floor(tonumber(cdb.trailParticleSpread) or 18), 0, 80),
      particle_speed = Clamp(math.floor(tonumber(cdb.trailParticleSpeed) or 80), 0, 260),
      particle_size = Clamp(math.floor(tonumber(cdb.trailParticleSize) or 12), 2, 48),
      sprite_count = segment_count,
      ribbon_count = max(segment_count - 1, 1),
    }
  end

  function system:GetLayerColorAndAlpha(layer_config, config, override_alpha)
    local r, g, b
    if layer_config and layer_config.color_mode == "custom" then
      local custom = layer_config.custom or {}
      r, g, b = custom.r, custom.g, custom.b
    elseif self.helpers and type(self.helpers.get_color) == "function" then
      r, g, b = self.helpers.get_color()
    else
      r, g, b = 1, 1, 1
    end

    local alpha = override_alpha
    if alpha == nil then
      alpha = config.alpha
      if self.helpers and type(self.helpers.get_alpha) == "function" then
        alpha = alpha * Clamp01(self.helpers.get_alpha())
      end
    end
    return r or 1, g or 1, b or 1, Clamp01(alpha or 1)
  end

  function system:HideAll()
    hide_texture_pool(self.sprite_pool)
    hide_texture_pool(self.ribbon_pool)
    for i = 1, #self.particle_pool do
      local particle = self.particle_pool[i]
      particle.active = false
      particle.texture:Hide()
    end
    self.frame:Hide()
  end

  function system:ResetTrail()
    clear_array(self.history)
    self.sample_accumulator = 0
    self.last_sample_x = nil
    self.last_sample_y = nil
    self.particle_cursor = 1
    self.was_active = false
    self:HideAll()
  end

  function system:RefreshConfig(force_reset)
    local config = self:GetConfig()
    local signature = table.concat({
      config.enabled and "1" or "0",
      config.glow.enabled and "1" or "0",
      config.ribbon.enabled and "1" or "0",
      config.particles.enabled and "1" or "0",
      config.asset,
      config.blend_mode,
      tostring(config.segment_count),
      tostring(config.particle_count),
    }, "|")

    if force_reset or self.last_signature ~= signature then
      self:ResetTrail()
      self.last_signature = signature
    end

    self.config = config

    if not config.enabled then
      self:HideAll()
      return
    end

    if config.glow.enabled then
      ensure_texture_pool(self.frame, self.sprite_pool, config.sprite_count, "ARTWORK")
    else
      hide_texture_pool(self.sprite_pool)
    end

    if config.ribbon.enabled then
      ensure_texture_pool(self.frame, self.ribbon_pool, config.ribbon_count, "BORDER")
    else
      hide_texture_pool(self.ribbon_pool)
    end

    if config.particles.enabled then
      ensure_particle_pool(self.frame, self.particle_pool, config.particle_count, "OVERLAY")
    else
      for i = 1, #self.particle_pool do
        self.particle_pool[i].active = false
        self.particle_pool[i].texture:Hide()
      end
    end

    self.frame:Show()
  end

  function system:PushHistory(x, y)
    local history = self.history
    local limit = self.config and self.config.segment_count or 8
    if #history < limit then
      history[#history + 1] = {}
    end
    for i = min(#history, limit), 2, -1 do
      local previous = history[i - 1]
      local current = history[i]
      current.x = previous.x
      current.y = previous.y
      current.age = previous.age
    end
    local head = history[1] or {}
    head.x = x
    head.y = y
    head.age = 0
    history[1] = head
    if #history > limit then
      history[limit + 1] = nil
    end
  end

  function system:AgeHistory(elapsed)
    local history = self.history
    local limit = self.config and self.config.length or 0.32
    for i = #history, 1, -1 do
      local sample = history[i]
      sample.age = (sample.age or 0) + elapsed
      if sample.age >= limit then
        table.remove(history, i)
      end
    end
  end

  function system:EmitParticles(x, y)
    local config = self.config
    if not config or not config.particles.enabled then
      return
    end
    ensure_particle_pool(self.frame, self.particle_pool, config.particle_count, "OVERLAY")

    local spread = config.particle_spread
    local speed = config.particle_speed
    for _ = 1, config.particle_burst do
      local particle = self.particle_pool[self.particle_cursor]
      self.particle_cursor = self.particle_cursor + 1
      if self.particle_cursor > config.particle_count then
        self.particle_cursor = 1
      end
      local angle = random() * pi * 2
      local distance = random() * spread
      particle.active = true
      particle.x = x + (cos(angle) * distance)
      particle.y = y + (sin(angle) * distance)
      particle.vx = cos(angle) * speed
      particle.vy = sin(angle) * speed
      particle.age = 0
      particle.life = max(config.length * 0.8, 0.08)
      particle.size = config.particle_size
    end
  end

  function system:RenderSprites()
    local config = self.config
    local history = self.history
    ensure_texture_pool(self.frame, self.sprite_pool, config.sprite_count, "ARTWORK")

    for i = 1, #self.sprite_pool do
      local texture = self.sprite_pool[i]
      local sample = history[i]
      if sample then
        local progress = 1 - Clamp01(sample.age / config.length)
        local alpha_scale = progress * progress
        local size_scale = 0.55 + (0.45 * progress)
        if i == 1 then
          size_scale = size_scale * config.head_scale
        end
        local size = max(config.size * size_scale * config.asset_scale, 2)
        local width = size * config.asset_aspect
        local r, g, b, a = self:GetLayerColorAndAlpha(config.glow, config, config.alpha * alpha_scale)
        apply_trail_asset(texture, config)
        texture:SetBlendMode(config.blend_mode)
        texture:SetVertexColor(r, g, b, a)
        texture:SetSize(width, size)
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sample.x, sample.y)
        if texture.SetRotation then
          texture:SetRotation(0)
        end
        texture:Show()
      else
        texture:Hide()
      end
    end
  end

  function system:RenderRibbon()
    local config = self.config
    local history = self.history
    ensure_texture_pool(self.frame, self.ribbon_pool, config.ribbon_count, "ARTWORK")

    for i = 1, #self.ribbon_pool do
      local texture = self.ribbon_pool[i]
      local a = history[i]
      local b = history[i + 1]
      if a and b then
        local dx = a.x - b.x
        local dy = a.y - b.y
        local length = sqrt((dx * dx) + (dy * dy))
        if length > 0.5 then
          local mid_x = (a.x + b.x) * 0.5
          local mid_y = (a.y + b.y) * 0.5
          local progress = 1 - Clamp01(((a.age or 0) + (b.age or 0)) * 0.5 / config.length)
          local alpha_scale = progress * progress
          local width = max(config.ribbon_width * (0.55 + (0.45 * progress)) * config.asset_scale, 1)
          local r, g, b2, a2 = self:GetLayerColorAndAlpha(config.ribbon, config, config.alpha * alpha_scale)
          apply_trail_asset(texture, config)
          texture:SetBlendMode(config.blend_mode)
          texture:SetVertexColor(r, g, b2, a2)
          texture:SetSize((length + width) * config.asset_aspect, width)
          texture:ClearAllPoints()
          texture:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mid_x, mid_y)
          if texture.SetRotation then
            texture:SetRotation(atan2(dy, dx))
          end
          texture:Show()
        else
          texture:Hide()
        end
      else
        texture:Hide()
      end
    end
  end

  function system:UpdateParticles(elapsed)
    local config = self.config
    if not config or not config.particles.enabled then
      for i = 1, #self.particle_pool do
        local particle = self.particle_pool[i]
        particle.active = false
        particle.texture:Hide()
      end
      return
    end

    ensure_particle_pool(self.frame, self.particle_pool, config.particle_count, "OVERLAY")

    for i = 1, #self.particle_pool do
      local particle = self.particle_pool[i]
      if particle.active then
        particle.age = particle.age + elapsed
        if particle.age >= particle.life then
          particle.active = false
          particle.texture:Hide()
        else
          local progress = 1 - Clamp01(particle.age / particle.life)
          local x = particle.x + (particle.vx * particle.age)
          local y = particle.y + (particle.vy * particle.age)
          local size = max(particle.size * (0.5 + (0.5 * progress)) * config.asset_scale, 1)
          local width = size * config.asset_aspect
          local r, g, b, a = self:GetLayerColorAndAlpha(config.particles, config, config.alpha * (progress * progress))
          local texture = particle.texture
          apply_trail_asset(texture, config)
          texture:SetBlendMode(config.blend_mode)
          texture:SetVertexColor(r, g, b, a)
          texture:SetSize(width, size)
          texture:ClearAllPoints()
          texture:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
          if texture.SetRotation then
            texture:SetRotation(0)
          end
          texture:Show()
        end
      else
        particle.texture:Hide()
      end
    end
  end

  function system:Update(elapsed, x, y, is_visible)
    if not self.config then
      self:RefreshConfig(true)
    end

    local config = self.config
    if not config or not config.enabled or not is_visible then
      if self.was_active then
        self:ResetTrail()
      else
        self:HideAll()
      end
      return
    end

    self.was_active = true
    self.frame:Show()
    self:AgeHistory(elapsed or 0)

    self.sample_accumulator = self.sample_accumulator + (elapsed or 0)
    local sample_interval = 1 / max(config.sample_rate, 1)
    local min_distance = config.min_distance
    local min_distance_sq = min_distance * min_distance

    while self.sample_accumulator >= sample_interval do
      self.sample_accumulator = self.sample_accumulator - sample_interval
      local should_add = false
      if self.last_sample_x == nil or self.last_sample_y == nil then
        should_add = true
      else
        local dx = x - self.last_sample_x
        local dy = y - self.last_sample_y
        if (dx * dx) + (dy * dy) >= min_distance_sq and (dx ~= 0 or dy ~= 0) then
          should_add = true
        end
      end

      if should_add then
        self:PushHistory(x, y)
        self.last_sample_x = x
        self.last_sample_y = y
        self:EmitParticles(x, y)
      end
    end

    if config.glow.enabled then
      self:RenderSprites()
    else
      hide_texture_pool(self.sprite_pool)
    end

    if config.ribbon.enabled then
      self:RenderRibbon()
    else
      hide_texture_pool(self.ribbon_pool)
    end

    self:UpdateParticles(elapsed or 0)
  end

  return system
end
