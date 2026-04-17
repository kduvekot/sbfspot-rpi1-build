# sbfspot-rpi-build

## What this repo does

Cross-compiles [SBFspot](https://github.com/SBFspot/SBFspot) for Raspberry Pi 1 (ARMv6 armhf)
using GitHub Actions. SBFspot reads power production data from SMA solar inverters via Bluetooth
or Speedwire and stores it in SQLite/MySQL/CSV/MQTT.

Official SBFspot releases only provide ARMv7+ (`arm`) and `arm64` binaries.
The Pi 1 is ARMv6, so it needs a dedicated build. This repo provides that.

## Architecture

### Build approach: debootstrap + QEMU user-mode

The workflow creates a genuine **Raspbian Trixie armhf** rootfs via `debootstrap`
on the x86 GitHub Actions runner, then uses `qemu-arm-static` user-mode emulation
to chroot into it and compile. This produces binaries with the correct ABI
(armhf, hard-float, ARMv6, `/lib/ld-linux-armhf.so.3`).

### Why not simpler approaches

- `debian:trixie --platform linux/arm/v6` → falls back to **armel** (soft-float),
  wrong ABI. Raspberry Pi OS uses **armhf**.
- `debian:trixie --platform linux/arm/v7` → standard Debian armhf is ARMv7+.
  The glibc crt startup code may contain ARMv7 instructions that crash on ARMv6.
- `arm32v6/alpine` → musl libc, not glibc. Binaries won't run on Raspberry Pi OS
  unless statically linked.
- No official Raspberry Pi OS Docker image exists for Trixie.

### Target platform: Raspberry Pi 1 (all revisions)

- CPU: ARM1176JZF-S — ARMv6 with VFPv2
- ABI: armhf (hard-float)
- OS: Raspberry Pi OS Lite 32-bit (Raspbian Trixie / Debian 13)
- Dynamic linker: `/lib/ld-linux-armhf.so.3`
- Lib path: `/lib/arm-linux-gnueabihf/`
- RAM: 256MB (Model A) or 512MB (Model B)
- Also works on: Pi Zero, Pi Zero W (same ARMv6 SoC)

### SBFspot build variant

- SQLite only (not MySQL/MariaDB) — simplest for single-board setups
- Bluetooth support enabled (`libbluetooth`)
- Includes SBFspotUploadDaemon (for optional PVoutput.org uploads)

### Linked libraries at runtime

SBFspot: `pthread`, `bluetooth`, `boost_date_time`, `boost_system`, `sqlite3`
SBFspotUploadDaemon: `pthread`, `curl`, `sqlite3`

## Files

- `.github/workflows/build.yml` — The build + verify + package workflow
- `install.sh` — Generic installer script for the Pi (run after downloading artifact)

## Key decisions and known issues

### __USE_TIME_BITS64 warning
Every compilation unit produces `oslinux.h:45:12: warning: "__USE_TIME_BITS64" redefined`.
This is an upstream SBFspot issue (fix for #692). Harmless — both definitions enable
64-bit time, just different syntax. Do not try to fix this in the build workflow.

### Verification stage
After building, the workflow strips -dev packages from the rootfs and verifies binaries
run with only runtime libs installed. Checks: ELF arch, ABI tags, ldd resolution,
SBFspot version output, SQLite support flag, database schema creation.

### SBFspot is run-once-and-exit
SBFspot has no daemon/loop mode. It connects to inverters, queries data, writes to
DB/CSV/MQTT, and exits. Continuous operation comes from cron or a wrapper loop.
The Docker container's `start.sh` runs it in a `while true` loop with configurable
`SBFSPOT_INTERVAL` (default 300s, minimum 60s).

### Bluetooth polling limits
Each SBFspot run does a full BT connect → authenticate → query → disconnect cycle.
For 2 inverters via Bluetooth, each run takes ~15-30 seconds. Minimum practical
polling interval is ~60 seconds. Recommended: every 2-5 minutes.

## Development workflow

1. Edit workflow or install script
2. Push to trigger build (or use `workflow_dispatch` with version input)
3. Wait ~15-20 minutes for QEMU-emulated compilation
4. Download artifact from Actions tab
5. Test on a real Pi

## Testing on the Pi

```bash
# Verify binary
/usr/local/bin/sbfspot.3/SBFspot -version
/usr/local/bin/sbfspot.3/SBFspot -?

# Test with inverter (daytime only unless -finq)
/usr/local/bin/sbfspot.3/SBFspot -v -finq -nocsv -nosql

# Check ABI
readelf -A /usr/local/bin/sbfspot.3/SBFspot | grep -E "Tag_CPU|Tag_FP"
# Should show: Tag_CPU_name: "6", Tag_FP_arch: VFPv2
```
