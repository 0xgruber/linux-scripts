#!/usr/bin/env bash
#
# usbguard-allow-all-blocked
#
# Description:
#   Generate a new USBGuard rules.d file containing allow rules for all
#   currently blocked devices. Rules preserve id, serial, hash, name,
#   interface-class, and connect-type, but drop port/topology-specific
#   fields such as via-port and parent-hash.
#

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

# Transform blocked device lines into allow rules:
# - strip leading index + "block"
# - change "block" → "allow"
# - drop via-port and parent-hash fields
rules=$(usbguard list-devices --blocked \
    | sed -E 's/^[0-9]+:\s+block/allow/' \
    | sed -E 's/\s+via-port "[^"]*"//g' \
    | sed -E 's/\s+parent-hash "[^"]*"//g')

if [[ -z "$rules" ]]; then
    echo "No blocked devices found. Nothing to do."
    exit 0
fi

echo "Writing rules to: $outfile"
{
    echo "# Auto-generated allow rules for currently blocked USB devices"
    echo "# Created: $(date)"
    printf '%s\n' "$rules"
} > "$outfile"

# Reload USBGuard
if command -v systemctl >/dev/null 2>&1 && systemctl is-active usbguard >/dev/null 2>&1; then
    systemctl reload usbguard || systemctl restart usbguard
elif command -v usbguard >/dev/null 2>&1; then
    usbguard reload || true
fi

echo "Done. $(wc -l <"$outfile") line(s) written to $outfile"
echo "Previously blocked devices should now be allowed (by id+serial+hash+interface)."
