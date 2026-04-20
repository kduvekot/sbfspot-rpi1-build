# sbfspot-rpi1-build

Pre-compiled [SBFspot](https://github.com/SBFspot/SBFspot) binaries for **Raspberry Pi 1 / Pi Zero** (ARMv6 armhf), plus a one-liner installer.

## Relationship to upstream SBFspot

This repo is **compile-only**. The binary we publish is byte-for-byte what `make sqlite` produces against the pinned upstream tag — no patches, no fork, no behaviour changes. For configuration, usage, troubleshooting and everything else, the upstream wiki is authoritative: <https://github.com/SBFspot/SBFspot/wiki>.

We pin to a specific upstream release tag (currently **[V3.9.12](https://github.com/SBFspot/SBFspot/releases/tag/V3.9.12)**, published 2025-02-22), set in `.github/workflows/build.yml`. Not a branch, not `master`.

Our own release tags look like `v3.9.12-rpi1.N`, where the prefix is the upstream version and `N` is our build number. You can always see which upstream release a binary came from.

## Why this repo exists

- Upstream ships `arm` (ARMv7+) and `arm64` binaries only — they won't run on a Pi 1 / Zero, which is ARMv6 + VFPv2.
- Compiling on the Pi 1 itself is painful (single-core, 512 MB RAM).
- The repo cross-compiles on GitHub Actions inside a genuine Raspbian Trixie armhf rootfs via `debootstrap` + `qemu-arm-static` user-mode emulation, so the ABI (armhf hard-float, ARMv6, `/lib/ld-linux-armhf.so.3`) matches Raspberry Pi OS Lite 32-bit exactly.

## Supported hardware

Any Raspberry Pi with an ARMv6 CPU running Raspberry Pi OS 32-bit (Trixie / Debian 13):

- Raspberry Pi 1 Model A / A+ / B / B+
- Raspberry Pi Zero / Zero W / Zero WH
- Compute Module 1

## Install

### One-liner (interactive, recommended)

On your Pi:

```bash
curl -sL https://raw.githubusercontent.com/kduvekot/sbfspot-rpi1-build/main/setup.sh | sudo bash
```

What this does:

- Downloads the [latest release](../../releases/latest) tarball.
- `apt-get install`s SBFspot's runtime dependencies (`libbluetooth3`, `libboost-*`, `libsqlite3-0`, `libcurl4t64`, `sqlite3`, `libcap2-bin`).
- Installs the binaries to `/usr/local/bin/sbfspot.3/` (matching the upstream Linux/SQLite wiki).
- Creates an `sbfspot` system user with home `/var/lib/sbfspot`.
- Applies `setcap cap_net_raw,cap_net_admin+eip` on the binary so the service user can open raw Bluetooth HCI sockets without being root.
- Creates a SQLite DB at `/var/lib/sbfspot/smadata/SBFspot.db`.
- Prompts for your inverter's Bluetooth MAC (repeat for multi-inverter setups), auto-detects approximate lat/lon via `ipapi.co` and asks to confirm, uses `/etc/timezone` for timezone.
- Templates `/usr/local/bin/sbfspot.3/SBFspot.cfg` with your values (based on upstream's `SBFspot.default.cfg`).

Add `--install-cron` to also drop `/etc/cron.d/sbfspot` with the upstream wiki's recommended schedule (every 5 minutes 06:00–22:00, daily archive at 05:55).

### Non-interactive (flags only)

```bash
curl -sL https://raw.githubusercontent.com/kduvekot/sbfspot-rpi1-build/main/setup.sh \
  | sudo bash -s -- \
      --inverter 00:80:25:XX:XX:XX \
      --lat 50.80 --lon 4.33 --tz Europe/Brussels \
      --install-cron --non-interactive
```

### Binaries only (stock config, edit by hand)

```bash
curl -sL https://raw.githubusercontent.com/kduvekot/sbfspot-rpi1-build/main/setup.sh \
  | sudo bash -s -- --skeleton
```

Drops the unmodified upstream `SBFspot.default.cfg` at `/usr/local/bin/sbfspot.3/SBFspot.cfg`. Edit it yourself following the upstream wiki.

### Flags

| Flag | Default | Notes |
|---|---|---|
| `--inverter <MAC>` | prompt | Repeatable; first is the MIS master. |
| `--lat <decimal>` | geoIP | `ipapi.co` lookup, asks to confirm. |
| `--lon <decimal>` | geoIP | |
| `--tz <zone>` | `/etc/timezone` | |
| `--locale <code>` | `en-US` | `nl-NL`, `de-DE`, `fr-FR`, … |
| `--run-user <name>` | `sbfspot` | Overridable. If it doesn't exist, it's created as a system user. |
| `--data-dir <path>` | `<run-user home>/smadata` | Where CSVs and `SBFspot.db` live. |
| `--plant-name <str>` | hostname | |
| `--decimal dot\|comma` | from locale | CSV decimal separator. |
| `--password <pw>` | `0000` | SMA factory default. |
| `--install-cron` | off | Installs `/etc/cron.d/sbfspot`. |
| `--cron <spec>` | `*/5 6-22 * * *` | Matches upstream wiki. |
| `--archive-cron <spec>` | `55 5 * * *` | Matches upstream wiki. |
| `--skeleton` | off | Stock config, no prompts. |
| `--non-interactive` | off | Error if a required field is missing. |
| `--no-geoip` | off | Skip the ipapi.co call entirely. |

Run `setup.sh --help` for the full list.

### Test after install

```bash
sudo -u sbfspot /usr/local/bin/sbfspot.3/SBFspot -v -finq -nocsv -nosql
```

This forces a Bluetooth handshake (`-finq` bypasses the daylight gate), prints everything the inverter reports, and writes nothing. A good first smoke test.

### Uninstall / reconfigure

- `sudo rm /etc/cron.d/sbfspot` — removes the schedule (one file).
- `sudo rm /usr/local/bin/sbfspot.3/SBFspot.cfg` and re-run `setup.sh` — re-templates your config.
- `sudo userdel sbfspot && sudo rm -rf /var/lib/sbfspot /var/log/sbfspot.3 /usr/local/bin/sbfspot.3` — full removal.

## Deviations from the upstream wiki install

We follow the [upstream Linux/SQLite wiki](https://github.com/SBFspot/SBFspot/wiki/Installation-Linux-SQLite) for install dir, config location, cron cadence and everything in the config itself. Three deliberate deviations:

1. **Dedicated `sbfspot` system user** instead of running as `pi`. Least privilege, clean uninstall, overridable with `--run-user`.
2. **`setcap cap_net_raw,cap_net_admin+eip` on the binary.** Raw HCI sockets (needed for SMA's custom Bluetooth protocol) require `CAP_NET_RAW`; the `bluetooth` group alone isn't enough. The wiki is silent on this; our choice makes non-root operation actually work.
3. **System-level `/etc/cron.d/sbfspot`** instead of the wiki's user crontab. Uninstall is one `rm`; no per-user state.

Everything else — install directory, config file next to binary, cron window, archive time, flag usage — matches the wiki.

## Manual install (offline / advanced)

If you don't want to curl-pipe a script, download the tarball from the [latest release](../../releases/latest) and run the bundled `install.sh`:

```bash
tar xzf sbfspot-armv6-armhf-sqlite.tar.gz
cd sbfspot-armv6-armhf-sqlite
sudo bash install.sh
```

`install.sh` is the simpler variant: it places files and creates the SQLite DB, but does not create the `sbfspot` user, does not apply `setcap`, and does not install cron. If you use it, follow the upstream wiki for the rest of the setup.

## What's in the artifact

| File | Description |
|---|---|
| `SBFspot` | Main binary (SQLite variant, ARMv6 armhf) |
| `SBFspotUploadDaemon` | PVoutput.org upload daemon (SQLite variant) |
| `SBFspot.default.cfg` | Upstream default config (unmodified) |
| `SBFspotUpload.default.cfg` | Upstream default upload config (unmodified) |
| `CreateSQLiteDB.sql` | Upstream SQLite schema |
| `TagList*.txt` | Upstream inverter tag definitions (6 languages) |
| `date_time_zonespec.csv` | Upstream timezone table |
| `install.sh` | Legacy offline installer |

## License

The build infrastructure in this repo (workflow, `setup.sh`, `install.sh`) is provided as-is. SBFspot itself is licensed under [CC BY-NC-SA 3.0](https://github.com/SBFspot/SBFspot/blob/master/license.md).
