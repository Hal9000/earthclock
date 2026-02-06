## EarthClock

Render Earth as seen from the Moon (Apollo 11 site), onto a circular display. Pure Ruby + GTK/Cairo. No libration, no nutation; axial tilt and seasons are represented via lighting.

### Compare against https://www.fourmilab.ch/cgi-bin/Earth/action?opt=-m  (believed to be correct); it does give a north/south view, unlike this app.

### Requirements (macOS)
- Ruby 3.x (rbenv recommended)
- Homebrew packages:
  - `brew install gtk+3 gobject-introspection cairo pkg-config`
- Gems:
  - `gem install bundler`
  - `bundle install`

### Quick start (macOS window)
```bash
cd /Users/Hal/Dropbox/topx/git/earthclock
bundle install
bin/earthclock
```

### Fullscreen on external display
```bash
EC_FULLSCREEN=1 EC_MONITOR_INDEX=1 bin/earthclock
```
- `EC_MONITOR_INDEX` is 0-based. Adjust as needed.

### Textures
- Default texture is `earth.jpg` (equirectangular 2:1).
- Use a different file without renaming:
```bash
EC_TEXTURE="/absolute/path/to/earth_clean.jpg" bin/earthclock
```
- Suggested sources: NASA Blue Marble NG (cloudless), Natural Earth II. Size 4096×2048 or 8192×4096.
 - If your texture’s seam/prime meridian differs, apply a longitude offset:
```bash
# shift sampling by +180° (move seam)
EC_TEX_LON_OFFSET_DEG=180 bin/earthclock
# small tweaks:
EC_TEX_LON_OFFSET_DEG=10 bin/earthclock
```
 - Auto-estimate texture seam and suggested offset:
```bash
bin/earthclock-texcal
# output:
# Estimated seam column: 512
# Suggested EC_TEX_LON_OFFSET_DEG: -180.0
```

### Orientation (single mode: Apollo 11 lunar-up)
- Screen up approximates the local lunar vertical at Apollo 11 (ignoring libration).
- Forward is Earth→Moon, so you see the sub‑lunar hemisphere.
- The axis tilt is visible relative to the lunar “horizon.”
- A constant roll trim is available for visual alignment:
```bash
EC_ROLL_DEG=45 bin/earthclock
```

### Timing presets
- Use real UTC by default. Override with:
```bash
# Apollo 11 landing (LM touchdown)
bin/earthclock 1stlanding
# or
EC_PRESET=1stlanding bin/earthclock

# First step
EC_PRESET=firststep bin/earthclock

# Specific time
EC_TIME="1969-07-20T20:17:40Z" bin/earthclock
# Or UNIX seconds
EC_UNIX_SECONDS=1234567890 bin/earthclock
```

### Shading and visibility
- Disable shading entirely (for debugging):
```bash
EC_DISABLE_SHADING=1 bin/earthclock
```
- Tune brightness:
```bash
EC_EXPOSURE=2.0 EC_NIGHT_FLOOR=0.35 EC_GAMMA=1.0 bin/earthclock
```
- Ocean boost (heuristic blue/cyan classification):
```bash
EC_WATER_BOOST=1.2 bin/earthclock
# Optional refinement (degrees/saturation)
EC_WATER_HUE_LO=180 EC_WATER_HUE_HI=250 EC_WATER_SAT_MIN=0.2 bin/earthclock
```

### Debug overlay
```bash
EC_DEBUG_OVERLAY=1 bin/earthclock
```
- Blue arrow: Earth’s spin axis (north).
- Yellow arrow: Sun direction in view.
- Dashed curve: day/night terminator great circle.

### Redraw cadence
- 1 Hz by default. The app recomputes from absolute time each frame (no drift).

### Pi notes (HDMI round display)
- If you use the Waveshare 3.4" HDMI round (800×800), it can run driverless on Pi.
- Install deps:
```bash
sudo apt update
sudo apt install -y ruby ruby-dev build-essential libgtk-3-dev libcairo2-dev
```
- Run:
```bash
bundle install
bin/earthclock
```
- Fullscreen to the HDMI panel:
```bash
EC_FULLSCREEN=1 EC_MONITOR_INDEX=0 bin/earthclock
```
- If 800×800 isn’t exposed, set it in Raspberry Pi OS display settings or use a custom mode.
- Systemd autostart: to be added when deploying to the Pi.

### Architecture (layers)
- Time/state → Astronomy/geometry → Earth model → Visibility/illumination → Projection/rasterization → Display/timing → App orchestration.
- All sampling is from a sphere; you are not rotating an image.

