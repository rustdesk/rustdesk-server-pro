#!/usr/bin/env bash
usern=$(whoami)
path=$(pwd)
echo $path

# Make folder /var/lib/rustdesk-server/
if [ ! -d "/var/lib/rustdesk-server" ]; then
    echo "Creating /var/lib/rustdesk-server"
    sudo mkdir -p /var/lib/rustdesk-server/
    sudo chown ${usern}:${usern} -R /var/lib/rustdesk-server/

fi

sudo apt update
sudo apt install sqlite3 -y

mkdir -p ${tmp_dir}/

tar -xf $path/*.tar -C $tmp_dir


cp -rf ${tmp_dir}/ /var/lib/rustdesk-server/
sqlite3 db.sqlite3 < db_backup_file.bak

# Get current release version
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }' | sed 's/-.*//')

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
        UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
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

cd /var/lib/rustdesk-server/
rm -rf static/

echo "Installing RustDesk Server"
if [ "${ARCH}" = "x86_64" ] ; then
wget https://github.com/rustdesk/rustdesk-server-pro/releases/download/${RDLATEST}/rustdesk-server-linux-amd64.tar.gz
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
sudo apt -y install nginx
sudo apt -y install python3-certbot-nginx

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

sudo rm /etc/nginx/sites-available/default
sudo rm /etc/nginx/sites-enabled/default

sudo ln -s /etc/nginx/sites-available/rustdesk.conf /etc/nginx/sites-enabled/rustdesk.conf

sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

sudo ufw enable && ufw reload

sudo certbot --nginx -d ${wanip}

break
;;
*) echo "Invalid option $REPLY";;
esac
done

echo -e "Your IP/DNS Address is ${wanip}"
echo -e "Your public key is ${key}"

echo -e "Restore is complete"
