local addonName, addon = ...

-- Resolve a route entry that may be a string, a condition/pass/fail table, or a switch table
-- Returns the resolved route name (string) or nil if unresolvable
function addon:ResolveRouteEntry(entry)
    if type(entry) == "string" then
        return entry
    elseif type(entry) == "table" then
        if entry.switch then
            for _, case in ipairs(entry.switch) do
                if not case.condition or addon:EvaluateCondition(case.condition) then
                    return case.route
                end
            end
            return nil
        elseif entry.condition then
            if addon:EvaluateCondition(entry.condition) then
                return entry.pass
            else
                return entry.fail
            end
        end
    end
    return nil
end

-- Append resolved route names from a value that may be a string, table of strings, or nil
-- Uses ResolveRouteList for arrays so nested switches/conditions are fully expanded
local function appendResolved(result, value)
    if type(value) == "string" then
        result[#result + 1] = value
    elseif type(value) == "table" then
        local resolved = addon:ResolveRouteList(value)
        for _, name in ipairs(resolved) do
            result[#result + 1] = name
        end
    end
end

-- Resolve an entire segment route array into a flat list of route names
-- Handles strings, condition/pass/fail (with array support), and switch (with route or routes)
function addon:ResolveRouteList(routeArray)
    local result = {}
    for _, entry in ipairs(routeArray) do
        if type(entry) == "table" and entry.switch then
            for _, case in ipairs(entry.switch) do
                if not case.condition or addon:EvaluateCondition(case.condition) then
                    if case.route then
                        result[#result + 1] = case.route
                    elseif case.routes then
                        appendResolved(result, case.routes)
                    end
                    break
                end
            end
        elseif type(entry) == "table" and entry.condition then
            if addon:EvaluateCondition(entry.condition) then
                appendResolved(result, entry.pass)
            else
                appendResolved(result, entry.fail)
            end
        else
            local resolved = addon:ResolveRouteEntry(entry)
            if resolved then
                result[#result + 1] = resolved
            end
        end
    end
    return result
end

-- Collect ALL possible route names from a route array without evaluating conditions
-- Used for orphan detection and export so that unreachable branches are still included
local function collectAllReferencedNames(routeArray, out)
    for _, entry in ipairs(routeArray) do
        if type(entry) == "string" then
            out[entry] = true
        elseif type(entry) == "table" then
            if entry.switch then
                for _, case in ipairs(entry.switch) do
                    if case.route then
                        out[case.route] = true
                    elseif case.routes then
                        collectAllReferencedNames(case.routes, out)
                    end
                end
            elseif entry.condition then
                local function collectBranch(val)
                    if type(val) == "string" then
                        out[val] = true
                    elseif type(val) == "table" then
                        collectAllReferencedNames(val, out)
                    end
                end
                collectBranch(entry.pass)
                collectBranch(entry.fail)
            end
        end
    end
end

function addon:GetRouteTree(routes, startingKey)
    local uniqueRoutes = {}
    local processed = {}

    local function processRoute(name, route)
        if processed[name] then
            return
        end

        processed[name] = true
        table.insert(uniqueRoutes, name)

        if route.route then
            -- Collect ALL referenced names across every branch (not just the evaluated one)
            local allRefs = {}
            collectAllReferencedNames(route.route, allRefs)
            for subrouteName in pairs(allRefs) do
                if routes[subrouteName] then
                    processRoute(subrouteName, routes[subrouteName])
                end
            end
        end
    end

    if routes[startingKey] then
        processRoute(startingKey, routes[startingKey])
    end

    return uniqueRoutes
end

local function processRoutes(routes)
    local menuStructure = {}

    local function processRoute(name, route, path)
        local entryPath = {}
        if #path ~= 0 then
            for index, value in ipairs(path) do
                if name == value then
                    print("ERROR: An endless loop was detected involving " .. name .. ".")
                    return nil
                end
                entryPath[index] = value
            end
        end
        entryPath[#entryPath + 1] = name

        local menuEntry = {
            display = route.display or name,
            name = name,
            path = entryPath,
            children = {}
        }

        if route.route then
            local resolved = addon:ResolveRouteList(route.route)
            for _, subrouteName in ipairs(resolved) do
                if routes[subrouteName] then
                    menuEntry.children[#menuEntry.children + 1] = processRoute(subrouteName, routes[subrouteName], entryPath)
                end
            end
        end

        return menuEntry
    end

    -- Build a set of all route names referenced by any segment (across all branches)
    local referenced = {}
    for _, route in pairs(routes) do
        if route.class == "segment" then
            collectAllReferencedNames(route.route, referenced)
        end
    end

    local orphaned = {}
    for name, route in pairs(routes) do
        local found = referenced[name] or false
        if not found then
            orphaned[name] = route
        end
    end

    for name, route in pairs(orphaned) do
        menuStructure[name] = processRoute(name, route, {})
    end

    return menuStructure
end

addon.processRoutes = processRoutes

function addon:FindMenuNode(name)
    local function search(node)
        if node.name == name then return node end
        if node.children then
            for _, child in ipairs(node.children) do
                local found = search(child)
                if found then return found end
            end
        end
        return nil
    end
    for _, root in pairs(addon.menu) do
        local found = search(root)
        if found then return found end
    end
    return nil
end
