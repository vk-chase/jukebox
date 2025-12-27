#Chase's Jukebox (QBCore) - v1.1.0

A lightweight, server-friendly jukebox system for QBCore using xsound and ox_lib. 
Placed jukeboxes persist across server restarts, keeping ownership, volume settings, range, and song history intact.

## Credits
- Inspired by jim-djbooth — huge thanks to Jimmathy for the original concept and groundwork.

## Dependencies
- qb-core  
- ox_lib  
- xsound

> Note: This script does not require jim-bridge.

## Features (v1.1.0)
- Persistent jukeboxes with ownership and location saved in the database.
- Song history: Stores up to 5 recent songs per station with thumbnails in the menu.
- Playback controls: Play, stop, pause/resume, and change volume.
- Range control: Audible radius can now be set up to 25 meters.
- Improved placement system: Ghost props with rotation, height adjustment, distance scroll, and valid placement visual indicators.
- Usable item integration: Placing a jukebox consumes "jukeboxone"; removing it returns the item.
- Optimized sync: Efficient client-server communication for new players and resource restarts.
- xSound safety: Handles missing or older builds gracefully.
- Clean menus via ox_lib: Play YouTube URLs, view history, change volume, stop music, pickup/remove jukebox.
<img width="910" height="887" alt="Untitled" src="https://github.com/user-attachments/assets/52e50fda-8d90-4173-b441-b4e3b642ad9b" />
## Roadmap
- Expand pause/resume functionality across all xSound builds.
- Add additional props/items for broader placement options.
- Introduce advanced configuration options for volume, range, and playlists.
- Consider customizable permissions for job-restricted jukeboxes.

## Status & Updates
This project is actively maintained. Expect regular updates as features expand.
If you like the project, star ⭐ and watch the repository to stay updated.
