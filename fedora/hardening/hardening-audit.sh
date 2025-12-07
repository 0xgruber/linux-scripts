#!/bin/bash

# Fedora Workstation Hardening Audit Script
# Checks against common hardening steps: Firewall, Kernel, Boot, and Services.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Header
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}       FEDORA WORKSTATION HARDENING AUDIT             ${NC}"
echo -e "${BLUE}======================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (sudo) to check sensitive configs like GRUB.${NC}"
  exit 1
fi

# ---------------------------------------------------------
# 1. NETWORK & FIREWALL CHECKS
# ---------------------------------------------------------
echo -e "\n${BLUE}[NETWORK & FIREWALL]${NC}"

# Check Firewall Zone
CURRENT_ZONE=$(firewall-cmd --get-default-zone 2>/dev/null)
ACTIVE_ZONES=$(firewall-cmd --get-active-zones | head -n 1)

if [ "$CURRENT_ZONE" == "FedoraWorkstation" ]; then
    echo -e "${RED}[FAIL] Default Firewall Zone is 'FedoraWorkstation' (Too Permissive).${NC}"
    echo -e "       Action: Switch to 'public' zone."
elif [ "$ACTIVE_ZONES" == "FedoraWorkstation" ]; then
    echo -e "${RED}[FAIL] Active Interface is using 'FedoraWorkstation' zone.${NC}"
    echo -e "       Action: Switch interface to 'public' zone."
else
    echo -e "${GREEN}[PASS] Firewall Zone is not default permissive ($CURRENT_ZONE).${NC}"
fi

# Check SSH
if systemctl is-active --quiet sshd; then
    echo -e "${YELLOW}[WARN] SSH Server (sshd) is RUNNING.${NC}"
    echo -e "       If you do not need remote access, disable this: 'systemctl disable --now sshd'"
else
    echo -e "${GREEN}[PASS] SSH Server is inactive.${NC}"
fi

# Check Encrypted DNS (DoT or DNSCrypt)
# --- Check A: Native Systemd-Resolved DoT ---
if grep -qr "^DNSOverTLS=yes" /etc/systemd/resolved.conf /etc/systemd/resolved.conf.d/ 2>/dev/null; then
    RESOLVED_DOT_CONF="yes"
else
    RESOLVED_DOT_CONF="no"
fi
# Runtime check for native DoT
RUNTIME_DOT=$(resolvectl status 2>/dev/null | grep "DNSOverTLS setting: yes")

# --- Check B: DNSCrypt-Proxy ---
DNSCRYPT_ACTIVE="no"
if systemctl is-active --quiet dnscrypt-proxy; then
    if grep -q "127.0.0.1:5053" /etc/systemd/resolved.conf 2>/dev/null || \
       resolvectl status 2>/dev/null | grep -q "127.0.0.1:5053"; then
        DNSCRYPT_ACTIVE="yes"
    fi
fi

# --- Final Decision ---
if [ "$DNSCRYPT_ACTIVE" == "yes" ]; then
    echo -e "${GREEN}[PASS] DNSCrypt-Proxy is active and forwarding correctly.${NC}"
elif [ "$RESOLVED_DOT_CONF" == "yes" ]; then
    echo -e "${GREEN}[PASS] Systemd-Resolved native DNS-over-TLS is enabled.${NC}"
elif [ -n "$RUNTIME_DOT" ]; then
    echo -e "${GREEN}[PASS] Systemd-Resolved native DNS-over-TLS is active.${NC}"
else
    echo -e "${YELLOW}[WARN] No Encrypted DNS detected.${NC}"
    echo -e "       Action: Enable 'DNSOverTLS=yes' in /etc/systemd/resolved.conf"
    echo -e "       OR install/configure 'dnscrypt-proxy'."
fi
# ---------------------------------------------------------
# 2. KERNEL HARDENING (SYSCTL)
# ---------------------------------------------------------
echo -e "\n${BLUE}[KERNEL HARDENING]${NC}"

check_sysctl() {
    KEY=$1
    EXPECTED=$2
    CURRENT=$(sysctl -n $KEY 2>/dev/null)
    
    if [ "$CURRENT" == "$EXPECTED" ]; then
        echo -e "${GREEN}[PASS] $KEY = $CURRENT${NC}"
    else
        echo -e "${RED}[FAIL] $KEY = $CURRENT (Recommended: $EXPECTED)${NC}"
    fi
}

check_sysctl "kernel.kptr_restrict" "2"
check_sysctl "kernel.dmesg_restrict" "1"
check_sysctl "kernel.yama.ptrace_scope" "1"
check_sysctl "net.core.bpf_jit_harden" "2"

# ---------------------------------------------------------
# 3. BOOT SECURITY
# ---------------------------------------------------------
echo -e "\n${BLUE}[BOOT SECURITY]${NC}"

# Check GRUB Password
# We look for password_pbkdf2 in grub.cfg or 40_custom
if grep -q "password_pbkdf2" /boot/grub2/grub.cfg 2>/dev/null || grep -q "password_pbkdf2" /etc/grub.d/40_custom 2>/dev/null; then
    echo -e "${GREEN}[PASS] GRUB2 password protection detected.${NC}"
else
    echo -e "${RED}[FAIL] GRUB2 is NOT password protected.${NC}"
    echo -e "       Action: Generate hash with 'grub2-mkpasswd-pbkdf2' and add to /etc/grub.d/40_custom"
fi

# Check UEFI Secure Boot
# Requires 'mokutil' (usually installed by default on Fedora)
if [ -d /sys/firmware/efi ]; then
    if command -v mokutil >/dev/null 2>&1; then
        if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
            echo -e "${GREEN}[PASS] UEFI Secure Boot is ENABLED.${NC}"
        else
            echo -e "${RED}[FAIL] UEFI Secure Boot is DISABLED.${NC}"
            echo -e "       Action: Enable Secure Boot in your BIOS/UEFI settings."
        fi
    else
        echo -e "${YELLOW}[WARN] 'mokutil' tool not found. Cannot verify Secure Boot.${NC}"
        echo -e "       Action: sudo dnf install mokutil"
    fi
else
    echo -e "${YELLOW}[INFO] System appears to be booting via Legacy BIOS (Not UEFI).${NC}"
    echo -e "       Secure Boot is not available in Legacy mode."
fi

# Check LUKS Full Disk Encryption
# Checks for any partition of type crypto_LUKS
if lsblk -o FSTYPE 2>/dev/null | grep -q "crypto_LUKS"; then
    echo -e "${GREEN}[PASS] LUKS Full Disk Encryption is present.${NC}"
else
    echo -e "${RED}[FAIL] No LUKS encrypted partitions found.${NC}"
    echo -e "       Action: Full Disk Encryption is highly recommended to protect data from physical theft."
fi

# ---------------------------------------------------------
# 4. PHYSICAL & SERVICES
# ---------------------------------------------------------
echo -e "\n${BLUE}[PHYSICAL & SERVICES]${NC}"

# Check USBGuard
if rpm -q usbguard >/dev/null 2>&1; then
    if systemctl is-active --quiet usbguard; then
        echo -e "${GREEN}[PASS] USBGuard is installed and running.${NC}"
    else
        echo -e "${YELLOW}[WARN] USBGuard is installed but NOT running.${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] USBGuard is not installed.${NC}"
    echo -e "       Consider installing it to protect against BadUSB attacks."
fi

# Check ABRT (Automated Bug Reporting Tool)
if rpm -q abrt >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] ABRT is installed.${NC}"
    echo -e "       Automated error reporting can leak sensitive data in logs."
    echo -e "       Action: Consider 'sudo dnf remove abrt' if not needed."
else
    echo -e "${GREEN}[PASS] ABRT is not installed.${NC}"
fi

# ---------------------------------------------------------
# 5. FILESYSTEM & MOUNT HARDENING
# ---------------------------------------------------------
echo -e "\n${BLUE}[FILESYSTEM MOUNTS]${NC}"

# Check shared memory (/dev/shm) for noexec/nosuid
# This prevents malware from executing directly from shared memory.
if mount | grep -q "on /dev/shm type tmpfs"; then
    if mount | grep "on /dev/shm type tmpfs" | grep -qE "noexec|nosuid"; then
        echo -e "${GREEN}[PASS] /dev/shm is mounted with restrictions (noexec/nosuid).${NC}"
    else
        echo -e "${YELLOW}[WARN] /dev/shm does not have 'noexec' or 'nosuid' set.${NC}"
        echo -e "       Action: Edit /etc/fstab to add 'defaults,noexec,nosuid,nodev' for /dev/shm."
    fi
else
    echo -e "${YELLOW}[INFO] /dev/shm mount point not found (uncommon).${NC}"
fi

# Check /tmp restriction
# Ensures scripts cannot be executed from the temporary directory.
if mount | grep "on /tmp " | grep -q "noexec"; then
    echo -e "${GREEN}[PASS] /tmp is mounted as noexec.${NC}"
else
    echo -e "${YELLOW}[WARN] /tmp is NOT mounted as noexec.${NC}"
    echo -e "       Action: If /tmp is a separate partition, add 'noexec' to /etc/fstab."
    echo -e "       (Note: Some updates/installers may fail if /tmp is noexec, toggle cautiously)."
fi

# ---------------------------------------------------------
# 6. SYSTEM CONFIGURATION
# ---------------------------------------------------------
echo -e "\n${BLUE}[SYSTEM CONFIGURATION]${NC}"

# Check SELinux Status
# Fedora relies heavily on SELinux. It must be 'Enforcing'.
if command -v getenforce >/dev/null 2>&1; then
    SELINUX_MODE=$(getenforce)
    if [ "$SELINUX_MODE" == "Enforcing" ]; then
        echo -e "${GREEN}[PASS] SELinux is Enforcing.${NC}"
    else
        echo -e "${RED}[FAIL] SELinux is '$SELINUX_MODE' (Expected: Enforcing).${NC}"
        echo -e "       Action: Edit /etc/selinux/config and set SELINUX=enforcing, then reboot."
    fi
else
    echo -e "${RED}[FAIL] SELinux is not installed.${NC}"
fi

# Check Core Dumps
# Core dumps contain memory contents of crashed programs (passwords/keys).
# We check systemd-coredump configuration.
if grep -q "Storage=none" /etc/systemd/coredump.conf 2>/dev/null; then
    echo -e "${GREEN}[PASS] Systemd Core Dumps are disabled (Storage=none).${NC}"
elif [ "$(sysctl -n kernel.core_pattern)" == "|/bin/false" ]; then
     echo -e "${GREEN}[PASS] Core Dumps disabled via sysctl.${NC}"
else
    echo -e "${YELLOW}[WARN] Core Dumps are enabled.${NC}"
    echo -e "       Action: Set 'Storage=none' in /etc/systemd/coredump.conf to prevent sensitive data leaks."
fi

# Check DNF GPG Check
# Ensures all software installed via DNF is cryptographically signed.
if grep -q "^gpgcheck=1" /etc/dnf/dnf.conf; then
    echo -e "${GREEN}[PASS] DNF GPG check is globally enabled.${NC}"
else
    echo -e "${RED}[FAIL] DNF GPG check is NOT globally enabled.${NC}"
    echo -e "       Action: Set 'gpgcheck=1' in /etc/dnf/dnf.conf."
fi

# Network Kernel Parameters
# Prevents MITM attacks via ICMP redirects
check_sysctl "net.ipv4.conf.all.accept_redirects" "0"
check_sysctl "net.ipv4.conf.default.accept_redirects" "0"

# Prevents this machine from acting as a router
check_sysctl "net.ipv4.ip_forward" "0"

# Logs "Martian" packets (packets with impossible source IPs)
check_sysctl "net.ipv4.conf.all.log_martians" "1"

# ---------------------------------------------------------
# 8. MALWARE & INTEGRITY
# ---------------------------------------------------------
echo -e "\n${BLUE}[MALWARE & INTEGRITY]${NC}"

# Check ClamAV & Automatic Updates
if rpm -q clamav >/dev/null 2>&1; then
    # UPDATED: Check if the service or timer is ENABLED (configured to auto-start)
    # This avoids race conditions where the service is effectively "dead" between updates.
    if systemctl is-enabled --quiet clamav-freshclam.service 2>/dev/null || \
       systemctl is-enabled --quiet clamav-freshclam.timer 2>/dev/null; then
        echo -e "${GREEN}[PASS] ClamAV Automatic Updates are enabled.${NC}"
    else
        echo -e "${YELLOW}[WARN] ClamAV Automatic Updates are NOT enabled.${NC}"
        echo -e "       Action: 'sudo systemctl enable --now clamav-freshclam.timer'"
    fi
else
    echo -e "${YELLOW}[WARN] ClamAV is not installed.${NC}"
    echo -e "       Action: 'sudo dnf install clamav clamav-update clamtk'"
fi

# Check Rootkit Hunter
if rpm -q rkhunter >/dev/null 2>&1; then
    if [ -f /var/log/rkhunter/rkhunter.log ]; then
        if grep -q "Possible rootkits: 0" /var/log/rkhunter/rkhunter.log; then
            echo -e "${GREEN}[PASS] Rootkit Hunter is installed and last scan was clean.${NC}"
        else
            echo -e "${YELLOW}[WARN] Rootkit Hunter found warnings in the last scan.${NC}"
            echo -e "       Action: Check /var/log/rkhunter/rkhunter.log"
        fi
    else
        echo -e "${YELLOW}[WARN] Rootkit Hunter is installed but no log found.${NC}"
        echo -e "       Action: Run 'sudo rkhunter --check --sk'"
    fi
else
    echo -e "${YELLOW}[WARN] Rootkit Hunter is not installed.${NC}"
    echo -e "       Action: 'sudo dnf install rkhunter'"
fi

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}                  AUDIT COMPLETE                      ${NC}"
echo -e "${BLUE}======================================================${NC}"
