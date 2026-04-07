# VK Music Players

Drag-and-drop QBCore music stations with ox_lib, qb-target, oxmysql, and xSound.

## Included upgrades
- One-table SQL structure using `chasemusicbox`
- Config-driven station types with multiple allowed props per item
- Per-station-type min/max/default volume and range
- Locale system
- History settings in config
- Custom station names
- Rebuilt client placement flow with cached camera raycasts and cached validity checks
- Namespaced events switched to `vk-musicplayers:*`

## Install
1. Drop the `vk-musicplayers` folder into your resources.
2. Run `readme/sql/chasemusicbox.sql`.
3. Ensure resource order includes:
   - `oxmysql`
   - `xsound`
   - `vk-musicplayers`
4. Add the matching usable items to `qb-core/shared/items.lua` if needed.
5. Adjust `config/config.lua` to match your items, props, range limits, and volume limits.

## Main events
- `vkmusicplayers:client:startPlacement`
- `vkmusicplayers:client:openMenu`
- `vkmusicplayers:server:addPlacedStation`
- `vkmusicplayers:server:playMusic`
- `vkmusicplayers:server:stopMusic`
- `vkmusicplayers:server:pauseResume`
- `vkmusicplayers:server:changeVolume`
- `vkmusicplayers:server:setRange`
- `vkmusicplayers:server:renameStation`
- `vkmusicplayers:server:removeStation`

## Notes
- The server keeps your old working xSound export call style.
- The default audio volume export stays on `setVolume` because that matched your working build.
- If you want different item types, add them under `Config.StationTypes`.
