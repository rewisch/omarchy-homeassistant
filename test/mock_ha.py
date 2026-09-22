#!/usr/bin/env python3
"""Minimal Home Assistant REST mock: /api/config, /api/states, /api/services/<d>/<s>."""
import json, sys, datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = "mock-token-123"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18123

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def ent(eid, state, **attrs):
    return {"entity_id": eid, "state": state, "attributes": attrs, "last_changed": now(), "last_updated": now()}

STATES = {}
def add(e): STATES[e["entity_id"]] = e

add(ent("light.kitchen", "on", friendly_name="Kitchen", brightness=180, supported_color_modes=["color_temp"], color_mode="color_temp", color_temp_kelvin=3200, min_color_temp_kelvin=2000, max_color_temp_kelvin=6500))
add(ent("light.living_room", "off", friendly_name="Living Room Lamp", supported_color_modes=["brightness"]))
add(ent("light.rgb_strip", "on", friendly_name="TV Strip", brightness=200, supported_color_modes=["hs", "color_temp"], color_mode="hs", hs_color=[210, 85], rgb_color=[38, 128, 255], min_color_temp_kelvin=2000, max_color_temp_kelvin=6500))
add(ent("camera.front_door", "idle", friendly_name="Front Door Camera", entity_picture="/api/camera_proxy/camera.front_door?token=cam-token", access_token="cam-token"))
add(ent("light.desk", "on", friendly_name="Desk Light", brightness=255, supported_color_modes=["onoff"]))
add(ent("switch.coffee_machine", "off", friendly_name="Coffee Machine", device_class="outlet"))
add(ent("switch.garden_pump", "on", friendly_name="Garden Pump"))
add(ent("input_boolean.guest_mode", "off", friendly_name="Guest Mode"))
add(ent("sensor.living_room_temperature", "21.4", friendly_name="Living Room Temperature", unit_of_measurement="°C", device_class="temperature", state_class="measurement"))
add(ent("sensor.outside_humidity", "63", friendly_name="Outside Humidity", unit_of_measurement="%", device_class="humidity"))
add(ent("sensor.solar_power", "2340", friendly_name="Solar Power", unit_of_measurement="W", device_class="power"))
add(ent("sensor.grid_energy_today", "7.82", friendly_name="Grid Energy Today", unit_of_measurement="kWh", device_class="energy"))
add(ent("sensor.phone_battery", "78", friendly_name="Phone Battery", unit_of_measurement="%", device_class="battery"))
add(ent("binary_sensor.front_door", "off", friendly_name="Front Door", device_class="door"))
add(ent("binary_sensor.hallway_motion", "on", friendly_name="Hallway Motion", device_class="motion"))
add(ent("climate.living_room", "heat", friendly_name="Living Room Thermostat", current_temperature=21.4, temperature=22.0, min_temp=7, max_temp=30, target_temp_step=0.5, hvac_modes=["off","heat","cool","auto"], preset_modes=["home","away","eco","boost"], preset_mode="home", supported_features=17, temperature_unit="°C"))
add(ent("cover.garage", "closed", friendly_name="Garage Door", device_class="garage", supported_features=15, current_position=0))
add(ent("cover.bedroom_blinds", "open", friendly_name="Bedroom Blinds", device_class="blind", supported_features=15, current_position=70))
add(ent("media_player.living_room_speaker", "playing", friendly_name="Living Room Speaker", media_title="Blue in Green", media_artist="Miles Davis", media_album_name="Kind of Blue", volume_level=0.35, supported_features=21437, entity_picture="/api/media_player_proxy/media_player.living_room_speaker?token=art-token&cache=1"))
add(ent("media_player.tv", "off", friendly_name="TV", supported_features=21437, device_class="tv"))
add(ent("scene.movie_night", "unknown", friendly_name="Movie Night"))
add(ent("scene.good_morning", "unknown", friendly_name="Good Morning"))
add(ent("script.goodnight", "off", friendly_name="Goodnight Routine"))
add(ent("automation.lights_at_sunset", "on", friendly_name="Lights at Sunset", last_triggered=now()))
add(ent("lock.front_door", "locked", friendly_name="Front Door Lock"))
add(ent("fan.bedroom", "on", friendly_name="Bedroom Fan", percentage=40, percentage_step=20, supported_features=1))
add(ent("person.reto", "home", friendly_name="Reto"))
add(ent("sun.sun", "above_horizon", friendly_name="Sun"))
add(ent("weather.home", "partlycloudy", friendly_name="Home Weather", temperature=19.2))
add(ent("vacuum.robo", "docked", friendly_name="Robo Vacuum"))
add(ent("input_select.house_mode", "Day", friendly_name="House Mode", options=["Day","Night","Away","Party"]))
add(ent("input_number.target_humidity", "45", friendly_name="Target Humidity", min=30, max=70, step=5, unit_of_measurement="%"))
add(ent("sensor.unavailable_thing", "unavailable", friendly_name="Broken Sensor"))
for i in range(40):
    add(ent(f"sensor.room_{i}_temperature", f"{18 + (i % 7) + 0.3:.1f}", friendly_name=f"Room {i} Temperature", unit_of_measurement="°C", device_class="temperature"))

def toggle(e):
    e["state"] = "off" if e["state"] == "on" else "on"

import zlib, struct, math, time as _time

def png_frame(w=320, h=180):
    """Solid-colour PNG whose hue changes over time, so refreshes are visible."""
    t = _time.time()
    r = int(128 + 120 * math.sin(t / 3)); g = int(128 + 120 * math.sin(t / 3 + 2)); b = int(128 + 120 * math.sin(t / 3 + 4))
    raw = b"".join(b"\x00" + bytes([r, g, b]) * w for _ in range(h))
    def chunk(tag, data): return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

def history_rows(eid, start_iso, end_iso):
    import datetime as _dt
    try:
        start = _dt.datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
        end = _dt.datetime.fromisoformat(end_iso.replace("Z", "+00:00")) if end_iso else _dt.datetime.now(_dt.timezone.utc)
    except Exception:
        end = _dt.datetime.now(_dt.timezone.utc); start = end - _dt.timedelta(hours=24)
    n = 60
    rows = []
    base = float(STATES[eid]["state"]) if eid in STATES and STATES[eid]["state"].replace(".", "", 1).isdigit() else 20.0
    for i in range(n):
        ts = start + (end - start) * i / (n - 1)
        v = base + 3 * math.sin(i / 6) + (i % 5) * 0.2
        rows.append({"state": f"{v:.1f}", "last_updated": ts.isoformat(), "s": f"{v:.1f}", "lu": ts.timestamp()})
    return rows

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _auth(self):
        return self.headers.get("Authorization") == f"Bearer {TOKEN}"
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if self.path.startswith("/api/camera_proxy/") or self.path.startswith("/api/media_player_proxy/"):
            body = png_frame()
            self.send_response(200); self.send_header("Content-Type", "image/png"); self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "no-cache"); self.end_headers(); self.wfile.write(body); return
        if not self._auth(): return self._send(401, {"message": "Unauthorized"})
        if self.path == "/api/config": return self._send(200, {"location_name": "Casa Wietlisbach", "version": "2026.9.1", "unit_system": {"temperature": "°C"}})
        if self.path == "/api/states": return self._send(200, list(STATES.values()))
        if self.path == "/api/": return self._send(200, {"message": "API running."})
        if self.path.startswith("/api/history/period/"):
            from urllib.parse import urlparse, parse_qs, unquote
            u = urlparse(self.path); q = parse_qs(u.query)
            eid = q.get("filter_entity_id", [""])[0]; start = unquote(u.path[len("/api/history/period/"):]); end = q.get("end_time", [""])[0]
            rows = [{"state": r["state"], "last_updated": r["last_updated"], "last_changed": r["last_updated"]} for r in history_rows(eid, start, end)]
            return self._send(200, [rows])
        if self.path.startswith("/api/states/"):
            e = STATES.get(self.path[len("/api/states/"):]); return self._send(200, e) if e else self._send(404, {"message": "not found"})
        self._send(404, {"message": "not found"})
    def do_POST(self):
        if not self._auth(): return self._send(401, {"message": "Unauthorized"})
        n = int(self.headers.get("Content-Length", 0)); data = json.loads(self.rfile.read(n) or b"{}")
        parts = self.path.strip("/").split("/")
        if len(parts) == 4 and parts[1] == "services":
            domain, service = parts[2], parts[3]
            eid = data.get("entity_id"); e = STATES.get(eid)
            print(f"CALL {domain}.{service} {json.dumps(data)}", flush=True)
            if e:
                a = e["attributes"]
                if service == "toggle": 
                    if domain == "cover": e["state"] = "closed" if e["state"] in ("open","opening") else "open"; a["current_position"] = 0 if e["state"]=="closed" else 100
                    else: toggle(e)
                elif service == "turn_on":
                    e["state"] = "on"
                    if "brightness_pct" in data: a["brightness"] = round(data["brightness_pct"] * 255 / 100)
                    if "color_temp_kelvin" in data: a["color_temp_kelvin"] = data["color_temp_kelvin"]; a["color_mode"] = "color_temp"
                    if "hs_color" in data: a["hs_color"] = data["hs_color"]; a["color_mode"] = "hs"
                    if domain == "scene": e["state"] = "unknown"
                elif service == "turn_off": e["state"] = "off"
                elif service == "set_temperature": a["temperature"] = data["temperature"]
                elif service == "set_hvac_mode": e["state"] = data["hvac_mode"]
                elif service == "set_preset_mode": a["preset_mode"] = data["preset_mode"]
                elif service == "set_percentage": a["percentage"] = data["percentage"]; e["state"] = "off" if data["percentage"] == 0 else "on"
                elif service == "open_cover": e["state"] = "open"; a["current_position"] = 100
                elif service == "close_cover": e["state"] = "closed"; a["current_position"] = 0
                elif service == "set_cover_position": a["current_position"] = data["position"]; e["state"] = "closed" if data["position"] == 0 else "open"
                elif service == "media_play_pause": e["state"] = "paused" if e["state"] == "playing" else "playing"
                elif service == "volume_set": a["volume_level"] = data["volume_level"]
                elif service == "lock": e["state"] = "locked"
                elif service == "unlock": e["state"] = "unlocked"
                elif service == "select_option": e["state"] = data["option"]
                elif service == "set_value": e["state"] = str(data["value"])
                elif service == "press": pass
                elif service == "start": e["state"] = "cleaning"
                elif service == "return_to_base": e["state"] = "docked"
                e["last_changed"] = now()
            return self._send(200, [e] if e else [])
        self._send(404, {"message": "not found"})

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
