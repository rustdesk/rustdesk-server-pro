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

# Select user for update
RUSTDESK_USER=$(whoami)
    run_as_non_root_user() {
        sudo -u "$RUSTDESK_USER" "$@";
    }

# Install needed dependencies
install_linux_package tar
if ! install_linux_package sqlite3
then
   install_linux_package sqlite 
fi

# Add the backup
if [ -d /opt/rustdesk-server ]
then
    if [[ $* == *--schedule* ]]
    then
        (
            crontab -l 2>/dev/null
            echo "0 0 * * * $path/backup.sh --auto"
        ) | crontab -

        if [ ! -d /opt/rustdesk-server-backups ]
        then
            mkdir -p /opt/rustdesk-server-backups
        fi

        if [ ! -d /opt/rustdesk-server-backups/daily ]
        then
            mkdir -p /opt/rustdesk-server-backups/daily
        fi

        if [ ! -d /opt/rustdesk-server-backups/weekly ]
        then
            mkdir -p /opt/rustdesk-server-backups/weekly
        fi

        if [ ! -d /opt/rustdesk-server-backups/monthly ]
        then
            mkdir -p /opt/rustdesk-server-backups/monthly
        fi
        chown "${RUSTDESK_USER}":"${RUSTDESK_USER}" -R /opt/rustdesk-server-backups

        printf >&2 "Backups setup to run at midnight and rotate."
        exit 0
    fi
elif [ -d $RUSTDESK_INSTALL_DIR ]
    if [[ $* == *--schedule* ]]
    then
        (
            crontab -l 2>/dev/null
            echo "0 0 * * * $path/backup.sh --auto"
        ) | crontab -

        if [ ! -d $RUSTDESK_BACKUP_DIR ]
        then
            mkdir -p $RUSTDESK_BACKUP_DIR
        fi

        if [ ! -d $RUSTDESK_BACKUP_DIR/daily ]
        then
            mkdir $RUSTDESK_BACKUP_DIR/daily
        fi

        if [ ! -d $RUSTDESK_BACKUP_DIR/weekly ]
        then
            mkdir $RUSTDESK_BACKUP_DIR/weekly
        fi

        if [ ! -d $RUSTDESK_BACKUP_DIR/monthly ]
        then
            mkdir $RUSTDESK_BACKUP_DIR/monthly
        fi
        sudo chown "${RUSTDESK_USER}":"${RUSTDESK_USER}" -R /opt/rustdesk-server-backups

        printf >&2 "Backups setup to run at midnight and rotate."
        exit 0
    fi
fi


################ didn't touch anything below this

dt_now=$(date '+%Y_%m_%d__%H_%M_%S')
tmp_dir=$(mktemp -d -t rustdesk-XXXXXXXXXXXXXXXXXXXXX)
sysd="/etc/systemd/system"

run_as_non_root_user cp -rf /var/lib/rustdesk-server/ "${tmp_dir}"/
run_as_non_root_user sqlite3 /var/lib/rustdesk-server/db.sqlite3 .dump > "${tmp_dir}"/db_backup_file.sql

if [[ $* == *--auto* ]]; then

    month_day=$(date +"%d")
    week_day=$(date +"%u")

    if [ "$month_day" -eq 10 ]; then
        run_as_non_root_user  tar -cf /opt/rustdesk-server-backups/monthly/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
    else
        if [ "$week_day" -eq 5 ]; then
            run_as_non_root_user  tar -cf /opt/rustdesk-server-backups/weekly/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
        else
            run_as_non_root_user tar -cf /opt/rustdesk-server-backups/daily/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
        fi
    fi

    rm -rf "${tmp_dir}"

    find /opt/rustdesk-server-backups/daily/ -type f -mtime +14 -name '*.tar' -execdir rm -- '{}' \;
    find /opt/rustdesk-server-backups/weekly/ -type f -mtime +60 -name '*.tar' -execdir rm -- '{}' \;
    find /opt/rustdesk-server-backups/monthly/ -type f -mtime +380 -name '*.tar' -execdir rm -- '{}' \;
    msg_box "Backup Completed"
    exit

else
    run_as_non_root_user tar -cf /opt/rustdesk-server-backups/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
    rm -rf "${tmp_dir}"
    msg_box "Backup saved to /opt/rustdesk-server-backups/rustdesk-backup-${dt_now}.tar"
fi
