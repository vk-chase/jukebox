local QBCore = exports['qb-core']:GetCoreObject()

local TABLE_NAME = Config.TableName or 'chasemusicbox'
local Locations = {}
local IsPaused = {}

local function L(key, ...)
    local lang = (Locales and Locales[Config.Locale]) or (Locales and Locales.en) or {}
    local phrase = lang[key] or key
    local argc = select('#', ...)
    if argc > 0 then
        return phrase:format(...)
    end
    return phrase
end

local function Debug(msg)
    if Config.Debug then
        print(('[vkmusicplayers][server] %s'):format(msg))
    end
end

local function Notify(src, msg, msgType)
    TriggerClientEvent('QBCore:Notify', src, msg, msgType or 'primary')
end

local function XS(fn, ...)
    local ok, res = pcall(function(...)
        local ex = exports[Config.Audio.XSoundResource]
        if not ex or type(ex[fn]) ~= 'function' then return false end
        return ex[fn](ex, ...)
    end, ...)
    return ok and res or false
end

local function LabelFor(id)
    return ('station_%s'):format(id)
end

local function ExtractId(payload)
    if type(payload) == 'table' then
        if payload.id then return tonumber(payload.id) end
        if payload.args and payload.args.id then return tonumber(payload.args.id) end
    end
    return tonumber(payload)
end

local function Trim(value)
    if type(value) ~= 'string' then return '' end
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function ToNum(value, fallback)
    if value == nil then return fallback end
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function AsArray(map)
    local out = {}
    for _, v in pairs(map) do
        out[#out + 1] = v
    end
    return out
end

local function GetStationTypeConfig(stationType)
    return Config.StationTypes[stationType or '']
end

local function GetHistoryKeep(stationType)
    local cfg = GetStationTypeConfig(stationType)
    return math.max(1, math.floor((cfg and cfg.HistoryKeep) or Config.History.DefaultKeep or 5))
end

local function IsModelAllowed(stationType, model)
    local cfg = GetStationTypeConfig(stationType)
    if not cfg then return false end

    local textModel = tostring(model)
    local numericModel = tonumber(model)
    for i = 1, #(cfg.AllowedProps or {}) do
        local entry = cfg.AllowedProps[i]
        if tostring(entry.model) == textModel then
            return true
        end
        local entryNum = tonumber(entry.model)
        if entryNum and numericModel and entryNum == numericModel then
            return true
        end
    end

    return false
end

local function DecodeHistory(historyJson)
    if type(historyJson) ~= 'string' or historyJson == '' then
        return {}
    end

    local decoded = nil
    local ok = pcall(function()
        decoded = json.decode(historyJson)
    end)

    if not ok or type(decoded) ~= 'table' then
        return {}
    end

    local out = {}
    for i = 1, #decoded do
        local entry = decoded[i]
        if type(entry) == 'string' and entry ~= '' then
            out[#out + 1] = entry
        elseif type(entry) == 'table' and type(entry.url) == 'string' and entry.url ~= '' then
            out[#out + 1] = entry.url
        end
    end
    return out
end

local function EncodeHistory(urls)
    return json.encode(urls or {}) or '[]'
end

local function NormalizeHistory(urls, stationType)
    local seen, out = {}, {}
    local keep = GetHistoryKeep(stationType)

    for i = 1, #(urls or {}) do
        local url = Trim(urls[i])
        if url ~= '' and not seen[url] then
            seen[url] = true
            out[#out + 1] = url
            if #out >= keep then
                break
            end
        end
    end

    return out
end

local function ExtractYouTubeId(url)
    if type(url) ~= 'string' or url == '' then return nil end
    url = Trim(url)

    local patterns = {
        '[?&]v=([%w-_]+)',
        'youtu%.be/([%w-_]+)',
        'youtube%.com/embed/([%w-_]+)',
        'youtube%.com/shorts/([%w-_]+)',
        'youtube%.com/live/([%w-_]+)',
        '/v/([%w-_]+)',
    }

    for i = 1, #patterns do
        local id = url:match(patterns[i])
        if id and #id >= 11 then
            return id:sub(1, 11)
        end
    end

    if url:match('^[%w-_]+$') and #url >= 11 then
        return url:sub(1, 11)
    end

    return nil
end

local function FetchYouTubeMeta(url)
    if not Config.History.FetchYouTubeMeta then
        return {
            videoId = ExtractYouTubeId(url),
            title = 'YouTube Video',
            author = 'Unknown Channel',
            thumbnail = nil,
            url = url,
        }
    end

    local videoId = ExtractYouTubeId(url)
    local fallbackThumb = videoId and ('https://img.youtube.com/vi/%s/hqdefault.jpg'):format(videoId) or nil

    if not videoId then
        return {
            videoId = nil,
            title = 'Audio Track',
            author = 'External Source',
            thumbnail = nil,
            url = url,
        }
    end

    local promiseHandle = promise.new()
    local apiUrl = ('https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=%s&format=json'):format(videoId)

    PerformHttpRequest(apiUrl, function(status, body)
        if status ~= 200 or not body or body == '' then
            promiseHandle:resolve({
                videoId = videoId,
                title = 'YouTube Video',
                author = 'Unknown Channel',
                thumbnail = fallbackThumb,
                url = url,
            })
            return
        end

        local decoded = nil
        local ok = pcall(function()
            decoded = json.decode(body)
        end)

        if not ok or type(decoded) ~= 'table' then
            promiseHandle:resolve({
                videoId = videoId,
                title = 'YouTube Video',
                author = 'Unknown Channel',
                thumbnail = fallbackThumb,
                url = url,
            })
            return
        end

        promiseHandle:resolve({
            videoId = videoId,
            title = decoded.title or 'YouTube Video',
            author = decoded.author_name or 'Unknown Channel',
            thumbnail = decoded.thumbnail_url or fallbackThumb,
            url = url,
        })
    end, 'GET', '', { ['Content-Type'] = 'application/json' })

    return Citizen.Await(promiseHandle)
end

local function SyncAll()
    TriggerClientEvent('vkmusicplayers:client:syncStations', -1, AsArray(Locations))
end

local function SyncOne(src)
    TriggerClientEvent('vkmusicplayers:client:syncStations', src, AsArray(Locations))
end

local function PlayerCanManage(src, booth)
    local player = QBCore.Functions.GetPlayer(src)
    if not player or not booth then return false, player end
    if booth.owner == player.PlayerData.citizenid then return true, player end
    if Config.Features.AdminBypass and QBCore.Functions.HasPermission(src, 'admin') then return true, player end
    return false, player
end

local function PushHistory(id, url)
    local booth = Locations[id]
    if not booth then return end

    local history = booth.history or {}
    local nextHistory = { url }

    for i = 1, #history do
        if history[i] ~= url then
            nextHistory[#nextHistory + 1] = history[i]
        end
    end

    nextHistory = NormalizeHistory(nextHistory, booth.stationType)
    booth.history = nextHistory

    MySQL.update.await(([[
        UPDATE `%s`
        SET history_json = ?, updated_at = NOW()
        WHERE id = ?
    ]]):format(TABLE_NAME), { EncodeHistory(nextHistory), id })
end

local function RemoveHistoryUrl(id, url)
    local booth = Locations[id]
    if not booth then return false end

    local history = booth.history or {}
    local nextHistory = {}
    local removed = false

    for i = 1, #history do
        if history[i] == url and not removed then
            removed = true
        else
            nextHistory[#nextHistory + 1] = history[i]
        end
    end

    if removed then
        booth.history = nextHistory
        MySQL.update.await(([[
            UPDATE `%s`
            SET history_json = ?, updated_at = NOW()
            WHERE id = ?
        ]]):format(TABLE_NAME), { EncodeHistory(nextHistory), id })
    end

    return removed
end

local function ValidatePlacementAgainstStations(idToIgnore, coords)
    local minSeparation = Config.Placement.MinSeparation or 1.2
    for id, booth in pairs(Locations) do
        if id ~= idToIgnore and booth.coords then
            local other = vector3(booth.coords.x, booth.coords.y, booth.coords.z)
            if #(other - coords) < minSeparation then
                return false
            end
        end
    end
    return true
end

local function BuildStationFromRow(row)
    local stationType = tostring(row.station_type or row.item or 'jukeboxone')
    local cfg = GetStationTypeConfig(stationType)
    local x = ToNum(row.x, 0.0)
    local y = ToNum(row.y, 0.0)
    local z = ToNum(row.z, 0.0)
    local h = ToNum(row.heading, 0.0)
    local volume = ToNum(row.volume, (cfg and cfg.DefaultVolume) or 0.2)
    local radius = math.floor(ToNum(row.radius, (cfg and cfg.DefaultRange) or 20))

    return {
        id = row.id,
        owner = row.citizenid,
        item = row.item,
        stationType = stationType,
        stationName = row.station_name,
        DefaultVolume = volume,
        radius = radius,
        coords = vector4(x, y, z, h),
        prop = {
            model = tostring(row.model or (cfg and cfg.DefaultProp) or 'prop_jukebox_02'),
            coords = vector4(x, y, z, h),
        },
        history = NormalizeHistory(DecodeHistory(row.history_json), stationType),
    }
end

local function LoadStations()
    Locations = {}
    IsPaused = {}

    local rows = MySQL.query.await(([[
        SELECT id, citizenid, item, station_type, station_name, model, x, y, z, heading, volume, radius, history_json
        FROM `%s`
    ]]):format(TABLE_NAME), {}) or {}

    for i = 1, #rows do
        local booth = BuildStationFromRow(rows[i])
        Locations[booth.id] = booth
        IsPaused[booth.id] = false
    end

    print(('[vkmusicplayers] Loaded %d stations from DB'):format(#rows))
    SyncAll()
end

MySQL.ready(function()
    local ok, err = pcall(LoadStations)
    if not ok then
        print(('[vkmusicplayers] Failed loading stations: %s'):format(tostring(err)))
    end
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source or player
    if src then
        SyncOne(src)
    end
end)

for stationType, cfg in pairs(Config.StationTypes) do
    local stationKey = stationType
    local itemName = cfg.Item

    if type(itemName) == 'string' and itemName ~= '' then
        QBCore.Functions.CreateUseableItem(itemName, function(source, item)
            local player = QBCore.Functions.GetPlayer(source)
            if not player then return end

            local usedItemName = itemName
            if type(item) == 'table' then
                usedItemName = item.name or item.item or itemName
            elseif type(item) == 'string' and item ~= '' then
                usedItemName = item
            end

            if usedItemName ~= itemName then
                return
            end

            TriggerClientEvent('vkmusicplayers:client:startPlacement', source, stationKey)
        end)
    end
end

lib.callback.register('vkmusicplayers:server:getHistory', function(_, id)
    id = tonumber(id)
    local booth = id and Locations[id] or nil
    if not booth then return {} end

    local out = {}
    for i = 1, #(booth.history or {}) do
        local url = booth.history[i]
        local meta = FetchYouTubeMeta(url)
        out[#out + 1] = {
            url = url,
            videoId = meta.videoId,
            title = meta.title,
            author = meta.author,
            thumbnail = meta.thumbnail,
        }
    end
    return out
end)

RegisterNetEvent('vkmusicplayers:server:addPlacedStation', function(data)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    local stationType = tostring((data and data.stationType) or '')
    local cfg = GetStationTypeConfig(stationType)
    if not cfg then
        Notify(src, L('notify_invalid_station_type'), 'error')
        return
    end

    if not player.Functions.RemoveItem(cfg.Item, 1) then
        Notify(src, L('notify_no_item'), 'error')
        return
    end

    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[cfg.Item], 'remove')

    local coords = data and data.coords or {}
    local x = ToNum(coords.x, 0.0)
    local y = ToNum(coords.y, 0.0)
    local z = ToNum(coords.z, 0.0)
    local heading = ToNum(coords.w, 0.0)
    local model = tostring((data and data.prop and data.prop.model) or cfg.DefaultProp)
    local stationName = Trim((data and data.stationName) or '')
    if stationName == '' then stationName = nil end
    if stationName then stationName = stationName:sub(1, Config.Placement.MaxNameLength or 32) end

    if not IsModelAllowed(stationType, model) then
        player.Functions.AddItem(cfg.Item, 1)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[cfg.Item], 'add')
        Notify(src, L('notify_invalid_model'), 'error')
        return
    end

    local pos = vector3(x, y, z)
    if not ValidatePlacementAgainstStations(nil, pos) then
        player.Functions.AddItem(cfg.Item, 1)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[cfg.Item], 'add')
        Notify(src, L('notify_invalid_placement'), 'error')
        return
    end

    local volume = Clamp(ToNum(cfg.DefaultVolume, 0.2), cfg.MinVolume or 0.05, cfg.MaxVolume or 1.0)
    local range = math.floor(Clamp(ToNum(cfg.DefaultRange, 20), cfg.MinRange or 5, cfg.MaxRange or 25))

    local insertId = MySQL.insert.await(([[
        INSERT INTO `%s` (citizenid, item, station_type, station_name, model, x, y, z, heading, volume, radius, history_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
    ]]):format(TABLE_NAME), {
        player.PlayerData.citizenid,
        cfg.Item,
        stationType,
        stationName,
        model,
        x,
        y,
        z,
        heading,
        volume,
        range,
        '[]'
    })

    if not insertId then
        player.Functions.AddItem(cfg.Item, 1)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[cfg.Item], 'add')
        Notify(src, L('notify_save_failed'), 'error')
        return
    end

    Locations[insertId] = {
        id = insertId,
        owner = player.PlayerData.citizenid,
        item = cfg.Item,
        stationType = stationType,
        stationName = stationName,
        DefaultVolume = volume,
        radius = range,
        coords = vector4(x, y, z, heading),
        prop = { model = model, coords = vector4(x, y, z, heading) },
        history = {},
    }
    IsPaused[insertId] = false

    SyncAll()
    Notify(src, L('notify_station_saved'), 'success')
end)

RegisterNetEvent('vkmusicplayers:server:removeStation', function(data)
    local src = source
    local id = ExtractId(data)
    if not id or not Locations[id] then
        Notify(src, L('notify_station_missing'), 'error')
        return
    end

    local canManage, player = PlayerCanManage(src, Locations[id])
    if not canManage or not player then
        Notify(src, L('notify_station_not_owner'), 'error')
        return
    end

    local booth = Locations[id]
    XS('Destroy', -1, LabelFor(id))
    MySQL.update.await(([[DELETE FROM `%s` WHERE id = ?]]):format(TABLE_NAME), { id })
    Locations[id] = nil
    IsPaused[id] = nil

    TriggerClientEvent('vkmusicplayers:client:removeSpawnedStation', -1, id)
    player.Functions.AddItem(booth.item, 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[booth.item], 'add')
    Notify(src, L('notify_station_removed'), 'success')
end)

RegisterNetEvent('vkmusicplayers:server:removeHistoryEntry', function(id, url)
    local src = source
    id = tonumber(id)
    url = Trim(url)

    if not id or url == '' or not Locations[id] then
        Notify(src, L('notify_history_missing'), 'error')
        return
    end

    local canManage = PlayerCanManage(src, Locations[id])
    if not canManage then
        Notify(src, L('notify_station_not_owner'), 'error')
        return
    end

    if RemoveHistoryUrl(id, url) then
        Notify(src, L('notify_history_removed'), 'success')
    else
        Notify(src, L('notify_history_missing'), 'error')
    end
end)

RegisterNetEvent('vkmusicplayers:server:playMusic', function(url, id)
    id = tonumber(id)
    url = Trim(url)
    if not id or url == '' then return end

    local booth = Locations[id]
    if not booth then return end

    local label = LabelFor(id)
    local pos = vector3(booth.coords.x, booth.coords.y, booth.coords.z)
    local volume = booth.DefaultVolume or 0.2
    local radius = booth.radius or 20

    XS('PlayUrlPos', -1, label, url, volume, pos)
    XS('Distance', -1, label, radius)
    XS(Config.Audio.VolumeExport or 'setVolume', -1, label, volume)

    if Config.History.Enabled then
        PushHistory(id, url)
    end

    IsPaused[id] = false
end)

RegisterNetEvent('vkmusicplayers:server:stopMusic', function(data)
    local id = ExtractId(data)
    if not id or not Locations[id] then return end
    XS('Destroy', -1, LabelFor(id))
    IsPaused[id] = false
end)

RegisterNetEvent('vkmusicplayers:server:pauseResume', function(data)
    local src = source
    local id = ExtractId(data)
    if not id or not Locations[id] then return end

    local label = LabelFor(id)
    if XS('TogglePause', -1, label) then
        IsPaused[id] = not IsPaused[id]
        return
    end

    local paused = IsPaused[id] == true
    if paused then
        if XS('Resume', -1, label) or XS('setPause', -1, label, false) then
            IsPaused[id] = false
            return
        end
    else
        if XS('Pause', -1, label) or XS('setPause', -1, label, true) then
            IsPaused[id] = true
            return
        end
    end

    Notify(src, L('notify_pause_unsupported'), 'error')
end)

RegisterNetEvent('vkmusicplayers:server:changeVolume', function(volume, id)
    local src = source
    id = tonumber(id)
    local booth = id and Locations[id] or nil
    if not booth then return end

    local cfg = GetStationTypeConfig(booth.stationType)
    local minVolume = (cfg and cfg.MinVolume) or 0.05
    local maxVolume = (cfg and cfg.MaxVolume) or 1.0
    volume = Clamp(ToNum(volume, booth.DefaultVolume or minVolume), minVolume, maxVolume)

    booth.DefaultVolume = volume
    XS(Config.Audio.VolumeExport or 'setVolume', -1, LabelFor(id), volume)
    MySQL.update.await(([[
        UPDATE `%s`
        SET volume = ?, updated_at = NOW()
        WHERE id = ?
    ]]):format(TABLE_NAME), { volume, id })

    TriggerClientEvent('vkmusicplayers:client:updateStationVolume', -1, id, volume)
    Notify(src, L('notify_volume_updated', math.floor((volume * 100) + 0.5)), 'success')
end)

RegisterNetEvent('vkmusicplayers:server:setRange', function(range, id)
    local src = source
    id = tonumber(id)
    local booth = id and Locations[id] or nil
    if not booth then
        Notify(src, L('notify_station_missing'), 'error')
        return
    end

    local cfg = GetStationTypeConfig(booth.stationType)
    range = math.floor(Clamp(ToNum(range, booth.radius or (cfg and cfg.DefaultRange) or 20), (cfg and cfg.MinRange) or 5, (cfg and cfg.MaxRange) or 25))

    booth.radius = range
    XS('Distance', -1, LabelFor(id), range)
    MySQL.update.await(([[
        UPDATE `%s`
        SET radius = ?, updated_at = NOW()
        WHERE id = ?
    ]]):format(TABLE_NAME), { range, id })

    TriggerClientEvent('vkmusicplayers:client:updateStationRange', -1, id, range)
    Notify(src, L('notify_range_updated', range), 'success')
end)

RegisterNetEvent('vkmusicplayers:server:renameStation', function(id, stationName)
    local src = source
    id = tonumber(id)
    local booth = id and Locations[id] or nil
    if not booth then
        Notify(src, L('notify_station_missing'), 'error')
        return
    end

    local canManage = PlayerCanManage(src, booth)
    if not canManage then
        Notify(src, L('notify_station_not_owner'), 'error')
        return
    end

    stationName = Trim(stationName)
    if stationName == '' then stationName = nil end
    if stationName then
        stationName = stationName:sub(1, Config.Placement.MaxNameLength or 32)
    end

    booth.stationName = stationName
    MySQL.update.await(([[
        UPDATE `%s`
        SET station_name = ?, updated_at = NOW()
        WHERE id = ?
    ]]):format(TABLE_NAME), { stationName, id })

    TriggerClientEvent('vkmusicplayers:client:updateStationName', -1, id, stationName)
end)

RegisterNetEvent('vkmusicplayers:server:requestSync', function()
    SyncOne(source)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Locations) do
        XS('Destroy', -1, LabelFor(id))
    end
end)
