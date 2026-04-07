Config = {}

-- Turn this on if you want extra console prints while testing.
-- Leave false for normal live server use.
Config.Debug = false

-- Which language file to use from /locales
Config.Locale = 'en'

-- SQL table name used to save placed music players and their saved data.
-- Change this only if you know you want a different table name.
Config.TableName = 'chasemusicbox'

Config.Target = {
    -- How close a player needs to be to interact with a placed music player.
    Distance = 2.0,

    -- Icon shown in target/interaction prompts.
    Icon = 'fas fa-music',
}

Config.Audio = {
    -- Resource name for xSound.
    -- Change this only if your xSound resource folder uses a different name.
    XSoundResource = 'xsound',

    -- Volume export used by your current xSound setup.
    -- Leave this as 'setVolume' since that is the path working for your server.
    VolumeExport = 'setVolume',

    -- Whether songs should automatically loop when played.
    -- False = plays once
    -- True = repeats until stopped
    Loop = false,
}

Config.Features = {
    -- Lets players view recently played songs for a station.
    AllowHistory = true,

    -- Lets owners remove songs from station history in-game.
    AllowHistoryDelete = true,

    -- Lets players pause and resume the current song.
    AllowPause = true,

    -- Lets players change how far the music can be heard.
    AllowRangeChange = true,

    -- Lets players change the station volume in-game.
    AllowVolumeChange = true,

    -- Lets owners rename their placed station.
    AllowStationRename = true,

    -- If true, only the station owner can pick it back up.
    -- Recommended for most servers.
    OwnerOnlyPickup = true,

    -- If true, admins can bypass ownership restrictions.
    -- Leave false unless you want staff to fully manage placed stations.
    AdminBypass = false,
}

Config.Placement = {
    -- Closest the preview object can be placed in front of the player.
    MinDistance = 0.75,

    -- Furthest the preview object can be placed from the player.
    MaxDistance = 8.0,

    -- Default starting distance when placement begins.
    DefaultDistance = 2.0,

    -- How much each mouse wheel tick rotates the object.
    RotationStep = 2.5,

    -- How much vertical offset is added or removed per step.
    HeightStep = 0.02,

    -- Highest the object can be adjusted above the snapped ground point.
    MaxHeightOffset = 1.0,

    -- Lowest the object can be adjusted below the snapped ground point.
    -- Usually best kept near or above -1.0.
    MinHeightOffset = -1.0,

    -- How far the object moves per directional input press.
    MoveStep = 0.08,

    -- Lower = faster repeated movement while holding a direction.
    -- Higher = slower repeated movement.
    MoveRepeatInterval = 35,

    -- Small amount of placement forgiveness for edge cases during movement.
    OffsetSlack = 1.5,

    -- Modifier key used for vertical adjustment.
    -- 21 = Left Shift
    VerticalModifierControl = 21,

    -- How far the client raycast checks forward when finding placement ground.
    RaycastDistance = 12.0,

    -- How often the raycast updates while placing.
    -- Lower feels more live, higher saves a bit more client work.
    RaycastInterval = 35,

    -- How often to check how far the player has walked from placement start.
    DistanceCheckInterval = 200,

    -- Placement auto-cancels if the player moves farther than this
    -- from where they started placing.
    MaxPlacementTravel = 20.0,

    -- How often validity checks run while placing.
    -- These are things like overlap / blocked placement checks.
    ValidityInterval = 125,

    -- How often placement help text / prompts refresh.
    PromptInterval = 250,

    -- Smoothing used when moving the preview object.
    -- Lower = snappier, higher = smoother / softer.
    Smoothing = 0.28,

    -- Transparency of the placement ghost prop.
    -- 255 = fully solid, lower numbers = more transparent.
    GhostAlpha = 210,

    -- Minimum distance required between placed stations/props.
    -- Helps stop stacking or clipping into each other.
    MinSeparation = 1.20,

    -- Show placement control hints on screen.
    ControlHints = true,

    -- Max amount of characters allowed when renaming a station.
    MaxNameLength = 32,
}

Config.History = {
    -- Master switch for song history support.
    Enabled = true,

    -- Default amount of recent songs to keep per station,
    -- unless a station type overrides it.
    DefaultKeep = 5,

    -- Try to fetch YouTube title/thumbnail info for history entries.
    -- Turn this off if you want simpler behavior with less outside lookups.
    FetchYouTubeMeta = true,
}

Config.StationTypes = {
    jukeboxone = {
        -- Friendly name shown to players/admins.
        Label = 'Classic Jukebox',

        -- Short description for menus or future shop display use.
        Description = 'A full-size vintage music station.',

        -- Inventory item required to place this station type.
        Item = 'jukeboxone',

        -- Default prop model used when placement starts.
        DefaultProp = 'prop_jukebox_02',

        -- Props players are allowed to swap between for this station type.
        -- The first one does not have to match DefaultProp, but usually should.
        AllowedProps = {
            { model = 'prop_jukebox_01', label = 'Jukebox (Lights Off)' },
            { model = 'prop_jukebox_02', label = 'Jukebox (Lights On)' },
        },

        -- Starting volume when this station is first placed.
        -- 0.20 = 20%
        DefaultVolume = 0.20,

        -- Lowest volume players can set this station to.
        MinVolume = 0.05,

        -- Highest volume players can set this station to.
        -- 0.50 = 50%
        -- Set to 1.0 if you want it to allow full 100% volume.
        MaxVolume = 0.50,

        -- Starting music range when this station is first placed.
        DefaultRange = 15,

        -- Smallest range players can shrink it to.
        MinRange = 5,

        -- Largest range players can expand it to.
        MaxRange = 25,

        -- How many recently played songs this station keeps saved.
        -- Owners can delete history in-game if that feature is enabled.
        HistoryKeep = 10,

        -- Interaction label shown when targeting the station.
        TargetLabel = 'Use Music Station',
    },

    -- Example extra station type:
    -- Copy this block, rename the table key, and change the item/props/settings.
    -- boombox = {
    --     Label = 'Street Boombox',
    --     Description = 'Compact portable speaker setup.',
    --     Item = 'boombox',
    --     DefaultProp = 'prop_boombox_01',
    --     AllowedProps = {
    --         { model = 'prop_boombox_01', label = 'Street Boombox' },
    --         { model = 'prop_cs_cd_player', label = 'Compact Deck' },
    --     },
    --     DefaultVolume = 0.15,
    --     MinVolume = 0.05,
    --     MaxVolume = 0.70,
    --     DefaultRange = 12,
    --     MinRange = 4,
    --     MaxRange = 18,
    --     HistoryKeep = 4,
    --     TargetLabel = 'Use Boombox',
    -- },
}