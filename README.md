# Home Assistant for Omarchy

Home Assistant in the Omarchy bar. A pill that shows the entities you pin,
a keyboard-first panel where you browse every entity in your home and star
the ones you want, and a shell service that keeps one live connection open
for notifications, the Omarchy menu, and presence automations.

![Dashboard](docs/dashboard.png)

## What it does

- **Dashboard** of the entities you picked, in the order you chose. Lights
  and switches get a toggle, covers get open/stop/close, media players get
  transport buttons, locks lock and unlock, scenes and scripts run, sensors
  show their value. Toggles flip immediately and reconcile with the real state.
- **Browser** with instant search across every entity, category chips, and
  area names. Star a row to add it to the dashboard.
- **Detail view** per entity: brightness and color temperature for lights,
  target temperature, mode and preset for climate, position for covers,
  volume and transport for media, speed for fans, options for selects, and
  every attribute.
- **Pin to bar**: any number of entities, their states next to the icon
  ("21.4° · Closed"). The pill turns urgent when a pinned entity goes
  unavailable or a smoke, gas, water, or alarm entity you watch fires.
- **Alerts**: mark an entity with the bell and get an Omarchy notification
  when it changes, worded for its device class ("Front Door · Opened",
  "Hallway Motion · Motion detected"). Click the notification to open it.
- **Home Assistant notifications** raised on the server show up on your
  desktop too.
- **Omarchy menu**: one toggle adds a "Home" submenu with your dashboard to
  the Omarchy menu. Toggles show a check mark when they are on. It is
  regenerated whenever the dashboard changes.
- **Automations**: run a scene or script when the screen locks, unlocks, or
  the screensaver starts. Picked in the panel, no YAML.
- **Live**: one WebSocket connection per shell, shared by every bar
  instance, with instant state pushes and automatic reconnect. Falls back to
  REST polling when the `qt6-websockets` package is missing and offers to
  install it.
- **Themed**: colors, fonts and spacing come from the Omarchy theme.

| Browser | Detail |
|---|---|
| ![Browser](docs/browser.png) | ![Detail](docs/detail.png) |

| Settings | Omarchy menu | Notifications |
|---|---|---|
| ![Settings](docs/settings.png) | ![Menu](docs/menu.png) | ![Notifications](docs/notifications.png) |

## Install

```bash
omarchy plugin add https://github.com/rewisch/omarchy-homeassistant.git --enable
```

Then click the house icon in the bar. Enter the address of your instance
and a long-lived access token (Home Assistant → your profile → Security →
Long-lived access tokens) and press Connect. Press `a` to browse, type to
search, `Enter` to star, `Esc` to return to the dashboard.

For live updates instead of polling, press **Install** on the "Get live
updates" banner the dashboard shows on first connect (or press `L`). It opens
Omarchy's floating terminal, installs `qt6-websockets`, and restarts the
shell. `omarchy plugin add` never runs plugin code or sudo by design, which
is why this cannot happen automatically. The manual equivalent:

```bash
omarchy pkg add qt6-websockets
omarchy restart shell
```

Your connection is saved to `~/.config/omarchy/homeassistant/connection.json`
with owner-only permissions. The dashboard, pins, alerts and preferences live
next to it in `dashboard.json`.

## Keyboard

Dashboard:

| Key | Action |
|---|---|
| `j` / `k` or arrows | move |
| `Enter` / `Space` | toggle, run, or open details |
| `→` / `l` / `e` | details |
| `p` | pin to bar |
| `n` | notify me when this changes |
| `J` / `K` | reorder |
| `x` / `d` | remove from dashboard |
| `a` / `/` | browse entities |
| `r` | refresh |
| `,` | settings |
| `Esc` | close |

Browser:

| Key | Action |
|---|---|
| type | search |
| `↑` / `↓` (or `Ctrl-j` / `Ctrl-k`) | move |
| `Enter` | star / unstar (or choose, when picking) |
| `Tab` / `Shift-Tab` | next / previous category |
| `→` (at end of text) | details |
| `Ctrl-Enter` | toggle the entity |
| `Ctrl-Space` | pin to bar |
| `Esc` | clear search, then back |

Details:

| Key | Action |
|---|---|
| `j` / `k` | move between controls |
| `←` / `→`, `-` / `+` | adjust slider, stepper or chip |
| `Enter` | apply the highlighted chip |
| `t` | toggle power |
| `s` | star / unstar |
| `p` | pin / unpin |
| `n` | alert on / off |
| `c` | copy the shell command for a keybinding |
| `Esc` / `h` | back |

Settings (`,`): `j` / `k` move, `Enter` toggles or opens the picker,
`x` clears an automation.

Bar pill: left click opens the panel, right click toggles the first pinned
entity (or refreshes), middle click refreshes.

## Keybindings and scripting

Every action is reachable over the shell IPC. Press `c` on any entity's
detail view to copy its command, then bind it in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT, H", "omarchy-shell rewisch.homeassistant toggle", "Home Assistant")
o.bind("SUPER SHIFT, L", "omarchy-shell rewisch.homeassistant toggleEntity light.desk", "Desk light")
```

Available methods:

```bash
omarchy-shell rewisch.homeassistant toggle                 # open / close the panel
omarchy-shell rewisch.homeassistant browse
omarchy-shell rewisch.homeassistant settings
omarchy-shell rewisch.homeassistant detail climate.living_room
omarchy-shell rewisch.homeassistant toggleEntity light.kitchen
omarchy-shell rewisch.homeassistant turnOn scene.movie_night
omarchy-shell rewisch.homeassistant turnOff switch.garden_pump
omarchy-shell rewisch.homeassistant call cover.open_cover cover.garage
omarchy-shell rewisch.homeassistant state sensor.living_room_temperature
omarchy-shell rewisch.homeassistant refresh
```

## Settings

Inside the panel (`,`): connection, notifications, the menu block, and
automations. In `Setup → Plugins` or the widget entry in
`~/.config/omarchy/shell.json`: `transport` (`Auto`, `WebSocket`, `Polling`)
and `refreshIntervalSec` for polling.

## Layout

```
manifest.json      plugin manifest: service + bar widget, settings schema
Panel.qml          bar pill, popup, view routing, IPC
Service.qml        shared connection, entity store, actions, notifications,
                   menu block, automations, persistence
WsTransport.qml    WebSocket transport (needs qt6-websockets)
RestTransport.qml  curl-based polling transport
Model.js           pure helpers: icons, state text, search, groups
HomeView.qml       dashboard
BrowseView.qml     search, pick, star
DetailView.qml     per-entity controls and attributes
SettingsView.qml   notifications, menu, automations
SetupView.qml      connection editor
EntityRow.qml      shared list row
HintBar.qml        keyboard hint footer
test/              mock Home Assistant servers for development
```

## Development

Clone into `~/src`, symlink it into the plugins directory, and restart the
shell after editing (hot reload keeps the cached QML):

```bash
git clone https://github.com/rewisch/omarchy-homeassistant.git ~/src/omarchy-homeassistant
ln -s ~/src/omarchy-homeassistant ~/.config/omarchy/plugins/rewisch.homeassistant
omarchy plugin enable rewisch.homeassistant
omarchy restart shell
```

See `test/README.md` for the mock servers.
