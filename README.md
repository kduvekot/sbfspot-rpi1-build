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

## Usage

### 1. Trigger the build

Go to [Actions](../../actions) → "Build SBFspot for ARMv6 armhf" → "Run workflow".

Enter the SBFspot version tag (e.g. `V3.9.12`). The build takes ~15-20 minutes.

### 2. Download the artifact

Once the build completes, download `sbfspot-armv6-armhf-sqlite.tar.gz` from the workflow run.

### 3. Install on your Pi

```bash
tar xzf sbfspot-armv6-armhf-sqlite.tar.gz
cd sbfspot-armv6-armhf-sqlite
sudo bash install.sh
```

The installer will:
- Install binaries to `/usr/local/bin/sbfspot.3/`
- Create the SQLite database
- Copy default config files (without overwriting existing ones)

### 4. Configure

Edit `/usr/local/bin/sbfspot.3/SBFspot.cfg`:

```ini
BTAddress=00:00:00:00:00:00     # Your inverter's Bluetooth address (hcitool scan)
Latitude=50.80                   # Your location
Longitude=4.33
Timezone=Europe/Brussels
SQL_Database=/home/pi/smadata/SBFspot.db
OutputPath=/home/pi/smadata/%Y
```

### 5. Test

```bash
# Check version
/usr/local/bin/sbfspot.3/SBFspot -v

# Query inverters (daytime only, or use -finq to force)
/usr/local/bin/sbfspot.3/SBFspot -v -finq -nocsv -nosql
```

### 6. Schedule via crontab

```bash
crontab -e
```

Add:
```cron
# Poll inverters every 2 minutes during daylight
*/2 6-22 * * * /usr/local/bin/sbfspot.3/SBFspot -v -ad0 -am0 -ae0 > /dev/null 2>&1

# Collect daily/monthly archive data once per day before sunrise
55 5 * * * /usr/local/bin/sbfspot.3/SBFspot -v -ad1 -am1 -ae1 > /dev/null 2>&1
```

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
