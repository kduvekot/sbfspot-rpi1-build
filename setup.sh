#!/usr/bin/env bash
#
# setup.sh - one-shot installer for the SBFspot ARMv6 armhf build.
#
# Downloads the latest release tarball from this repo, installs binaries
# into /usr/local/bin/sbfspot.3/ (matching the upstream SBFspot Linux/SQLite
# wiki), creates an 'sbfspot' system user, templates SBFspot.cfg from flags
# or 2-3 interactive prompts, and optionally installs a cron schedule.
#
# Upstream: https://github.com/SBFspot/SBFspot
# Wiki:     https://github.com/SBFspot/SBFspot/wiki/Installation-Linux-SQLite
#
# This script only arranges the install; the SBFspot binary itself is
# byte-for-byte what upstream's `make sqlite` produces on ARMv6. For
# configuration, usage and troubleshooting refer to the upstream wiki.

set -euo pipefail

REPO="kduvekot/sbfspot-rpi1-build"
INSTALL_DIR="/usr/local/bin/sbfspot.3"
LOG_DIR="/var/log/sbfspot.3"
SERVICE_USER="sbfspot"
SERVICE_HOME="/var/lib/sbfspot"
CRON_FILE="/etc/cron.d/sbfspot"
GEOIP_URL="https://ipapi.co/json/"

# ---- defaults (empty = derive/prompt) ------------------------------------
RELEASE=""
SKELETON=0
NON_INTERACTIVE=0
INSTALL_CRON=0
NO_GEOIP=0

RUN_USER=""
DATA_DIR=""
INVERTERS=()
LAT=""
LON=""
PLANT_NAME=""
TIMEZONE=""
LOCALE="en-US"
DECIMAL=""
PASSWORD="0000"
# Defaults mirror the upstream SBFspot wiki cron recommendation.
CRON_POLL=""            # resolved from profile below; empty = not explicitly set
CRON_ARCHIVE="55 5 * * *"
CRON_PROFILE=""         # upstream | location | 24x7 | custom (set by flags or prompt)

usage() {
    cat <<EOF
Usage: sudo bash setup.sh [flags]

Required (if not using --skeleton, prompted interactively when omitted):
  --inverter <BT-MAC>       Inverter Bluetooth address (repeat for MIS).
                            First one is written as BTAddress (the MIS master).
  --lat <decimal>           Latitude, e.g. 50.80. Auto-detected via IP geolocation if omitted.
  --lon <decimal>           Longitude, e.g. 4.33. Auto-detected via IP geolocation if omitted.

Optional (sensible defaults, silent unless overridden):
  --run-user <name>         User to own data and run cron. Default: ${SERVICE_USER}
                            (created as a system user if missing).
  --data-dir <path>         Data + DB directory. Default: \${home-of-run-user}/smadata
                            (i.e. ${SERVICE_HOME}/smadata for the default service user).
  --plant-name <str>        Plantname in config. Default: system hostname.
  --tz <zone>               Timezone, e.g. Europe/Brussels. Default: /etc/timezone.
  --locale <code>           SBFspot locale, e.g. en-US, nl-NL. Default: en-US.
  --decimal <dot|comma>     CSV decimal separator. Default: derived from locale.
  --password <pw>           SMA user password. Default: 0000 (SMA factory default).

Modes:
  --install-cron            Install /etc/cron.d/sbfspot. Schedule is picked from
                            --cron-profile (or prompted interactively if omitted).
  --cron-profile <name>     Pick a polling-schedule preset. Implies --install-cron.
                            upstream  - */5 6-22 * * *  (matches SBFspot wiki)
                            location  - computed from lat/lon to cover the summer
                                        solstice with a 1-hour buffer on each side
                                        (this is our recommended default)
                            24x7      - */5 * * * *  (SBFspot's internal gate decides)
                            custom    - requires --cron <spec>
  --cron "<spec>"           Override polling cron (implies --cron-profile custom).
  --archive-cron "<spec>"   Override archive cron (default: 55 5 * * *).
  --skeleton                Install binaries only, drop the stock default config
                            at ${INSTALL_DIR}/SBFspot.cfg unchanged. No prompts.
  --non-interactive         Never prompt. Error if a required field is missing.
  --no-geoip                Don't call ipapi.co for lat/lon; prompt or require flags.

Advanced:
  --release <tag>           Pin to a specific release tag (default: latest non-prerelease).

Examples:
  # Fully interactive — prompts only for inverter MAC(s) and confirms geo-lookup:
  curl -sL https://raw.githubusercontent.com/${REPO}/main/setup.sh | sudo bash

  # Fully non-interactive:
  curl -sL https://raw.githubusercontent.com/${REPO}/main/setup.sh | sudo bash -s -- \\
      --inverter 00:80:25:XX:XX:X1 --inverter 00:80:25:XX:XX:X2 \\
      --lat 50.80 --lon 4.33 --tz Europe/Brussels \\
      --install-cron --non-interactive

  # Binaries only, hand-edit config later:
  curl -sL https://raw.githubusercontent.com/${REPO}/main/setup.sh | sudo bash -s -- --skeleton
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">>> $*"; }
warn() { echo "WARN: $*" >&2; }

# ---- parse flags ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)         RELEASE="$2"; shift 2;;
        --run-user)        RUN_USER="$2"; shift 2;;
        --data-dir)        DATA_DIR="$2"; shift 2;;
        --inverter)        INVERTERS+=("$2"); shift 2;;
        --lat)             LAT="$2"; shift 2;;
        --lon)             LON="$2"; shift 2;;
        --plant-name)      PLANT_NAME="$2"; shift 2;;
        --tz|--timezone)   TIMEZONE="$2"; shift 2;;
        --locale)          LOCALE="$2"; shift 2;;
        --decimal)         DECIMAL="$2"; shift 2;;
        --password)        PASSWORD="$2"; shift 2;;
        --install-cron)    INSTALL_CRON=1; shift;;
        --cron-profile)    CRON_PROFILE="$2"; INSTALL_CRON=1; shift 2;;
        --cron)            CRON_POLL="$2"; CRON_PROFILE="custom"; INSTALL_CRON=1; shift 2;;
        --archive-cron)    CRON_ARCHIVE="$2"; INSTALL_CRON=1; shift 2;;
        --skeleton)        SKELETON=1; NON_INTERACTIVE=1; shift;;
        --non-interactive) NON_INTERACTIVE=1; shift;;
        --no-geoip)        NO_GEOIP=1; shift;;
        -h|--help)         usage; exit 0;;
        *)                 die "Unknown flag: $1 (run with --help)";;
    esac
done

# ---- preflight -----------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

ARCH="$(uname -m)"
case "$ARCH" in
    armv6l|armv7l) ;;
    *) warn "This build targets ARMv6 armhf; running on $ARCH — binaries will not execute." ;;
esac

for cmd in curl tar; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd."
done

# Install SBFspot's runtime libs + tools the installer itself needs.
# Package names track Trixie (Debian 13 / Raspberry Pi OS Lite 12+); the
# binary is built against these so mismatched releases will get a clear
# apt error rather than a confusing runtime failure.
APT_PACKAGES=(
    libbluetooth3
    libboost-date-time1.83.0
    libboost-system1.83.0
    libsqlite3-0
    libcurl4t64
    sqlite3
    libcap2-bin
)
info "Installing runtime dependencies via apt-get"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"

for cmd in sqlite3 setcap useradd; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing $cmd after apt-get install — check apt output above."
done

prompt() {
    local q="$1" def="${2:-}" ans
    if [[ $NON_INTERACTIVE == 1 ]]; then
        [[ -n "$def" ]] && { echo "$def"; return; }
        die "Missing value and --non-interactive set: $q"
    fi
    if [[ -n "$def" ]]; then
        read -r -p "$q [$def]: " ans < /dev/tty || true
    else
        read -r -p "$q: " ans < /dev/tty || true
    fi
    echo "${ans:-$def}"
}

# ---- download release ----------------------------------------------------
info "Fetching release metadata..."
if [[ -z "$RELEASE" ]]; then
    API_URL="https://api.github.com/repos/${REPO}/releases/latest"
else
    API_URL="https://api.github.com/repos/${REPO}/releases/tags/${RELEASE}"
fi
RELEASE_JSON="$(curl -sfL "$API_URL")" || die "Failed to fetch release from $API_URL"
TAG="$(echo "$RELEASE_JSON" | grep -oE '"tag_name":\s*"[^"]+"' | head -1 | cut -d'"' -f4)"
TARBALL_URL="$(echo "$RELEASE_JSON" | grep -oE '"browser_download_url":\s*"[^"]+\.tar\.gz"' | head -1 | cut -d'"' -f4)"
[[ -n "$TAG" && -n "$TARBALL_URL" ]] || die "Could not parse release metadata (tag=$TAG url=$TARBALL_URL)."

info "Installing SBFspot from release $TAG"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
curl -sfL "$TARBALL_URL" -o "$TMPDIR/sbfspot.tar.gz" || die "Download failed: $TARBALL_URL"
tar -xzf "$TMPDIR/sbfspot.tar.gz" -C "$TMPDIR"
PKG_DIR="$(find "$TMPDIR" -maxdepth 1 -type d -name 'sbfspot-*' | head -1)"
[[ -d "$PKG_DIR" ]] || die "Unexpected tarball layout — no sbfspot-* directory."

# ---- service user --------------------------------------------------------
[[ -n "$RUN_USER" ]] || RUN_USER="$SERVICE_USER"
if [[ "$RUN_USER" == "$SERVICE_USER" ]]; then
    if ! id "$SERVICE_USER" &>/dev/null; then
        info "Creating system user '$SERVICE_USER' (home $SERVICE_HOME)"
        useradd --system --home-dir "$SERVICE_HOME" --create-home \
                --shell /usr/sbin/nologin --user-group "$SERVICE_USER"
    fi
    RUN_HOME="$SERVICE_HOME"
else
    id "$RUN_USER" &>/dev/null || die "User '$RUN_USER' does not exist. Create it or pass a different --run-user."
    RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
fi

if getent group bluetooth >/dev/null; then
    usermod -a -G bluetooth "$RUN_USER" || true
fi

[[ -n "$DATA_DIR" ]] || DATA_DIR="$RUN_HOME/smadata"

# ---- install files -------------------------------------------------------
info "Installing binaries to $INSTALL_DIR"
install -d -m 755 "$INSTALL_DIR" "$LOG_DIR" "$DATA_DIR"
install -m 755 "$PKG_DIR/SBFspot"              "$INSTALL_DIR/SBFspot"
install -m 755 "$PKG_DIR/SBFspotUploadDaemon"  "$INSTALL_DIR/SBFspotUploadDaemon"
install -m 644 "$PKG_DIR"/TagList*.txt         "$INSTALL_DIR/"
install -m 644 "$PKG_DIR/date_time_zonespec.csv" "$INSTALL_DIR/"
install -m 644 "$PKG_DIR/CreateSQLiteDB.sql"   "$INSTALL_DIR/"
install -m 644 "$PKG_DIR/SBFspot.default.cfg"  "$INSTALL_DIR/SBFspot.default.cfg"
install -m 644 "$PKG_DIR/SBFspotUpload.default.cfg" "$INSTALL_DIR/SBFspotUpload.default.cfg"

# Raw HCI socket access (for SMA's custom Bluetooth protocol) requires
# CAP_NET_RAW; the 'bluetooth' group alone isn't enough. Silent on the
# upstream wiki, but needed for any non-root run.
info "Granting CAP_NET_RAW / CAP_NET_ADMIN on SBFspot"
setcap cap_net_raw,cap_net_admin+eip "$INSTALL_DIR/SBFspot"

DB_FILE="$DATA_DIR/SBFspot.db"
if [[ ! -f "$DB_FILE" ]]; then
    info "Creating SQLite database at $DB_FILE"
    sqlite3 "$DB_FILE" < "$INSTALL_DIR/CreateSQLiteDB.sql" >/dev/null
fi

chown -R "$RUN_USER:$RUN_USER" "$DATA_DIR" "$LOG_DIR"

# ---- config file ---------------------------------------------------------
# Upstream wiki keeps SBFspot.cfg alongside the binary; SBFspot's default
# lookup is $INSTALL_DIR/SBFspot.cfg, so no -cfg flag is needed in cron.
CFG="$INSTALL_DIR/SBFspot.cfg"
UPLOAD_CFG="$INSTALL_DIR/SBFspotUpload.cfg"

if [[ $SKELETON == 1 ]]; then
    if [[ -f "$CFG" ]]; then
        info "Config exists at $CFG — leaving unchanged."
    else
        info "Skeleton mode — copying default config to $CFG (unmodified)"
        install -m 640 "$INSTALL_DIR/SBFspot.default.cfg" "$CFG"
    fi
    [[ -f "$UPLOAD_CFG" ]] || install -m 640 "$INSTALL_DIR/SBFspotUpload.default.cfg" "$UPLOAD_CFG"
    chown root:"$RUN_USER" "$CFG" "$UPLOAD_CFG"
    echo
    info "Skeleton install complete. Edit $CFG to set BTAddress, Latitude, Longitude, etc."
    exit 0
fi

if [[ -f "$CFG" ]]; then
    info "Existing $CFG found — not overwriting. Use --skeleton or delete it first."
else
    if [[ ${#INVERTERS[@]} -eq 0 ]]; then
        while :; do
            mac="$(prompt "Inverter Bluetooth MAC (blank to finish)" "")"
            [[ -z "$mac" ]] && break
            INVERTERS+=("$mac")
        done
        [[ ${#INVERTERS[@]} -gt 0 ]] || die "At least one --inverter required."
    fi
    for mac in "${INVERTERS[@]}"; do
        [[ "$mac" =~ ^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$ ]] || die "Not a valid BT MAC: $mac"
    done

    if [[ -z "$LAT" || -z "$LON" ]]; then
        geo_lat=""; geo_lon=""; geo_city=""; geo_tz=""
        if [[ $NO_GEOIP == 0 ]]; then
            info "Fetching approximate location from $GEOIP_URL (IP-based)"
            geo_json="$(curl -sfL "$GEOIP_URL" 2>/dev/null || true)"
            geo_lat="$(echo "$geo_json"  | grep -oE '"latitude":\s*[-0-9.]+'  | head -1 | grep -oE '[-0-9.]+$' || true)"
            geo_lon="$(echo "$geo_json"  | grep -oE '"longitude":\s*[-0-9.]+' | head -1 | grep -oE '[-0-9.]+$' || true)"
            geo_city="$(echo "$geo_json" | grep -oE '"city":\s*"[^"]*"'       | head -1 | cut -d'"' -f4)"
            geo_tz="$(echo "$geo_json"   | grep -oE '"timezone":\s*"[^"]*"'   | head -1 | cut -d'"' -f4)"
        fi
        if [[ -n "$geo_lat" && -n "$geo_lon" ]]; then
            info "ipapi.co says: ${geo_city:-?} @ ($geo_lat, $geo_lon) — tz=${geo_tz:-?}"
            ans="$(prompt "Use this location?" "Y")"
            case "$ans" in
                Y|y|Yes|yes|"")
                    LAT="${LAT:-$geo_lat}"; LON="${LON:-$geo_lon}"
                    [[ -z "$TIMEZONE" && -n "$geo_tz" ]] && TIMEZONE="$geo_tz"
                    ;;
            esac
        fi
        [[ -z "$LAT" ]] && LAT="$(prompt "Latitude (decimal, e.g. 50.80)" "")"
        [[ -z "$LON" ]] && LON="$(prompt "Longitude (decimal, e.g. 4.33)" "")"
        [[ -n "$LAT" && -n "$LON" ]] || die "Latitude/Longitude required."
    fi

    if [[ -z "$TIMEZONE" ]]; then
        [[ -r /etc/timezone ]] && TIMEZONE="$(tr -d '[:space:]' </etc/timezone || true)"
        [[ -z "$TIMEZONE" ]] && TIMEZONE="$(prompt "Timezone (e.g. Europe/Brussels)" "Europe/Brussels")"
    fi

    [[ -n "$PLANT_NAME" ]] || PLANT_NAME="$(hostname -s 2>/dev/null || echo MyPlant)"

    if [[ -z "$DECIMAL" ]]; then
        case "$LOCALE" in
            nl-*|de-*|fr-*|es-*|it-*|pt-*) DECIMAL="comma";;
            *)                             DECIMAL="point";;
        esac
    fi

    MIS=0
    [[ ${#INVERTERS[@]} -gt 1 ]] && MIS=1

    info "Writing $CFG"
    cp "$INSTALL_DIR/SBFspot.default.cfg" "$CFG"

    set_key() {
        local key="$1" val="$2" esc
        esc=$(printf '%s' "$val" | sed -e 's/[&|/]/\\&/g')
        if grep -qE "^${key}=" "$CFG"; then
            sed -i -E "s|^${key}=.*|${key}=${esc}|" "$CFG"
        elif grep -qE "^#\s*${key}=" "$CFG"; then
            sed -i -E "0,/^#\s*${key}=.*/s||${key}=${esc}|" "$CFG"
        else
            printf '\n%s=%s\n' "$key" "$val" >> "$CFG"
        fi
    }

    set_key BTAddress         "${INVERTERS[0]}"
    set_key Password          "$PASSWORD"
    set_key MIS_Enabled       "$MIS"
    set_key Plantname         "$PLANT_NAME"
    set_key OutputPath        "$DATA_DIR/%Y"
    set_key OutputPathEvents  "$DATA_DIR/%Y/Events"
    set_key Latitude          "$LAT"
    set_key Longitude         "$LON"
    set_key Locale            "$LOCALE"
    set_key Timezone          "$TIMEZONE"
    set_key DecimalPoint      "$DECIMAL"
    set_key SQL_Database      "$DB_FILE"

    chmod 640 "$CFG"
    chown root:"$RUN_USER" "$CFG"
fi

if [[ ! -f "$UPLOAD_CFG" ]]; then
    install -m 640 "$INSTALL_DIR/SBFspotUpload.default.cfg" "$UPLOAD_CFG"
    chown root:"$RUN_USER" "$UPLOAD_CFG"
fi

# ---- cron profile resolution --------------------------------------------
# Computes a cron polling window that covers sunrise-to-sunset on the summer
# solstice (the longest day of the year) for the given lat/lon/tz, plus a
# 1-hour safety buffer each side. Prints a cron spec like "*/5 4-23 * * *".
# Falls back to "*/5 * * * *" if lat is inside an Arctic circle.
compute_location_cron() {
    local lat="$1" lon="$2" tz="$3"
    local year solstice
    year=$(date +%Y)
    if awk -v lat="$lat" 'BEGIN{exit !(lat+0 >= 0)}'; then
        solstice="${year}-06-21"      # Northern hemisphere longest day
    else
        solstice="${year}-12-21"      # Southern hemisphere longest day
    fi

    # UTC noon on the solstice -> local wall-clock hour (handles TZ + DST).
    local noon_local_h
    noon_local_h=$(TZ="$tz" date -d "${solstice}T12:00:00Z" +%H:%M 2>/dev/null \
        | awk -F: '{printf "%.4f\n", $1 + $2/60}')
    [[ -n "$noon_local_h" ]] || { echo "*/5 4-23 * * *"; return; }

    # Compute daylight length + cron hour range via awk (all floating-point
    # math done once, in a single invocation). Emits two lines: the cron spec,
    # then a reason code ("", "arctic", "midnight-cross") so the caller can
    # print a targeted warning when the fallback triggers.
    awk -v lat="$lat" -v lon="$lon" -v noon_h="$noon_local_h" 'BEGIN {
        PI = 3.14159265358979323846
        d2r = PI/180
        decl = 23.44 * d2r                       # solstice declination (rad)
        al = (lat < 0 ? -lat : lat) * d2r        # |latitude| in rad
        # cos(H) = -tan(al) * tan(decl); |c|>=1 means 24h daylight (midnight sun)
        # or 24h night (polar night). Either way, a daylight-sized cron range
        # is meaningless — use 24/7 and let SBFspot decide.
        c = -sin(al)/cos(al) * sin(decl)/cos(decl)
        if (c >= 1 || c <= -1) { print "*/5 * * * *"; print "arctic"; exit }
        H_rad = atan2(sqrt(1-c*c), c)            # acos(c) via atan2
        daylight = 2 * H_rad / d2r / 15          # hours of daylight
        # Near-arctic: 20+ hours of daylight, not quite midnight sun.
        if (daylight > 20) { print "*/5 * * * *"; print "arctic"; exit }
        # Solar noon in local wall-clock time: local time of 12Z - longitude/15
        solar_noon = noon_h - lon/15
        sunrise = solar_noon - daylight/2
        sunset  = solar_noon + daylight/2
        # Safety buffer of 1 hour on each side.
        start_h = sunrise - 1
        end_h   = sunset  + 1
        # If the daylight window wraps past midnight in the chosen timezone
        # (lat/lon far from the natural longitude of the chosen TZ) a single-
        # range cron cannot express it. Fall back to 24/7.
        if (start_h < 0 || end_h > 24) {
            print "*/5 * * * *"; print "midnight-cross"; exit
        }
        # Round outward to whole hours.
        start = int(start_h);  if (start_h < start) start--
        end   = int(end_h);    if (end_h   > end)   end++
        if (start < 0)  start = 0
        if (end > 23)   end = 23
        if (start >= end) { print "*/5 * * * *"; print "midnight-cross"; exit }
        printf "*/5 %d-%d * * *\n", start, end
        print ""   # empty reason line for the "normal" case
    }'
}

# ---- cron ----------------------------------------------------------------
if [[ $INSTALL_CRON == 1 ]]; then
    # Resolve the profile (interactive prompt if nothing set).
    if [[ -z "$CRON_PROFILE" ]]; then
        if [[ $NON_INTERACTIVE == 1 ]]; then
            CRON_PROFILE="location"
        else
            { read -r loc_preview; read -r loc_reason; } < <(compute_location_cron "$LAT" "$LON" "$TIMEZONE")
            loc_note=""
            case "$loc_reason" in
                arctic)         loc_note="  — same as option 3; your latitude (${LAT}°) has 20+ h of daylight on the solstice";;
                midnight-cross) loc_note="  — same as option 3; your daylight window crosses midnight in TZ=$TIMEZONE";;
            esac
            echo
            echo "Cron schedule — SBFspot internally gates on Latitude/Longitude + SunRSOffset,"
            echo "so the window below only affects how often we *try*. Pick one:"
            echo "  1) Upstream default       */5 6-22 * * *  (matches wiki; may miss summer mornings north of ~49°N)"
            echo "  2) Location-optimized     ${loc_preview}${loc_note}"
            echo "  3) 24/7                   */5 * * * *     (lightest logic)"
            echo "  4) Custom                 (you type a cron expression)"
            choice="$(prompt "Choice" "2")"
            case "$choice" in
                1) CRON_PROFILE="upstream";;
                2|"") CRON_PROFILE="location";;
                3) CRON_PROFILE="24x7";;
                4) CRON_PROFILE="custom"
                   CRON_POLL="$(prompt "Cron expression for polling" "*/5 6-22 * * *")";;
                *) die "Invalid choice: $choice";;
            esac
        fi
    fi

    case "$CRON_PROFILE" in
        upstream) CRON_POLL="*/5 6-22 * * *";;
        location)
            { read -r CRON_POLL; read -r CRON_REASON; } < <(compute_location_cron "$LAT" "$LON" "$TIMEZONE")
            case "$CRON_REASON" in
                arctic)
                    warn "Location profile fell back to */5 * * * * because your latitude (${LAT}°)"
                    warn "is in the 20+ hour daylight zone on the summer solstice (near or inside the"
                    warn "Arctic/Antarctic Circle). Functionally fine — SBFspot's sunrise/sunset gate"
                    warn "still limits actual polling — but if you want a tighter cron pick"
                    warn "--cron-profile upstream or --cron-profile custom."
                    ;;
                midnight-cross)
                    warn "Location profile fell back to */5 * * * * because the daylight window at"
                    warn "lat=${LAT}, lon=${LON} crosses midnight in TZ=${TIMEZONE}. This happens when"
                    warn "lat/lon sit far from the longitude the timezone is built around."
                    warn "Functionally fine — SBFspot's own gate handles actual polling — but for a"
                    warn "tighter cron either set --tz to a zone matching your longitude, or pick"
                    warn "--cron-profile upstream."
                    ;;
            esac
            ;;
        24x7)     CRON_POLL="*/5 * * * *";;
        custom)   [[ -n "$CRON_POLL" ]] || die "--cron-profile=custom requires --cron <spec>.";;
        *)        die "Invalid --cron-profile: $CRON_PROFILE (upstream|location|24x7|custom)";;
    esac

    info "Installing $CRON_FILE (runs as $RUN_USER, profile=$CRON_PROFILE)"
    SBF="$INSTALL_DIR/SBFspot -q"
    cat > "$CRON_FILE" <<EOF
# SBFspot cron — installed by setup.sh
# See https://github.com/${REPO} and the upstream SBFspot wiki.
# Profile: $CRON_PROFILE
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Regular polling; SBFspot internally gates on Latitude/Longitude + SunRSOffset.
${CRON_POLL} ${RUN_USER} timeout --foreground 180 ${SBF} -ad0 -am0 -ae0 >/dev/null 2>&1

# Daily archive
${CRON_ARCHIVE} ${RUN_USER} timeout --foreground 180 ${SBF} -ad1 -am1 -ae1 >/dev/null 2>&1
EOF
    chmod 644 "$CRON_FILE"
fi

# ---- summary -------------------------------------------------------------
echo
info "Installed SBFspot release $TAG"
cat <<EOF
  Binary:       $INSTALL_DIR/SBFspot
  Config:       $CFG
  Database:     $DB_FILE
  Data dir:     $DATA_DIR
  Log dir:      $LOG_DIR
  Service user: $RUN_USER
$([[ $INSTALL_CRON == 1 ]] && echo "  Cron:         $CRON_FILE")

Test now:
  sudo -u $RUN_USER $INSTALL_DIR/SBFspot -v -finq -nocsv -nosql

Review config:
  sudo nano $CFG

Upstream docs for everything beyond install:
  https://github.com/SBFspot/SBFspot/wiki
EOF
