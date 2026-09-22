# Test tooling

`node --test test/test_model.js` runs the unit tests in `test_model.js` against `Model.js`.
The menu-splice tests parse their output with a replica of the shell's JSONC
reader, so a change that breaks `~/.config/omarchy/extensions/omarchy-menu.jsonc`
fails here first.

Two dependency-free mock Home Assistant servers for developing the plugin
without touching a real instance. Token is `mock-token-123`.

```bash
python3 test/mock_ha.py 18123      # REST only  (polling transport)
python3 test/mock_ha_ws.py         # REST + WebSocket on port 18124 (live transport)
```

Point the plugin at `http://127.0.0.1:18123` or `http://127.0.0.1:18124`.
The WebSocket mock pushes a changing `sensor.solar_power` and a flipping
`binary_sensor.hallway_motion` every few seconds and logs every service call.

Driving the UI from a script: `omarchy-shell rewisch.homeassistant open`,
`wtype` for keystrokes, `grim -g "<x>,<y> <w>x<h>"` for screenshots.
Note: after editing QML, run `omarchy restart shell`; the hot reload keeps
the cached component.
