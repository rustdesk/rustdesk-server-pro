#!/bin/bash

##################################################################################################################

# Install curl and whiptail if needed
if [ ! -x "$(command -v curl)" ] || [ ! -x "$(command -v whiptail)" ]
then
    # We need curl to fetch the lib
    # There are the package managers for different OS:
    # osInfo[/etc/redhat-release]=yum
    # osInfo[/etc/arch-release]=pacman
    # osInfo[/etc/gentoo-release]=emerge
    # osInfo[/etc/SuSE-release]=zypp
    # osInfo[/etc/debian_version]=apt-get
    # osInfo[/etc/alpine-release]=apk
    NEEDED_DEPS=(curl whiptail)
    echo "Installing" "${NEEDED_DEPS[@]}"
    if [ -x "$(command -v apt-get)" ]
    then
        sudo apt-get install "${NEEDED_DEPS[@]}" -y
    elif [ -x "$(command -v apk)" ]
    then
        sudo apk add --no-cache "${NEEDED_DEPS[@]}"
    elif [ -x "$(command -v dnf)" ]
    then
        sudo dnf install "${NEEDED_DEPS[@]}"
    elif [ -x "$(command -v zypper)" ]
    then
        sudo zypper install "${NEEDED_DEPS[@]}"
    elif [ -x "$(command -v pacman)" ]
    then
        sudo pacman -S install "${NEEDED_DEPS[@]}"
    elif [ -x "$(command -v yum)" ]
    then
        sudo yum install "${NEEDED_DEPS[@]}"
    elif [ -x "$(command -v emerge)" ]
    then
        sudo emerge -av "${NEEDED_DEPS[@]}"
    else
        echo "FAILED TO INSTALL! Package manager not found. You must manually install:" "${NEEDED_DEPS[@]}"
        exit 1
    fi
fi

# We need to source directly from the Github repo to be able to use the functions here
# shellcheck disable=2034,2059,2164
true
SCRIPT_NAME="Uninstall script"
export SCRIPT_NAME
# shellcheck source=lib.sh
source <(curl -sL https://raw.githubusercontent.com/rustdesk/rustdesk-server-pro/main/lib.sh)
# see https://github.com/koalaman/shellcheck/wiki/Directive
unset SCRIPT_NAME

##################################################################################################################

# Check if root
root_check

# Output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]
then
    identify_os
    print_text_in_color "$ICyan" "OS: $OS"
    print_text_in_color "$ICyan" "VER: $VER"
    print_text_in_color "$ICyan" "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Switch for Certbot
if [ -d /etc/letsencrypt ]
then
    CERTBOT_SWITCH=ON
else
    CERTBOT_SWITCH=OFF
fi

# Uninstall Rustdesk Menu
choice=$(whiptail --title "$TITLE" --checklist \
"What do you want to uninstall?
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"nginxconf" "(Removes Rustdesk Nginx config)" OFF \
"nginxall" "(Removes *everything* releated to Nginx)" ON \
"wget" "(Removes wget linux package)" ON \
"unzip" "(Removes unzip linux package)" ON \
"whiptail" "(Removes whiptail linux package)" ON \
"dnsutils" "(Removes dnsutils linux package)" ON \
"bind-utils" "(Removes bind-utils linux package)" ON \
"bind" "(Removes bind linux package)" ON \
"UFW" "(Removes UFW linux package plus rules)" ON \
"Rustdesk LOGs" "(Removes RustDesk log dir)" ON \
"Rustdesk Server" "(Removes Rustdesk server + services)" ON \
"curl" "(Removes curl:// linux package)" OFF \
"Certbot" "(Removes Certbot package plus Let's Encrypt)" "$CERTBOT_SWITCH" 3>&1 1>&2 2>&3)

case "$choice" in
    *"nginxconf"*)
        REMOVE_NGINX_CONF="yes"
    ;;&
    *"nginxall"*)
        REMOVE_NGINX_ALL="yes"
    ;;&
    *"wget"*)
        REMOVE_WGET="yes"
    ;;&
    *"unzip"*)
        REMOVE_UNZIP="yes"
    ;;&
    *"whiptail"*)
        REMOVE_WHIPTAIL="yes"
    ;;&
    *"dnsutils"*)
        REMOVE_DNSUTILS="yes"
    ;;&
    *"bind-utils"*)
        REMOVE_BIND_UTILS="yes"
    ;;&
    *"bind"*)
        REMOVE_BIND="yes"
    ;;&
    *"UFW"*)
        REMOVE_UFW="yes"
    ;;&
    *"Rustdesk LOGs"*)
        REMOVE_RUSTDESK_LOG="yes"
    ;;&
    *"Rustdesk SERVER"*)
        REMOVE_RUSTDESK_SERVER="yes"
    ;;&
    *"curl"*)
        REMOVE_CURL="yes"
    ;;&
    *"Certbot"*)
        REMOVE_CERTBOT="yes"
    ;;&
    *)
    ;;
esac

msg_box "WARNING WARNING WARNING

This script will remove EVERYTHING that was chosen in the previous selection.
You can choose to opt out after you hit OK."

if ! yesno_box_no "Are you REALLY sure you want to continue with the uninstallation?"
then
    exit 0
fi

if [ -n "$UFW" ]
then
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
    ufw --force disable
    ufw --force reload
fi

# Rustdesk Server
if [ -n "$REMOVE_RUSTDESK_SERVER" ]
then
    # Rustdesk installation dir
    print_text_in_color "$IGreen" "Removing RustDesk Server..."
    rm -rf "$RUSTDESK_INSTALL_DIR"
    rm -rf /usr/bin/hbbr
    rm -rf /usr/bin/hbbr

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
fi

# Rustdesk LOG
if [ -n "$REMOVE_RUSTDESK_LOG" ]
then
    # Rustdesk LOG dir
    rm -rf "$RUSTDESK_LOG_DIR"
fi

# Certbot
if [ -n "$REMOVE_CERTBOT" ]
then
    if snap list | grep -q certbot > /dev/null
    then
        purge_linux_package snap
        snap remove certbot
    else
        purge_linux_package python3-certbot-nginx -y
    fi
    # Also remove the actual certs
    rm -rf /etc/letsencrypt
fi

# Nginx
if [ -n "$REMOVE_NGINX_CONF" ]
then
    rm -f "/etc/nginx/sites-available/rustdesk.conf"
    rm -f "/etc/nginx/sites-enabled/rustdesk.conf"
    service nginx restart
elif [ -n "$REMOVE_NGINX_ALL" ]
then
    purge_linux_package nginx
    rm -rf "/etc/nginx"
fi

# The rest
if [ -n "$REMOVE_CURL" ]
then
    purge_linux_package curl
fi

if [ -n "$REMOVE_WGET" ]
then
    purge_linux_package wget
fi

if [ -n "$REMOVE_UNZIP" ]
then
    purge_linux_package unzip
fi

if [ -n "$REMOVE_DNSUTILS" ]
then
    purge_linux_package dnsutils
fi

if [ -n "$REMOVE_BIND_UTILS" ]
then
    purge_linux_package bind-utils
fi

if [ -n "$REMOVE_BIND" ]
then
    purge_linux_package bind
fi

if [ -n "$REMOVE_UFW" ]
then
    purge_linux_package ufw
fi

msg_box "Uninstallation complete!

Please hit OK to remove the last package."

if [ -n "$REMOVE_WHIPTAIL" ]
then
    purge_linux_package whiptail
fi
