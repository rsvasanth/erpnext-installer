#!/usr/bin/env bash

# ERPNext Version 16 Beta 2 Installer - Optimized
# Supports Ubuntu 22.04+, Debian 12+

set -euo pipefail

# Color definitions
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly LIGHT_BLUE='\033[1;34m'
readonly NC='\033[0m'

# Version configuration for ERPNext v16
readonly BENCH_VERSION="v16.0.0-beta.2"
readonly PYTHON_MIN_VERSION="3.10"
readonly NODE_VERSION="22"
readonly MIN_UBUNTU_VERSION="22.04"
readonly MIN_DEBIAN_VERSION="12"

# Global state for detected python
PYTHON_BIN="python3"

# Error handler
handle_error() {
    echo -e "${RED}Error on line $1 with exit code $2${NC}" >&2
    exit "$2"
}

trap 'handle_error ${LINENO} $?' ERR

# Version comparison: returns 0 if $1 >= $2
version_ge() {
    [[ "$1" == "$(echo -e "$1\n$2" | sort -V | tail -n1)" ]]
}

# Logging helpers
log_info() {
    echo -e "${LIGHT_BLUE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

# Password prompt with confirmation
ask_password() {
    local prompt="$1"
    local val1 val2

    while true; do
        read -rsp "$prompt: " val1
        echo >&2
        read -rsp "Confirm password: " val2
        echo >&2

        if [[ "$val1" == "$val2" ]]; then
            log_success "Password confirmed"
            echo "$val1"
            return
        else
            log_error "Passwords do not match. Please try again."
            echo >&2
        fi
    done
}

# Check OS compatibility for v16
check_os_compatibility() {
    local os_name os_version
    os_name=$(lsb_release -is 2>/dev/null)
    os_version=$(lsb_release -rs 2>/dev/null)

    log_info "Detected OS: $os_name $os_version"

    case "$os_name" in
        Ubuntu)
            if ! version_ge "$os_version" "$MIN_UBUNTU_VERSION"; then
                log_error "ERPNext v16 requires Ubuntu $MIN_UBUNTU_VERSION or higher. Current: $os_version"
                exit 1
            fi
            ;;
        Debian)
            if ! version_ge "$os_version" "$MIN_DEBIAN_VERSION"; then
                log_error "ERPNext v16 requires Debian $MIN_DEBIAN_VERSION or higher. Current: $os_version"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported OS: $os_name. ERPNext v16 requires Ubuntu 22.04+ or Debian 12+"
            exit 1
            ;;
    esac

    log_success "OS compatibility check passed"
}

# Prompt for confirmation
confirm_action() {
    local prompt="$1"
    local response

    while true; do
        read -rp "$prompt (yes/no): " response
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
        
        case "$response" in
            yes|y) return 0 ;;
            no|n) return 1 ;;
            *) log_error "Invalid response. Please answer 'yes' or 'no'." ;;
        esac
    done
}

# Install system packages
install_system_packages() {
    log_warning "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    log_success "System packages updated"

    log_warning "Installing required packages..."
    sudo apt install -y \
        software-properties-common \
        git curl wget bc pkg-config \
        build-essential \
        python3-dev python3-setuptools python3-pip python3-venv \
        redis-server \
        libssl-dev libffi-dev libsqlite3-dev \
        libncurses5-dev libgdbm-dev libnss3-dev \
        libreadline-dev libbz2-dev zlib1g-dev \
        mariadb-server mariadb-client \
        libmariadb-dev libcups2-dev \
        fontconfig libxrender1 xfonts-75dpi xfonts-base xvfb \
        npm snapd

    log_success "System packages installed"
}

# Install Python 3.11
install_python() {
    local current_version
    current_version=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)

    if version_ge "$current_version" "$PYTHON_MIN_VERSION"; then
        log_success "System Python $current_version is compatible."
        PYTHON_BIN="python3"
        return
    fi

    log_warning "Installing Python 3.11 as system python $current_version is too old..."
    
    local py_full="3.11.7"
    wget -q "https://www.python.org/ftp/python/${py_full}/Python-${py_full}.tgz"
    tar -xf "Python-${py_full}.tgz"
    cd "Python-${py_full}"
    
    ./configure --prefix=/usr/local --enable-optimizations --enable-shared \
        LDFLAGS="-Wl,-rpath /usr/local/lib"
    make -j "$(nproc)"
    sudo make altinstall
    
    cd ..
    rm -rf "Python-${py_full}" "Python-${py_full}.tgz"
    
    PYTHON_BIN="python3.11"
    "$PYTHON_BIN" -m pip install --user --upgrade pip
    
    log_success "Python 3.11 installed"
}

# Install wkhtmltopdf
install_wkhtmltopdf() {
    log_warning "Installing wkhtmltopdf..."
    
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac

    wget -q "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${arch}.deb"
    sudo dpkg -i "wkhtmltox_0.12.6.1-3.jammy_${arch}.deb" 2>/dev/null || true
    sudo apt --fix-broken install -y -qq
    sudo cp /usr/local/bin/wkhtmlto* /usr/bin/ 2>/dev/null || true
    sudo chmod a+x /usr/bin/wkhtmlto* 2>/dev/null || true
    rm "wkhtmltox_0.12.6.1-3.jammy_${arch}.deb"
    
    log_success "wkhtmltopdf installed"
}

# Configure MariaDB
configure_mariadb() {
    local sql_password="$1"
    local marker_file="$HOME/.mysql_configured_v16.marker"

    if [[ -f "$marker_file" ]]; then
        log_success "MariaDB already configured"
        return
    fi

    log_warning "Configuring MariaDB..."

    # Configure character set for v16
    sudo tee /etc/mysql/mariadb.conf.d/z_frappe.cnf >/dev/null <<-'EOF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

    sudo systemctl restart mysql

    # Secure installation and set password for Ubuntu 24.04+ plugin compatibility
    sudo mysql <<-EOSQL
		ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$sql_password');
		DELETE FROM mysql.user WHERE User='';
		DROP DATABASE IF EXISTS test;
		DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
		FLUSH PRIVILEGES;
	EOSQL

    touch "$marker_file"
    log_success "MariaDB configured"
}

# Install Node.js via NVM
install_nodejs() {
    log_warning "Installing Node.js $NODE_VERSION via NVM..."

    # Install NVM
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash >/dev/null 2>&1

    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    # Install Node
    nvm install "$NODE_VERSION" >/dev/null 2>&1
    nvm alias default "$NODE_VERSION" >/dev/null 2>&1
    nvm use "$NODE_VERSION" >/dev/null 2>&1

    # Install Yarn
    npm install -g yarn >/dev/null 2>&1

    log_success "Node.js $NODE_VERSION and Yarn installed"
}

# Install Frappe Bench
install_bench() {
    log_warning "Installing Frappe Bench..."

    # Handle PEP 668 (externally managed environment)
    local py_ver
    py_ver=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    if [[ -f "/usr/lib/python${py_ver}/EXTERNALLY-MANAGED" ]]; then
        sudo rm -f "/usr/lib/python${py_ver}/EXTERNALLY-MANAGED"
    fi

    sudo "$PYTHON_BIN" -m pip install frappe-bench
    
    log_success "Frappe Bench installed"
}

# Initialize Bench
init_bench() {
    log_warning "Initializing Frappe Bench..."
    
    # Ensure pkg-config is available for the current user session
    if ! command -v pkg-config &>/dev/null; then
        log_error "pkg-config is still not found in PATH. Attempting force install..."
        sudo apt install -y pkg-config
    fi
    
    cd "$HOME"
    if [[ -d "frappe-bench" ]]; then
        if [[ ! -f "frappe-bench/env/bin/python" ]]; then
            log_warning "Incomplete frappe-bench found. Removing and re-initializing..."
            rm -rf frappe-bench
        else
            log_warning "frappe-bench directory already exists and seems valid. Skipping 'bench init'."
            return
        fi
    fi
    
    # Load NVM for bench init
    export NVM_DIR="$HOME/.nvm"
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    nvm use "$NODE_VERSION"

    bench init frappe-bench --version "$BENCH_VERSION" --verbose --python "$PYTHON_BIN"
    
    log_success "Frappe Bench initialized"
}

# Create new site
create_site() {
    local site_name="$1"
    local sql_password="$2"
    local admin_password="$3"

    log_warning "Creating site: $site_name..."
    
    cd "$HOME/frappe-bench"
    sudo chmod -R o+rx "$HOME"

    bench new-site "$site_name" \
        --db-root-username root \
        --db-root-password "$sql_password" \
        --admin-password "$admin_password"
    
    log_success "Site created: $site_name"
}

# Install ERPNext
install_erpnext() {
    local site_name="$1"
    
    log_warning "Installing ERPNext v16 beta 2..."
    
    cd "$HOME/frappe-bench"
    bench get-app erpnext --branch "$BENCH_VERSION"
    bench --site "$site_name" install-app erpnext
    
    log_success "ERPNext installed"
}

# Install HRMS
install_hrms() {
    local site_name="$1"
    
    log_warning "Installing HRMS..."
    
    cd "$HOME/frappe-bench"
    bench get-app hrms --branch "$BENCH_VERSION"
    bench --site "$site_name" install-app hrms
    
    log_success "HRMS installed"
}

# Setup production
setup_production() {
    local site_name="$1"
    
    log_warning "Setting up production environment..."
    
    cd "$HOME/frappe-bench"

    # Fix playbook include statements
    local python_ver
    python_ver=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    local playbook_file="/usr/local/lib/python${python_ver}/dist-packages/bench/playbooks/roles/mariadb/tasks/main.yml"
    
    if [[ ! -f "$playbook_file" ]]; then
        # Check system site-packages as well
        playbook_file="/usr/lib/python3/dist-packages/bench/playbooks/roles/mariadb/tasks/main.yml"
    fi
    
    if [[ -f "$playbook_file" ]]; then
        sudo sed -i 's/- include: /- include_tasks: /g' "$playbook_file"
    fi

    # Setup production
    yes | sudo bench setup production "$USER"

    # Configure supervisor
    local supervisor_conf="/etc/supervisor/supervisord.conf"
    if ! grep -q "chown=$USER:$USER" "$supervisor_conf"; then
        sudo sed -i "5a chown=$USER:$USER" "$supervisor_conf"
    fi

    sudo systemctl restart supervisor

    # Setup services for v16
    bench setup socketio
    yes | bench setup supervisor
    bench setup redis

    # Enable scheduler
    bench --site "$site_name" scheduler enable
    bench --site "$site_name" scheduler resume

    # Restart services
    sudo supervisorctl reload
    sudo chmod 755 "$HOME"

    log_success "Production environment configured"
}

# Install SSL certificate
install_ssl() {
    local site_name="$1"
    local email="$2"
    
    log_warning "Installing SSL certificate..."

    # Install certbot
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot

    # Obtain certificate
    sudo certbot --nginx --non-interactive --agree-tos \
        --email "$email" -d "$site_name"
    
    log_success "SSL certificate installed"
}

# Main installation flow
main() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    log_info "╔════════════════════════════════════════════╗"
    log_info "║  ERPNext v16 Beta 2 Installer (Optimized) ║"
    log_info "╚════════════════════════════════════════════╝"
    echo

    # Check OS compatibility
    check_os_compatibility
    echo

    # Confirm installation
    if ! confirm_action "Install ERPNext v16 Beta 2?"; then
        log_warning "Installation cancelled"
        exit 0
    fi

    # Get passwords
    log_warning "Configuration Setup"
    local sql_password admin_password
    sql_password=$(ask_password "MariaDB root password")
    echo
    admin_password=$(ask_password "ERPNext Administrator password")
    echo

    # Install packages
    install_system_packages
    install_python
    install_wkhtmltopdf
    configure_mariadb "$sql_password"
    install_nodejs
    install_bench
    init_bench

    # Create site
    echo
    read -rp "Enter site name (use FQDN for SSL): " site_name
    echo
    create_site "$site_name" "$sql_password" "$admin_password"

    # Install ERPNext
    if confirm_action "Install ERPNext?"; then
        install_erpnext "$site_name"
    fi

    # Production or Development
    echo
    if confirm_action "Setup for production?"; then
        setup_production "$site_name"

        # Install HRMS
        if confirm_action "Install HRMS?"; then
            install_hrms "$site_name"
        fi

        # Install SSL
        if confirm_action "Install SSL certificate?"; then
            read -rp "Enter email address: " email
            install_ssl "$site_name" "$email"
        fi

        echo
        log_success "════════════════════════════════════════════"
        log_success " Installation Complete! 🎉"
        log_success "════════════════════════════════════════════"
        log_success "Access your site at:"
        log_success "  https://$site_name (if SSL enabled)"
        log_success "  http://$server_ip"
        log_success ""
        log_success "Documentation: https://docs.erpnext.com"
        log_success "════════════════════════════════════════════"
    else
        # Development setup
        cd "$HOME/frappe-bench"
        bench use "$site_name"
        bench build

        echo
        log_success "════════════════════════════════════════════"
        log_success " Development Environment Ready! 🎉"
        log_success "════════════════════════════════════════════"
        log_success "Start with: cd ~/frappe-bench && bench start"
        log_success "Access at: http://$server_ip:8000"
        log_success ""
        log_success "Documentation: https://frappeframework.com"
        log_success "════════════════════════════════════════════"
    fi
}

# Run main function
main "$@"
