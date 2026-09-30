# Home Assistant integration

## 1. Add the device

With the logger on the network, HA discovers it (Settings → Devices & services → ESPHome).
Otherwise add the ESPHome integration by hand with host `heat-exchanger-logger.local`.
It asks for the **API encryption key**: `api_encryption_key` from `esphome/secrets.yaml`.

Keep the device name `heat-exchanger-logger` / friendly name `Heat Exchanger Logger`: the
entity IDs used below are derived from it.

## 2. Install the package (statistics, KPIs, alerts)

In `configuration.yaml`:

```yaml
homeassistant:
  packages: !include_dir_named packages
```

Copy `packages/heat_exchanger.yaml` to `<config>/packages/heat_exchanger.yaml` and restart HA.

It provides:

| Entity | What |
|--------|------|
| `sensor.heat_exchanger_energy_{daily,weekly,monthly,yearly}` | Heat per period (utility meters, for automations/cards; charts are in the Energy panel) |
| `binary_sensor.heat_exchanger_active` | Power above `input_number.heat_exchanger_active_threshold` |
| `sensor.heat_exchanger_effectiveness` | Thermal effectiveness ε = Q / Q_max [%] |
| `sensor.heat_exchanger_lmtd` | Log-mean temperature difference (counterflow) [K] |
| `sensor.heat_exchanger_ua` | UA = P / LMTD [kW/K]: heat transfer capability |
| `sensor.heat_exchanger_ua_relative` | 24 h mean UA vs. clean reference [%]: fouling indicator |
| `sensor.heat_exchanger_power_24h_{mean,max}` | Rolling statistics |
| `sensor.heat_exchanger_operating_time_today` | Hours active today |
| Automations | Notification on CAN signal loss (10 min), and on UA < 80 % for 24 h |

## 3. Dashboard

Copy `dashboards/heat_exchanger.yaml` to `<config>/dashboards/heat_exchanger.yaml` and add:

```yaml
lovelace:
  dashboards:
    heat-exchanger:
      mode: yaml
      title: Heat exchanger
      icon: mdi:heat-wave
      show_in_sidebar: true
      filename: dashboards/heat_exchanger.yaml
```

## 4. Energy panel (the energy story)

Heat energy is shown in HA's built-in **Energy** panel (sidebar "Energy"): consumption per
hour/day/week/month/year, comparisons and costs.

HA has no dedicated heat/district-heating category. The established way to add a heat meter
is the **gas** slot, which accepts energy sensors in kWh:

1. Settings → Dashboards → Energy (or the sidebar "Energy" → ⋮ → Energy configuration).
2. **Gas consumption → Add gas source** → `sensor.heat_exchanger_logger_heat_energy`
   ("Heat Exchanger Logger Heat energy", kWh).
3. Optional: set a price per kWh (district heating tariff) to get costs.
4. Save. The panel fills from the next full hour on (long-term statistics are hourly).

The panel labels it "Gas". The values are the heat delivered through the heat exchanger,
measured by the Hoval heat meter.

Requirements the sensor already meets: `device_class: energy`, `state_class: total_increasing`,
unit `kWh`. The firmware drops zero and decreasing glitch readings, so a bus glitch cannot
show up as a huge fake consumption spike.

## 5. Setting the UA reference (fouling detection)

After commissioning or after cleaning the heat exchanger:
1. Let it run under typical load for a day.
2. Read `sensor.heat_exchanger_ua_24h_mean`.
3. Enter that value in `input_number.heat_exchanger_ua_reference`.

`UA relative` then tracks the heat transfer capability against the clean state. A slow decline
means fouling or scaling. UA also depends somewhat on flow rates, so compare periods with similar load.

## Data retention

- **Long-term statistics** (hourly mean/min/max, energy sums) are kept **forever** for every
  sensor with a `state_class`. All logger sensors have one, so the dashboard's statistics
  graphs and year-over-year comparisons work indefinitely.
- **Raw states** are purged after `recorder: purge_keep_days` (default 10). The logger
  publishes at most every 10 s per signal (`publish_interval`), about 60k rows/day in total.
  Raise `purge_keep_days` (e.g. 90) if you want detailed raw history, or add InfluxDB
  for high-resolution archival.
- For exports / external analysis: Developer tools → Statistics, or the history download (CSV).
