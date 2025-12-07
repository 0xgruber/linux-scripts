#!/usr/bin/env bash
#
# usbguard-allow-all-blocked
#
# Description:
#   This script scans the system for all USB devices currently marked as
#   "blocked" by USBGuard and generates a new rule file inside:
#
#       /etc/usbguard/rules.d/<filename>.conf
#
#   The file will contain entries in the form:
#
#       allow id <ID>
#
#   allowing each previously-blocked device. USBGuard is then reloaded so the
#   new rules take effect immediately.
#
# Usage:
#   Run as root or via sudo:
#       sudo usbguard-allow-all-blocked
#
#   The script will prompt for a filename (without extension) and will refuse
#   to overwrite an existing rule file of the same name.
#
# Requirements:
#   - Must be executed with root privileges
#   - usbguard(1) must be installed and functional
#   - Systemd is recommended but not required (script falls back to usbguard reload)
#
# Behavior:
#   - Extracts numeric device IDs from "usbguard list-devices" output
#   - Filters only devices marked as "block"
#   - Strips non-numeric characters (e.g., "#" or ":")
#   - Writes allow-rules for each ID into the requested rules file
#   - Reloads USBGuard to activate the new rules
#
# Notes:
#   This script is intended for administrators who want to quickly allow
#   previously-blocked USB devices while keeping rules organized in rules.d.
#   It does NOT modify the main rules.conf file.
#
# Author: Aaron Gruber
# Repository: https://gitlab.vaultcloud.xyz/aarongruber/linux-scripts.git
#

#!/usr/bin/env bash
set -euo pipefail

# Must be root
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run this as root." >&2
    exit 1
fi

if ! command -v usbguard >/dev/null 2>&1; then
    echo "usbguard command not found. Is USBGuard installed?" >&2
    exit 1
fi

read -rp "Enter new USBGuard rules filename (without extension): " fname

if [[ -z "${fname}" ]]; then
    echo "Filename cannot be empty." >&2
    exit 1
fi

outfile="/etc/usbguard/rules.d/${fname}.conf"

if [[ -e "$outfile" ]]; then
    echo "Refusing to overwrite existing file: $outfile" >&2
    exit 1
fi

echo "Collecting blocked USB devices..."

# Get unique numeric IDs of blocked devices
ids=$(usbguard list-devices \
    | awk '/block/ { gsub(/[^0-9]/, "", $1); print $1 }' \
    | sort -u)

if [[ -z "${ids}" ]]; then
    echo "No blocked devices found. Nothing to do."
    exit 0
fi

echo "Writing rules to: $outfile"
{
    echo "# Auto-generated allow rules for currently blocked USB devices"
    echo "# Created: $(date)"
    for id in $ids; do
        echo "allow id $id"
    done
} > "$outfile"

# Reload USBGuard
if command -v systemctl >/dev/null 2>&1 && systemctl is-active usbguard >/dev/null 2>&1; then
    systemctl reload usbguard || systemctl restart usbguard
elif command -v usbguard >/dev/null 2>&1; then
    usbguard reload || true
fi

echo "Done. $(wc -l <"$outfile") line(s) written to $outfile"
echo "Previously blocked devices should now be allowed."
