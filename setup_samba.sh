```bash
#!/usr/bin/env bash

set -Eeuo pipefail

# --------------------------------------------------
# Samba File Sharing Setup
# Debian / Ubuntu Linux <-> Windows
# --------------------------------------------------

SHARE_NAME="sambashare"
LINUX_USER="when"
SHARE_DIR="/home/${LINUX_USER}/${SHARE_NAME}"
CONFIG="/etc/samba/smb.conf"
BACKUP="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

# --------------------------------------------------
# Check root privileges
# --------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run this script using sudo:"
    echo "sudo bash setup_samba.sh"
    exit 1
fi

# --------------------------------------------------
# Verify the Linux account
# --------------------------------------------------

if ! id "${LINUX_USER}" >/dev/null 2>&1; then
    echo "ERROR: Linux user '${LINUX_USER}' does not exist."
    echo "Edit LINUX_USER in this script and try again."
    exit 1
fi

# --------------------------------------------------
# Install Samba packages
# --------------------------------------------------

echo "[1/7] Installing Samba..."

apt-get update
apt-get install -y samba smbclient

# --------------------------------------------------
# Create the shared directory
# --------------------------------------------------

echo "[2/7] Creating shared directory..."

install -d -o "${LINUX_USER}" -g "$(id -gn "${LINUX_USER}")" -m 0700 "${SHARE_DIR}"

# --------------------------------------------------
# Back up the current Samba configuration
# --------------------------------------------------

echo "[3/7] Backing up Samba configuration..."

cp -a "${CONFIG}" "${BACKUP}"

# --------------------------------------------------
# Configure the Samba share
# --------------------------------------------------

echo "[4/7] Configuring Samba share..."

if grep -qE '^[[:space:]]*\[sambashare\][[:space:]]*$' "${CONFIG}"; then
    echo "A [sambashare] section already exists."
    echo "To avoid overwriting existing settings, setup has stopped."
    echo "Backup: ${BACKUP}"
    echo "Review ${CONFIG} manually before running this script again."
    exit 1
fi

cat >> "${CONFIG}" <<EOF

[${SHARE_NAME}]
    comment = Linux Windows File Sharing
    path = ${SHARE_DIR}
    browseable = yes
    read only = no
    guest ok = no
    valid users = ${LINUX_USER}
    create mask = 0644
    directory mask = 0755
EOF

# --------------------------------------------------
# Validate configuration and restore if invalid
# --------------------------------------------------

if ! testparm -s "${CONFIG}" >/dev/null; then
    echo "ERROR: Invalid Samba configuration."
    cp -a "${BACKUP}" "${CONFIG}"
    exit 1
fi

# --------------------------------------------------
# Create or update Samba password
# --------------------------------------------------

echo "[5/7] Set the Samba password for ${LINUX_USER}..."

if ! pdbedit -L | cut -d: -f1 | grep -Fxq "${LINUX_USER}"; then
    smbpasswd -a "${LINUX_USER}"
else
    echo "Samba user already exists. Updating its password..."
    smbpasswd "${LINUX_USER}"
fi

smbpasswd -e "${LINUX_USER}"

# --------------------------------------------------
# Start Samba service
# --------------------------------------------------

echo "[6/7] Starting Samba..."

systemctl enable --now smbd
systemctl restart smbd

# --------------------------------------------------
# Display connection details
# --------------------------------------------------

echo
echo "[7/7] Samba setup completed!"
echo
echo "Shared directory: ${SHARE_DIR}"
echo "Samba username:   ${LINUX_USER}"
echo "Configuration:    ${CONFIG}"
echo "Backup:           ${BACKUP}"
echo
echo "Linux IP addresses:"
hostname -I
echo
echo "On Windows, open File Explorer and enter:"
echo "\\\\<LINUX_IP_ADDRESS>\\${SHARE_NAME}"
echo
echo "Example:"
echo "\\\\192.168.1.100\\${SHARE_NAME}"
echo
echo "Use your Samba username and Samba password."
echo
echo "Check Samba service:"
systemctl --no-pager --full status smbd
```