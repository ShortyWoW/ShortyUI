local addonName, ns = ...
ns = ns or {}

local Controls = {}
ns.Controls = Controls

local function set_slider_enabled(frame, enabled)
  if not frame then return end
  if frame.Slider then
    if enabled then frame.Slider:Enable() else frame.Slider:Disable() end
    frame.Slider:EnableMouse(enabled)
  end
  if frame.DecrementButton then
    if enabled then frame.DecrementButton:Enable() else frame.DecrementButton:Disable() end
  end
  if frame.IncrementButton then
    if enabled then frame.IncrementButton:Enable() else frame.IncrementButton:Disable() end
  end
  if frame._left then
    if enabled then frame._left:Enable() else frame._left:Disable() end
  end
  if frame._right then
    if enabled then frame._right:Enable() else frame._right:Disable() end
  end
  frame:SetAlpha(enabled and 1 or 0.4)
end

function Controls.createCheck(parent, label, initial, on_click)
  local button = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  button.Text:SetText(label)
  button:SetChecked(initial)
  button:SetScript("OnClick", function(self)
    if on_click then
      on_click(not not self:GetChecked())
    end
  end)
  return button
end

function Controls.createSlider(parent, label, min_value, max_value, step, value, on_changed, low_text, high_text)
  local holder = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
  local slider = holder and holder.Slider
  if holder and slider then
    holder:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
    slider:EnableMouse(true)
    slider:SetMinMaxValues(min_value, max_value)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(value)
    holder._min, holder._max, holder._step = min_value, max_value, step
    holder.Text = holder.Text or holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holder.Text:ClearAllPoints()
    holder.Text:SetPoint("BOTTOM", holder, "TOP", 0, 2)
    holder.Text:SetText(label .. ": " .. value)
    if holder.Low and holder.High then
      holder.Low:ClearAllPoints()
      holder.Low:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)
      holder.Low:SetText(low_text or min_value)
      holder.High:ClearAllPoints()
      holder.High:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -8)
      holder.High:SetText(high_text or max_value)
    end
    slider:SetScript("OnValueChanged", function(_, raw_value)
      local rounded = math.floor(raw_value + 0.5)
      if holder.Text then
        holder.Text:SetText(label .. ": " .. rounded)
      end
      if on_changed then
        on_changed(rounded)
      end
    end)
    local function nudge(delta)
      local current = slider:GetValue() or value
      local next_value = math.min(holder._max, math.max(holder._min, current + (delta * holder._step)))
      slider:SetValue(next_value)
    end
    if holder.DecrementButton then
      holder.DecrementButton:SetScript("OnClick", function() nudge(-1) end)
    end
    if holder.IncrementButton then
      holder.IncrementButton:SetScript("OnClick", function() nudge(1) end)
    end
    holder.SetEnabled = holder.SetEnabled or set_slider_enabled
    holder.SetValue = holder.SetValue or function(self, next_value)
      if self.Slider then
        self.Slider:SetValue(next_value)
      end
    end
    return holder
  end

  local legacy = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  legacy:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
  legacy:EnableMouse(true)
  legacy:SetMinMaxValues(min_value, max_value)
  legacy:SetValueStep(step)
  legacy:SetObeyStepOnDrag(true)
  legacy:SetValue(value)
  legacy._min, legacy._max, legacy._step = min_value, max_value, step
  if legacy.SetThumbTexture then
    legacy:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  end
  if not legacy.Text then
    legacy.Text = legacy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  end
  legacy.Text:ClearAllPoints()
  legacy.Text:SetPoint("BOTTOM", legacy, "TOP", 0, 2)
  legacy.Text:SetText(label .. ": " .. value)
  if legacy.Low and legacy.High then
    legacy.Low:ClearAllPoints()
    legacy.Low:SetPoint("TOPLEFT", legacy, "BOTTOMLEFT", 0, -8)
    legacy.Low:SetText(low_text or min_value)
    legacy.High:ClearAllPoints()
    legacy.High:SetPoint("TOPRIGHT", legacy, "BOTTOMRIGHT", 0, -8)
    legacy.High:SetText(high_text or max_value)
  end
  legacy:SetScript("OnValueChanged", function(self, raw_value)
    local rounded = math.floor(raw_value + 0.5)
    if self.Text then
      self.Text:SetText(label .. ": " .. rounded)
    end
    if on_changed then
      on_changed(rounded)
    end
  end)
  local function nudge(delta)
    local current = legacy:GetValue() or value
    local next_value = math.min(legacy._max, math.max(legacy._min, current + (delta * legacy._step)))
    legacy:SetValue(next_value)
  end
  local left = CreateFrame("Button", nil, legacy, "UIPanelButtonTemplate")
  left:SetSize(18, 18)
  left:SetText("<")
  left:SetPoint("RIGHT", legacy, "LEFT", -4, 0)
  left:SetScript("OnClick", function() nudge(-1) end)
  legacy._left = left

  local right = CreateFrame("Button", nil, legacy, "UIPanelButtonTemplate")
  right:SetSize(18, 18)
  right:SetText(">")
  right:SetPoint("LEFT", legacy, "RIGHT", 4, 0)
  right:SetScript("OnClick", function() nudge(1) end)
  legacy._right = right
  legacy.SetEnabled = legacy.SetEnabled or set_slider_enabled
  legacy.SetValue = legacy.SetValue or function(self, next_value)
    self:SetValue(next_value)
  end
  return legacy
end

function Controls.createDropdown(parent, width, current, items, on_select)
  local selected = current
  local frame = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(frame, width)
  UIDropDownMenu_SetText(frame, selected)
  UIDropDownMenu_Initialize(frame, function(_, level)
    local info = UIDropDownMenu_CreateInfo()
    for _, item in ipairs(items or {}) do
      info.text = item
      info.func = function()
        selected = item
        UIDropDownMenu_SetText(frame, item)
        if on_select then
          on_select(item)
        end
        if CloseDropDownMenus then
          CloseDropDownMenus()
        end
      end
      info.checked = (item == selected)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  return frame
end

function Controls.createMainActionButton(parent, text, on_click)
  local button
  if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
    local ok, modern = pcall(CreateFrame, "Button", nil, parent, "UIMenuButtonStretchTemplate")
    if ok and modern then
      button = modern
      button:SetHeight(24)
      if button.SetNormalFontObject then button:SetNormalFontObject("GameFontNormalSmall") end
      if button.SetHighlightFontObject then button:SetHighlightFontObject("GameFontHighlightSmall") end
      if button.SetDisabledFontObject then button:SetDisabledFontObject("GameFontDisableSmall") end
    end
  end
  if not button then
    button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetHeight(22)
  end
  button:SetText(text or "")
  button:SetScript("OnClick", on_click)
  return button
end

function Controls.initLegacyScrollFrame(scroll_frame, pan_extent)
  if not scroll_frame then return end
  local scroll_bar = scroll_frame.ScrollBar
  if not scroll_bar and scroll_frame.GetName then
    scroll_bar = _G[(scroll_frame:GetName() or "") .. "ScrollBar"]
  end
  if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar and scroll_bar and scroll_bar.RegisterCallback then
    ScrollUtil.InitScrollFrameWithScrollBar(scroll_frame, scroll_bar)
    if pan_extent and scroll_frame.SetPanExtent then
      scroll_frame:SetPanExtent(pan_extent)
    end
    scroll_frame:EnableMouseWheel(true)
    return
  end

  scroll_frame:EnableMouseWheel(true)
  if scroll_bar and not scroll_frame:GetScript("OnMouseWheel") then
    scroll_frame:SetScript("OnMouseWheel", function(self, delta)
      local range = self:GetVerticalScrollRange() or 0
      local current = self:GetVerticalScroll() or 0
      local step = pan_extent or 30
      local next_value = math.max(0, math.min(range, current - (delta * step)))
      self:SetVerticalScroll(next_value)
    end)
  end
end
