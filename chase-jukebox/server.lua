--====================================================================--
--  chase-jukebox / server.lua  (QBCore + oxmysql + xSound)
--====================================================================--

local QBCore = exports['qb-core']:GetCoreObject()

local USABLE_ITEM = "jukeboxone"
local DEFAULT_PROP = "prop_jukebox_02"
local HISTORY_KEEP = 5

local Locations = {}
local IsPaused  = {}

local function labelFor(id)
    return ("station_%s"):format(id)
end

local function extractId(payload)
    if type(payload) == "table" then
        if payload.id then return tonumber(payload.id) end
        if payload.args and payload.args.id then return tonumber(payload.args.id) end
    end
    return tonumber(payload)
end

local function xs(fn, ...)
    local ok, res = pcall(function(...)
        local ex = exports.xsound
        if not ex or type(ex[fn]) ~= "function" then return false end
        return ex[fn](ex, ...)
    end, ...)
    return ok and res or false
end

local function toNum(v, fallback)
    if v == nil then return fallback end
    local n = tonumber(v)
    if n == nil then return fallback end
    return n
end

local function asArray(map)
    local arr = {}
    for _, v in pairs(map) do arr[#arr+1] = v end
    return arr
end

local function syncAll()
    TriggerClientEvent("djbooth:client:syncLocations", -1, asArray(Locations))
end

local function syncOne(src)
    TriggerClientEvent("djbooth:client:syncLocations", src, asArray(Locations))
end

AddEventHandler("onResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end
    Locations = {}
    IsPaused  = {}

    local rows = MySQL.query.await("SELECT * FROM music_stations", {}) or {}
    for _, r in ipairs(rows) do
        local x = toNum(r.x, 0.0)
        local y = toNum(r.y, 0.0)
        local z = toNum(r.z, 0.0)
        local h = toNum(r.heading, 0.0)
        local vol = toNum(r.volume, 0.2)
        local rad = math.floor(toNum(r.radius, 30))

        Locations[r.id] = {
            id = r.id,
            owner = r.citizenid,
            job = "public",
            enableBooth = true,
            DefaultVolume = vol,
            radius = rad,
            coords = vector4(x, y, z, h),
            prop = { model = tostring(r.model), coords = vector4(x, y, z, h) },
        }
        IsPaused[r.id] = false
    end

    print(("[MusicStation] Loaded %d stations from DB"):format(#rows))
    syncAll()
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == "table" and player.PlayerData and player.PlayerData.source or player
    if src then
        if syncOne then syncOne(src) elseif syncAll then syncAll() end
    end
end)

QBCore.Functions.CreateUseableItem(USABLE_ITEM, function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    if Player.Functions.GetItemByName(USABLE_ITEM) then
        TriggerClientEvent("djbooth:client:startPlacement", source, DEFAULT_PROP)
    else
        TriggerClientEvent("QBCore:Notify", source, "You don’t have a Music Station", "error")
    end
end)

RegisterNetEvent("djbooth:server:addPlacedBooth", function(boothData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Player.Functions.RemoveItem(USABLE_ITEM, 1) then
        TriggerClientEvent("QBCore:Notify", src, "No Music Station to place", "error")
        return
    end
    TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[USABLE_ITEM], "remove")

    local cid = Player.PlayerData.citizenid
    local c = boothData.coords or {}
    local x, y, z, h = toNum(c.x, 0.0), toNum(c.y, 0.0), toNum(c.z, 0.0), toNum(c.w, 0.0)
    local modelField = (boothData.prop and boothData.prop.model) or DEFAULT_PROP
    local modelStr = tostring(modelField)
    local vol = toNum(boothData.DefaultVolume, 0.2)
    if vol < 0.0 then vol = 0.0 elseif vol > 1.0 then vol = 1.0 end
    local rad = math.max(1, math.floor(toNum(boothData.radius, 30)))

    local insertId = MySQL.insert.await([[
        INSERT INTO music_stations (citizenid, item, model, x, y, z, heading, volume, radius, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    ]], { cid, USABLE_ITEM, modelStr, x, y, z, h, vol, rad })

    if not insertId then
        TriggerClientEvent("QBCore:Notify", src, "Failed to save station", "error")
        return
    end

    Locations[insertId] = {
        id = insertId,
        owner = cid,
        job = "public",
        enableBooth = true,
        DefaultVolume = vol,
        radius = rad,
        coords = vector4(x, y, z, h),
        prop = { model = modelStr, coords = vector4(x, y, z, h) },
    }

    IsPaused[insertId] = false
    syncAll()
    TriggerClientEvent("QBCore:Notify", src, "Music Station placed", "success")
end)

RegisterNetEvent("djbooth:server:removeBooth", function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local id = extractId(data)
    if not id then return end

    local booth = Locations[id]
    if not booth then
        TriggerClientEvent("QBCore:Notify", src, "Station not found", "error")
        return
    end
    if booth.owner ~= Player.PlayerData.citizenid then
        TriggerClientEvent("QBCore:Notify", src, "You do not own this station", "error")
        return
    end

    xs('Destroy', -1, labelFor(id))
    MySQL.update.await("DELETE FROM music_stations WHERE id = ?", { id })
    Locations[id] = nil
    IsPaused[id] = nil

    TriggerClientEvent("djbooth:client:removeSpawnedBooth", -1, id)

    Player.Functions.AddItem(USABLE_ITEM, 1)
    TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[USABLE_ITEM], "add")
    TriggerClientEvent("QBCore:Notify", src, "Music Station removed", "success")
end)

lib.callback.register('djbooth:songInfo', function(src, id)
    id = tonumber(id)
    if not id then return {} end

    local rows = MySQL.query.await([[
        SELECT url
        FROM music_station_history
        WHERE station_id = ?
        ORDER BY played_at DESC
        LIMIT ?
    ]], { id, HISTORY_KEEP }) or {}

    local out = {}
    for _, r in ipairs(rows) do out[#out+1] = r.url end
    return out
end)

RegisterNetEvent("djbooth:server:playMusic", function(url, id)
    id = tonumber(id); if not id then return end
    local booth = Locations[id]; if not booth then return end

    local lbl = labelFor(id)
    local pos = vector3(booth.coords.x, booth.coords.y, booth.coords.z)
    local vol = booth.DefaultVolume or 0.2
    local rad = booth.radius or 30

    xs('PlayUrlPos', -1, lbl, url, vol, pos)
    xs('Distance',  -1, lbl, rad)
    xs('setVolume', -1, lbl, vol)

    MySQL.prepare.await([[
        INSERT INTO music_station_history (station_id, url, played_at)
        VALUES (?, ?, NOW())
        ON DUPLICATE KEY UPDATE played_at = VALUES(played_at)
    ]], { id, url })

    MySQL.update.await(([[DELETE h FROM music_station_history h
        WHERE h.station_id = ? AND h.id NOT IN (
            SELECT id FROM (
                SELECT id FROM music_station_history
                WHERE station_id = ?
                ORDER BY played_at DESC
                LIMIT %d
            ) t
        )
    ]]):format(HISTORY_KEEP), { id, id })

    IsPaused[id] = false
end)

RegisterNetEvent("djbooth:server:stopMusic", function(data)
    local id = extractId(data); if not id then return end
    if not Locations[id] then return end
    xs('Destroy', -1, labelFor(id))
    IsPaused[id] = false
end)

RegisterNetEvent("djbooth:server:PauseResume", function(data)
    local src = source
    local id = extractId(data); if not id then return end
    if not Locations[id] then return end
    local lbl = labelFor(id)

    if xs('TogglePause', -1, lbl) then
        IsPaused[id] = not IsPaused[id]
        return
    end

    local nowPaused = IsPaused[id] == true
    if nowPaused then
        if xs('Resume', -1, lbl) or xs('setPause', -1, lbl, false) then
            IsPaused[id] = false
            return
        end
    else
        if xs('Pause', -1, lbl) or xs('setPause', -1, lbl, true) then
            IsPaused[id] = true
            return
        end
    end

    TriggerClientEvent("QBCore:Notify", src, "Pause/Resume not supported on this audio build.", "error")
end)

RegisterNetEvent("djbooth:server:changeVolume", function(vol, id)
    id = tonumber(id); if not id then return end
    local booth = Locations[id]; if not booth then return end
    vol = toNum(vol, booth.DefaultVolume or 0.2)
    if vol < 0.0 then vol = 0.0 elseif vol > 1.0 then vol = 1.0 end
    xs('setVolume', -1, labelFor(id), vol)
    booth.DefaultVolume = vol
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Locations) do
        xs('Destroy', -1, labelFor(id))
    end
end)

RegisterNetEvent('djbooth:server:requestSync', function()
    local src = source
    if syncOne then
        syncOne(src)
    else
        if syncAll then syncAll() end
    end
end)

RegisterNetEvent("djbooth:server:setRange", function(range, id)
    local src = source
    id = tonumber(id)
    range = tonumber(range)
    if not id or not Locations[id] then
        TriggerClientEvent("QBCore:Notify", src, "Station not found", "error")
        return
    end

    range = math.max(1, math.min(25, range))
    Locations[id].radius = range
    xs('Distance', -1, labelFor(id), range)
    MySQL.update("UPDATE music_stations SET radius = ? WHERE id = ?", { range, id })
    TriggerClientEvent("QBCore:Notify", src, ("Station range set to %d"):format(range), "success")
    syncAll()
end)
