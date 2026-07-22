#!/bin/bash
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Starting Security & Health Audit ===${NC}\n"

# 1. Check for "Instant Root" (The NOPASSWD:ALL check)
echo -n "[ ] Checking Sudoers Restriction... "
if grep -q "NOPASSWD: ALL" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    echo -e "${RED}FAILED: Instant Root vulnerability found!${NC}"
else
    echo -e "${GREEN}PASSED: No NOPASSWD:ALL detected.${NC}"
fi

# 2. Check SSH Hardening
echo -n "[ ] Checking SSH Root Lockdown... "
if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED: Root login is still allowed!${NC}"
fi

# 3. Check Firewall (UFW) Status
echo -n "[ ] Checking Firewall Status... "
if ufw status | grep -q "active"; then
    echo -e "${GREEN}ACTIVE${NC}"
else
    echo -e "${RED}INACTIVE: Firewall is down!${NC}"
fi

# 4. Check for Open Leaks (Internal vs External)
echo -n "[ ] Checking for exposed internal services... "
LEAKS=$(ss -tulpn | grep LISTEN | grep -v "127.0.0.1" | grep -v "::1" | grep -E "9100|8080")
if [ -z "$LEAKS" ]; then
    echo -e "${GREEN}PASSED: No leaks detected.${NC}"
else
    echo -e "${RED}WARNING: Internal services (9100/8080) are exposed to the PUBLIC!${NC}"
fi

# 5. Check Docker Health
echo -n "[ ] Checking Docker App Status... "
if docker ps | grep -q "demo-app"; then
    echo -e "${GREEN}RUNNING${NC}"
else
    echo -e "${RED}DOWN: App container is not running.${NC}"
fi

# 6. Check Fail2ban
echo -n "[ ] Checking Fail2ban Jail... "
if fail2ban-client status sshd >/dev/null 2>&1; then
    echo -e "${GREEN}ACTIVE${NC}"
else
    echo -e "${RED}FAILED: Fail2ban not monitoring SSH.${NC}"
fi

# 7. Check PAM Alerts
echo -n "[ ] Checking SSH Login Alerts... "
if [ -f "/usr/local/bin/ssh-login-notify.sh" ]; then
    echo -e "${GREEN}INSTALLED${NC}"
else
    echo -e "${RED}MISSING: No alert script found.${NC}"
fi

echo -e "\n${YELLOW}=== Audit Complete ===${NC}"