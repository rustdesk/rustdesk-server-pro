#!/bin/bash

# This script will do the following to install RustDesk Server Pro replacing RustDesk Server Open Source
# 1. Disable and removes the old services
# 2. Install some dependencies
# 3. Setup UFW firewall if available
# 4. Create a folder /var/lib/rustdesk-server and copy the certs here
# 5. Download and extract RustDesk Pro Services to the above folder
# 6. Create systemd services for hbbs and hbbr
# 7. If you choose Domain, it will install Nginx and Certbot, allowing the API to be available on port 443 (https) and get an SSL certificate over port 80, it is automatically renewed

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
    echo "Installing these packages:" "${NEEDED_DEPS[@]}"
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
SCRIPT_NAME="Install script"
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

# Stop all old services
sudo systemctl stop gohttpserver.service
sudo systemctl stop rustdesksignal.service
sudo systemctl stop rustdeskrelay.service
sudo systemctl disable gohttpserver.service
sudo systemctl disable rustdesksignal.service
sudo systemctl disable rustdeskrelay.service
sudo rm -f /etc/systemd/system/gohttpserver.service
sudo rm -f /etc/systemd/system/rustdesksignal.service
sudo rm -f /etc/systemd/system/rustdeskrelay.service

# We need to create the new install dir before the migration task, otherwise mv will fail
mkdir -p "$RUSTDESK_INSTALL_DIR"

# Migration tasks
if [ -d /opt/rustdesk ]
then
    mv /opt/rustdesk/id_* "$RUSTDESK_INSTALL_DIR/"
    rm -rf /opt/rustdesk
fi

# Install Rustdesk again 
# It won't install RustDesk again since there's a check in the install script which checks for the installation folder, but services and everything else will be created
# Would it be possible to move L93-98 after the installation?
if ! curl -fSLO --retry 3 https://raw.githubusercontent.com/rustdesk/rustdesk-server-pro/main/install.sh
    msg_box "Sorry, we couldn't fetch the install script, please try again.
Your old installation now lives in $RUSTDESK_INSTALL_DIR"
    exit
else
    if sudo bash install.sh
    then
        rm -f install.sh
        msg_box "Conversion from OS seems to have been OK!"
    else
        msg_box "Sorry, but something seems to have gone wrong, please report this to:
https://github.com/rustdesk/rustdesk-server-pro/"
    fi
fi
