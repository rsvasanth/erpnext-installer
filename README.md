# ERPNext v16 Beta 2 Installer

An optimized installation script for ERPNext Version 16 Beta 2 on Ubuntu 22.04+ and Debian 12+.

## Features

- ✅ Automated installation of ERPNext v16 Beta 2
- ✅ Python 3.11 support
- ✅ Node.js 20 via NVM
- ✅ MariaDB configuration with proper character sets
- ✅ Production and development environment setup
- ✅ Optional HRMS installation
- ✅ Optional SSL certificate installation via Let's Encrypt
- ✅ Error handling and logging
- ✅ OS compatibility checks

## System Requirements

- Ubuntu 22.04 or higher
- Debian 12 or higher
- Minimum 2GB RAM (4GB recommended)
- Minimum 20GB disk space

## Usage

1. Make the script executable:
```bash
chmod +x install_erpnext_v16_beta2.sh
```

2. Run the installation script:
```bash
./install_erpnext_v16_beta2.sh
```

3. Follow the interactive prompts to configure your installation

## What Gets Installed

- Python 3.11
- Node.js 20 (via NVM)
- MariaDB
- Redis
- Nginx (for production setup)
- Supervisor (for production setup)
- wkhtmltopdf
- Frappe Framework v16 Beta 2
- ERPNext v16 Beta 2
- HRMS (optional)

## Documentation

- [ERPNext Documentation](https://docs.erpnext.com)
- [Frappe Framework Documentation](https://frappeframework.com)

## License

This is an installation script. ERPNext and Frappe Framework have their own licenses.
