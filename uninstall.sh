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
    identify_os
    print_text_in_color "$ICyan" "OS: $OS"
    print_text_in_color "$ICyan" "VER: $VER"
    print_text_in_color "$ICyan" "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Uninstall Rustdesk Menu
choice=$(whiptail --title "$TITLE" --checklist \
"What do you want to uninstall?
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"curl" "(Removes curl package)" OFF \
"nginxconf" "(Removes Rustdesk Nginx config)" ON \
"nginxall" "(Removes Nginx package + all configurations)" ON \
"wget" "(Removes wget package)" ON \
"unzip" "(Removes unzip package)" ON \
"tar" "(Removes tar package)" ON \
"whiptail" "(Removes whiptail package)" ON \
"dnsutils" "(Removes dnsutils package)" ON \
"bind-utils" "(Removes bind-utils package)" ON \
"bind" "(Removes bind package)" ON \
"UFW" "(Removes UFW package plus rules)" ON \
"Rustdesk LOGs" "(Removes RustDesk log dir)" ON \
"Rustdesk Server" "(Removes Rustdesk server + services)" ON \
"Certbot" "(Removes Certbot package plus Let's Encrypt)" ON 3>&1 1>&2 2>&3)

case "$choice" in
    *"curl"*)
        curl=yes
    ;;&
    *"nginx"*)
        nginx=yes
    ;;&
    *"wget"*)
        wget=yes
    ;;&
    *"unzip"*)
        unzip=yes
    ;;&
    *"tar"*)
        tar=yes
    ;;&
    *"whiptail"*)
        whiptail=yes
    ;;&
    *"dnsutils"*)
        dnsutils=yes
    ;;&
    *"bind-utils"*)
        bind-utils=yes
    ;;&
    *"bind"*)
        bind=yes
    ;;&
    *"UFW"*)
        UFW=yes
    ;;&
    *"Rustdesk LOGs"*)
        Rustdesk_LOGs=yes
    ;;&
    *"Rustdesk Server"*)
        Rustdesk_Server=yes
    ;;&
    *"Certbot"*)
        Certbot=yes
    ;;&
    *)
    ;;
esac
exit

msg_box "WARNING WARNING WARNING

This script will remove EVERYTHING that was you chose in the previous selection.
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
    ufw disable
    ufw reload
fi

# Rustdesk Server
if [ -n "$Rustdesk_Server" ]
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
if [ -n "$Rustdesk_LOGs" ]
then
    # Rustdesk LOG dir
    rm -rf "$RUSTDESK_LOG_DIR"
fi

# Certbot
if [ -n "$Certbot" ]
then
    if snap list | grep -q certbot > /dev/null
    then
        purge_linux_package snap
        snap remove certbot
    else
        purge_linux_packagepython3-certbot-nginx -y
    fi
    # Also remove the actual certs
    rm -rf /etc/letsencrypt
fi

# Nginx
if [ -n "$nginxconf" ]
then
    rm -f "/etc/nginx/sites-available/rustdesk.conf"
    rm -f "/etc/nginx/sites-enabled/rustdesk.conf"
    service nginx restart
elif [ -n "$nginxall" ]
then
    purge_linux_package nginx
    rm -rf "/etc/nginx"
fi

# The rest
if [ -n "$curl" ]
then
    purge_linux_package curl
fi

if [ -n "$wget" ]
then
    purge_linux_package wget
fi

if [ -n "$unzip" ]
then
    purge_linux_package unzip
fi

if [ -n "$tar" ]
then
    purge_linux_package tar
fi

if [ -n "$whiptail" ]
then
    purge_linux_package whiptail
fi

if [ -n "$dnsutils" ]
then
    purge_linux_package dnsutils
fi

if [ -n "$bind-utils" ]
then
    purge_linux_package bind-utils
fi

if [ -n "$bind" ]
then
    purge_linux_package bind
fi

if [ -n "$UFW" ]
then
    purge_linux_package ufw
fi

msg_box "Uninstallation complete!

Please hit OK to remove the last file."

rm -f lib.sh
