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

PATH=$(pwd)
echo "$path"

# Check for /var/lib/rustdesk-server/
if [ -d "$RUSTDESK_INSTALL_DIR" ]
then
    print_text_in_color "$ICyan" "$RUSTDESK_INSTALL_DIR already exists so not needing to restore"
    exit
fi

# But we never downloaded the tar? Why do we expect the tar to be in path?
tmp_dir=$(mktemp -d -t)
tar -xf "$path"/*.tar -C "$tmp_dir"

cp -rf "${tmp_dir}"/rustdesk-server/ /var/lib/
sudo chown "${usern}":"${usern}" -R /var/lib/rustdesk-server/
rm /var/lib/rustdesk-server/db.sqlite3
sqlite3 /var/lib/rustdesk-server/db.sqlite3 < "${tmp_dir}"/db_backup_file.sql

# Get current release version
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }' | sed 's/-.*//')

cd /var/lib/rustdesk-server/
rm -rf static/

echo "Installing RustDesk Server"
if [ "${ARCH}" = "x86_64" ] ; then
wget https://github.com/rustdesk/rustdesk-server-pro/releases/download/"${RDLATEST}"/rustdesk-server-linux-amd64.tar.gz
tar -xf rustdesk-server-linux-amd64.tar.gz
mv amd64/static /var/lib/rustdesk-server/
sudo mv amd64/hbbr /usr/bin/
sudo mv amd64/hbbs /usr/bin/
rm -rf amd64/
rm -rf rustdesk-server-linux-amd64.tar.gz
elif [ "${ARCH}" = "armv7l" ] ; then
wget "https://github.com/rustdesk/rustdesk-server-pro/releases/download/${RDLATEST}/rustdesk-server-linux-armv7.tar.gz"
tar -xf rustdesk-server-linux-armv7.tar.gz
mv armv7/static /var/lib/rustdesk-server/
sudo mv armv7/hbbr /usr/bin/
sudo mv armv7/hbbs /usr/bin/
rm -rf armv7/
rm -rf rustdesk-server-linux-armv7.tar.gz
elif [ "${ARCH}" = "aarch64" ] ; then
wget "https://github.com/rustdesk/rustdesk-server-pro/releases/download/${RDLATEST}/rustdesk-server-linux-arm64v8.tar.gz"
tar -xf rustdesk-server-linux-arm64v8.tar.gz
mv arm64v8/static /var/lib/rustdesk-server/
sudo mv arm64v8/hbbr /usr/bin/
sudo mv arm64v8/hbbs /usr/bin/
rm -rf arm64v8/
rm -rf rustdesk-server-linux-arm64v8.tar.gz
fi

sudo chmod +x /usr/bin/hbbs
sudo chmod +x /usr/bin/hbbr

# Make folder /var/log/rustdesk-server/
if [ ! -d "/var/log/rustdesk-server" ]; then
    echo "Creating /var/log/rustdesk-server"
    sudo mkdir -p /var/log/rustdesk-server/
fi
sudo chown "${usern}" -R /var/log/rustdesk-server/

# Setup systemd to launch hbbs
rustdeskhbbs="$(cat << EOF
[Unit]
Description=RustDesk Signal Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbs
WorkingDirectory=/var/lib/rustdesk-server/
User=${usern}
Group=${usern}
Restart=always
StandardOutput=append:/var/log/rustdesk-server/hbbs.log
StandardError=append:/var/log/rustdesk-server/hbbs.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${rustdeskhbbs}" | sudo tee /etc/systemd/system/rustdesk-hbbs.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable rustdesk-hbbs.service
sudo systemctl start rustdesk-hbbs.service

# Setup systemd to launch hbbr
rustdeskhbbr="$(cat << EOF
[Unit]
Description=RustDesk Relay Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbr
WorkingDirectory=/var/lib/rustdesk-server/
User=${usern}
Group=${usern}
Restart=always
StandardOutput=append:/var/log/rustdesk-server/hbbr.log
StandardError=append:/var/log/rustdesk-server/hbbr.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${rustdeskhbbr}" | sudo tee /etc/systemd/system/rustdesk-hbbr.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable rustdesk-hbbr.service
sudo systemctl start rustdesk-hbbr.service

while ! [[ $CHECK_RUSTDESK_READY ]]; do
  CHECK_RUSTDESK_READY=$(sudo systemctl status rustdesk-hbbr.service | grep "Active: active (running)")
  echo -ne "RustDesk Relay not ready yet...${NC}\n"
  sleep 3
done

pubname=$(find /var/lib/rustdesk-server/ -name "*.pub")
key=$(cat "${pubname}")

echo "Tidying up install"
if [ "${ARCH}" = "x86_64" ] ; then
rm rustdesk-server-linux-amd64.tar.gz
rm -rf amd64
elif [ "${ARCH}" = "armv7l" ] ; then
rm rustdesk-server-linux-armv7.tar.gz
rm -rf armv7
elif [ "${ARCH}" = "aarch64" ] ; then
rm rustdesk-server-linux-arm64v8.tar.gz
rm -rf arm64v8
fi

rm -rf "${tmp_dir:?}"/

# Choice for DNS or IP
PS3='Choose your preferred option, IP or DNS/Domain:'
WAN=("IP" "DNS/Domain")
select WANOPT in "${WAN[@]}"; do
case $WANOPT in
"IP")
wanip=$(dig @resolver4.opendns.com myip.opendns.com +short)
sudo ufw allow 21114/tcp

sudo ufw enable && ufw reload
break
;;

"DNS/Domain")
echo -ne "Enter your preferred domain/DNS address ${NC}: "
read wanip
# Check wanip is valid domain
if ! [[ $wanip =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]]; then
    echo -e "${RED}Invalid domain/DNS address${NC}"
    exit 1
fi

echo "Installing nginx"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    sudo apt -y install nginx
    sudo apt -y install python3-certbot-nginx
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ] ; then
# openSUSE 15.4 fails to run the relay service and hangs waiting for it
# Needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    sudo yum -y install nginx
    sudo yum -y install python3-certbot-nginx
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -S install nginx
    sudo pacman -S install python3-certbot-nginx
else
    echo "Unsupported OS"
    # Here you could ask the user for permission to try and install anyway
    # If they say yes, then do the install
    # If they say no, exit the script
    exit 1
fi

rustdesknginx="$(
  cat <<EOF
server {
  server_name ${wanip};
      location / {
        proxy_pass http://127.0.0.1:21114/;
}
}
EOF
)"
echo "${rustdesknginx}" | sudo tee /etc/nginx/sites-available/rustdesk.conf >/dev/null

sudo ln -s /etc/nginx/sites-available/rustdesk.conf /etc/nginx/sites-enabled/rustdesk.conf

sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

sudo ufw enable && ufw reload

sudo certbot --nginx -d "${wanip}"

break
;;
*) echo "Invalid option $REPLY";;
esac
done

echo -e "Your IP/DNS Address is ${wanip}"
echo -e "Your public key is ${key}"

echo -e "Restore is complete"
