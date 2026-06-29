local addonName, addon = ...

addon.active = nil

function addon:FindFirstLeaf(item)
    if #item.children ~= 0 then
        return addon:FindFirstLeaf(item.children[1])
    else
        return item
    end
end

local function InitializeDropDown(self, level)
    level = level or 1
    
    local function addSubMenuItems(menuData, currentLevel)
        for _, item in ipairs(menuData.children) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.display
            info.notCheckable = true
            info.hasArrow = #item.children > 0
            info.value = item
            
            if addon.active then
                local isInPath = true
                for index=1,#item.path do
                    if addon.active.path[index] ~= item.path[index] then
                        isInPath = false
                        break
                    end 
                end
                if isInPath then
                    info.colorCode = "|cFF00FF00"
                end
            end
            
            info.func = function(self)
                addon:UpdateActive(item)
                CloseDropDownMenus()
            end
            
            UIDropDownMenu_AddButton(info, currentLevel)
        end
    end

    local function addSeparator()
        local info = UIDropDownMenu_CreateInfo()
        info.text = ""
        info.notCheckable = true
        info.isTitle = true
        info.disabled = true
        UIDropDownMenu_AddButton(info, level)
    end
    
    if level == 1 then
        if addon.ui.RoutesFrame.viewer and addon.ui.RoutesFrame.viewer.editing and #addon.ui.RoutesFrame.viewer.editing == 0 then
            --[[ Import Menu Option
            if addon.importExportEnabled then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "Import"
                info.notCheckable = true
                info.func = function(self)
                    addon.ui.RoutesFrame.selection:Hide()
                    addon.ui.RoutesFrame.import:Show()
                end
                UIDropDownMenu_AddButton(info, level)
                addSeparator()
            end
            --]]
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Segment"
            info.notCheckable = true
            info.func = function(self)
                addon.ui.RoutesFrame:NewSegment("segment")
            end
            UIDropDownMenu_AddButton(info, level)
        
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Path"
            info.notCheckable = true
            info.func = function(self)
                addon.ui.RoutesFrame:NewSegment("path")
            end
            UIDropDownMenu_AddButton(info, level)
        end
                
        if addon.ui.RoutesFrame.viewer and addon.ui.RoutesFrame.viewer.editing and #addon.ui.RoutesFrame.viewer.editing ~= 0 then
            local editingEntry = addon.ui.RoutesFrame.viewer.editing[#addon.ui.RoutesFrame.viewer.editing]
            local editingName = type(editingEntry) == "string" and editingEntry or nil
            local editingRoute = editingName and addon.data.routes[editingName]
            local isCaseRef = type(editingEntry) == "table" and editingEntry.caseRef

            for name, item in pairs(addon.menu) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.display or name
                info.notCheckable = true
                info.hasArrow = #item.children > 0
                info.value = item

                info.func = function(self)
                    addon:UpdateActive(item)
                    if addon.active.path[1] ~= item.name then
                        addon:StartNewRun()
                    end
                    CloseDropDownMenus()
                end

                UIDropDownMenu_AddButton(info, level)
            end

            if (editingRoute and editingRoute.class == "segment") or isCaseRef then
                addSeparator()

                local info = UIDropDownMenu_CreateInfo()
                info.text = "|cFFFFCC00New Conditional|r"
                info.notCheckable = true
                info.func = function(self)
                    addon.ui.RoutesFrame.conditional.editing = nil
                    addon.ui.RoutesFrame:NewConditional()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

    else
        local menuData = UIDROPDOWNMENU_MENU_VALUE
        if menuData and menuData.children then
            local currentPath = {}
            local parent = menuData
            while parent do
                table.insert(currentPath, 1, parent)
                parent = parent.parent
            end
            
            addSubMenuItems(menuData, level, currentPath)
        end
    end
end

local function CreateDropDown()
    local dropdown = CreateFrame("Frame", "RouteViewerDropDown", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(dropdown, InitializeDropDown, "MENU")
    return dropdown
end

addon.CreateDropDown = CreateDropDown