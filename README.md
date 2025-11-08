# boussole — FFXI Map Addon for Ashita

<p align="center">
  <img src="https://github.com/loonsies/boussole/blob/main/assets/logo.png?raw=true" alt="Image 1" width="700" style="max-width: 100%;"/>
</p>

### Map replacement addon for Ashita v4 with useful overlays and simple customization

<p align="center">
  <img src="https://i.imgur.com/oP3Kilw.png" alt="Image 1" width="600px" style="max-width: 100%;"/>
</p>

# Features
- Zone/floor-aware map with pan & zoom
- Player / party / alliance cursors updated in real-time
- Homepoints and survival guide markers
- Persistent, custom map points
- Custom PNG icons per point (optional tint)
- Custom maps
- XiPivot support

# Quick use
- You can open the right panel to filter what overlays are displayed, browse maps, redirect maps, customize UI, export maps to .BMP, and more
- Maintaining right-click and moving the mouse will pan the map
- Right-click the map to add a point; right-click a point to edit or delete it

# Custom maps and icons
- Custom maps : `<Ashita install>\config\addons\boussole\custom_maps`
- Custom icons : `<Ashita install>\config\addons\boussole\custom_icons`
- Enter the exact filename, **including** file extension, in the point editor; missing icons fall back to a dot
- Custom maps uses the ZONEID_FLOORID format, .png, .jpg and .bmp formats are supported
- If you're not sure about ZONEID or FLOORID, simply browse maps in the panel and export the map as .BMP, the file will be named correctly for being used as a custom map

# Commands
- `/boussole` Toggles the UI
- `/boussole show` Shows the UI
- `/boussole` Hides the UI
- `/boussole genfloors` Regenerates zonesFloors.lua

# Planned features
- Fullscreen map
- Uber Warp integration
- Websocket support for LS position update
- More ?





