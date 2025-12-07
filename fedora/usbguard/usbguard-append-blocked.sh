#!/usr/bin/env bash
#
# usbguard-append-blocked
#
# Description:
#   Append allow rules for all currently blocked USBGuard devices to an existing
#   rule file under /etc/usbguard/rules.d. Rules preserve id, serial, hash,
#   name, interface-class, and connect-type, but drop via-port and parent-hash.
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

# We'll loop per-device so we can de-duplicate rules
added=0
skipped=0

while IFS= read -r line; do
    # Only process lines with "block"
    [[ "$line" =~ block ]] || continue

    rule=$(printf '%s\n' "$line" \
        | sed -E 's/^[0-9]+:\s+block/allow/' \
        | sed -E 's/\s+via-port "[^"]*"//g' \
        | sed -E 's/\s+parent-hash "[^"]*"//g')

    # Skip empty or malformed transforms
    [[ -z "$rule" ]] && continue

    # If exact rule already present, skip
    if grep -qxF "$rule" "$outfile"; then
        ((skipped++))
    else
        echo "$rule" >> "$outfile"
        ((added++))
    fi
done < <(usbguard list-devices --blocked)

if (( added == 0 && skipped == 0 )); then
    echo "No blocked devices found. Nothing to do."
    exit 0
fi

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
