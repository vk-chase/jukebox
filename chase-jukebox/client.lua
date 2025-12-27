-- =========================
-- QBCore Init
-- =========================
local QBCore = exports['qb-core']:GetCoreObject()
local _didInitialSync = false

-- =========================
-- State
-- =========================
local Locations = {}          -- map: id -> booth table
local Spawned = {}            -- map: id -> { obj = entity }
local PlacingInProgress = false
local placing, ghostProp, currentCoords, currentHeading, currentDist, zOffset = false, nil, nil, 0.0, 2.0, 0.0

-- =========================
-- Helpers
-- =========================
local function DrawTextTopCenter(text)
    SetTextFont(4); SetTextScale(0.45, 0.45); SetTextColour(255,255,255,255)
    SetTextOutline(); SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.02)
end

local function RequestStationSync()
    TriggerServerEvent("djbooth:server:requestSync")
end

local function RotationToDirection(rot)
    local z = math.rad(rot.z); local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function RaycastFromCamera(dist)
    local camRot = GetGameplayCamRot(2)
    local camPos = GetGameplayCamCoord()
    local dir = RotationToDirection(camRot)
    local dest = camPos + dir * dist
    local rayHandle = StartShapeTestRay(camPos.x,camPos.y,camPos.z, dest.x,dest.y,dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords = GetShapeTestResult(rayHandle)
    return hit == 1, endCoords
end

local function parseModel(modelField)
    if type(modelField) == "number" then
        return modelField
    elseif type(modelField) == "string" then
        local asNum = tonumber(modelField)
        if asNum then return asNum end
        return GetHashKey(modelField)
    end
    return 0
end

-- ===== Tagging & cleanup =====
local DECOR_KEY = "dj_station"

local function tagStationEntity(ent)
    if not DecorIsRegisteredAsType(DECOR_KEY, 2) then
        DecorRegister(DECOR_KEY, 2)
    end
    DecorSetBool(ent, DECOR_KEY, true)
    local ok, entity = pcall(function() return Entity(ent) end)
    if ok and entity and entity.state then
        entity.state:set(DECOR_KEY, true, true)
    end
end

local function isTaggedStation(ent)
    if not DoesEntityExist(ent) then return false end
    if DecorExistOn(ent, DECOR_KEY) and DecorGetBool(ent, DECOR_KEY) then return true end
    local ok, entity = pcall(function() return Entity(ent) end)
    if ok and entity and entity.state and entity.state[DECOR_KEY] then return true end
    return false
end

local function forEachObject(fn)
    local handle, obj = FindFirstObject()
    if handle == -1 then return end
    local ok = true
    repeat
        if DoesEntityExist(obj) then
            if fn(obj) then break end
        end
        ok, obj = FindNextObject(handle)
    until not ok
    EndFindObject(handle)
end

local function cleanupOrphanStations()
    forEachObject(function(obj)
        if isTaggedStation(obj) then
            DeleteObject(obj)
        end
    end)
end

-- =========================
-- Spawning
-- =========================
local function despawnAllStations()
    for _, data in pairs(Spawned) do
        if data.obj and DoesEntityExist(data.obj) then
            pcall(function() exports['qb-target']:RemoveTargetEntity(data.obj) end)
            DeleteObject(data.obj)
        end
    end
    Spawned = {}
end

local function spawnOneStation(booth)
    if not booth or not booth.id or not booth.prop or not booth.prop.coords then return end
    if Spawned[booth.id] and DoesEntityExist(Spawned[booth.id].obj) then return end

    local model = parseModel(booth.prop.model)
    if model == 0 then return end

    RequestModel(model); while not HasModelLoaded(model) do Wait(0) end
    local pos = booth.prop.coords
    local obj = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, true, true, false)
    if not obj or not DoesEntityExist(obj) then return end

    SetEntityAsMissionEntity(obj, true, true)
    SetEntityHeading(obj, pos.w or 0.0)
    FreezeEntityPosition(obj, true)
    tagStationEntity(obj)

    exports['qb-target']:AddTargetEntity(obj, {
        options = {
            {
                type  = "client",
                event = "djbooth:client:openBoothMenu",
                icon  = "fas fa-music",
                label = "Use Music Station",
                args  = { id = booth.id },
                id    = booth.id,
            },
        },
        distance = 2.0
    })

    Spawned[booth.id] = { obj = obj }
end

-- =========================
-- Placement Mode
-- =========================
RegisterNetEvent("djbooth:client:startPlacement", function(model)
    if PlacingInProgress then
        QBCore.Functions.Notify("Placement already in progress", "error")
        return
    end
    PlacingInProgress, placing = true, true
    currentHeading, currentDist, zOffset = GetEntityHeading(PlayerPedId()), 2.0, 0.0

    local mhash = parseModel(model)
    RequestModel(mhash); while not HasModelLoaded(mhash) do Wait(0) end

    if ghostProp and DoesEntityExist(ghostProp) then DeleteObject(ghostProp) end
    local base = GetEntityCoords(PlayerPedId()) + (GetEntityForwardVector(PlayerPedId()) * 1.5)
    ghostProp = CreateObjectNoOffset(mhash, base.x, base.y, base.z, false, false, false)
    if ghostProp and DoesEntityExist(ghostProp) then
        SetEntityAsMissionEntity(ghostProp, true, true)
        SetEntityVisible(ghostProp, true, false)
        SetEntityCollision(ghostProp, false, false)
        FreezeEntityPosition(ghostProp, true)
        SetEntityAlpha(ghostProp, 220, false)
        SetEntityDrawOutline(ghostProp, true)
        SetEntityDrawOutlineColor(0, 255, 0, 255)
        SetEntityNoCollisionEntity(ghostProp, PlayerPedId(), true)
    end

    CreateThread(function()
        while placing do
            local playerPed = PlayerPedId()
            local playerPos = GetEntityCoords(playerPed)
            local forward = GetEntityForwardVector(playerPed)
            local distance = currentDist or 1.5 -- distance in front of player

            -- calculate placement coords in front of player
            local localCoords = playerPos + forward * distance

            -- get ground Z
            local ok, gz = GetGroundZFor_3dCoord(localCoords.x, localCoords.y, localCoords.z + 5.0, true)
            if ok and gz > 0.0 then
                localCoords = vector3(localCoords.x, localCoords.y, gz + zOffset)
            else
                localCoords = localCoords + vector3(0, 0, zOffset)
            end

            -- move ghost prop
            if ghostProp and DoesEntityExist(ghostProp) then
                SetEntityCoordsNoOffset(ghostProp, localCoords.x, localCoords.y, localCoords.z, true, true, true)
                SetEntityHeading(ghostProp, currentHeading)
            end

            -- rotation controls
            if IsControlPressed(0, 175) then currentHeading = (currentHeading + 1.0) % 360.0 end -- right arrow
            if IsControlPressed(0, 174) then currentHeading = (currentHeading - 1.0) % 360.0 end -- left arrow

            -- Z offset controls
            if IsControlPressed(0, 172) then zOffset = zOffset + 0.02 end -- up arrow
            if IsControlPressed(0, 173) then zOffset = zOffset - 0.02 end -- down arrow

            -- scroll distance controls
            if IsControlJustPressed(0, 241) then currentDist = math.max(0.5, currentDist - 0.2) end -- scroll up
            if IsControlJustPressed(0, 242) then currentDist = math.min(10.0, currentDist + 0.2) end -- scroll down

            -- validate placement
            local validPlacement = true
            for _, data in pairs(Spawned) do
                if data.obj and DoesEntityExist(data.obj) and #(GetEntityCoords(data.obj) - localCoords) < 1.0 then
                    validPlacement = false
                    break
                end
            end

            if ghostProp and DoesEntityExist(ghostProp) then
                SetEntityDrawOutlineColor(validPlacement and 0 or 255, validPlacement and 255 or 0, 0, 255)
            end

            -- place object
            if IsControlJustPressed(0, 191) then -- Enter
                if validPlacement then
                    TriggerServerEvent("djbooth:server:addPlacedBooth", {
                        job = "public",
                        enableBooth = true,
                        DefaultVolume = 0.2,
                        radius = 30,
                        coords = vector4(localCoords.x, localCoords.y, localCoords.z, currentHeading),
                        prop = { model = mhash, coords = vector4(localCoords.x, localCoords.y, localCoords.z, currentHeading) }
                    })
                    placing = false
                else
                    QBCore.Functions.Notify("Invalid placement", "error")
                end
            end

            -- cancel placement
            if IsControlJustPressed(0, 177) then -- Backspace
                if ghostProp and DoesEntityExist(ghostProp) then
                    SetEntityDrawOutline(ghostProp, false)
                    DeleteObject(ghostProp)
                end
                ghostProp, placing = nil, false
            end

            DrawTextTopCenter("~g~Arrows~w~ Rotate/Up/Down | ~g~Scroll~w~ Distance | ~g~Enter~w~ Place | ~g~Backspace~w~ Cancel")
            Wait(0)
        end

        -- cleanup ghost
        if ghostProp and DoesEntityExist(ghostProp) then
            SetEntityDrawOutline(ghostProp, false)
            DeleteObject(ghostProp)
        end
        ghostProp, PlacingInProgress = nil, false
    end)

end)

-- =========================
-- Sync From Server
-- =========================
RegisterNetEvent("djbooth:client:syncLocations", function(serverList)
    local newMap = {}
    for _, booth in ipairs(serverList or {}) do
        if booth and booth.id then
            newMap[booth.id] = booth
        end
    end
    Locations = newMap
    despawnAllStations()
    for _, booth in pairs(Locations) do
        spawnOneStation(booth)
    end
    _didInitialSync = true
end)

-- =========================
-- Menus (ox_lib)
-- =========================
local function extractId(payload)
    if type(payload) == "table" then
        if payload.id then return payload.id end
        if payload.args and payload.args.id then return payload.args.id end
    end
    local n = tonumber(payload)
    if n then return n end
    return nil
end

RegisterNetEvent("djbooth:client:openBoothMenu", function(data)
    local id = extractId(data)
    if not id or not Locations[id] then return end

    local menu = {
        {
            title = "Play Song",
            description = "Enter a YouTube URL",
            icon = "fab fa-youtube",
            onSelect = function() TriggerEvent("djbooth:client:musicMenu", { id = id }) end
        },
        {
            title = "History",
            description = "Recent songs at this station",
            icon = "fas fa-clock-rotate-left",
            onSelect = function() TriggerEvent("djbooth:client:history", { id = id }) end
        },
        {
            title = "Stop Music",
            icon = "fas fa-stop",
            onSelect = function() TriggerServerEvent("djbooth:server:stopMusic", { id = id }) end
        },
        {
            title = "Change Volume",
            description = "1–100",
            icon = "fas fa-volume-up",
            onSelect = function() TriggerEvent("djbooth:client:changeVolume", { id = id }) end
        },
        {
            title = "Set Range",
            description = "Max 25 units",
            icon = "fas fa-ruler-combined",
            onSelect = function()
                local dialog = lib.inputDialog("Set Range", { { type = "input", label = "1-25", required = true } })
                if dialog then
                    local range = tonumber(dialog[1]) or 25
                    range = math.max(1, math.min(25, range))
                    TriggerServerEvent("djbooth:server:setRange", range, id)
                end
            end
        },
        -- blank separator
        { title = " ", disabled = true },
        {
            title = "Pickup / Remove",
            icon = "fas fa-trash",
            description = "Remove this music station",
            onSelect = function()
                TriggerServerEvent("djbooth:server:removeBooth", { id = id })
            end
        }
    }

    lib.registerContext({ id = "djbooth_menu_"..id, title = "MUSIC STATION", options = menu })
    lib.showContext("djbooth_menu_"..id)
end)



RegisterNetEvent("djbooth:client:musicMenu", function(data)
    local id = extractId(data) or data.id
    if not id then return end
    local dialog = lib.inputDialog("Play Song", { { type = "input", label = "YouTube URL", required = true } })
    if not dialog then return end
    local url = dialog[1]
    if not url:find("youtu") then url = "https://www.youtube.com/watch?v="..url end
    TriggerServerEvent("djbooth:server:playMusic", url, id)
end)

RegisterNetEvent("djbooth:client:history", function(data)
    local id = extractId(data) or data.id
    if not id then return end
    local list = lib.callback.await('djbooth:songInfo', false, id) or {}

    local opts = {}
    for i = #list, 1, -1 do
        local url = list[i]
        local vid = string.sub(url, -11)
        local thumb = "https://img.youtube.com/vi/"..vid.."/mqdefault.jpg"
        opts[#opts+1] = {
            title = url,
            image = thumb,
            onSelect = function()
                TriggerServerEvent("djbooth:server:playMusic", url, id)
            end
        }
    end

    if #opts == 0 then
        opts[#opts+1] = { title = "No history yet", disabled = true }
    end

    local hid = "djbooth_history_"..id
    lib.registerContext({ id = hid, title = "Song History", options = opts })
    lib.showContext(hid)
end)

RegisterNetEvent("djbooth:client:changeVolume", function(data)
    local id = extractId(data) or data.id
    if not id then return end
    local dialog = lib.inputDialog("Set Volume", { { type = "input", label = "1-100", required = true } })
    if not dialog then return end
    local vol = tonumber(dialog[1]) or 50
    vol = math.max(1, math.min(100, vol))
    TriggerServerEvent("djbooth:server:changeVolume", vol/100, id)
end)

-- =========================
-- Startup & Cleanup hooks
-- =========================
CreateThread(function()
    Wait(200)
    cleanupOrphanStations()
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end
    if ghostProp and DoesEntityExist(ghostProp) then
        SetEntityDrawOutline(ghostProp, false)
        DeleteObject(ghostProp)
    end
    despawnAllStations()
end)

-- initial pull on client start
CreateThread(function()
    Wait(600)
    RequestStationSync()
end)

-- hard sync on character load
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    _didInitialSync = false
    CreateThread(function()
        Wait(500)
        despawnAllStations()
        cleanupOrphanStations()
        RequestStationSync()
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    _didInitialSync = false
    despawnAllStations()
end)

-- fallback for non-QBCore respawns
AddEventHandler('playerSpawned', function()
    if not _didInitialSync then
        SetTimeout(800, RequestStationSync)
    end
end)

RegisterNetEvent("djbooth:client:removeSpawnedBooth", function(id)
    local data = Spawned[id]
    if data and data.obj and DoesEntityExist(data.obj) then
        pcall(function() exports['qb-target']:RemoveTargetEntity(data.obj) end)
        DeleteObject(data.obj)
    end
    Spawned[id] = nil
end)
