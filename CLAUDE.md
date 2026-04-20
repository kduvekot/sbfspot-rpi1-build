# sbfspot-rpi1-build

## What this repo is

A **compile-only** project: cross-compiles [SBFspot](https://github.com/SBFspot/SBFspot)
for Raspberry Pi 1 / Zero (ARMv6 armhf) and publishes a GitHub Release with the tarball
plus a `setup.sh` one-liner installer. The SBFspot binary we publish is byte-for-byte
what upstream's `make sqlite` produces on ARMv6 — we do not patch, fork, or modify
upstream behaviour. For usage, configuration and troubleshooting, upstream's wiki is
authoritative: <https://github.com/SBFspot/SBFspot/wiki>.

Why this repo exists: upstream only ships ARMv7+ / arm64 binaries. The Pi 1 and Pi Zero
are ARMv6 (ARM1176JZF-S, VFPv2), so they need a dedicated build.

## Upstream pinning

`.github/workflows/build.yml` pins `SBFSPOT_VERSION=V3.9.12` (upstream tag, released
2025-02-22). Not `master`, not a branch. To rebuild against a newer upstream release,
trigger the workflow manually with the new tag as the input.

## Architecture

**Build:** `ubuntu-latest` runner → `debootstrap` a Raspbian Trixie armhf rootfs →
`qemu-arm-static` user-mode chroot into it → `make sqlite` inside. Produces
armhf/ARMv6/VFPv2 ELF with dynamic linker `/lib/ld-linux-armhf.so.3`. Functionally
equivalent to pi-gen stage 0 — see README "How it's built" for the full mapping
and the rationale for not depending on pi-gen directly.

**Why debootstrap + QEMU (vs simpler options):**
- `debian:trixie --platform linux/arm/v6` falls back to armel (soft-float, wrong ABI).
- `debian:trixie --platform linux/arm/v7` is ARMv7+; crt0 can contain ARMv7 instructions that crash on ARMv6.
- `arm32v6/alpine` is musl, not glibc — incompatible with Raspberry Pi OS.
- No official Raspberry Pi OS Docker image exists.

**Raspbian keyring:** debootstrap needs `raspbian-archive-keyring`, which isn't in
Ubuntu's repos. The workflow fetches the `.deb` directly from `archive.raspbian.org`
and installs it before debootstrap runs.

**Verification stage:** after build, strips `-dev` packages from the rootfs, installs
only runtime libs, then checks: ELF class, `Tag_CPU_arch=v6`, `Tag_FP_arch=VFPv2`,
ldd resolution, `SBFspot -version`, SQLite support flag, schema creation.

**Release publishing:** separate job after build. Tag `v<sbfspot-version>-rpi1.<run_number>`
(e.g. `v3.9.12-rpi1.7`). Pre-release flag set when branch ≠ `main` (tag gets `-dev` suffix).

## Files

- `.github/workflows/build.yml` — build + verify + package + release
- `setup.sh` — one-liner installer (curl-pipeable from raw.githubusercontent.com)
- `install.sh` — legacy offline installer bundled in the tarball (no service user, no cron)
- `README.md` — user documentation
- `CLAUDE.md` — this file

## Deviations from the upstream wiki install

All four have reasons; otherwise we stay wiki-exact (install dir, config
location, archive time, example coords, etc.).

1. **Dedicated `sbfspot` system user** (wiki uses `pi`). Cleaner uninstall, least
   privilege. Overridable via `--run-user`.
2. **`setcap cap_net_raw,cap_net_admin+eip`** (wiki silent). Raw HCI sockets require
   `CAP_NET_RAW`; the `bluetooth` group alone isn't enough for SMA's custom protocol.
3. **`/etc/cron.d/sbfspot`** (wiki uses a user crontab). System-level file; uninstall
   is one `rm`.
4. **Location-optimised cron window** (wiki fixes `*/5 6-22 * * *`, which misses
   ~45 min of morning data at Ukkel/50.8°N on the summer solstice). Default profile
   is `location` — solar-geometry formula in awk, no external service. `upstream`,
   `24x7`, and `custom` profiles available via `--cron-profile`.

Nothing else changes the binary's behaviour.

## Key gotchas

**`__USE_TIME_BITS64` redefined** warning on every compile unit. Upstream issue
(SBFspot fix for #692). Harmless, both macros enable 64-bit time. Do not try to
"fix" it in the workflow.

**SBFspot is run-once-and-exit.** No daemon loop. Continuous operation comes from
cron. Each BT run takes ~15-30s for 2 inverters; minimum practical interval is ~60s.
Upstream recommends 5 minutes (wiki) / 300s (Docker `SBFSPOT_INTERVAL`).

**Tarball-level install.sh is legacy.** Real users curl `setup.sh`; the bundled
`install.sh` is kept for offline/advanced use only and does not create the service
user or cron file.

## Development

1. Edit workflow or scripts on a feature branch (currently `claude/...`).
2. Push → triggers build + pre-release (`-dev` suffix).
3. Test on the Pi with `--release <tag>`.
4. Merge to `main` → triggers stable release; `latest` resolves to it.

## Testing on the Pi

```bash
/usr/local/bin/sbfspot.3/SBFspot -version
readelf -A /usr/local/bin/sbfspot.3/SBFspot | grep -E "Tag_CPU|Tag_FP"
sudo -u sbfspot /usr/local/bin/sbfspot.3/SBFspot -v -finq -nocsv -nosql
```
