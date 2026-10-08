Here is the cleaned-up **Samba installation and configuration procedure for sharing a folder between Debian Linux and Windows**, followed by a Bash script that automates the setup.

Since you use Debian GNU/Linux 13 and Windows, these instructions are suitable for your environment.

# 1. How Samba works



Samba allows you to access files on your Linux computer directly from Windows File Explorer over your local network.

For example:
- **Linux:** Debian GNU/Linux 13.
- **Windows:** Your Windows PC.
- **Shared folder:** `/home/when/sambashare`
- **Windows access:** `\\LINUX_IP_ADDRESS\sambashare`

You don't need an FTP client. Windows can access the shared folder directly.

# 2. Install Samba

Open your Linux terminal and run:

```bash
sudo apt update
sudo apt install samba smbclient -y
```

Verify the installation:

```bash
samba --version
```

Check the service:

```bash
systemctl status smbd
```

# 3. Create the shared folder

Create a directory for sharing:

```bash
mkdir -p /home/when/sambashare
```

Set the folder permissions:

```bash
chmod 700 /home/when/sambashare
```

This restricts access to your Linux user. We will configure Samba to authenticate users before allowing access.

# 4. Configure Samba

First, back up your existing configuration:

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
```

Open the configuration file:

```bash
sudo nano /etc/samba/smb.conf
```

Add the following section at the bottom:

```ini
[sambashare]
    comment = Linux Windows File Sharing
    path = /home/when/sambashare
    browseable = yes
    read only = no
    guest ok = no
    valid users = when
    create mask = 0644
    directory mask = 0755
```

**Important:** This configuration assumes your Linux username is `when`. If your username differs, replace `when` in the configuration with your actual Linux username.

Save the file:
- Press `Ctrl + O`.
- Press `Enter`.
- Press `Ctrl + X`.

Validate the configuration:

```bash
sudo testparm
```

If the configuration is valid, restart Samba:

```bash
sudo systemctl enable --now smbd
sudo systemctl restart smbd
```

# 5. Create a Samba password

Samba requires a Samba password for the Linux account.

Run:

```bash
sudo smbpasswd -a when
```

Enter a password when prompted.

This password can be different from your Linux login password.

Enable the Samba account:

```bash
sudo smbpasswd -e when
```

# 6. Configure the firewall

If you use UFW, allow Samba traffic:

```bash
sudo ufw allow Samba
```

Check the firewall:

```bash
sudo ufw status
```

If UFW is inactive, you do not need to enable it just for Samba. If another firewall is active, configure it to allow SMB traffic from your trusted local network.

**Security:** Do not expose Samba ports 137–139 or 445 directly to the internet.

# 7. Find your Linux IP address

Run:

```bash
hostname -I
```

Example output:

```text
192.168.1.100
```

Your actual address will be different.

# 8. Connect from Windows

On your Windows PC:

1. Press `Win + E` to open File Explorer.
2. Click the address bar.
3. Enter the following, replacing the IP address with your Linux IP:

```text
\\192.168.1.100\sambashare
```

4. Press `Enter`.
5. Enter your Samba username:

```text
when
```

6. Enter the Samba password you created earlier.

You should now be able to access your Linux shared folder from Windows.

Files you create in the shared directory on Linux will be accessible from Windows, and files created from Windows will be accessible on Linux.

---

# 9. Automatic Bash script

Instead of running each command manually, you can use this script to install and configure Samba.

The script:
- Installs Samba and `smbclient`.
- Creates `/home/when/sambashare`.
- Backs up your existing Samba configuration.
- Adds a dedicated Samba share.
- Creates or updates the Samba user password interactively.
- Validates the configuration.
- Starts and enables the Samba service.
- Displays your Linux IP addresses and Windows connection path.

It assumes your Linux username is `when`, as in your existing environment.

Create the script:

```bash
nano setup_samba.sh
```

Paste the following code.

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

## 10. Run the script

Make the script executable:

```bash
chmod +x setup_samba.sh
```

Run it:

```bash
sudo ./setup_samba.sh
```

When prompted, enter a Samba password.

**Important:** The script backs up your existing configuration and stops if a share named `sambashare` already exists. If validation fails, it restores the backup. If a failure occurs at another stage, inspect `/etc/samba/smb.conf` before rerunning the script.

## 11. Test the share from Linux

Check the configured shares:

```bash
smbclient -L localhost -U when
```

Test access to the shared directory:

```bash
smbclient //localhost/sambashare -U when
```

After authentication, you will see the `smb:\>` prompt.

Try:

```text
ls
```

To exit:

```text
quit
```

## 12. My recommendation

For your Debian and Windows computers, **Samba is the best starting point for everyday folder sharing over a local network**.

| Feature | Samba | FTP |
|---|---|---|
| Windows File Explorer access | Yes | Usually requires an FTP URL or client |
| Linux-to-Windows file sharing | Yes | Yes |
| Dedicated client required | No | Often |
| User authentication | Yes | Depends on server configuration |
| Encrypted connection | SMB3 can encrypt traffic when configured | Standard FTP is unencrypted; FTPS or SFTP is preferable |
| Best use | Local network folder sharing | FTP-based file transfer workflows |

For your setup, start with Samba. Keep it restricted to your trusted local network, use password authentication, and avoid exposing it directly to the internet.

You can also consult the official [Ubuntu Samba installation and configuration guide](https://ubuntu.com/tutorials/install-and-configure-samba?utm_source=chatgpt.com) for additional details.