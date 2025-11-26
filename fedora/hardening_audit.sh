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

# Check DNS over TLS (Smart Check)
echo -e "\nChecking DNS-over-TLS status..."

# 1. Check if configured in file (grep recursively in /etc/systemd/)
if grep -qr "^DNSOverTLS=yes" /etc/systemd/resolved.conf /etc/systemd/resolved.conf.d/ 2>/dev/null; then
    CONFIG_SET="yes"
else
    CONFIG_SET="no"
fi

# 2. Check runtime status via resolvectl
RUNTIME_DOT=$(resolvectl status 2>/dev/null | grep "DNSOverTLS setting: yes")

if [ "$CONFIG_SET" == "yes" ]; then
    echo -e "${GREEN}[PASS] DNS-over-TLS is enabled in configuration.${NC}"
elif [ -n "$RUNTIME_DOT" ]; then
    echo -e "${GREEN}[PASS] DNS-over-TLS is active (Runtime check passed).${NC}"
else
    echo -e "${YELLOW}[WARN] DNS-over-TLS is NOT enabled.${NC}"
    echo -e "       Action: Create /etc/systemd/resolved.conf with 'DNSOverTLS=yes'"
    echo -e "       (Note: The file /etc/systemd/resolved.conf does not exist by default on Fedora 43+; you must create it.)"
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

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}                  AUDIT COMPLETE                      ${NC}"
echo -e "${BLUE}======================================================${NC}"