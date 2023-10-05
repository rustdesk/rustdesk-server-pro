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
SCRIPT_NAME="Update script"
export SCRIPT_NAME
# shellcheck source=lib.sh
source <(curl -sL https://raw.githubusercontent.com/rustdesk/rustdesk-server-pro/main/lib.sh)
# see https://github.com/koalaman/shellcheck/wiki/Directive
unset SCRIPT_NAME

##################################################################################################################

# Output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]
then
    identify_os
    echo "OS: $OS"
    echo "VER: $VER"
    echo "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Select user for update
RUSTDESK_USER=$(whoami)
    run_as_non_root_user() {
        sudo -u "$RUSTDESK_USER" "$@";
    }

# A variant of whoami to be complaint with the install script
if [ "$RUSTDESK_USER" = 'root' ]
then
    RDCURRENT=$(/usr/bin/hbbr --version | sed -r 's/hbbr (.*)/\1/')
else
    RDCURRENT=$(run_as_non_root_user /usr/bin/hbbr --version | sed -r 's/hbbr (.*)/\1/')
fi

# Get current release version
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }')

if [ "$RDLATEST" == "$RDCURRENT" ]
then
    msg_box "Same version, no need to update."
    exit 0
fi

# Stop services
# HBBS
sudo systemctl stop rustdesk-hbbs.service
# HBBR
sudo systemctl stop rustdesk-hbbr.service
sleep 10

if [ ! -d "$RUSTDESK_INSTALL_DIR" ]
then
    msg_box "$RUSTDESK_INSTALL_DIR not found. No update of RustDesk possible (use install.sh script?)"
    exit 4
else
    cd "$RUSTDESK_INSTALL_DIR"
    rm -rf "$RUSTDESK_INSTALL_DIR"/static
fi

# Download, extract, and move Rustdesk in place
if [ -n "${ARCH}" ]
then
    # If not /var/lib/rustdesk-server/ ($RUSTDESK_INSTALL_DIR) exists we can assume this is a fresh install. If it exists though, we can't move it and it will produce an error
    if [ ! -d "$RUSTDESK_INSTALL_DIR/static" ]
    then
        print_text_in_color "$IGreen" "Installing RustDesk Server..."
        # Create dir
        mkdir -p "$RUSTDESK_INSTALL_DIR"
        if [ -d "$RUSTDESK_INSTALL_DIR" ]
        then
            cd "$RUSTDESK_INSTALL_DIR"
        else
            msg_box "It seems like the installation folder wasn't created, we can't continue.
Please report this to: https://github.com/rustdesk/rustdesk-server-pro/issues"
            exit 1
        fi
        # Since the name of the actual tar files differs from the output of uname -m we need to rename acutal download file.
        # Preferably we would instead rename the download tarballs to the output of uname -m. This would make it possible to run a single $VAR for ARCH.
        if [ "${ARCH}" = "x86_64" ]
        then
            ACTUAL_TAR_NAME=amd64
        elif [ "${ARCH}" = "armv7l" ]
        then
            ACTUAL_TAR_NAME=armv7
        elif [ "${ARCH}" = "aarch64" ]
        then
            ACTUAL_TAR_NAME=arm64v8
        fi
        # Download
        if ! curl -fSLO --retry 3 https://github.com/rustdesk/rustdesk-server-pro/releases/download/"${RDLATEST}"/rustdesk-server-linux-"${ACTUAL_TAR_NAME}".tar.gz
        then
            msg_box "Sorry, the installation package failed to download.
This might be temporary, so please try to run the installation script again."
            exit 1
        fi
        # Extract, move in place, and make it executable
        tar -xf rustdesk-server-linux-"${ACTUAL_TAR_NAME}".tar.gz
        # Set permissions
        if [ -n "$RUSTDESK_USER" ]
        then
            chown "$RUSTDESK_USER":"$RUSTDESK_USER" -R "$RUSTDESK_INSTALL_DIR"
        fi
        # Move as root if RUSTDESK_USER is not set.
        if [ -n "$RUSTDESK_USER" ]
        then
            run_as_non_root_user mv "${ACTUAL_TAR_NAME}"/static "$RUSTDESK_INSTALL_DIR"
        else
            mv "${ACTUAL_TAR_NAME}"/static "$RUSTDESK_INSTALL_DIR"
        fi
        mv "${ACTUAL_TAR_NAME}"/hbbr /usr/bin/
        mv "${ACTUAL_TAR_NAME}"/hbbs /usr/bin/
        rm -rf "$RUSTDESK_INSTALL_DIR"/"${ACTUAL_TAR_NAME:?}"
        rm -rf rustdesk-server-linux-"${ACTUAL_TAR_NAME}".tar.gz
        chmod +x /usr/bin/hbbs
        chmod +x /usr/bin/hbbr
        if [ -n "$RUSTDESK_USER" ]
        then
            chown "$RUSTDESK_USER":"$RUSTDESK_USER" -R /usr/bin/hbbr
            chown "$RUSTDESK_USER":"$RUSTDESK_USER" -R /usr/bin/hbbr
        fi
    else
        print_text_in_color "$IGreen" "Rustdesk server already installed."
    fi
else
    msg_box "Sorry, we can't figure out your distro, this script will now exit.
Please report this to: https://github.com/rustdesk/rustdesk-server-pro/issues"
    exit 1
fi

# Start services
# HBBR
sudo systemctl start rustdesk-hbbr.service
# HBBS
sudo systemctl start rustdesk-hbbs.service

while :
do
    if ! sudo systemctl status rustdesk-hbbr.service | grep "Active: active (running)"
    then
        sleep 2
        print_text_in_color "$ICyan" "Waiting for RustDesk Relay service to become active..."
    else
        break
    fi
done

while :
do
    PUBKEYNAME=$(find "$RUSTDESK_INSTALL_DIR" -name "*.pub")
    if [ -z "$PUBKEYNAME" ]
    then
        print_text_in_color "$ICyan" "Checking if public key is generated..."
        sleep 5
    else
        print_text_in_color "$IGreen" "Public key path: $PUBKEYNAME"
        PUBLICKEY=$(cat "$PUBKEYNAME")
        break
    fi
done

msg_box "Rustdesk is now updated!"
