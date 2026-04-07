#Chase's Jukebox (QBCore) - v1.1.0

A lightweight, server-friendly jukebox system for QBCore using xsound and ox_lib. 
Placed jukeboxes persist across server restarts, keeping ownership, volume settings, range, and song history intact.

## Credits
- Inspired by jim-djbooth — huge thanks to Jimmathy for the original concept and groundwork.

## Dependencies
- qb-core  
- ox_lib  
- xsound
- qb-target

  
## v2 COMPLETE RE-WORK!
- Expand pause/resume functionality across all xSound builds. - in prog (possible xsound overhaul)
- Add additional props/items for broader placement options. - done
- Introduce advanced configuration options for volume, range, and playlists.  - done
- Consider customizable permissions for job-restricted jukeboxes. - not needed still player locked


<img width="209" height="330" alt="{54C89D0B-819B-405D-8547-10A9F9FD304E}" src="https://github.com/user-attachments/assets/62bc058a-1be2-4cc4-b68b-d8559ce23e96" />

<img width="322" height="156" alt="{413BE8B5-4AA0-4B38-BCBD-D50A29575619}" src="https://github.com/user-attachments/assets/dad19929-97d4-496e-84a6-bd3050615aaf" />

<img width="326" height="151" alt="{986B0810-B799-4EC7-86FA-9B1A4ACCA2C9}" src="https://github.com/user-attachments/assets/d75565b7-19b3-4fcc-b8e1-81242ea0643d" />

<img width="153" height="149" alt="{3D18931B-C7CB-44D9-AF84-E5B9E0EB48AC}" src="https://github.com/user-attachments/assets/6d94569e-0766-4f7a-9457-d4056abff2b7" />

<img width="168" height="103" alt="image" src="https://github.com/user-attachments/assets/942ea5e2-524f-4915-92f0-36588868fb67" />


## Status & Updates
This project is actively maintained. Expect regular updates as features expand.
If you like the project, star ⭐ and watch the repository to stay updated.


## Features (v1.1.0) ( STILL IN PACK AS chase-jukebox ) still works but no longer supported or updated. Download and use vk-musicplayers! :)
- Persistent jukeboxes with ownership and location saved in the database.
- Song history: Stores up to 5 recent songs per station with thumbnails in the menu.
- Playback controls: Play, stop, pause/resume, and change volume.
- Range control: Audible radius can now be set up to 25 meters.
- Improved placement system: Ghost props with rotation, height adjustment, distance scroll, and valid placement visual indicators.
- Usable item integration: Placing a jukebox consumes "jukeboxone"; removing it returns the item.
- Optimized sync: Efficient client-server communication for new players and resource restarts.
- xSound safety: Handles missing or older builds gracefully.
- Clean menus via ox_lib: Play YouTube URLs, view history, change volume, stop music, pickup/remove jukebox.

