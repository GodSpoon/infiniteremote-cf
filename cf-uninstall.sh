#!/bin/bash

#
# InfiniteRemote Uninstall Script (Cloudflare Version)
#

RED='\e[31m'
BLUE='\e[36m'
GREEN='\e[0;32m'
YELLOW='\e[93m'
NC='\e[39m' # No Color

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Please run this script as root${NC}"
    exit 1
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  InfiniteRemote Uninstaller${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${RED}WARNING: This will remove ALL InfiniteRemote and RustDesk components${NC}"
echo -e "${YELLOW}Press CTRL+C to cancel, or ENTER to continue...${NC}"
read

# Get username
usern=$(whoami)

# Stop and disable services
echo -e "${GREEN}Stopping services...${NC}"
systemctl stop rustdesk-hbbs.service 2>/dev/null
systemctl stop rustdesk-hbbr.service 2>/dev/null
systemctl stop rustdesk-api.service 2>/dev/null
systemctl stop cloudflared.service 2>/dev/null

systemctl disable rustdesk-hbbs.service 2>/dev/null
systemctl disable rustdesk-hbbr.service 2>/dev/null
systemctl disable rustdesk-api.service 2>/dev/null
systemctl disable cloudflared.service 2>/dev/null

# Remove Cloudflare Tunnel
echo -e "${GREEN}Removing Cloudflare Tunnel...${NC}"
if command -v cloudflared &> /dev/null; then
    # List and delete all tunnels
    TUNNELS=$(cloudflared tunnel list 2>/dev/null | grep -v "ID" | awk '{print $1}')
    for TUNNEL_ID in $TUNNELS; do
        echo -e "${YELLOW}Deleting tunnel: ${TUNNEL_ID}${NC}"
        cloudflared tunnel delete -f ${TUNNEL_ID} 2>/dev/null
    done
    
    # Uninstall service
    cloudflared service uninstall 2>/dev/null
fi

# Remove Cloudflared
if [ -f /etc/apt/sources.list.d/cloudflared.list ]; then
    rm /etc/apt/sources.list.d/cloudflared.list
    apt-get remove -y cloudflared 2>/dev/null
elif [ -f /usr/local/bin/cloudflared ]; then
    rm /usr/local/bin/cloudflared
fi

rm -rf /etc/cloudflared
rm -rf /root/.cloudflared
rm -rf /var/log/cloudflared

# Remove systemd service files
echo -e "${GREEN}Removing systemd services...${NC}"
rm -f /etc/systemd/system/rustdesk-hbbs.service
rm -f /etc/systemd/system/rustdesk-hbbr.service
rm -f /etc/systemd/system/rustdesk-api.service
systemctl daemon-reload

# Remove RustDesk executables and folders
echo -e "${GREEN}Removing RustDesk files...${NC}"
rm -f /usr/bin/hbbs
rm -f /usr/bin/hbbr
rm -rf /var/lib/rustdesk-server
rm -rf /var/log/rustdesk-server

# Remove InfiniteRemote API files
echo -e "${GREEN}Removing InfiniteRemote API files...${NC}"
rm -rf /opt/rustdesk-api-server
rm -rf /var/log/rustdesk-server-api

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Uninstall Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Note: Cloudflare DNS records may still exist${NC}"
echo -e "${YELLOW}Please check your Cloudflare dashboard to remove them manually${NC}"
echo ""
