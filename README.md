# sbfspot-rpi-build

Cross-compile [SBFspot](https://github.com/SBFspot/SBFspot) for **Raspberry Pi 1 / Pi Zero** (ARMv6 armhf) using GitHub Actions.

## Why?

- Official SBFspot releases only ship `arm` (ARMv7+) and `arm64` binaries
- The Pi 1 and Pi Zero use an ARMv6 CPU — the official binaries won't run
- The `sbfspot-config` installer rejects Debian Trixie
- Compiling on the Pi 1 itself is painfully slow (single-core, 512MB RAM)

This repo builds SBFspot inside a genuine **Raspbian Trixie armhf** rootfs using QEMU emulation on GitHub Actions, producing ABI-correct binaries you can download and run directly on your Pi.

## Supported hardware

Any Raspberry Pi with an **ARMv6** processor running **Raspberry Pi OS (32-bit)**:

- Raspberry Pi 1 Model A/A+/B/B+
- Raspberry Pi Zero / Zero W / Zero WH
- Compute Module 1

## Install

### One-liner (interactive)

On your Pi:

```bash
curl -sL https://raw.githubusercontent.com/kduvekot/sbfspot-rpi1-build/main/setup.sh | sudo bash
```

This downloads the latest [release](../../releases/latest), installs the binaries into `/usr/local/bin/sbfspot.3/`, creates a dedicated `sbfspot` system user, and prompts for your inverter's Bluetooth MAC. Latitude/longitude are auto-detected via IP geolocation (confirm before use). Everything else gets sensible defaults.

### One-liner (flags, no prompts)

```bash
curl -sL https://raw.githubusercontent.com/kduvekot/sbfspot-rpi1-build/main/setup.sh \
  | sudo bash -s -- \
      --inverter 00:80:25:XX:XX:XX \
      --lat 50.80 --lon 4.33 --tz Europe/Amsterdam --locale nl-NL \
      --install-cron --non-interactive
```

### Binaries only (edit config by hand)

```bash
curl -sL https://raw.githubusercontent.com/kduvekot/sbfspot-rpi1-build/main/setup.sh \
  | sudo bash -s -- --skeleton
```

Drops the stock SBFspot default config at `/etc/sbfspot/SBFspot.cfg`, then you edit it manually.

### Flags

| Flag | Default | Notes |
|---|---|---|
| `--inverter <MAC>` | prompt | Repeatable; first is the MIS master. |
| `--lat <decimal>` | geoIP | ipapi.co lookup, asks to confirm. |
| `--lon <decimal>` | geoIP | |
| `--tz <zone>` | `/etc/timezone` | |
| `--locale <code>` | `en-US` | `nl-NL`, `de-DE`, etc. |
| `--run-user <name>` | `sbfspot` | System user created automatically. |
| `--data-dir <path>` | `/var/lib/sbfspot/data` | Where CSVs and `SBFspot.db` live. |
| `--plant-name <str>` | hostname | |
| `--decimal dot\|comma` | from locale | CSV decimal separator. |
| `--password <pw>` | `0000` | SMA factory default. |
| `--install-cron` | off | Installs `/etc/cron.d/sbfspot`. |
| `--cron <spec>` | `*/5 * * * *` | Upstream default polling cadence. |
| `--archive-cron <spec>` | `55 23 * * *` | Daily archive. |
| `--skeleton` | off | Stock config, no prompts. |
| `--non-interactive` | off | Error if required field missing. |
| `--no-geoip` | off | Skip the ipapi.co call. |

Run `setup.sh --help` for the full list.

### Test after install

```bash
sudo -u sbfspot /usr/local/bin/sbfspot.3/SBFspot -v -finq -nocsv -nosql -cfg/etc/sbfspot/SBFspot.cfg
```

### Uninstall / reconfigure

`/etc/cron.d/sbfspot` is a single file — `sudo rm` removes the schedule. To re-template the config, `sudo rm /etc/sbfspot/SBFspot.cfg` and re-run `setup.sh`.

## Manual install (offline / advanced)

If you'd rather unpack the tarball yourself, download it from the [latest release](../../releases/latest) and run the bundled `install.sh`:

```bash
tar xzf sbfspot-armv6-armhf-sqlite.tar.gz
cd sbfspot-armv6-armhf-sqlite
sudo bash install.sh
```

The bundled `install.sh` is the older, simpler installer — it only lays down files and creates the DB, no system user or cron.

## What's included in the artifact

| File | Description |
|------|-------------|
| `SBFspot` | Main binary (SQLite variant) |
| `SBFspotUploadDaemon` | PVoutput.org upload daemon (SQLite variant) |
| `SBFspot.default.cfg` | Default SBFspot configuration |
| `SBFspotUpload.default.cfg` | Default upload daemon configuration |
| `CreateSQLiteDB.sql` | SQLite database schema |
| `TagList*.txt` | Inverter tag definitions (6 languages) |
| `date_time_zonespec.csv` | Timezone definitions |
| `install.sh` | Installation script |

## Runtime dependencies

These must be installed on your Pi (most are pre-installed on Raspberry Pi OS):

```bash
sudo apt install libbluetooth3 libboost-date-time1.83.0 libboost-system1.83.0 \
  libsqlite3-0 libcurl4t64 sqlite3
```

## License

The build infrastructure in this repo (workflow, install script) is provided as-is.
SBFspot itself is licensed under [CC BY-NC-SA 3.0](https://github.com/SBFspot/SBFspot/blob/master/license.md).
