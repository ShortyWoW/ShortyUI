local addonName, addon = ...

local function isVersionOlder(a, b)
    if not a then return true end
    local a1, a2, a3 = a:match("(%d+)%.(%d+)%.(%d+)")
    local b1, b2, b3 = b:match("(%d+)%.(%d+)%.(%d+)")
    if not a1 or not b1 then return true end
    a1, a2, a3 = tonumber(a1), tonumber(a2), tonumber(a3)
    b1, b2, b3 = tonumber(b1), tonumber(b2), tonumber(b3)
    if a1 ~= b1 then return a1 < b1 end
    if a2 ~= b2 then return a2 < b2 end
    return a3 < b3
end

local migrations = {
    {
        version = "2.8.0",
        migrate = function()
            local defaults = addon:DefaultRoutes()
            for name, route in pairs(defaults) do
                addon.data.routes[name] = route
            end

            addon.data.routes["Midnight 10-90 (Horde)"] = nil
            addon.data.routes["Midnight 10-90 (Alliance)"] = nil
        end
    }
}

function addon:RunMigrations(oldVersion)
    local migrated = false
    for _, entry in ipairs(migrations) do
        if isVersionOlder(oldVersion, entry.version) then
            entry.migrate()
            addon.pendingChangelog = entry.version
            migrated = true
        end
    end
    return migrated
end
