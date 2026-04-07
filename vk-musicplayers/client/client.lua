local QBCore = exports['qb-core']:GetCoreObject()
local VKMusicPlayers = rawget(_G, 'VKMusicPlayers') or {}
_G.VKMusicPlayers = VKMusicPlayers

local Locations = {}
local Spawned = {}
local InitialSyncComplete = false
local DECOR_KEY = 'vk_musicplayer'

local Placement = {
    active = false,
    stationType = nil,
    stationCfg = nil,
    model = nil,
    modelValue = nil,
    modelGroundOffset = 0.0,
    ghost = nil,
    heading = 0.0,
    distance = 2.0,
    zOffset = 0.0,
    planarOffsetX = 0.0,
    planarOffsetY = 0.0,
    startPlayerCoords = nil,
    anchorCoords = nil,
    targetCoords = nil,
    moveBasisYaw = 0.0,
    lastRaycastAt = 0,
    lastValidityAt = 0,
    lastPromptAt = 0,
    lastMoveAt = 0,
    lastDistanceCheckAt = 0,
    cachedCoords = nil,
    cachedValid = false,
    cachedReason = nil,
    promptVisible = false,
}

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
        print(('[vkmusicplayers][client] %s'):format(msg))
    end
end

local function Notify(msg, msgType)
    QBCore.Functions.Notify(msg, msgType or 'primary')
end

local function RequestStationSync()
    TriggerServerEvent('vkmusicplayers:server:requestSync')
end

local function GetStationConfig(stationType)
    return Config.StationTypes[stationType or '']
end

local function GetStationLabel(booth)
    if booth and booth.stationName and booth.stationName ~= '' then
        return booth.stationName
    end

    local cfg = booth and booth.stationType and GetStationConfig(booth.stationType) or nil
    return (cfg and cfg.Label) or L('menu_main_title')
end

local function ParseModel(modelField)
    if type(modelField) == 'number' then
        return modelField
    elseif type(modelField) == 'string' then
        local numeric = tonumber(modelField)
        if numeric then
            return numeric
        end
        return GetHashKey(modelField)
    end
    return 0
end

local function ExtractId(payload)
    if type(payload) == 'table' then
        if payload.id then return tonumber(payload.id) end
        if payload.args and payload.args.id then return tonumber(payload.args.id) end
    end
    return tonumber(payload)
end

local function RotationToDirection(rot)
    local rz = math.rad(rot.z)
    local rx = math.rad(rot.x)
    local cosX = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * cosX, math.cos(rz) * cosX, math.sin(rx))
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function LerpVector3(a, b, t)
    return vector3(Lerp(a.x, b.x, t), Lerp(a.y, b.y, t), Lerp(a.z, b.z, t))
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end


local function GetModelGroundOffset(model)
    if not model or model == 0 then
        return 0.0
    end

    local minDim, _ = GetModelDimensions(model)
    if not minDim then
        return 0.0
    end

    return -minDim.z
end

local function SnapCoordsToGroundForModel(model, coords)
    if not coords then return nil end

    local probeHeights = { 8.0, 4.0, 1.5 }
    local groundZ = nil

    for i = 1, #probeHeights do
        local ok, gz = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + probeHeights[i], true)
        if ok then
            groundZ = gz
            break
        end
    end

    if not groundZ then
        groundZ = coords.z
    end

    local modelOffset = GetModelGroundOffset(model)
    return vector3(coords.x, coords.y, groundZ + modelOffset)
end

local function EnsureDecorRegistered()
    if not DecorIsRegisteredAsType(DECOR_KEY, 2) then
        DecorRegister(DECOR_KEY, 2)
    end
end

local function TagStationEntity(ent)
    EnsureDecorRegistered()
    DecorSetBool(ent, DECOR_KEY, true)

    local ok, entity = pcall(function()
        return Entity(ent)
    end)

    if ok and entity and entity.state then
        entity.state:set(DECOR_KEY, true, true)
    end
end

local function IsTaggedStation(ent)
    if not DoesEntityExist(ent) then return false end
    if DecorExistOn(ent, DECOR_KEY) and DecorGetBool(ent, DECOR_KEY) then return true end

    local ok, entity = pcall(function()
        return Entity(ent)
    end)

    return ok and entity and entity.state and entity.state[DECOR_KEY] == true
end

local function ForEachObject(fn)
    local handle, obj = FindFirstObject()
    if handle == -1 then return end

    local success = true
    repeat
        if DoesEntityExist(obj) and fn(obj) then
            break
        end
        success, obj = FindNextObject(handle)
    until not success

    EndFindObject(handle)
end

local function CleanupOrphanStations()
    ForEachObject(function(obj)
        if IsTaggedStation(obj) then
            DeleteObject(obj)
        end
        return false
    end)
end

local function RemoveTargetEntity(entity)
    pcall(function()
        exports['qb-target']:RemoveTargetEntity(entity)
    end)
end

local function DespawnAllStations()
    for _, data in pairs(Spawned) do
        if data.obj and DoesEntityExist(data.obj) then
            RemoveTargetEntity(data.obj)
            DeleteObject(data.obj)
        end
    end
    Spawned = {}
end

local function LoadModel(model)
    local timeoutAt = GetGameTimer() + 5000
    RequestModel(model)
    while not HasModelLoaded(model) do
        if GetGameTimer() > timeoutAt then
            return false
        end
        Wait(0)
    end
    return true
end

local function AddTargetToStation(obj, booth)
    local cfg = GetStationConfig(booth.stationType)
    exports['qb-target']:AddTargetEntity(obj, {
        options = {
            {
                type = 'client',
                event = 'vkmusicplayers:client:openMenu',
                icon = Config.Target.Icon,
                label = (cfg and cfg.TargetLabel) or L('target_use'),
                args = { id = booth.id },
                id = booth.id,
            },
        },
        distance = Config.Target.Distance,
    })
end

local function SpawnOneStation(booth)
    if not booth or not booth.id or not booth.prop or not booth.prop.coords then return end
    if Spawned[booth.id] and DoesEntityExist(Spawned[booth.id].obj) then return end

    local model = ParseModel(booth.prop.model)
    if model == 0 then return end
    if not LoadModel(model) then return end

    local pos = booth.prop.coords
    local obj = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, true, true, false)
    if not obj or not DoesEntityExist(obj) then return end

    SetEntityAsMissionEntity(obj, true, true)
    SetEntityHeading(obj, pos.w or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    TagStationEntity(obj)
    AddTargetToStation(obj, booth)

    Spawned[booth.id] = { obj = obj }
    SetModelAsNoLongerNeeded(model)
end

local function ComputeRaycastPlacement(distance)
    local playerPed = PlayerPedId()
    local camPos = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local dir = RotationToDirection(camRot)
    local traceDistance = math.max(distance or 1.5, Config.Placement.RaycastDistance)
    local dest = camPos + (dir * traceDistance)
    local ray = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, playerPed, 0)
    local _, hit, endCoords = GetShapeTestResult(ray)

    local target = camPos + (dir * (distance or 1.5))
    if hit == 1 then
        local fromPlayer = #(GetEntityCoords(playerPed) - endCoords)
        if fromPlayer <= (Config.Placement.MaxDistance + 4.0) then
            target = endCoords
        end
    end

    local playerPos = GetEntityCoords(playerPed)
    local offset = target - playerPos
    local planar = vector3(offset.x, offset.y, 0.0)
    local planarLength = #(planar)

    if planarLength > 0.001 then
        local clampedDistance = Clamp(planarLength, Config.Placement.MinDistance, Config.Placement.MaxDistance)
        local dir2d = planar / planarLength
        target = vector3(playerPos.x + (dir2d.x * clampedDistance), playerPos.y + (dir2d.y * clampedDistance), target.z)
    else
        local fallback = GetEntityForwardVector(playerPed)
        local clampedDistance = Clamp(distance or 1.5, Config.Placement.MinDistance, Config.Placement.MaxDistance)
        target = vector3(playerPos.x + (fallback.x * clampedDistance), playerPos.y + (fallback.y * clampedDistance), target.z)
    end

    local ok, groundZ = GetGroundZFor_3dCoord(target.x, target.y, target.z + 5.0, true)
    if ok then
        target = vector3(target.x, target.y, groundZ)
    else
        target = vector3(target.x, target.y, playerPos.z - 1.0)
    end

    return vector3(target.x, target.y, target.z)
end

local function GetPlacementBasisVectors()
    local yaw = Placement.moveBasisYaw or math.rad(GetEntityHeading(PlayerPedId()))
    local forward = vector3(-math.sin(yaw), math.cos(yaw), 0.0)
    local right = vector3(forward.y, -forward.x, 0.0)
    return forward, right
end

local function ApplyPlacementOffsets(baseCoords)
    if not baseCoords then return nil end

    local forward, right = GetPlacementBasisVectors()

    local coords = baseCoords
    if Placement.planarOffsetY ~= 0.0 then
        coords = coords + (forward * Placement.planarOffsetY)
    end
    if Placement.planarOffsetX ~= 0.0 then
        coords = coords + (right * Placement.planarOffsetX)
    end

    return vector3(coords.x, coords.y, coords.z + Placement.zOffset)
end

local function RebuildPlacementTarget()
    if not Placement.anchorCoords then return nil end
    Placement.targetCoords = ApplyPlacementOffsets(Placement.anchorCoords)
    if not Placement.cachedCoords then
        Placement.cachedCoords = Placement.targetCoords
    end
    return Placement.targetCoords
end

local function StepPlacementOffset(deltaX, deltaY)
    local nextX = Placement.planarOffsetX + deltaX
    local nextY = Placement.planarOffsetY + deltaY

    local baseCoords = Placement.anchorCoords
    if not baseCoords then return end

    local forward, right = GetPlacementBasisVectors()
    local previewCoords = baseCoords + (forward * nextY) + (right * nextX)
    local playerPos = GetEntityCoords(PlayerPedId())
    local planarDistance = #(vector3(previewCoords.x - playerPos.x, previewCoords.y - playerPos.y, 0.0))

    if planarDistance <= (Config.Placement.MaxDistance + (Config.Placement.OffsetSlack or 1.5)) then
        Placement.planarOffsetX = nextX
        Placement.planarOffsetY = nextY
        RebuildPlacementTarget()
    end
end

local function ValidatePlacement(coords)
    if not coords then
        return false, 'missing_coords'
    end

    for id, data in pairs(Spawned) do
        if data.obj and DoesEntityExist(data.obj) then
            local existingCoords = GetEntityCoords(data.obj)
            if #(existingCoords - coords) < Config.Placement.MinSeparation then
                return false, ('too_close_%s'):format(id)
            end
        end
    end

    return true, nil
end

local function HidePlacementText()
    if Placement.promptVisible then
        lib.hideTextUI()
        Placement.promptVisible = false
    end
end

local function ShowPlacementText()
    if not Config.Placement.ControlHints then return end
    if not Placement.promptVisible then
        lib.showTextUI(L('placement_help'), { position = 'top-center' })
        Placement.promptVisible = true
    end
end

local function DestroyGhost()
    if Placement.ghost and DoesEntityExist(Placement.ghost) then
        SetEntityDrawOutline(Placement.ghost, false)
        DeleteObject(Placement.ghost)
    end
    Placement.ghost = nil
end

local function EndPlacement()
    HidePlacementText()
    DestroyGhost()
    Placement.active = false
    Placement.stationType = nil
    Placement.stationCfg = nil
    Placement.model = nil
    Placement.modelValue = nil
    Placement.modelGroundOffset = 0.0
    Placement.planarOffsetX = 0.0
    Placement.planarOffsetY = 0.0
    Placement.startPlayerCoords = nil
    Placement.anchorCoords = nil
    Placement.targetCoords = nil
    Placement.moveBasisYaw = 0.0
    Placement.cachedCoords = nil
    Placement.cachedValid = false
    Placement.cachedReason = nil
    Placement.lastMoveAt = 0
    Placement.lastDistanceCheckAt = 0
end

local function FinalizePlacement(coords)
    if not coords or not Placement.stationType or not Placement.stationCfg then
        Notify(L('notify_invalid_placement'), 'error')
        return
    end

    local stationName = nil
    if Config.Features.AllowStationRename then
        local response = lib.inputDialog(L('input_name_title'), {
            {
                type = 'input',
                label = L('input_name_label'),
                description = L('input_name_desc'),
                required = false,
                max = Config.Placement.MaxNameLength,
            }
        })

        if response and response[1] and response[1] ~= '' then
            stationName = tostring(response[1]):sub(1, Config.Placement.MaxNameLength)
        end
    end

    TriggerServerEvent('vkmusicplayers:server:addPlacedStation', {
        stationType = Placement.stationType,
        stationName = stationName,
        coords = vector4(coords.x, coords.y, coords.z, Placement.heading),
        prop = {
            model = Placement.modelValue or Placement.model,
            coords = vector4(coords.x, coords.y, coords.z, Placement.heading),
        },
    })

    EndPlacement()
end

local function PlacementTick()
    CreateThread(function()
        while Placement.active do
            local now = GetGameTimer()

            local shiftHeld = IsControlPressed(0, Config.Placement.VerticalModifierControl or 21)
            local moveStep = Config.Placement.MoveStep or 0.08
            local moveRepeat = Config.Placement.MoveRepeatInterval or 35
            local canMove = (now - Placement.lastMoveAt) >= moveRepeat

            if IsControlJustPressed(0, 241) then
                if shiftHeld then
                    Placement.zOffset = Clamp(Placement.zOffset + Config.Placement.HeightStep, Config.Placement.MinHeightOffset, Config.Placement.MaxHeightOffset)
                    RebuildPlacementTarget()
                else
                    Placement.heading = (Placement.heading + Config.Placement.RotationStep) % 360.0
                end
            end
            if IsControlJustPressed(0, 242) then
                if shiftHeld then
                    Placement.zOffset = Clamp(Placement.zOffset - Config.Placement.HeightStep, Config.Placement.MinHeightOffset, Config.Placement.MaxHeightOffset)
                    RebuildPlacementTarget()
                else
                    Placement.heading = (Placement.heading - Config.Placement.RotationStep) % 360.0
                end
            end

            if canMove then
                local moved = false

                if IsControlPressed(0, 172) then
                    StepPlacementOffset(0.0, moveStep)
                    moved = true
                end
                if IsControlPressed(0, 173) then
                    StepPlacementOffset(0.0, -moveStep)
                    moved = true
                end
                if IsControlPressed(0, 174) then
                    StepPlacementOffset(-moveStep, 0.0)
                    moved = true
                end
                if IsControlPressed(0, 175) then
                    StepPlacementOffset(moveStep, 0.0)
                    moved = true
                end

                if moved then
                    Placement.lastMoveAt = now
                end
            end

            if Placement.targetCoords then
                if Placement.cachedCoords then
                    Placement.cachedCoords = LerpVector3(Placement.cachedCoords, Placement.targetCoords, Config.Placement.Smoothing)
                else
                    Placement.cachedCoords = Placement.targetCoords
                end
            end

            if now - Placement.lastDistanceCheckAt >= (Config.Placement.DistanceCheckInterval or 200) then
                Placement.lastDistanceCheckAt = now
                if Placement.startPlayerCoords then
                    local travelDistance = #(GetEntityCoords(PlayerPedId()) - Placement.startPlayerCoords)
                    if travelDistance > (Config.Placement.MaxPlacementTravel or 20.0) then
                        Notify(L('notify_placement_too_far'), 'error')
                        EndPlacement()
                        break
                    end
                end
            end


            if Placement.ghost and DoesEntityExist(Placement.ghost) and Placement.cachedCoords then
                SetEntityCoordsNoOffset(Placement.ghost, Placement.cachedCoords.x, Placement.cachedCoords.y, Placement.cachedCoords.z, false, false, false)
                SetEntityHeading(Placement.ghost, Placement.heading)
            end

            if now - Placement.lastValidityAt >= Config.Placement.ValidityInterval then
                Placement.lastValidityAt = now
                Placement.cachedValid, Placement.cachedReason = ValidatePlacement(Placement.cachedCoords)
                if Placement.ghost and DoesEntityExist(Placement.ghost) then
                    if Placement.cachedValid then
                        SetEntityDrawOutlineColor(0, 255, 0, 255)
                    else
                        SetEntityDrawOutlineColor(255, 0, 0, 255)
                    end
                end
            end

            if now - Placement.lastPromptAt >= Config.Placement.PromptInterval then
                Placement.lastPromptAt = now
                ShowPlacementText()
            end

            if IsControlJustPressed(0, 191) then
                if Placement.cachedValid then
                    FinalizePlacement(Placement.cachedCoords)
                else
                    Notify(L('notify_invalid_placement'), 'error')
                end
            end

            if IsControlJustPressed(0, 177) then
                EndPlacement()
                break
            end

            Wait(0)
        end
    end)
end

local function BeginPlacement(stationType, chosenModel)
    if Placement.active then
        Notify(L('notify_already_placing'), 'error')
        return
    end

    local stationCfg = GetStationConfig(stationType)
    if not stationCfg then
        Notify(L('notify_invalid_station_type'), 'error')
        return
    end

    local modelHash = ParseModel(chosenModel or stationCfg.DefaultProp)
    if modelHash == 0 then
        Notify(L('notify_invalid_model'), 'error')
        return
    end

    if not LoadModel(modelHash) then
        Notify(L('notify_model_load_failed'), 'error')
        return
    end

    local startPlayerCoords = GetEntityCoords(PlayerPedId())
    local startAnchor = ComputeRaycastPlacement(Clamp(Config.Placement.DefaultDistance or 2.0, Config.Placement.MinDistance, Config.Placement.MaxDistance))
    startAnchor = SnapCoordsToGroundForModel(modelHash, startAnchor)
    if not startAnchor then
        Notify(L('notify_invalid_placement'), 'error')
        return
    end

    Placement.active = true
    Placement.stationType = stationType
    Placement.stationCfg = stationCfg
    Placement.model = modelHash
    Placement.modelValue = chosenModel or stationCfg.DefaultProp
    Placement.modelGroundOffset = GetModelGroundOffset(modelHash)
    Placement.heading = GetEntityHeading(PlayerPedId())
    Placement.distance = Clamp(Config.Placement.DefaultDistance or 2.0, Config.Placement.MinDistance, Config.Placement.MaxDistance)
    Placement.zOffset = 0.0
    Placement.planarOffsetX = 0.0
    Placement.planarOffsetY = 0.0
    Placement.startPlayerCoords = startPlayerCoords
    Placement.anchorCoords = startAnchor
    Placement.moveBasisYaw = math.rad(GetEntityHeading(PlayerPedId()))
    Placement.lastRaycastAt = 0
    Placement.lastValidityAt = 0
    Placement.lastPromptAt = 0
    Placement.lastMoveAt = 0
    Placement.lastDistanceCheckAt = 0
    Placement.targetCoords = ApplyPlacementOffsets(Placement.anchorCoords)
    Placement.cachedCoords = Placement.targetCoords

    Placement.ghost = CreateObjectNoOffset(modelHash, Placement.cachedCoords.x, Placement.cachedCoords.y, Placement.cachedCoords.z, false, false, false)
    if Placement.ghost and DoesEntityExist(Placement.ghost) then
        SetEntityAsMissionEntity(Placement.ghost, true, true)
        SetEntityVisible(Placement.ghost, true, false)
        SetEntityCollision(Placement.ghost, false, false)
        FreezeEntityPosition(Placement.ghost, true)
        SetEntityAlpha(Placement.ghost, Config.Placement.GhostAlpha, false)
        SetEntityDrawOutline(Placement.ghost, true)
        SetEntityDrawOutlineColor(0, 255, 0, 255)
        SetEntityNoCollisionEntity(Placement.ghost, PlayerPedId(), true)
    end

    PlacementTick()
    SetModelAsNoLongerNeeded(modelHash)
end

local function OpenPlacementSelector(stationType)
    local stationCfg = GetStationConfig(stationType)
    if not stationCfg then
        Notify(L('notify_invalid_station_type'), 'error')
        return
    end

    local allowed = stationCfg.AllowedProps or {}
    if #allowed <= 1 then
        local fallback = allowed[1] and allowed[1].model or stationCfg.DefaultProp
        BeginPlacement(stationType, fallback)
        return
    end

    local options = {}
    for i = 1, #allowed do
        local entry = allowed[i]
        options[#options + 1] = {
            title = entry.label or stationCfg.Label,
            description = entry.model,
            icon = 'fas fa-cube',
            onSelect = function()
                BeginPlacement(stationType, entry.model)
            end,
        }
    end

    lib.registerContext({
        id = ('vkmusicplayers_prop_select_%s'):format(stationType),
        title = L('menu_select_prop'),
        options = options,
    })

    lib.showContext(('vkmusicplayers_prop_select_%s'):format(stationType))
end

RegisterNetEvent('vkmusicplayers:client:startPlacement', function(stationType)
    OpenPlacementSelector(stationType)
end)

RegisterNetEvent('vkmusicplayers:client:syncStations', function(serverList)
    local map = {}
    for _, booth in ipairs(serverList or {}) do
        if booth and booth.id then
            map[booth.id] = booth
        end
    end

    Locations = map
    DespawnAllStations()

    for _, booth in pairs(Locations) do
        SpawnOneStation(booth)
    end

    InitialSyncComplete = true
end)

RegisterNetEvent('vkmusicplayers:client:openMenu', function(data)
    local id = ExtractId(data)
    if not id or not Locations[id] then return end

    local booth = Locations[id]
    local stationCfg = GetStationConfig(booth.stationType) or {}
    local currentVolume = math.floor(((booth.defaultVolume or booth.DefaultVolume or stationCfg.DefaultVolume or 0.2) * 100) + 0.5)
    local currentRange = math.floor(tonumber(booth.radius) or tonumber(stationCfg.DefaultRange) or 20)

    local options = {
        {
            title = L('menu_play'),
            description = L('menu_play_desc'),
            icon = 'fab fa-youtube',
            onSelect = function()
                TriggerEvent('vkmusicplayers:client:openPlayDialog', { id = id })
            end,
        },
    }

    if Config.Features.AllowHistory and Config.History.Enabled then
        options[#options + 1] = {
            title = L('menu_history'),
            description = L('menu_history_desc'),
            icon = 'fas fa-clock-rotate-left',
            onSelect = function()
                TriggerEvent('vkmusicplayers:client:openHistory', { id = id })
            end,
        }
    end

    if Config.Features.AllowPause then
        options[#options + 1] = {
            title = L('menu_pause'),
            description = L('menu_pause_desc'),
            icon = 'fas fa-pause',
            onSelect = function()
                TriggerServerEvent('vkmusicplayers:server:pauseResume', { id = id })
            end,
        }
    end

    options[#options + 1] = {
        title = L('menu_stop'),
        description = L('menu_stop_desc'),
        icon = 'fas fa-stop',
        onSelect = function()
            TriggerServerEvent('vkmusicplayers:server:stopMusic', { id = id })
        end,
    }

    if Config.Features.AllowVolumeChange then
        options[#options + 1] = {
            title = L('menu_volume'),
            description = L('menu_volume_desc', currentVolume),
            icon = 'fas fa-volume-up',
            onSelect = function()
                TriggerEvent('vkmusicplayers:client:changeVolume', { id = id })
            end,
        }
    end

    if Config.Features.AllowRangeChange then
        options[#options + 1] = {
            title = L('menu_range'),
            description = L('menu_range_desc', currentRange, stationCfg.MaxRange or currentRange),
            icon = 'fas fa-ruler-combined',
            onSelect = function()
                TriggerEvent('vkmusicplayers:client:changeRange', { id = id })
            end,
        }
    end

    if Config.Features.AllowStationRename then
        options[#options + 1] = {
            title = L('menu_rename'),
            description = L('menu_rename_desc'),
            icon = 'fas fa-signature',
            onSelect = function()
                TriggerEvent('vkmusicplayers:client:renameStation', { id = id })
            end,
        }
    end

    options[#options + 1] = { title = ' ', disabled = true }
    options[#options + 1] = {
        title = L('menu_pickup'),
        description = L('menu_pickup_desc'),
        icon = 'fas fa-trash',
        onSelect = function()
            TriggerServerEvent('vkmusicplayers:server:removeStation', { id = id })
        end,
    }

    local menuId = ('vkmusicplayers_menu_%s'):format(id)
    lib.registerContext({
        id = menuId,
        title = GetStationLabel(booth),
        options = options,
    })

    lib.showContext(menuId)
end)

RegisterNetEvent('vkmusicplayers:client:openPlayDialog', function(data)
    local id = ExtractId(data)
    if not id then return end

    local response = lib.inputDialog(L('input_url_title'), {
        { type = 'input', label = L('input_url_label'), required = true }
    })

    if not response or not response[1] then return end

    local value = tostring(response[1]):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then
        Notify(L('notify_invalid_url'), 'error')
        return
    end

    if not value:find('http', 1, true) and not value:find('youtu', 1, true) then
        value = 'https://www.youtube.com/watch?v=' .. value
    end

    TriggerServerEvent('vkmusicplayers:server:playMusic', value, id)
end)

RegisterNetEvent('vkmusicplayers:client:openHistory', function(data)
    local id = ExtractId(data)
    if not id then return end

    local list = lib.callback.await('vkmusicplayers:server:getHistory', false, id) or {}
    local options = {}

    for i = 1, #list do
        local entry = list[i]
        local url = type(entry) == 'table' and entry.url or entry
        local title = type(entry) == 'table' and entry.title or 'YouTube Video'
        local author = type(entry) == 'table' and entry.author or 'Unknown Channel'
        local thumb = type(entry) == 'table' and entry.thumbnail or nil

        options[#options + 1] = {
            title = title ~= '' and title or 'YouTube Video',
            description = author ~= '' and ('Channel: ' .. author) or 'Unknown Channel',
            image = thumb and thumb ~= '' and thumb or nil,
            icon = thumb and thumb ~= '' and nil or 'fab fa-youtube',
            metadata = {
                { label = 'Channel', value = author ~= '' and author or 'Unknown Channel' }
            },
            onSelect = function()
                local actionId = ('vkmusicplayers_history_action_%s_%s'):format(id, i)
                local actionOptions = {
                    {
                        title = L('menu_history_play'),
                        icon = 'fa-solid fa-play',
                        image = thumb and thumb ~= '' and thumb or nil,
                        onSelect = function()
                            TriggerServerEvent('vkmusicplayers:server:playMusic', url, id)
                        end,
                    },
                }

                if Config.Features.AllowHistoryDelete then
                    actionOptions[#actionOptions + 1] = {
                        title = L('menu_history_remove'),
                        icon = 'fa-solid fa-trash',
                        onSelect = function()
                            TriggerServerEvent('vkmusicplayers:server:removeHistoryEntry', id, url)
                            SetTimeout(150, function()
                                TriggerEvent('vkmusicplayers:client:openHistory', { id = id })
                            end)
                        end,
                    }
                end

                lib.registerContext({
                    id = actionId,
                    title = L('menu_history_action'),
                    menu = ('vkmusicplayers_history_%s'):format(id),
                    options = actionOptions,
                })

                lib.showContext(actionId)
            end,
        }
    end

    if #options == 0 then
        options[#options + 1] = {
            title = L('menu_history_empty'),
            disabled = true,
        }
    end

    local menuId = ('vkmusicplayers_history_%s'):format(id)
    lib.registerContext({
        id = menuId,
        title = L('menu_history'),
        options = options,
    })

    lib.showContext(menuId)
end)

RegisterNetEvent('vkmusicplayers:client:changeVolume', function(data)
    local id = ExtractId(data)
    if not id or not Locations[id] then return end

    local booth = Locations[id]
    local stationCfg = GetStationConfig(booth.stationType) or {}
    local minVolume = math.floor(((stationCfg.MinVolume or 0.05) * 100) + 0.5)
    local maxVolume = math.floor(((stationCfg.MaxVolume or 1.0) * 100) + 0.5)
    local currentVolume = math.floor((((booth.DefaultVolume or stationCfg.DefaultVolume or 0.2)) * 100) + 0.5)

    local response = lib.inputDialog(L('input_volume_title'), {
        {
            type = 'slider',
            label = L('input_volume_label'),
            description = L('input_volume_desc'),
            required = true,
            min = minVolume,
            max = maxVolume,
            step = 1,
            default = currentVolume,
        }
    })

    if not response or not response[1] then return end
    TriggerServerEvent('vkmusicplayers:server:changeVolume', tonumber(response[1]) / 100.0, id)
end)

RegisterNetEvent('vkmusicplayers:client:changeRange', function(data)
    local id = ExtractId(data)
    if not id or not Locations[id] then return end

    local booth = Locations[id]
    local stationCfg = GetStationConfig(booth.stationType) or {}
    local response = lib.inputDialog(L('input_range_title'), {
        {
            type = 'slider',
            label = L('input_range_label'),
            description = L('input_range_desc'),
            required = true,
            min = stationCfg.MinRange or 5,
            max = stationCfg.MaxRange or 25,
            step = 1,
            default = math.floor(tonumber(booth.radius) or tonumber(stationCfg.DefaultRange) or 20),
        }
    })

    if not response or not response[1] then return end
    TriggerServerEvent('vkmusicplayers:server:setRange', tonumber(response[1]), id)
end)

RegisterNetEvent('vkmusicplayers:client:renameStation', function(data)
    local id = ExtractId(data)
    if not id or not Locations[id] then return end

    local currentName = Locations[id].stationName or ''
    local response = lib.inputDialog(L('input_name_title'), {
        {
            type = 'input',
            label = L('input_name_label'),
            description = L('input_name_desc'),
            required = false,
            default = currentName,
            max = Config.Placement.MaxNameLength,
        }
    })

    if not response then return end
    local value = response[1]
    if value and value ~= '' then
        value = tostring(value):sub(1, Config.Placement.MaxNameLength)
    else
        value = ''
    end

    TriggerServerEvent('vkmusicplayers:server:renameStation', id, value)
end)

RegisterNetEvent('vkmusicplayers:client:removeSpawnedStation', function(id)
    id = tonumber(id)
    local data = id and Spawned[id] or nil
    if data and data.obj and DoesEntityExist(data.obj) then
        RemoveTargetEntity(data.obj)
        DeleteObject(data.obj)
    end
    if id then
        Spawned[id] = nil
        Locations[id] = nil
    end
end)

RegisterNetEvent('vkmusicplayers:client:updateStationVolume', function(id, vol)
    id = tonumber(id)
    vol = tonumber(vol)
    if not id or not vol or not Locations[id] then return end
    Locations[id].DefaultVolume = vol
end)

RegisterNetEvent('vkmusicplayers:client:updateStationRange', function(id, range)
    id = tonumber(id)
    range = tonumber(range)
    if not id or not range or not Locations[id] then return end
    Locations[id].radius = range
end)

RegisterNetEvent('vkmusicplayers:client:updateStationName', function(id, stationName)
    id = tonumber(id)
    if not id or not Locations[id] then return end
    Locations[id].stationName = stationName
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    InitialSyncComplete = false
    CreateThread(function()
        Wait(500)
        DespawnAllStations()
        CleanupOrphanStations()
        RequestStationSync()
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    InitialSyncComplete = false
    DespawnAllStations()
    EndPlacement()
end)

AddEventHandler('playerSpawned', function()
    if not InitialSyncComplete then
        SetTimeout(800, RequestStationSync)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    EndPlacement()
    DespawnAllStations()
end)

CreateThread(function()
    Wait(200)
    CleanupOrphanStations()
end)

CreateThread(function()
    Wait(600)
    RequestStationSync()
end)
