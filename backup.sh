#!/usr/bin/env bash

# shellcheck disable=2034,2059,2164
true

usern=$(whoami)
path=$(pwd)
echo "$path"

ARCH=$(uname -m)


# Identify OS
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    UPSTREAM_ID=${ID_LIKE,,}

    # Fallback to ID_LIKE if ID was not 'ubuntu' or 'debian'
    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
        UPSTREAM_ID="$(echo "${ID_LIKE,,}" | sed s/\"//g | cut -d' ' -f1)"
    fi

elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian, Ubuntu, etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSE-release ]; then
    # Older SuSE, etc.
    OS=SuSE
    VER=$(cat /etc/SuSE-release)
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi


# Output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]; then
    echo "OS: $OS"
    echo "VER: $VER"
    echo "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Setup prereqs for server
# Common named prereqs
PREREQ="tar"
PREREQDEB="sqlite3"
PREREQRPM="sqlite"
PREREQARCH="sqlite"

echo "Installing prerequisites"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y ${PREREQ} ${PREREQDEB} # git
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] ; then
# openSUSE 15.4 fails to run the relay service and hangs waiting for it
# Needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    sudo yum update -y
    sudo dnf install -y epel-release
    sudo yum install -y ${PREREQ} ${PREREQRPM} # git
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -Syu
    sudo pacman -S ${PREREQ} ${PREREQARCH}
else
    echo "Unsupported OS"
    # Here you could ask the user for permission to try and install anyway
    # If they say yes, then do the install
    # If they say no, exit the script
    exit 1
fi

if [[ $* == *--schedule* ]]; then
    (
        crontab -l 2>/dev/null
        echo "0 0 * * * $path/backup.sh --auto"
    ) | crontab -

    if [ ! -d /opt/rustdesk-server-backups ]; then
        sudo mkdir /opt/rustdesk-server-backups
    fi

    if [ ! -d /opt/rustdesk-server-backups/daily ]; then
        sudo mkdir /opt/rustdesk-server-backups/daily
    fi

    if [ ! -d /opt/rustdesk-server-backups/weekly ]; then
        sudo mkdir /opt/rustdesk-server-backups/weekly
    fi

    if [ ! -d /opt/rustdesk-server-backups/monthly ]; then
        sudo mkdir /opt/rustdesk-server-backups/monthly
    fi
    sudo chown "${usern}":"${usern}" -R /opt/rustdesk-server-backups

    printf >&2 "Backups setup to run at midnight and rotate."
    exit 0
fi

if [ ! -d /opt/rustdesk-server-backups ]; then
    sudo mkdir /opt/rustdesk-server-backups
    sudo chown "${usern}":"${usern}" /opt/rustdesk-server-backups
fi

dt_now=$(date '+%Y_%m_%d__%H_%M_%S')
tmp_dir=$(mktemp -d -t rustdesk-XXXXXXXXXXXXXXXXXXXXX)
sysd="/etc/systemd/system"

cp -rf /var/lib/rustdesk-server/ "${tmp_dir}"/
sqlite3 /var/lib/rustdesk-server/db.sqlite3 .dump > "${tmp_dir}"/db_backup_file.sql

if [[ $* == *--auto* ]]; then

    month_day=$(date +"%d")
    week_day=$(date +"%u")

    if [ "$month_day" -eq 10 ]; then
        tar -cf /opt/rustdesk-server-backups/monthly/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
    else
        if [ "$week_day" -eq 5 ]; then
            tar -cf /opt/rustdesk-server-backups/weekly/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
        else
            tar -cf /opt/rustdesk-server-backups/daily/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
        fi
    fi

    rm -rf "${tmp_dir}"

    find /opt/rustdesk-server-backups/daily/ -type f -mtime +14 -name '*.tar' -execdir rm -- '{}' \;
    find /opt/rustdesk-server-backups/weekly/ -type f -mtime +60 -name '*.tar' -execdir rm -- '{}' \;
    find /opt/rustdesk-server-backups/monthly/ -type f -mtime +380 -name '*.tar' -execdir rm -- '{}' \;
    echo -ne "Backup Completed"
    exit

else
    tar -cf /opt/rustdesk-server-backups/rustdesk-backup-"${dt_now}".tar -C "${tmp_dir}" .
    rm -rf "${tmp_dir}"
    echo -ne "Backup saved to /opt/rustdesk-server-backups/rustdesk-backup-${dt_now}.tar"
fi
