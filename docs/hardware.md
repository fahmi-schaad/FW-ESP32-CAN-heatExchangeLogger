# Hardware

Source: [Schematic.pdf](Schematic.pdf) (4 sheets: Esp devkit rev 1.2, RJ45 connectors, CanBus, Power input — drawn by nliaudat, CC BY-NC-SA 4.0).

## Block diagram

```
 RJ45 IN ─┬─ CAN_H / CAN_L ──> SN65HVD230 ──CAN_TX/RX──> ESP32-WROOM-32 devkit ──WiFi──> Home Assistant
 RJ45 OUT ┘   +12 V ────────> AMS1117-3.3 ──3V3───────────┘
              (pins 4–7 looped through IN→OUT)
```

## ESP32 pin usage

| Signal            | ESP32 GPIO | Devkit pin | Notes |
|-------------------|-----------:|-----------:|-------|
| CAN_TX (→ D)      | GPIO22     | 22 (IO22)  | `can_tx_pin` substitution |
| CAN_RX (← R)      | GPIO21     | 25 (IO21)  | `can_rx_pin` substitution |
| SRCLK (SH_CP)     | GPIO5      | 29         | Net label only, no shift register on these sheets. Strapping pin. Unused in firmware. |
| RCLK (ST_CP)      | GPIO17     | 30         | Net label only, unused in firmware |
| SER (DS)          | GPIO16     | 31         | Net label only, unused in firmware |
| 3V3               | 3.3v       | 1          | From AMS1117 (sheet "Power input") |

Schematic note: do not use GPIO23/24 (TXD0/RXD0 area) for CAN. The firmware follows that.

## CAN transceiver (sheet "CanBus")

- **SN65HVD230** 3.3 V transceiver, 100 nF decoupling.
- **Rs (pin 8)**: 10 kΩ to GND = slope-control mode (the fastest slope). Well suited to the
  Hoval TopTronic bus (50 kbit/s) and reduces EMI on long cables.
- **Termination**: 120 Ω via the `TERMINATOR` jumper. Fit it **only if this board is at one
  physical end of the bus**. On an existing Hoval installation the bus is normally already terminated. A CAN bus needs exactly two 120 Ω terminations (≈ 60 Ω between
  CAN_H and CAN_L with power off).
- `CAN-DEBUG` header: CAN_H (1) / CAN_L (2), for a scope or USB-CAN adapter.
  `CAN-DEBUG1`: +12 V (1) / GND (2).

## RJ45 pinout (both jacks, wired 1:1)

| Pin | Signal |
|----:|--------|
| 1   | CAN_H  |
| 2   | CAN_L  |
| 3   | GND    |
| 4–7 | looped through IN ↔ OUT (not used on this board) |
| 8   | +12 V  |
| shield | GND |

⚠ This is **not** an Ethernet port. Never plug it into a switch or PoE equipment.

## Power (sheet "Power input")

12 V from RJ45 pin 8 → AMS1117-3.3 (10 µF + 100 nF in/out) → 3V3 of the devkit.

### ⚠ Review items for the production batch

1. **AMS1117 thermal load.** A linear regulator from 12 V burns (12 − 3.3) V × I.
   (Check what voltage the Hoval bus actually supplies on pin 8 before relying on it.)
   The ESP32 with WiFi averages 100–150 mA and peaks above 350 mA, which gives **≈ 1–1.3 W
   continuous**. In SOT-223 with typical copper (θJA ≈ 60–90 K/W) that is a 60–120 K rise:
   hot, and it can reach thermal shutdown (random reboots) in a warm plant room.
   Mitigation: a buck converter (e.g. MP1584, TPS62160 or a drop-in 78xx-style buck module)
   instead of, or in front of, the AMS1117. Otherwise use a large copper pour and measure the
   temperature.
2. **Input voltage rating.** The sheet says "12V <= 18V", but the AMS1117's absolute maximum
   input is **15 V**. Do not feed more than 15 V (and less is better, see 1.).
3. **USB and 12 V at the same time.** The devkit's own 3.3 V regulator (USB) and the AMS1117
   then both drive the 3V3 rail. It usually works, but for flashing over USB it is cleaner to
   disconnect the RJ45 power (or flash over OTA once installed).

## First flash

1. Connect the devkit over USB (CP210x/CH340 driver), without the heat exchanger connected.
2. `make upload DEVICE=/dev/ttyUSB0`. Hold BOOT while it connects if the devkit has no auto-reset.
3. After this, all updates go over WiFi: `make upload` (OTA, encrypted with the API key).
