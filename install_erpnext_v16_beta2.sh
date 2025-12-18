#!/usr/bin/env bash

# ERPNext Multi-Version Installer (Updated for v16)
# Supports Ubuntu 20.04 - 24.04 & Debian 10 - 12

# Setting error handler
handle_error() {
    local line=$1
    local exit_code=$2
    echo -e "${RED}An error occurred on line $line with exit status $exit_code${NC}"
    exit "$exit_code"
}

trap 'handle_error $LINENO $?' ERR
set -e

# Retrieve server IP
server_ip=$(hostname -I | awk '{print $1}')

# Setting up colors for echo commands
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
LIGHT_BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Logging helpers
log_info() { echo -e "${LIGHT_BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }

# Checking Supported OS and distribution
SUPPORTED_DISTRIBUTIONS=("Ubuntu" "Debian")
SUPPORTED_VERSIONS=("24.04" "23.04" "22.04" "20.04" "12" "11" "10" "9" "8")

check_os() {
    local os_name=$(lsb_release -is 2>/dev/null)
    local os_version=$(lsb_release -rs 2>/dev/null)
    local os_supported=false
    local version_supported=false

    for i in "${SUPPORTED_DISTRIBUTIONS[@]}"; do
        if [[ "$i" = "$os_name" ]]; then
            os_supported=true
            break
        fi
    done

    for i in "${SUPPORTED_VERSIONS[@]}"; do
        if [[ "$i" = "$os_version" ]]; then
            version_supported=true
            break
        fi
    done

    if [[ "$os_supported" = false ]] || [[ "$version_supported" = false ]]; then
        echo -e "${RED}This script is not compatible with your operating system or its version ($os_name $os_version).${NC}"
        exit 1
    fi
}

check_os

# Detect the platform
OS="`uname`"
case $OS in
  'Linux')
    OS='Linux'
    if [ -f /etc/redhat-release ] ; then
      DISTRO='CentOS'
    elif [ -f /etc/debian_version ] ; then
      if [ "$(lsb_release -si 2>/dev/null)" == "Ubuntu" ]; then
        DISTRO='Ubuntu'
      else
        DISTRO='Debian'
      fi
    fi
    ;;
  *) ;;
esac

ask_twice() {
    local prompt="$1"
    local secret="$2"
    local val1 val2

    while true; do
        if [ "$secret" = "true" ]; then
            read -rsp "$prompt: " val1
            echo >&2
        else
            read -rp "$prompt: " val1
            echo >&2
        fi

        if [ "$secret" = "true" ]; then
            read -rsp "Confirm password: " val2
            echo >&2
        else
            read -rp "Confirm password: " val2
            echo >&2
        fi

        if [ "$val1" = "$val2" ]; then
            printf "${GREEN}Password confirmed${NC}" >&2
            echo "$val1"
            break
        else
            printf "${RED}Inputs do not match. Please try again${NC}\n" >&2
            echo -e "\n"
        fi
    done
}

echo -e "${LIGHT_BLUE}Welcome to the ERPNext Multi-Version Installer...${NC}"
echo -e "\n"
sleep 1

# Selection menu
echo -e "${YELLOW}Please select the ERPNext version you wish to install:${NC}"
versions=("Version 13" "Version 14" "Version 15" "Version 16 (v16.0.0-beta.2)")
select version_choice in "${versions[@]}"; do
    case $REPLY in
        1) bench_version="version-13"; break;;
        2) bench_version="version-14"; break;;
        3) bench_version="version-15"; break;;
        4) bench_version="v16.0.0-beta.2"; break;;
        *) echo -e "${RED}Invalid option.${NC}";;
    esac
done

# Version Logic Verification
if [[ "$bench_version" == "v16.0.0-beta.2" ]]; then
    if [[ "$(lsb_release -rs 2>/dev/null)" < "22.04" ]]; then
        echo -e "${RED}Version 16 requires Ubuntu 22.04+ or Debian 12+.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Proceeding with the installation of $version_choice.${NC}"
sleep 1

# Passwords
echo -e "${YELLOW}Configuration Setup...${NC}"
sqlpasswrd=$(ask_twice "What is your required SQL root password" "true")
echo -e "\n"

# Update System
echo -e "${YELLOW}Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y

# Dependencies
echo -e "${YELLOW}Installing system requirements (including pkg-config and build tools)...${NC}"
sudo apt install -y software-properties-common git curl wget bc pkg-config build-essential \
    python3-dev python3-setuptools python3-venv python3-pip redis-server \
    libssl-dev libffi-dev libsqlite3-dev libncurses5-dev libgdbm-dev libnss3-dev \
    libreadline-dev libbz2-dev zlib1g-dev libmariadb-dev libcups2-dev \
    fontconfig libxrender1 xfonts-75dpi xfonts-base xvfb npm snapd

# Detect architecture for wkhtmltopdf
arch=$(uname -m)
case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) echo -e "${RED}Unsupported arch: $arch${NC}"; exit 1 ;;
esac

# wkhtmltopdf
if ! command -v wkhtmltopdf &>/dev/null; then
    wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_$arch.deb
    sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_$arch.deb || true
    sudo apt --fix-broken install -y
    sudo cp /usr/local/bin/wkhtmlto* /usr/bin/ 2>/dev/null || true
    sudo chmod a+x /usr/bin/wk* 2>/dev/null || true
    rm -f wkhtmltox_0.12.6.1-2.jammy_$arch.deb
fi

# MariaDB Setup with Ubuntu 24.04 Compatibility
echo -e "${YELLOW}Configuring MariaDB...${NC}"
sudo apt install -y mariadb-server mariadb-client

# Apply MariaDB Settings
sudo tee /etc/mysql/mariadb.conf.d/z_frappe.cnf >/dev/null <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

sudo systemctl restart mysql

# Secure MariaDB - Robust Authentication Handling
log_info "Applying MariaDB security settings and password..."

# SQL commands to run
SQL_CMDS=$(cat <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$sqlpasswrd');
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
)

# Try 3 ways to apply the changes
success=false

# 1. Try socket-based (no password, sudo)
if [[ "$success" = false ]] && sudo mysql -e "status" >/dev/null 2>&1; then
    log_info "Logging in via system socket..."
    echo "$SQL_CMDS" | sudo mysql && success=true
fi

# 2. Try maintenance user (debian.cnf)
if [[ "$success" = false ]] && [[ -f /etc/mysql/debian.cnf ]]; then
    log_info "Logging in via maintenance user..."
    echo "$SQL_CMDS" | sudo mysql --defaults-file=/etc/mysql/debian.cnf && success=true
fi

# 3. Try with the provided password
if [[ "$success" = false ]]; then
    log_info "Logging in with provided password..."
    export MYSQL_PWD="$sqlpasswrd"
    if echo "$SQL_CMDS" | sudo -E mysql -u root; then
        success=true
    else
        log_error "Could not gain root access to MariaDB. Please check if MariaDB is running and if the password is correct."
        exit 1
    fi
    unset MYSQL_PWD
fi

# Node.js
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if [[ "$bench_version" == "v16.0.0-beta.2" ]]; then
    node_version="22"
elif [[ "$bench_version" == "version-15" ]]; then
    node_version="18"
else
    node_version="16"
fi

nvm install $node_version
nvm use $node_version
nvm alias default $node_version
npm install -g yarn

# Install Bench
echo -e "${YELLOW}Installing Frappe Bench...${NC}"
# Handle PEP 668 for newer Ubuntu/Debian
sudo rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED 2>/dev/null || true
sudo python3 -m pip install --upgrade pip
sudo python3 -m pip install frappe-bench

# Initialize Bench
cd $HOME
if [[ -d "frappe-bench" ]]; then
    echo -e "${YELLOW}Removing existing frappe-bench for clean install...${NC}"
    rm -rf frappe-bench
fi

bench init frappe-bench --version $bench_version --verbose
cd frappe-bench

# Site Creation
echo -e "${YELLOW}Preparing site creation...${NC}"
read -p "Enter the site name (e.g., bookpondy.in): " site_name
adminpasswrd=$(ask_twice "Enter the ERPNext Administrator password" "true")

sudo chmod -R o+rx $HOME
bench new-site $site_name \
    --db-root-username root \
    --db-root-password "$sqlpasswrd" \
    --admin-password "$adminpasswrd"

# Install Apps
echo -e "${LIGHT_BLUE}Would you like to install ERPNext? (yes/no)${NC}"
read -p "Response: " erpnext_install
if [[ "$erpnext_install" =~ ^[Yy] ]]; then
    bench get-app erpnext --branch $bench_version
    bench --site $site_name install-app erpnext
fi

# Production Setup
echo -e "${LIGHT_BLUE}Would you like to setup for production? (yes/no)${NC}"
read -p "Response: " continue_prod
if [[ "$continue_prod" =~ ^[Yy] ]]; then
    # Fix Ansible include issue
    py_ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    pb_file="/usr/local/lib/python${py_ver}/dist-packages/bench/playbooks/roles/mariadb/tasks/main.yml"
    [[ ! -f "$pb_file" ]] && pb_file="/usr/lib/python${py_ver}/dist-packages/bench/playbooks/roles/mariadb/tasks/main.yml"
    
    if [[ -f "$pb_file" ]]; then
        sudo sed -i 's/- include: /- include_tasks: /g' "$pb_file"
    fi

    yes | sudo bench setup production $USER
    
    # Enable scheduler
    bench --site $site_name scheduler enable
    bench --site $site_name scheduler resume

    # SSL Cert
    echo -e "${LIGHT_BLUE}Install SSL certificate? (yes/no)${NC}"
    read -p "Response: " ssl_install
    if [[ "$ssl_install" =~ ^[Yy] ]]; then
        read -p "Enter email for SSL: " email
        sudo snap install --classic certbot
        sudo ln -sf /snap/bin/certbot /usr/bin/certbot
        sudo certbot --nginx --non-interactive --agree-tos --email "$email" -d "$site_name"
    fi
fi

echo -e "${GREEN}--------------------------------------------------------------------------------"
echo -e "Installation Complete! Access your site at: http://$server_ip"
echo -e "--------------------------------------------------------------------------------${NC}"
