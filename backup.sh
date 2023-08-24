#!/usr/bin/env bash

path=$(pwd)
echo $path

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
    sudo chown ${USER}:${USER} -R /opt/rustdesk-server-backups

    printf >&2 "${GREEN}Backups setup to run at midnight and rotate.${NC}\n"
    exit 0
fi

if [ ! -d /opt/rustdesk-server-backups ]; then
    sudo mkdir /opt/rustdesk-server-backups
    sudo chown ${USER}:${USER} /opt/rustdesk-server-backups
	sudo apt install sqlite3 -y
fi

dt_now=$(date '+%Y_%m_%d__%H_%M_%S')
tmp_dir=$(mktemp -d -t rustdesk-XXXXXXXXXXXXXXXXXXXXX)
sysd="/etc/systemd/system"

mkdir -p ${tmp_dir}/rustdesk

cp -rf /var/lib/rustdesk-server/ ${tmp_dir}/
sqlite3 db.sqlite3 ".backup '${tmp_dir}/db_backup_file.sq3'"

if [[ $* == *--auto* ]]; then

    month_day=$(date +"%d")
    week_day=$(date +"%u")

    if [ "$month_day" -eq 10 ]; then
        tar -cf /opt/rustdesk-server-backups/monthly/rustdesk-backup-${dt_now}.tar -C ${tmp_dir} .
    else
        if [ "$week_day" -eq 5 ]; then
            tar -cf /opt/rustdesk-server-backups/weekly/rustdesk-backup-${dt_now}.tar -C ${tmp_dir} .
        else
            tar -cf /opt/rustdesk-server-backups/daily/rustdesk-backup-${dt_now}.tar -C ${tmp_dir} .
        fi
    fi

    rm -rf ${tmp_dir}

    find /opt/rustdesk-server-backups/daily/ -type f -mtime +14 -name '*.tar' -execdir rm -- '{}' \;
    find /opt/rustdesk-server-backups/weekly/ -type f -mtime +60 -name '*.tar' -execdir rm -- '{}' \;
    find /opt/rustdesk-server-backups/monthly/ -type f -mtime +380 -name '*.tar' -execdir rm -- '{}' \;
    echo -ne "${GREEN}Backup Completed${NC}\n"
    exit

else
    tar -cf /opt/rustdesk-server-backups/rustdesk-backup-${dt_now}.tar -C ${tmp_dir} .
    rm -rf ${tmp_dir}
    echo -ne "${GREEN}Backup saved to /opt/rustdesk-server-backups/rustdesk-backup-${dt_now}.tar${NC}\n"
fi
