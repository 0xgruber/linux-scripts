#!/usr/bin/env bash
#
# usbguard-append-blocked
#
# Description:
#   Append allow rules for all currently blocked USBGuard devices to an existing
#   rule file under:
#
#       /etc/usbguard/rules.d/<filename>.conf
#
#   The script only appends rules for IDs not already present in the file, using
#   the format:
#
#       allow id <ID>
#
# Usage:
#   Run as root or via sudo:
#       sudo usbguard-append-blocked
#
#   The script will:
#     - List existing rule files in /etc/usbguard/rules.d with index numbers
#     - Prompt for an index selection
#     - Append allow rules for all currently blocked devices that are not yet
#       present in the selected file
#
# Requirements:
#   - Must be executed with root privileges
#   - usbguard(1) must be installed and functional
#
# Behavior:
#   - Extracts numeric device IDs from `usbguard list-devices`
#   - Filters only devices marked as "block"
#   - Strips non-numeric characters (e.g., "#" or ":") from ID field
#   - Skips IDs that already have an `allow id <ID>` rule
#   - Appends new allow rules for remaining IDs
#   - Reloads USBGuard to activate the updated rules
#
# Notes:
#   This is intended as a companion to scripts that generate rule files for
#   blocked devices. It lets you incrementally extend an existing rules file
#   instead of creating a new one each time.
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

rules_dir="/etc/usbguard/rules.d"

if [[ ! -d "$rules_dir" ]]; then
    echo "Rules directory does not exist: $rules_dir" >&2
    exit 1
fi

# Collect existing rule files
mapfile -t files < <(find "$rules_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)

if [[ "${#files[@]}" -eq 0 ]]; then
    echo "No rule files found in $rules_dir" >&2
    exit 1
fi

echo "Existing USBGuard rule files in $rules_dir:"
for i in "${!files[@]}"; do
    printf "  %2d) %s\n" "$((i + 1))" "${files[i]}"
done

echo
read -rp "Select rules file by index: " choice

# Basic sanity check
if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "Invalid selection (not a number)." >&2
    exit 1
fi

index=$((choice - 1))

if (( index < 0 || index >= ${#files[@]} )); then
    echo "Invalid selection (out of range)." >&2
    exit 1
fi

outfile="${rules_dir}/${files[index]}"

echo "Using existing rules file: $outfile"
echo "Collecting blocked USB devices..."

ids=$(usbguard list-devices \
    | awk '/block/ { gsub(/[^0-9]/, "", $1); print $1 }' \
    | sort -u)

if [[ -z "${ids}" ]]; then
    echo "No blocked devices found. Nothing to do."
    exit 0
fi

added=0
skipped=0

for id in $ids; do
    if grep -qE "^allow[[:space:]]+id[[:space:]]+${id}([[:space:]]|$)" "$outfile"; then
        ((skipped++))
    else
        echo "allow id $id" >> "$outfile"
        ((added++))
    fi
done

echo "Append complete."
echo "  Added  : $added rule(s)"
echo "  Skipped: $skipped existing rule(s)"

# Reload USBGuard
if command -v systemctl >/dev/null 2>&1 && systemctl is-active usbguard >/dev/null 2>&1; then
    systemctl reload usbguard || systemctl restart usbguard
elif command -v usbguard >/dev/null 2>&1; then
    usbguard reload || true
fi

echo "USBGuard reloaded. Updated rules from: $outfile"
