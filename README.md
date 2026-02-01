# boussole — FFXI Map Addon for Ashita

<p align="center">
  <img src="https://raw.githubusercontent.com/loonsies/boussole/refs/heads/main/assets/logo.png" alt="Image 1" width="700" style="max-width: 100%;"/>
</p>

<h3 align="center" style="margin-bottom: 50px;">
  Map replacement addon for Ashita v4 with useful overlays and simple customization
</h3>

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
- Map UI controls:
  - Always center on player
  - Center once
  - Show nametags above entities
  - Reset map zoom
- Tracked entities display (ported from scenthound):
  - Displays tracked entities as dots on the map
  - Save tracked entities into profiles
  - **Use with extreme caution**
  - This feature is effectively cheating and may be dangerous for your account, disabled by default
- Custom maps data handling:
  - Supports maps for areas such as Temenos / Apollyon 119
  - Includes offsets and calibration data out of the box
  - Compatible with custom maps from https://github.com/loonsies/boussole_custom_maps
  - If using different maps, offsets must be calibrated manually

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

### A collection of redirections and custom maps is available at https://github.com/loonsies/boussole_custom_maps

# Commands
- `/boussole` Toggles the UI
- `/boussole show` Shows the UI
- `/boussole hide` Hides the UI
- `/boussole genfloors` Regenerates zonesFloors.lua

# Planned features
- Fullscreen map
- Minimap
- Uber Warp integration
- Websocket support for LS position update
- Hide maps if not in possession of the map key item
- Widescan support
- More ?

# Credits and thanks
atom0s & Thorny for providing code and help
