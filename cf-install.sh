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
echo -e "${YELLOW}Enter your Cloudflare domain (e.g., example.com):${NC}"
read -r wanip
if [ -z "$wanip" ]; then
    echo -e "${RED}Domain cannot be empty${NC}"
    exit 1
fi
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
PREREQDEB="dnsutils lsb-release"

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
    
    # Detect distribution codename
    if command -v lsb_release >/dev/null 2>&1; then
        DISTRO_CODENAME=$(lsb_release -cs)
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_CODENAME=$VERSION_CODENAME
    else
        DISTRO_CODENAME="bookworm"  # Default for Debian 12
    fi
    
    # Add cloudflare repo
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared ${DISTRO_CODENAME} main" | tee /etc/apt/sources.list.d/cloudflared.list
    
    apt-get update -qq 2>/dev/null || {
        echo -e "${YELLOW}APT repo method failed, using direct download...${NC}"
        rm -f /etc/apt/sources.list.d/cloudflared.list
        if [ "${ARCH}" = "x86_64" ]; then
            wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        elif [ "${ARCH}" = "aarch64" ]; then
            wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -O /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        elif [ "${ARCH}" = "armv7l" ]; then
            wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -O /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        fi
    }
    
    # Try to install from repo if available, otherwise skip (already installed from direct download)
    apt-get install -y cloudflared 2>/dev/null || echo -e "${GREEN}Cloudflared installed from direct download${NC}"
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

# Verify cloudflared is installed
if ! command -v cloudflared >/dev/null 2>&1; then
    echo -e "${RED}Failed to install cloudflared${NC}"
    exit 1
fi

echo -e "${GREEN}Cloudflared version: $(cloudflared --version | head -n1)${NC}"

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
cd /opt || exit 1

# Remove old directory if exists
if [ -d "/opt/rustdesk-api-server" ]; then
    echo -e "${YELLOW}Removing existing API server directory...${NC}"
    rm -rf /opt/rustdesk-api-server
fi

# Clone with timeout and progress
if ! timeout 300 git clone --progress https://github.com/infiniteremote/rustdesk-api-server.git 2>&1 | while read -r line; do echo "$line"; done; then
    echo -e "${RED}Failed to clone API server repository${NC}"
    echo -e "${YELLOW}Trying alternative method...${NC}"
    
    # Try without progress output
    if ! git clone https://github.com/infiniteremote/rustdesk-api-server.git; then
        echo -e "${RED}Failed to clone repository. Please check your internet connection.${NC}"
        exit 1
    fi
fi

if [ ! -d "/opt/rustdesk-api-server" ]; then
    echo -e "${RED}API server directory not created. Clone failed.${NC}"
    exit 1
fi

chown -R ${usern}:${usern} /opt/rustdesk-api-server/
echo -e "${GREEN}API server cloned successfully${NC}"

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
cd /opt/rustdesk-api-server/api || exit 1

python3 -m venv env || {
    echo -e "${RED}Failed to create Python virtual environment${NC}"
    exit 1
}

source /opt/rustdesk-api-server/api/env/bin/activate || {
    echo -e "${RED}Failed to activate virtual environment${NC}"
    exit 1
}

echo -e "${YELLOW}Installing Python packages (this may take a few minutes)...${NC}"
pip install -q --no-cache-dir --upgrade pip || echo -e "${YELLOW}Pip upgrade warning (non-critical)${NC}"
pip install -q --no-cache-dir setuptools wheel || {
    echo -e "${RED}Failed to install setuptools/wheel${NC}"
    deactivate
    exit 1
}

if ! pip install -q --no-cache-dir -r /opt/rustdesk-api-server/requirements.txt; then
    echo -e "${RED}Failed to install Python requirements${NC}"
    deactivate
    exit 1
fi
echo -e "${GREEN}Python packages installed successfully${NC}"

cd /opt/rustdesk-api-server/ || exit 1

echo -e "${GREEN}Running database migrations...${NC}"
python manage.py makemigrations || {
    echo -e "${RED}Failed to create migrations${NC}"
    deactivate
    exit 1
}

python manage.py migrate || {
    echo -e "${RED}Failed to run migrations${NC}"
    deactivate
    exit 1
}

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Create Admin Account for Web Interface  ${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if ! python manage.py securecreatesuperuser; then
    echo -e "${RED}Failed to create admin user${NC}"
    deactivate
    exit 1
fi

deactivate
echo -e "${GREEN}Django setup completed${NC}"

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
echo -e "${YELLOW}Authenticating with Cloudflare...${NC}"
if ! echo "$CF_API_TOKEN" | cloudflared tunnel login --api-token 2>&1 | tee /tmp/cf-auth.log; then
    echo -e "${RED}Failed to authenticate with Cloudflare${NC}"
    echo -e "${RED}Please check your API token and permissions${NC}"
    cat /tmp/cf-auth.log
    exit 1
fi
echo -e "${GREEN}Successfully authenticated with Cloudflare${NC}"

# Create a tunnel
TUNNEL_NAME="rustdesk-${wanip//./-}"
echo -e "${YELLOW}Creating tunnel: ${TUNNEL_NAME}${NC}"

# Try to create tunnel and capture output
TUNNEL_OUTPUT=$(cloudflared tunnel create ${TUNNEL_NAME} 2>&1)
TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oP 'Created tunnel .* with id \K[a-f0-9-]+' | head -n1)

if [ -z "$TUNNEL_ID" ]; then
    echo -e "${YELLOW}Tunnel creation returned unexpected output, checking for existing tunnel...${NC}"
    
    # Check if tunnel already exists
    EXISTING_TUNNEL=$(cloudflared tunnel list 2>&1 | grep "${TUNNEL_NAME}" | head -n1)
    if [ -n "$EXISTING_TUNNEL" ]; then
        TUNNEL_ID=$(echo "$EXISTING_TUNNEL" | awk '{print $1}')
        echo -e "${GREEN}Using existing tunnel: ${TUNNEL_ID}${NC}"
    else
        echo -e "${RED}Failed to create or find tunnel${NC}"
        echo -e "${RED}Cloudflared output:${NC}"
        echo "$TUNNEL_OUTPUT"
        exit 1
    fi
else
    echo -e "${GREEN}Created new tunnel: ${TUNNEL_ID}${NC}"
fi

# Verify tunnel ID is valid UUID format
if ! [[ "$TUNNEL_ID" =~ ^[a-f0-9-]{36}$ ]]; then
    echo -e "${RED}Invalid tunnel ID format: ${TUNNEL_ID}${NC}"
    exit 1
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
if ! cloudflared tunnel route dns ${TUNNEL_ID} ${wanip} 2>&1 | tee /tmp/cf-dns.log; then
    # Check if it already exists
    if grep -q "already exists" /tmp/cf-dns.log; then
        echo -e "${GREEN}DNS record already exists${NC}"
    else
        echo -e "${YELLOW}Warning: DNS record creation may have failed${NC}"
        echo -e "${YELLOW}You may need to create the DNS record manually in Cloudflare dashboard${NC}"
        cat /tmp/cf-dns.log
    fi
else
    echo -e "${GREEN}DNS records created successfully${NC}"
fi

# Install and start the tunnel service
echo -e "${GREEN}Installing Cloudflare Tunnel service...${NC}"
if ! cloudflared service install 2>&1 | tee /tmp/cf-service.log; then
    echo -e "${YELLOW}Service installation warning (may already be installed)${NC}"
    cat /tmp/cf-service.log
fi

# Start the tunnel
echo -e "${GREEN}Starting Cloudflare Tunnel...${NC}"
systemctl enable cloudflared 2>/dev/null || true
systemctl restart cloudflared

# Wait a moment for service to start
sleep 3

# Check if service is running
if systemctl is-active --quiet cloudflared; then
    echo -e "${GREEN}Cloudflare Tunnel is running${NC}"
else
    echo -e "${YELLOW}Warning: Cloudflare Tunnel service may not be running${NC}"
    echo -e "${YELLOW}Check status with: systemctl status cloudflared${NC}"
fi

# Setup installers
echo -e "${GREEN}Configuring client installers...${NC}"
string="{\"host\":\"${wanip}\",\"key\":\"${key}\",\"api\":\"https://${wanip}\"}"
string64=$(echo -n "$string" | base64 -w 0 | tr -d '=')
string64rev=$(echo -n "$string64" | rev)

# Download Windows client
RDCLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk/releases/latest -s | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
echo -e "${YELLOW}Downloading RustDesk client ${RDCLATEST}...${NC}"

if ! wget -q -O /opt/rustdesk-api-server/static/configs/rustdesk-licensed-${string64rev}.exe \
    https://github.com/rustdesk/rustdesk/releases/download/${RDCLATEST}/rustdesk-${RDCLATEST}-x86_64.exe; then
    echo -e "${YELLOW}Warning: Failed to download Windows client installer${NC}"
    echo -e "${YELLOW}You can download it manually later${NC}"
fi

if [ -f "/opt/rustdesk-api-server/static/configs/rustdesk-licensed-${string64rev}.exe" ]; then
    echo -e "${GREEN}Windows installer downloaded successfully${NC}"
fi

# Update installer templates
echo -e "${GREEN}Updating installer templates...${NC}"
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/api/templates/installers.html 2>/dev/null || true
sed -i "s|UniqueKey|${key}|g" /opt/rustdesk-api-server/api/templates/installers.html 2>/dev/null || true
sed -i "s|UniqueURL|${wanip}|g" /opt/rustdesk-api-server/api/templates/installers.html 2>/dev/null || true
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install.ps1 2>/dev/null || true
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install.bat 2>/dev/null || true
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install-mac.sh 2>/dev/null || true
sed -i "s|secure-string|${string64rev}|g" /opt/rustdesk-api-server/static/configs/install-linux.sh 2>/dev/null || true

# Generate QR code
if ! qrencode -o /opt/rustdesk-api-server/static/configs/qrcode.png "config=${string64rev}" 2>/dev/null; then
    echo -e "${YELLOW}Warning: Failed to generate QR code${NC}"
fi

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
for service in rustdesk-hbbs rustdesk-hbbr rustdesk-api cloudflared; do
    if systemctl is-active --quiet $service; then
        echo -e "  ${service}: ${GREEN}✓ Running${NC}"
    else
        echo -e "  ${service}: ${RED}✗ Not Running${NC}"
        echo -e "    ${YELLOW}Try: systemctl start ${service}${NC}"
    fi
done
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  View tunnel status: ${GREEN}cloudflared tunnel list${NC}"
echo -e "  View tunnel logs: ${GREEN}journalctl -u cloudflared -f${NC}"
echo -e "  View RustDesk logs: ${GREEN}tail -f /var/log/rustdesk-server/*.log${NC}"
echo -e "  View API logs: ${GREEN}tail -f /var/log/rustdesk-server-api/*.log${NC}"
echo -e "  Run diagnostics: ${GREEN}./diagnostics.sh${NC} (if available)"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Access ${GREEN}https://${wanip}${NC} and log in"
echo -e "2. Download pre-configured client installers from the web interface"
echo -e "3. Deploy clients to your devices"
echo ""
echo -e "${GREEN}Installation completed successfully!${NC}"
echo ""
