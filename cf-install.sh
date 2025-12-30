#!/bin/bash

#
# InfiniteRemote Installation Script with Cloudflare Tunnel Support
# Modified for Cloudflare Zero Trust tunneling
#

# Get username
usern=$(whoami)

ARCH=$(uname -m)

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

# Check for folder /opt/rustdesk-api-server/
if [ -d "/opt/rustdesk-api-server/" ]; then
    echo -e "${RED}/opt/rustdesk-api-server/ already exists${NC}"
    echo "Please remove it using: rm -rf /opt/rustdesk-api-server/"
    exit 1
fi

# Check the installed Python version
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR_MINOR=$(echo $PYTHON_VERSION | cut -d. -f1,2)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  InfiniteRemote Cloudflare Installer  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Prompt for domain
echo -e "${YELLOW}Enter your Cloudflare domain (e.g., ir.spoon.rip):${NC}"
read -r wanip
if ! [[ $wanip =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]]; then
    echo -e "${RED}Invalid domain format${NC}"
    exit 1
fi

# Prompt for Cloudflare API token
echo -e "${YELLOW}Enter your Cloudflare API Token:${NC}"
read -rs CF_API_TOKEN
echo ""

if [ -z "$CF_API_TOKEN" ]; then
    echo -e "${RED}Cloudflare API Token cannot be empty${NC}"
    exit 1
fi

# Prompt for local IP (optional, with default)
echo -e "${YELLOW}Enter the local IP of this server (default: auto-detect):${NC}"
read -r LOCAL_IP
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}Auto-detected IP: ${LOCAL_IP}${NC}"
fi

# Identify OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    UPSTREAM_ID=${ID_LIKE,,}

    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
        UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
    fi
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    OS=Debian
    VER=$(cat /etc/debian_version)
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

echo -e "${GREEN}Detected OS: ${OS} ${VER}${NC}"

# Setup prereqs
PREREQ="curl wget unzip tar git qrencode python$PYTHON_MAJOR_MINOR-venv jq"
PREREQDEB="dnsutils"

echo -e "${GREEN}Installing prerequisites...${NC}"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ]; then
    apt update -qq
    apt-get install -y ${PREREQ} ${PREREQDEB}
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ]; then
    yum update -y
    yum install -y ${PREREQ} bind-utils
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    pacman -Syu
    pacman -S ${PREREQ} bind
else
    echo -e "${RED}Unsupported OS${NC}"
    exit 1
fi

# Install Cloudflared
echo -e "${GREEN}Installing Cloudflared...${NC}"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ]; then
    # Add cloudflare gpg key
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    
    # Add cloudflare repo
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflared.list
    
    apt-get update
    apt-get install -y cloudflared
else
    # Generic installation for other distros
    if [ "${ARCH}" = "x86_64" ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
    elif [ "${ARCH}" = "aarch64" ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -O /usr/local/bin/cloudflared
    elif [ "${ARCH}" = "armv7l" ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -O /usr/local/bin/cloudflared
    fi
    chmod +x /usr/local/bin/cloudflared
fi

# Make folder /var/lib/rustdesk-server/
echo -e "${GREEN}Creating RustDesk directories...${NC}"
if [ ! -d "/var/lib/rustdesk-server" ]; then
    mkdir -p /var/lib/rustdesk-server/
fi
chown "${usern}" -R /var/lib/rustdesk-server
cd /var/lib/rustdesk-server/ || exit 1

# Download latest version of RustDesk
echo -e "${GREEN}Downloading RustDesk Server...${NC}"
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest -s | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')

if [ "${ARCH}" = "x86_64" ]; then
    wget -q https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-amd64.zip
    unzip -q rustdesk-server-linux-amd64.zip
    mv amd64/hbbr /usr/bin/
    mv amd64/hbbs /usr/bin/
    rm -rf amd64/ rustdesk-server-linux-amd64.zip
elif [ "${ARCH}" = "armv7l" ]; then
    wget -q https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-armv7.zip
    unzip -q rustdesk-server-linux-armv7.zip
    mv armv7/hbbr /usr/bin/
    mv armv7/hbbs /usr/bin/
    rm -rf armv7/ rustdesk-server-linux-armv7.zip
elif [ "${ARCH}" = "aarch64" ]; then
    wget -q https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-arm64v8.zip
    unzip -q rustdesk-server-linux-arm64v8.zip
    mv arm64v8/hbbr /usr/bin/
    mv arm64v8/hbbs /usr/bin/
    rm -rf arm64v8/ rustdesk-server-linux-arm64v8.zip
fi

chmod +x /usr/bin/hbbs
chmod +x /usr/bin/hbbr

# Make folder /var/log/rustdesk-server/
if [ ! -d "/var/log/rustdesk-server" ]; then
    mkdir -p /var/log/rustdesk-server/
fi
chown "${usern}" -R /var/log/rustdesk-server/

# Setup systemd to launch hbbs (binding to localhost since Cloudflare will proxy)
echo -e "${GREEN}Setting up RustDesk services...${NC}"
cat > /etc/systemd/system/rustdesk-hbbs.service <<EOF
[Unit]
Description=RustDesk Signal Server
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbs -r ${wanip}
WorkingDirectory=/var/lib/rustdesk-server/
Environment=ALWAYS_USE_RELAY=Y
User=${usern}
Group=${usern}
Restart=always
StandardOutput=append:/var/log/rustdesk-server/hbbs.log
StandardError=append:/var/log/rustdesk-server/hbbs.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rustdesk-hbbs.service
systemctl start rustdesk-hbbs.service

# Setup systemd to launch hbbr
cat > /etc/systemd/system/rustdesk-hbbr.service <<EOF
[Unit]
Description=RustDesk Relay Server
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbr
WorkingDirectory=/var/lib/rustdesk-server/
User=${usern}
Group=${usern}
Restart=always
StandardOutput=append:/var/log/rustdesk-server/hbbr.log
StandardError=append:/var/log/rustdesk-server/hbbr.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rustdesk-hbbr.service
systemctl start rustdesk-hbbr.service

# Wait for RustDesk to be ready
echo -e "${YELLOW}Waiting for RustDesk services to start...${NC}"
sleep 5
while ! systemctl is-active --quiet rustdesk-hbbr.service; do
    echo -ne "${YELLOW}Waiting for RustDesk Relay...${NC}\n"
    sleep 3
done

# Get the public key
pubname=$(find /var/lib/rustdesk-server/ -name "*.pub")
key=$(cat "${pubname}")
echo -e "${GREEN}RustDesk Key: ${key}${NC}"

# Clone API server
echo -e "${GREEN}Cloning InfiniteRemote API Server...${NC}"
cd /opt
git clone -q https://github.com/infiniteremote/rustdesk-api-server.git
chown -R ${usern}:${usern} /opt/rustdesk-api-server/

# Generate secrets
SECRET_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 80 | head -n 1)
UNISALT=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1)

cat > /opt/rustdesk-api-server/rustdesk_server_api/secret_config.py <<EOF
SECRET_KEY = "${SECRET_KEY}"
SALT_CRED = "${UNISALT}"
CSRF_TRUSTED_ORIGINS = ["https://${wanip}"]
EOF

# Setup logging
if [ ! -d "/var/log/rustdesk-server-api" ]; then
    mkdir -p /var/log/rustdesk-server-api/
fi
chown -R ${usern}:${usern} /var/log/rustdesk-server-api/

# Setup Python environment
echo -e "${GREEN}Setting up Python environment...${NC}"
cd /opt/rustdesk-api-server/api
python3 -m venv env
source /opt/rustdesk-api-server/api/env/bin/activate
pip install -q --no-cache-dir --upgrade pip
pip install -q --no-cache-dir setuptools wheel
pip install -q --no-cache-dir -r /opt/rustdesk-api-server/requirements.txt

cd /opt/rustdesk-api-server/
python manage.py makemigrations
python manage.py migrate
echo -e "${YELLOW}Please set your admin username and password for the Web UI${NC}"
python manage.py securecreatesuperuser
deactivate

# Create API config (bind to localhost since Cloudflare will proxy)
cat > /opt/rustdesk-api-server/api/api_config.py <<EOF
bind = "127.0.0.1:8000"
workers = 4
timeout = 120
user = "${usern}"
group = "${usern}"

wsgi_app = "rustdesk_server_api.wsgi:application"

# Logging
errorlog = "/var/log/rustdesk-server-api/error.log"
accesslog = "/var/log/rustdesk-server-api/access.log"
loglevel = "info"
EOF

# Create API service
cat > /etc/systemd/system/rustdesk-api.service <<EOF
[Unit]
Description=rustdesk-api-server gunicorn daemon
After=network.target

[Service]
User=${usern}
WorkingDirectory=/opt/rustdesk-api-server/
Environment="PATH=/opt/rustdesk-api-server/api/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/rustdesk-api-server/api/env/bin/gunicorn -c /opt/rustdesk-api-server/api/api_config.py
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rustdesk-api
systemctl start rustdesk-api

# Wait for API to start
sleep 3

# Setup Cloudflare Tunnel
echo -e "${GREEN}Setting up Cloudflare Tunnel...${NC}"

# Create tunnel directory
mkdir -p /etc/cloudflared
mkdir -p /var/log/cloudflared
chown -R ${usern}:${usern} /var/log/cloudflared

# Authenticate cloudflared with the API token
echo "$CF_API_TOKEN" | cloudflared tunnel login --api-token

# Create a tunnel
TUNNEL_NAME="rustdesk-${wanip//./-}"
echo -e "${YELLOW}Creating tunnel: ${TUNNEL_NAME}${NC}"
TUNNEL_ID=$(cloudflared tunnel create ${TUNNEL_NAME} 2>&1 | grep -oP 'Created tunnel .* with id \K[a-f0-9-]+')

if [ -z "$TUNNEL_ID" ]; then
    echo -e "${RED}Failed to create tunnel. Checking if tunnel already exists...${NC}"
    TUNNEL_ID=$(cloudflared tunnel list | grep ${TUNNEL_NAME} | awk '{print $1}')
    
    if [ -z "$TUNNEL_ID" ]; then
        echo -e "${RED}Could not create or find tunnel${NC}"
        exit 1
    fi
    echo -e "${GREEN}Using existing tunnel: ${TUNNEL_ID}${NC}"
fi

# Create tunnel configuration
cat > /etc/cloudflared/config.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

ingress:
  # Web interface (HTTPS)
  - hostname: ${wanip}
    service: http://localhost:8000
  
  # RustDesk Signal Server (hbbs) - Port 21115
  - hostname: ${wanip}
    service: tcp://localhost:21115
  
  # RustDesk Signal Server (hbbs) - Port 21116 TCP
  - hostname: ${wanip}
    service: tcp://localhost:21116
  
  # RustDesk Signal Server (hbbs) - Port 21118
  - hostname: ${wanip}
    service: tcp://localhost:21118
  
  # RustDesk Relay Server (hbbr) - Port 21117
  - hostname: ${wanip}
    service: tcp://localhost:21117
  
  # RustDesk Relay Server (hbbr) - Port 21119
  - hostname: ${wanip}
    service: tcp://localhost:21119
  
  # Catch-all rule
  - service: http_status:404

# Optional: Enable metrics
metrics: localhost:2000
EOF

# Create DNS records for the tunnel
echo -e "${GREEN}Creating DNS records...${NC}"
cloudflared tunnel route dns ${TUNNEL_ID} ${wanip}

# Install and start the tunnel service
echo -e "${GREEN}Installing Cloudflare Tunnel service...${NC}"
cloudflared service install

# Start the tunnel
systemctl start cloudflared
systemctl enable cloudflared

# Setup installers
echo -e "${GREEN}Configuring client installers...${NC}"
string="{\"host\":\"${wanip}\",\"key\":\"${key}\",\"api\":\"https://${wanip}\"}"
string64=$(echo -n "$string" | base64 -w 0 | tr -d '=')
string64rev=$(echo -n "$string64" | rev)

# Download Windows client
RDCLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk/releases/latest -s | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
wget -q -O /opt/rustdesk-api-server/static/configs/rustdesk-licensed-${string64rev}.exe \
    https://github.com/rustdesk/rustdesk/releases/download/${RDCLATEST}/rustdesk-${RDCLATEST}-x86_64.exe

# Update installer templates
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/api/templates/installers.html
sed -i "s|UniqueKey|${key}|g" /opt/rustdesk-api-server/api/templates/installers.html
sed -i "s|UniqueURL|${wanip}|g" /opt/rustdesk-api-server/api/templates/installers.html
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install.ps1
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install.bat
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install-mac.sh
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install-linux.sh

# Generate QR code
qrencode -o /opt/rustdesk-api-server/static/configs/qrcode.png config=${string64rev}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Domain:${NC} https://${wanip}"
echo -e "${BLUE}RustDesk Key:${NC} ${key}"
echo -e "${BLUE}Config String:${NC} ${string64rev}"
echo -e "${BLUE}Tunnel ID:${NC} ${TUNNEL_ID}"
echo ""
echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
echo -e "1. Access your web interface at: ${GREEN}https://${wanip}${NC}"
echo -e "2. Configure your RustDesk clients with server: ${GREEN}${wanip}${NC}"
echo -e "3. Use the key displayed above in your client configuration"
echo -e "4. All traffic is routed through Cloudflare Tunnel (no direct port exposure)"
echo ""
echo -e "${YELLOW}Service Status:${NC}"
systemctl status rustdesk-hbbs --no-pager | grep "Active:"
systemctl status rustdesk-hbbr --no-pager | grep "Active:"
systemctl status rustdesk-api --no-pager | grep "Active:"
systemctl status cloudflared --no-pager | grep "Active:"
echo ""
echo -e "${BLUE}Cloudflare Tunnel Logs:${NC} journalctl -u cloudflared -f"
echo -e "${BLUE}RustDesk Logs:${NC} /var/log/rustdesk-server/"
echo -e "${BLUE}API Logs:${NC} /var/log/rustdesk-server-api/"
echo ""
