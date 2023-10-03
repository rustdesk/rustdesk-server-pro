#!/bin/bash

# shellcheck disable=2034,2059,2164
true
# see https://github.com/koalaman/shellcheck/wiki/Directive

##################################################################################################################

if [[ "$EUID" -ne 0 ]]
then
    echo "Sorry, you are not root. You now have two options:"
    echo
    echo "1. Use SUDO directly:"
    echo "   a) :~$ sudo bash install.sh"
    echo
    echo "2. Become ROOT and then type your command:"
    echo "   a) :~$ sudo -i"
    echo "   b) :~# bash install.sh"
    echo
    echo "More information can be found here: https://unix.stackexchange.com/a/3064"
    exit 1
fi

# Identify OS
if [ -f /etc/os-release ]
then
    # freedesktop.org and systemd
    # shellcheck source=/dev/null
    source /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    UPSTREAM_ID=${ID_LIKE,,}

    # Fallback to ID_LIKE if ID was not 'ubuntu' or 'debian'
    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]
    then
        UPSTREAM_ID="$(echo "${ID_LIKE,,}" | sed s/\"//g | cut -d' ' -f1)"
    fi

elif type lsb_release >/dev/null 2>&1
then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]
then
    # For some versions of Debian/Ubuntu without lsb_release command
    # shellcheck source=/dev/null
    source /etc/os-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]
then
    # Older Debian, Ubuntu, etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSE-release ]
then
    # Older SuSE, etc.
    OS=SuSE
    VER=$(cat /etc/SuSE-release)
elif [ -f /etc/redhat-release ]
then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Setup prereqs for server
# Common named prereqs
PREREQ=(wget unzip tar whiptail)
PREREQDEB=(dnsutils)
PREREQRPM=(bind-utils)
PREREQARCH=(bind)

echo "Removing packages..."
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]
then
    apt-get purge -y "${PREREQ[@]}" "${PREREQDEB[@]}"
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ]
then
# openSUSE 15.4 fails to run the relay service and hangs waiting for it
# Needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    yum purge -y "${PREREQ[@]}" "${PREREQRPM[@]}" # git
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]
then
    pacman -R "${PREREQ[@]}" "${PREREQARCH[@]}"
fi

# Download the lib file
if ! curl -fSL https://raw.githubusercontent.com/rustdesk/rustdesk-server-pro/main/lib.sh -o lib.sh
then
    echo "Failed to download the lib.sh file. Please try again"
    exit 1
fi

# shellcheck disable=2034,2059,2164
true
# shellcheck source=lib.sh
source lib.sh

# Output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]
then
    print_text_in_color "$ICyan" "OS: $OS"
    print_text_in_color "$ICyan" "VER: $VER"
    print_text_in_color "$ICyan" "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

msg_box "WARNING WARNING WARNING

This script will remove EVERYTHING that was installed by the Rustdesk Linux installer.
You can choose to opt out after you hit OK."

if ! yesno_box_no "Are you REALLY sure you want to continue with the uninstallation?"
then
    exit 0
fi

# Deleting UFW rules
ufw delete allow 21115:21119/tcp
# ufw delete 22/tcp # If connected to a remote VPS, this deletion will make the connection go down
ufw delete allow 21116/udp
if [ -f "/etc/nginx/sites-available/rustdesk.conf" ]
then
    ufw delete allow 80/tcp
    ufw delete allow 443/tcp
else
    ufw delete allow 21114/tcp
fi
ufw disable
ufw reload

# Rustdesk installation dir
print_text_in_color "$IGreen" "Removing RustDesk Server..."
rm -rf "$RUSTDESK_INSTALL_DIR"
rm -rf /usr/bin/hbbr
rm -rf /usr/bin/hbbr

# Rustdesk LOG dir
rm -rf "$RUSTDESK_LOG_DIR"

# systemctl services
# HBBS
systemctl disable rustdesk-hbbs.service
systemctl stop rustdesk-hbbs.service
rm -f "/etc/systemd/system/rustdesk-hbbs.service"
# HBBR
systemctl disable rustdesk-hbbr.service
systemctl stop rustdesk-hbbr.service
rm -f "/etc/systemd/system/rustdesk-hbbr.service"
# daemon-reload
systemctl daemon-reload

# Certbot & NGINX
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]
then
    if snap list | grep -q certbot > /dev/null
    then
        apt-get purge snapd -y
        snap remove certbot
    else
        apt-get purge nginx -y
        apt-get purge python3-certbot-nginx -y
    fi
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ]
then
# openSUSE 15.4 fails to run the relay service and hangs waiting for it
# Needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    yum -y purge nginx
    yum -y purge python3-certbot-nginx
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]
then
    pacman -S purge nginx
    pacman -S purge python3-certbot-nginx
fi
rm -f "/etc/nginx/sites-available/rustdesk.conf"
rm -f "/etc/nginx/sites-enabled/rustdesk.conf"
service nginx restart

# Let's Encrypt
rm -rf /etc/letsencrypt

# The rest
apt-get purge curl ufw -y
apt autoremove -y

msg_box "Uninstallation complete!

Please hit OK to remove the last file."

rm -f lib.sh
