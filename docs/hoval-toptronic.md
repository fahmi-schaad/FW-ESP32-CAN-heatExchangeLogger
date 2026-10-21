# Hoval TopTronic E integration

The heat exchanger is controlled by a **Hoval TopTronic E** controller. The logger talks to
it with the `toptronic` ESPHome component from
[nliaudat/esp_canbus](https://github.com/nliaudat/esp_canbus) (Apache-2.0). That is the same
project the board schematic comes from. Protocol reference:
[hoval_canbus.md](https://github.com/nliaudat/esp_canbus/blob/main/docs/hoval_canbus.md).

## Protocol in short

| | |
|---|---|
| Bus | CAN 2.0B, **29-bit IDs, 50 kbit/s** |
| Model | Request/response: the logger joins as a **gateway (GW) node** and sends GET requests; the controller answers |
| Addressing | device type (FW=192, WEZ=0, HK=256, …) \| device address (default FW=1, WEZ=1, HK=9, MWA=13) |
| Datapoint | (function group, function number, datapoint), e.g. `20,1,4` = heat meter (2) flow temperature |
| Framing | multi-frame messages with CRC-16. Handled by the component |

Values are only sent in answer to requests. The FW controller **broadcasts** its answers
(receiver `0x7FF`), so every node sees every answer.

This installation also has a **Hoval gateway** (HovalConnect, GW address 1 = CAN node `0x481`).
That is exactly the component's default sender ID for `device_addr: 1`, so the patched
component sends with its own node id instead: `gateway_node_id: 0x48A`
(`hoval_gateway_node_id`). Nodes on the bus (candump, 2026-10-21): `0x0C1` FW 1,
`0x401` BM 1 (display), `0x481` Hoval gateway, `0x48A` this logger.

`can_mode: LISTENONLY` sends nothing and only decodes what the Hoval gateway asks for. That is
~40 datapoints (outdoor, supply (1), heating circuit 2, hot water 1) and **no heat meter**,
so the production firmware runs `NORMAL`. The discovery firmware defaults to `LISTENONLY`;
switch it to `NORMAL` only briefly (it polls ~250 datapoints).

## Two firmware variants

| | Production `heat-exchanger-logger.yaml` | Discovery `heat-exchanger-logger-discovery.yaml` |
|---|---|---|
| Polls | only the **8 datapoints in the signal map** | **every** preset datapoint of the device type (~250 for FW) |
| Entities | logger signals (stable names used by the HA package) | all preset entities, incl. **writable** setpoints/modes |
| Writes to Hoval | none (no writable entities) | possible via the number/select entities ⚠ |
| Purpose | continuous logging | commissioning: find which datapoints carry the values |

Both use the same device name, so you can OTA-flash between them:
`make upload CONFIG=heat-exchanger-logger-discovery.yaml` ↔ `make upload`.

## Commissioning

1. **Confirm the device type and address** on the TopTronic control panel (or with the
   installer). Set `hoval_device_type` / `hoval_device_addr` in **both** YAML files. Candidates:
   - `FW` district heating / transfer station (heat exchanger + heat meter). **Default.**
   - `WEZ` heat generator. Its preset has heat quantity (MWh) counters but no heat meter group.
   - `MWA` energy meter module, if a separate meter module is installed.
2. **Termination:** the TopTronic bus is normally already terminated at both ends. Fit the
   120 Ω `TERMINATOR` jumper only if the logger is at a physical end of the bus.
3. Connect to the bus (RJ45: 1 = CAN_H, 2 = CAN_L, 3 = GND) and flash the **discovery**
   firmware. Check `CAN frame rate` > 0 and `CAN bus receiving` = on.
   Address unknown? Turn on **CAN find device debug** (runs 120 s) and watch `make logs`:
   response frames show the controller's node ID.
4. After ~1 min, browse the entities in HA or on `http://heat-exchanger-logger.local`: which heat
   meter index (`… (2)`, `… (3)`, …) has values? Which temperatures match the TopTronic display?
   The (group, number, datapoint) of every preset entity is in its ID (`FW_20_1_4` = 20, 1, 4)
   and in `esphome/components/toptronic/presets/<TYPE>/sensors_en.yaml`, together with its
   type and scale (`multiply`).
5. **Fill in the signal map** in `heat-exchanger-logger.yaml`:

   ```yaml
   t_prim_in: {group: 20, number: 1, datapoint: 4, type: S16, scale: 0.1, poll: "${poll_interval}"}
   ```

   | Signal | This installation (checked 2026-10-21) | Notes |
   |---|---|---|
   | `t_sec_out` | 1,0,2 S16 ×0.1 → °C | **VF**, station supply ("Supply actual (1)") |
   | `t_prim_out` | 1,0,3 S16 ×0.1 → °C | **RLF**, return limitation sensor ("Return actual (1)", not in the FW preset) |
   | `heat_energy`, `heat_power`, `flow_prim`, `meter_status`, `t_prim_in` | unmapped | heat meter (group 20, all 16 meters) answers only zeros: no M-Bus data. Meter (2) = 20,1,0/1/2/8/4 once it reports |
   | `t_sec_in` | unmapped | no secondary return sensor on this installation |

   Further real values (AF, YFW valve, heating circuit VF1/MK1/YK1, hot water SF1/SLP1) are in
   `esphome/packages/hoval_plant.yaml`. SF2 is wired but no datapoint was found for it
   (probe of datapoints 0–20 in groups 0, 1, 2, 10).

   Any (group, number, datapoint) works, also ones not in any preset (e.g. from Hoval's
   Modbus datapoint list, `TTE-GW-Modbus-datapoints.xlsx`). An unmapped signal gets
   `poll: never` and stays "unknown".
6. Flash the **production** firmware (`make upload`) and check the logger signals against the
   TopTronic display.

## The vendored, patched component

`esphome/components/toptronic/` is upstream at a pinned commit **plus** the patches in
`patches/toptronic/`. It is generated by `tools/vendor_toptronic.sh` (`make vendor`), and CI
verifies it (`make vendor-check`). Never edit it by hand.

Patch `0002-not-connected-sentinel-as-nan`: a signed value at its minimum (S16 `0x8000`) means
"sensor not connected" and is published as NAN (HA: unknown) instead of -3276.8.

Patch `0003-configurable-gateway-node-id`: hub option `gateway_node_id`, see above.

Patch `0001-optional-presets-late-configure-hub`:
- **`presets: false` hub option.** Upstream always generates every preset entity (~290 for FW,
  including writable ones) and polls them all. With `presets: false`, only the entities
  declared in the YAML are created and polled.
- **Fix: YAML-declared entities were never polled.** Upstream emits `configure_hub()` (which
  wires the polling) inside the hub's code generation, before `sensor: - platform: toptronic`
  entities from the YAML are registered. Those entities got no GET requests. The patch
  emits it from a LATE codegen job.

Both changes are candidates to contribute upstream. Once upstream has an equivalent, drop the
patch and re-vendor.

### Updating upstream

1. Change `REF` in `tools/vendor_toptronic.sh` (read the upstream commits first).
2. `make vendor`. If a patch no longer applies, rebase it (or drop it if upstream fixed it).
3. `make check && make compile`, then check the signal map's datapoints still make sense.

## Known limitations

- **Energy counter precision.** Stored as float: exact to 1 kWh up to ~16.7 million kWh.
- **Discovery bus load.** ~250 datapoints every 30 s on 50 kbit/s is within what upstream runs,
  but use discovery only temporarily, especially if another gateway (HoxPi, Hoval GW) shares the bus.
