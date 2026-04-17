#!/bin/bash
#
# install.sh - Install pre-compiled SBFspot binaries on Raspberry Pi
#
# Usage:
#   tar xzf sbfspot-armv6-armhf-sqlite.tar.gz
#   cd sbfspot-armv6-armhf-sqlite
#   sudo bash install.sh
#
set -e

INSTALLDIR="/usr/local/bin/sbfspot.3"
LOGDIR="/var/log/sbfspot.3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CURRENT_USER="${SUDO_USER:-$(whoami)}"
DEFAULT_DATADIR="/home/$CURRENT_USER/smadata"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

echo "=== SBFspot ARMv6 armhf Installer ==="
echo ""
echo "Installing as user: $CURRENT_USER"

read -r -p "Data directory [$DEFAULT_DATADIR]: " DATADIR
DATADIR="${DATADIR:-$DEFAULT_DATADIR}"
DB_FILE="$DATADIR/SBFspot.db"

echo ""
echo "Creating directories..."
mkdir -p "$INSTALLDIR"
mkdir -p "$LOGDIR"
mkdir -p "$DATADIR"

echo "Installing SBFspot binary..."
cp "$SCRIPT_DIR/SBFspot" "$INSTALLDIR/"
chmod 755 "$INSTALLDIR/SBFspot"

echo "Installing SBFspotUploadDaemon binary..."
cp "$SCRIPT_DIR/SBFspotUploadDaemon" "$INSTALLDIR/"
chmod 755 "$INSTALLDIR/SBFspotUploadDaemon"

echo "Installing support files..."
cp "$SCRIPT_DIR"/TagList*.txt "$INSTALLDIR/"
cp "$SCRIPT_DIR/date_time_zonespec.csv" "$INSTALLDIR/"

if [ -f "$INSTALLDIR/SBFspot.cfg" ]; then
    echo "SBFspot.cfg already exists — not overwriting (default saved as SBFspot.default.cfg)"
else
    cp "$SCRIPT_DIR/SBFspot.default.cfg" "$INSTALLDIR/SBFspot.cfg"
    echo "Copied default SBFspot.cfg — edit it with your inverter settings"
fi
cp "$SCRIPT_DIR/SBFspot.default.cfg" "$INSTALLDIR/SBFspot.default.cfg"

if [ -f "$INSTALLDIR/SBFspotUpload.cfg" ]; then
    echo "SBFspotUpload.cfg already exists — not overwriting"
else
    cp "$SCRIPT_DIR/SBFspotUpload.default.cfg" "$INSTALLDIR/SBFspotUpload.cfg"
fi
cp "$SCRIPT_DIR/SBFspotUpload.default.cfg" "$INSTALLDIR/SBFspotUpload.default.cfg"

cp "$SCRIPT_DIR/CreateSQLiteDB.sql" "$INSTALLDIR/"

if [ -f "$DB_FILE" ]; then
    echo "SQLite database already exists at $DB_FILE — skipping"
else
    echo "Creating SQLite database at $DB_FILE..."
    sqlite3 "$DB_FILE" < "$SCRIPT_DIR/CreateSQLiteDB.sql"
fi

chown -R "$CURRENT_USER:$CURRENT_USER" "$DATADIR"
chown "$CURRENT_USER:$CURRENT_USER" "$LOGDIR"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Installed to:    $INSTALLDIR"
echo "Database:        $DB_FILE"
echo "Log directory:   $LOGDIR"
echo ""
echo "Next steps:"
echo "  1. Configure:  sudo nano $INSTALLDIR/SBFspot.cfg"
echo "     - Set BTAddress to your inverter's Bluetooth address"
echo "     - Set Latitude/Longitude for your location"
echo "     - Set SQL_Database=$DB_FILE"
echo "     - Set OutputPath=$DATADIR/%Y"
echo "     - Set Timezone for your region"
echo "  2. Test:       $INSTALLDIR/SBFspot -v -finq -nocsv -nosql"
echo "  3. Crontab:    crontab -e"
echo "     Add:  */2 6-22 * * * $INSTALLDIR/SBFspot -v -ad0 -am0 -ae0 > /dev/null 2>&1"
echo "     Add:  55 5 * * * $INSTALLDIR/SBFspot -v -ad1 -am1 -ae1 > /dev/null 2>&1"
echo ""
