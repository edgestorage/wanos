#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Uninstall Function ---
do_uninstall() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${RED}      WANOS Uninstall Script              ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    # Check for root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        echo -e "Please run with sudo."
        exit 1
    fi
    
    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}No WANOS installation found in current directory.${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}WARNING: This will stop and remove all WANOS containers.${NC}"
    echo -n "Are you sure you want to continue? [y/N]: "
    read CONFIRM < /dev/tty
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
    
    # Stop and remove containers
    echo -e "\n${BLUE}Stopping WANOS services...${NC}"
    docker compose down
    
    # Ask about volumes
    echo -e "\n${YELLOW}Do you want to delete all data volumes (DATABASE, Caddy certs)?${NC}"
    echo -e "${RED}WARNING: This will permanently delete all stored data!${NC}"
    echo -n "Delete volumes? [y/N]: "
    read DEL_VOLUMES < /dev/tty
    if [[ "$DEL_VOLUMES" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Removing volumes...${NC}"
        docker compose down -v
        # Also remove local data directory if exists
        if [ -d "./data" ]; then
            echo -e "${BLUE}Removing local data directory...${NC}"
            rm -rf ./data
        fi
        echo -e "${GREEN}Volumes removed.${NC}"
    fi
    
    # Ask about config files
    echo -e "\n${YELLOW}Do you want to delete configuration files?${NC}"
    echo "(docker-compose.yml, .env, Caddyfile)"
    echo -n "Delete config files? [y/N]: "
    read DEL_CONFIG < /dev/tty
    if [[ "$DEL_CONFIG" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Removing configuration files...${NC}"
        rm -f docker-compose.yml docker-compose.yml.bak
        rm -f .env .env.bak
        rm -f Caddyfile
        echo -e "${GREEN}Configuration files removed.${NC}"
    fi
    
    echo -e "\n${GREEN}WANOS has been uninstalled.${NC}"
    exit 0
}

# --- Command Parsing ---
case "${1:-}" in
    uninstall|remove|--uninstall|--remove)
        do_uninstall
        ;;
    help|--help|-h)
        echo "WANOS Installation Script"
        echo ""
        echo "Usage:"
        echo "  ./install.sh              Install or upgrade WANOS"
        echo "  ./install.sh uninstall    Uninstall WANOS"
        echo "  ./install.sh help         Show this help message"
        exit 0
        ;;
esac

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}      WANOS Installation Script          ${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    echo -e "Please run with sudo."
    exit 1
fi

# Check for existing installation or running containers
INSTALL_DETECTED=false
DETECT_MSG=""

if [ -f "docker-compose.yml" ]; then
    INSTALL_DETECTED=true
    DETECT_MSG="Detected existing installation (docker-compose.yml found)."
fi

if command -v docker &> /dev/null; then
    # Check for running containers via compose
    if [ -f "docker-compose.yml" ] && [ -n "$(docker compose ps -q 2>/dev/null)" ]; then
        INSTALL_DETECTED=true
        DETECT_MSG="Detected WANOS services are currently running."
    # Fallback: check by name if compose file missing or just general check
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "wanos"; then
        INSTALL_DETECTED=true
        DETECT_MSG="Detected running WANOS containers."
    fi
fi

if [ "$INSTALL_DETECTED" = true ]; then
    echo -e "${BLUE}$DETECT_MSG${NC}"
    echo -n "Do you want to upgrade? [Y/n]: "
    read UPGRADE_REQ < /dev/tty
    UPGRADE_REQ=${UPGRADE_REQ:-Y}
    if [[ ! "$UPGRADE_REQ" =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 0
    fi
fi

# --- Confirm Installation Directory ---
CURRENT_DIR=$(pwd)
echo -e "Installation will occur in the current directory: ${BLUE}$CURRENT_DIR${NC}"
echo -n "Do you want to continue? [y/N]: "
read CONFIRM_INSTALL < /dev/tty
if [[ ! "$CONFIRM_INSTALL" =~ ^[Yy]$ ]]; then
    echo "Installation aborted."
    exit 1
fi

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${BLUE}Docker not found. Installing Docker...${NC}"
    if curl -fsSL https://get.docker.com | sh; then
        echo -e "${GREEN}Docker installed successfully.${NC}"
    else
        echo -e "\033[0;31mFailed to install Docker. Please install Docker manually.\033[0m"
        exit 1
    fi
else
    echo -e "${GREEN}Docker is already installed.${NC}"
fi

# Prepare .env file
CONF_FILE=".env"
# Start with a fresh .env or append? Let's backup if exists
if [ -f "$CONF_FILE" ]; then
    echo -e "${BLUE}Backing up existing .env to .env.bak${NC}"
    cp "$CONF_FILE" "$CONF_FILE.bak"
fi

# Initialize .env content
cat > "$CONF_FILE" <<EOL
# WANOS Configuration
# Generated by install.sh

EOL

# --- Database Selection ---
echo -e "\n${BLUE}Database Configuration${NC}"
echo "Choose database type:"
echo "1) PostgreSQL (Default, Recommended)"
echo "2) SQLite (For Testing Only)"
echo -n "Enter choice [1/2]: "
read DB_CHOICE < /dev/tty
DB_CHOICE=${DB_CHOICE:-1}

if [ "$DB_CHOICE" == "1" ]; then
    echo -e "\n${BLUE}PostgreSQL setup${NC}"
    echo "1) Auto-deploy via Docker (Default)"
    echo "2) Use external PostgreSQL"
    echo -n "Enter choice [1/2]: "
    read PG_MODE < /dev/tty
    PG_MODE=${PG_MODE:-1}
    
    if [ "$PG_MODE" == "1" ]; then
        # Docker Mode
        echo -n "Enter Postgres User [wanos]: "
        read POSTGRES_USER < /dev/tty
        POSTGRES_USER=${POSTGRES_USER:-wanos}
        
        echo -n "Enter Postgres Password [wanos]: "
        read POSTGRES_PASSWORD < /dev/tty
        POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-wanos}
        
        echo -n "Enter Postgres DB Name [wanos]: "
        read POSTGRES_DB < /dev/tty
        POSTGRES_DB=${POSTGRES_DB:-wanos}
        
        DB_DSN="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
        
        # Enable profile
        cat >> "$CONF_FILE" <<EOL
DB_TYPE=postgres
DB_DSN=$DB_DSN
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
COMPOSE_PROFILES=postgres
EOL
    else
        # External Mode
        echo -n "Enter External Host [127.0.0.1]: "
        read EXT_HOST < /dev/tty
        EXT_HOST=${EXT_HOST:-127.0.0.1}
        
        echo -n "Enter External Port [5432]: "
        read EXT_PORT < /dev/tty
        EXT_PORT=${EXT_PORT:-5432}

        echo -n "Enter Postgres User [wanos]: "
        read POSTGRES_USER < /dev/tty
        POSTGRES_USER=${POSTGRES_USER:-wanos}
        
        echo -n "Enter Postgres Password [wanos]: "
        read POSTGRES_PASSWORD < /dev/tty
        POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-wanos}
        
        echo -n "Enter Postgres DB Name [wanos]: "
        read POSTGRES_DB < /dev/tty
        POSTGRES_DB=${POSTGRES_DB:-wanos}
        
        DB_DSN="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${EXT_HOST}:${EXT_PORT}/${POSTGRES_DB}?sslmode=disable"
        
        cat >> "$CONF_FILE" <<EOL
DB_TYPE=postgres
DB_DSN=$DB_DSN
EOL
    fi
    echo -e "${GREEN}Configured for PostgreSQL.${NC}"
else
    # SQLite
    DB_TYPE="sqlite"
    DB_DSN="/data/wanos.db"
    cat >> "$CONF_FILE" <<EOL
DB_TYPE=sqlite
DB_DSN=$DB_DSN
EOL
    echo -e "${GREEN}Configured for SQLite.${NC}"
fi

# --- Network Configuration ---
echo -e "\n${BLUE}Network Configuration${NC}"

HOST_IP=""
# Try ip route (Linux)
if command -v ip >/dev/null 2>&1; then
    HOST_IP=$(ip route get 1 2>/dev/null | awk '{print $7;exit}')
fi

# Try hostname -I (Linux)
if [ -z "$HOST_IP" ] && command -v hostname >/dev/null 2>&1; then
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

# Try ifconfig (Mac/BSD)
if [ -z "$HOST_IP" ] && command -v ifconfig >/dev/null 2>&1; then
    HOST_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
fi

HOST_IP=${HOST_IP:-localhost}
echo "Detected Server IP: $HOST_IP"

cat >> "$CONF_FILE" <<EOL
HOST_IP=$HOST_IP
EOL

# --- Reverse Proxy Configuration ---
echo -e "\n${BLUE}Reverse Proxy Configuration${NC}"
echo "Choose reverse proxy mode:"
echo "1) Self-managed (Default, expose ports 3000/9000-9002 directly)"
echo "2) Caddy (Auto HTTPS with Let's Encrypt)"
echo -n "Enter choice [1/2]: "
read PROXY_CHOICE < /dev/tty
PROXY_CHOICE=${PROXY_CHOICE:-1}

USE_CADDY=false
if [ "$PROXY_CHOICE" == "2" ]; then
    USE_CADDY=true
    
    echo -n "Enter your domain (e.g., wanos.example.com): "
    read DOMAIN < /dev/tty
    
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Domain is required for Caddy. Falling back to self-managed mode.${NC}"
        USE_CADDY=false
    else
        echo -e "\n${BLUE}TLS Mode${NC}"
        echo "1) Auto (Let's Encrypt - requires public domain + ports 80/443 accessible)"
        echo "2) Internal (Self-signed certificate - for testing/internal use)"
        echo -n "Enter choice [1/2]: "
        read TLS_CHOICE < /dev/tty
        TLS_CHOICE=${TLS_CHOICE:-1}
        
        if [ "$TLS_CHOICE" == "1" ]; then
            TLS_MODE=""  # Empty means auto in Caddy
        else
            TLS_MODE="internal"
        fi
        
        # Append caddy to COMPOSE_PROFILES
        if grep -q "COMPOSE_PROFILES=" "$CONF_FILE"; then
            # Append to existing COMPOSE_PROFILES
            sed -i.bak 's/COMPOSE_PROFILES=\(.*\)/COMPOSE_PROFILES=\1,caddy/' "$CONF_FILE"
            rm -f "$CONF_FILE.bak"
        else
            echo "COMPOSE_PROFILES=caddy" >> "$CONF_FILE"
        fi
        
        cat >> "$CONF_FILE" <<EOL
DOMAIN=$DOMAIN
TLS_MODE=$TLS_MODE
EOL
        echo -e "${GREEN}Caddy reverse proxy configured for $DOMAIN.${NC}"
    fi
fi

if [ "$USE_CADDY" = false ]; then
    echo -e "${GREEN}Self-managed mode selected. Ports will be exposed directly.${NC}"
fi

# --- Admin Credentials --- (Optional, can rely on defaults)
echo -e "\n${BLUE}Admin Credentials${NC}"
echo -n "Set Admin Username [admin]: "
read ADMIN_USER < /dev/tty
ADMIN_USER=${ADMIN_USER:-admin}

echo -n "Set Admin Password [Press Enter for Random]: "
read ADMIN_PASSWORD < /dev/tty

if [ -z "$ADMIN_PASSWORD" ]; then
    # Generate random password (alphanumeric)
    if command -v openssl &> /dev/null; then
        ADMIN_PASSWORD=$(openssl rand -base64 15 | tr -dc 'a-zA-Z0-9' | head -c 12)
    else
        ADMIN_PASSWORD=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 12)
    fi
    echo -e "Generated Admin Password: ${GREEN}$ADMIN_PASSWORD${NC}"
fi

# --- Security Secrets ---
echo -e "\n${BLUE}Generating Security Secrets...${NC}"

# Generate random SESSION_SECRET if not already set
if [ -z "$SESSION_SECRET" ]; then
    if command -v openssl &> /dev/null; then
        SESSION_SECRET=$(openssl rand -hex 32)
    elif command -v python3 &> /dev/null; then
        SESSION_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    else
        SESSION_SECRET=$(head -c 32 /dev/urandom | base64)
    fi
    echo "Generated SESSION_SECRET."
fi

# Generate AKSK_SECRET_KEY (32 bytes base64)
if command -v openssl &> /dev/null; then
    AKSK_SECRET_KEY=$(openssl rand -base64 32)
elif command -v python3 &> /dev/null; then
    AKSK_SECRET_KEY=$(python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())")
else 
    echo "Warning: openssl and python3 not found. Using weaker key generation."
    AKSK_SECRET_KEY=$(head -c 32 /dev/urandom | base64)
fi
echo "Generated AKSK_SECRET_KEY."

cat >> "$CONF_FILE" <<EOL
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$ADMIN_PASSWORD
SESSION_SECRET=$SESSION_SECRET
AKSK_SECRET_KEY=$AKSK_SECRET_KEY
EOL


echo -e "\n${GREEN}Configuration saved to $CONF_FILE.${NC}"

# --- Prepare Files ---
echo -e "\n${BLUE}Downloading deployment files...${NC}"

GITHUB_RAW_URL="https://raw.githubusercontent.com/edgestorage/wanos/main/deploy/docker-compose.yml"

if [ -d ".git" ]; then
    echo -e "${GREEN}Git repository detected. Using local docker-compose.yml.${NC}"
else
    if [ -f "docker-compose.yml" ]; then
        echo -e "${BLUE}Backing up existing docker-compose.yml...${NC}"
        mv -f docker-compose.yml docker-compose.yml.bak
    fi

    echo "Downloading docker-compose.yml from GitHub..."
    if curl -fsSL "$GITHUB_RAW_URL" -o docker-compose.yml; then
        echo -e "${GREEN}Downloaded docker-compose.yml successfully.${NC}"
    else
        echo -e "\033[0;31mFailed to download docker-compose.yml. Please check your network.${NC}"
        if [ -f "docker-compose.yml.bak" ]; then
            echo "Restoring backup..."
            mv docker-compose.yml.bak docker-compose.yml
        fi
        exit 1
    fi
fi

# --- Port Check ---
echo -e "\n${BLUE}Checking Ports...${NC}"

if [ "$USE_CADDY" = true ]; then
    REQUIRED_PORTS=(80 443)
    PORT_DESC="80, 443"
else
    REQUIRED_PORTS=(3000 9000 9001 9002)
    PORT_DESC="3000, 9000-9002"
fi

PORT_BUSY=false

for PORT in "${REQUIRED_PORTS[@]}"; do
    if command -v lsof &> /dev/null; then
        if lsof -i :$PORT >/dev/null 2>&1; then
            echo -e "\033[0;31mError: Port $PORT is already in use.\033[0m"
            PORT_BUSY=true
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -an | grep ":$PORT " | grep "LISTEN" >/dev/null 2>&1; then
             echo -e "\033[0;31mError: Port $PORT is already in use.\033[0m"
             PORT_BUSY=true
        fi
    else
         # Fallback verification skipped if tools missing, or warn user?
         # Just proceed with warning.
         echo "Warning: Cannot verify port $PORT (lsof/netstat not found)."
    fi
done

if [ "$PORT_BUSY" = true ]; then
    echo -e "\033[0;31mAborting installation due to port conflicts.\nPlease free up ports $PORT_DESC and try again.\033[0m"
    exit 1
fi
echo -e "${GREEN}Ports $PORT_DESC are available.${NC}"

# --- Download Caddyfile if using Caddy ---
if [ "$USE_CADDY" = true ]; then
    CADDYFILE_URL="https://raw.githubusercontent.com/edgestorage/wanos/main/deploy/Caddyfile"
    
    if [ -d ".git" ]; then
        echo -e "${GREEN}Git repository detected. Using local Caddyfile.${NC}"
    else
        echo "Downloading Caddyfile from GitHub..."
        if curl -fsSL "$CADDYFILE_URL" -o Caddyfile; then
            echo -e "${GREEN}Downloaded Caddyfile successfully.${NC}"
        else
            echo -e "${RED}Failed to download Caddyfile. Creating default...${NC}"
            cat > Caddyfile <<'CADDYEOF'
# WANOS Caddyfile
{$DOMAIN:localhost} {
    tls {$TLS_MODE:internal}
    reverse_proxy console:3000
}

s3.{$DOMAIN:localhost} {
    tls {$TLS_MODE:internal}
    reverse_proxy server:9000
}

api.{$DOMAIN:localhost} {
    tls {$TLS_MODE:internal}
    reverse_proxy server:9001
}

webdav.{$DOMAIN:localhost} {
    tls {$TLS_MODE:internal}
    reverse_proxy server:9002
}

# Catch-all: unmatched domains default to S3
:443 {
    tls {$TLS_MODE:internal}
    reverse_proxy server:9000
}

:80 {
    reverse_proxy server:9000
}
CADDYEOF
        fi
    fi
fi

# --- Launch ---
echo -e "\n${BLUE}Starting Services...${NC}"

# Docker compose will pick up COMPOSE_PROFILES if set
docker compose up -d

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}Success! WANOS is running.${NC}"
    
    if [ "$USE_CADDY" = true ]; then
        PROTOCOL="https"
        if [ "$TLS_MODE" = "internal" ]; then
            echo -e "${BLUE}Note: Using self-signed certificate. Your browser may show a security warning.${NC}"
        fi
        echo -e "Console:  ${PROTOCOL}://${DOMAIN}"
        echo -e "S3 API:   ${PROTOCOL}://s3.${DOMAIN}"
        echo -e "API:      ${PROTOCOL}://api.${DOMAIN}"
        echo -e "WebDAV:   ${PROTOCOL}://webdav.${DOMAIN}"
        echo -e "\n${BLUE}Make sure to configure DNS records pointing to this server:${NC}"
        echo -e "  ${DOMAIN}        -> ${HOST_IP}"
        echo -e "  s3.${DOMAIN}     -> ${HOST_IP}"
        echo -e "  api.${DOMAIN}    -> ${HOST_IP}"
        echo -e "  webdav.${DOMAIN} -> ${HOST_IP}"
    else
        echo -e "Console:  http://${HOST_IP}:3000"
        echo -e "S3 API:   http://${HOST_IP}:9000"
        echo -e "API:      http://${HOST_IP}:9001"
        echo -e "WebDAV:   http://${HOST_IP}:9002"
    fi
else
    echo -e "\n\033[0;31mFailed to start services. Check logs with 'docker compose logs -f'\033[0m"
fi
