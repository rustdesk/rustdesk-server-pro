#!/bin/bash

# This script will do the following to install RustDesk Pro
# 1. Install some dependencys
# 2. Setup ufw firewall if available
# 3. Create a Folder /var/lib/rustdesk-server
# 4. Download and extract RustDesk Pro Services to the above folder
# 5. Create systemd services for hbbs and hbbr
# 6. If you chose Domain, it will install Nginx and certbot, allowing the API to be available on port 443 (https) and get an SSL certificate over port 80, this will autorenew.

# Get Username
uname=$(whoami)
admintoken=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)

ARCH=$(uname -m)


# identify OS
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
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    OS=SuSE
    VER=$(cat /etc/SuSe-release)
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi


# output ebugging info if $DEBUG set
if [ "$DEBUG" = "true" ]; then
    echo "OS: $OS"
    echo "VER: $VER"
    echo "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Setup prereqs for server
# common named prereqs
PREREQ="curl wget unzip tar"
PREREQDEB="dnsutils ufw" 
PREREQRPM="bind-utils"
PREREQARCH="bind"

echo "Installing prerequisites"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ]  || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y  ${PREREQ} ${PREREQDEB} # git
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ]   || [ "${UPSTREAM_ID}" = "rhel" ] ; then
# opensuse 15.4 fails to run the relay service and hangs waiting for it
# needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    sudo yum update -y
    sudo yum install -y  ${PREREQ} ${PREREQRPM} # git
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -Syu
    sudo pacman -S ${PREREQ} ${PREREQARCH}
else
    echo "Unsupported OS"
    # here you could ask the user for permission to try and install anyway
    # if they say yes, then do the install
    # if they say no, exit the script
    exit 1
fi

# Setting up firewall

sudo ufw allow 21115:21119/tcp
sudo ufw allow 22/tcp
sudo ufw allow 21116/udp
sudo ufw enable

# Make Folder /var/lib/rustdesk-server/
if [ ! -d "/var/lib/rustdesk-server" ]; then
    echo "Creating /var/lib/rustdesk-server"
    sudo mkdir -p /var/lib/rustdesk-server/
fi

sudo chown "${uname}" -R /var/lib/rustdesk-server
cd /var/lib/rustdesk-server/ || exit 1


#Download latest version of Rustdesk
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }')

echo "Installing Rustdesk Server"
if [ "${ARCH}" = "x86_64" ] ; then
wget https://github.com/rustdesk/rustdesk-server-pro/releases/download/1.1.8/rustdesk-server-linux-amd64.zip
unzip rustdesk-server-linux-amd64.zip
mv amd64/static /var/lib/rustdesk-server/
sudo mv amd64/hbbr /usr/bin/
sudo mv amd64/hbbs /usr/bin/
rm -rf amd64/
rm -rf rustdesk-server-linux-amd64.zip
elif [ "${ARCH}" = "armv7l" ] ; then
wget "https://github.com/rustdesk/rustdesk-server-pro/releases/download/${RDLATEST}/rustdesk-server-linux-armv7.zip"
unzip rustdesk-server-linux-armv7.zip
mv armv7/static /var/lib/rustdesk-server/
sudo mv armv7/hbbr /usr/bin/
sudo mv armv7/hbbs /usr/bin/
rm -rf armv7/
rm -rf rustdesk-server-linux-armv7.zip
elif [ "${ARCH}" = "aarch64" ] ; then
wget "https://github.com/rustdesk/rustdesk-server-pro/releases/download/${RDLATEST}/rustdesk-server-linux-arm64v8.zip"
unzip rustdesk-server-linux-arm64v8.zip
mv arm64v8/static /var/lib/rustdesk-server/
sudo mv arm64v8/hbbr /usr/bin/
sudo mv arm64v8/hbbs /usr/bin/
rm -rf arm64v8/
rm -rf rustdesk-server-linux-arm64v8.zip
fi

sudo chmod +x /usr/bin/hbbs
sudo chmod +x /usr/bin/hbbr


# Make Folder /var/log/rustdesk/
if [ ! -d "/var/log/rustdesk" ]; then
    echo "Creating /var/log/rustdesk"
    sudo mkdir -p /var/log/rustdesk/
fi
sudo chown "${uname}" -R /var/log/rustdesk/

# Setup Systemd to launch hbbs
rustdeskhbbs="$(cat << EOF
[Unit]
Description=Rustdesk Signal Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbs
WorkingDirectory=/var/lib/rustdesk-server/
User=${uname}
Group=${uname}
Restart=always
StandardOutput=append:/var/log/rustdesk/rustdeskhbbs.log
StandardError=append:/var/log/rustdesk/rustdeskhbbs.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${rustdeskhbbs}" | sudo tee /etc/systemd/system/rustdeskhbbs.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable rustdeskhbbs.service
sudo systemctl start rustdeskhbbs.service

# Setup Systemd to launch hbbr
rustdeskhbbr="$(cat << EOF
[Unit]
Description=Rustdesk Relay Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbr
WorkingDirectory=/var/lib/rustdesk-server/
User=${uname}
Group=${uname}
Restart=always
StandardOutput=append:/var/log/rustdesk/rustdeskhbbr.log
StandardError=append:/var/log/rustdesk/rustdeskhbbr.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${rustdeskhbbr}" | sudo tee /etc/systemd/system/rustdeskhbbr.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable rustdeskhbbr.service
sudo systemctl start rustdeskhbbr.service

while ! [[ $CHECK_RUSTDESK_READY ]]; do
  CHECK_RUSTDESK_READY=$(sudo systemctl status rustdeskhbbr.service | grep "Active: active (running)")
  echo -ne "Rustdesk Relay not ready yet...${NC}\n"
  sleep 3
done

pubname=$(find /var/lib/rustdesk-server/ -name "*.pub")
key=$(cat "${pubname}")

echo "Tidying up install"
if [ "${ARCH}" = "x86_64" ] ; then
rm rustdesk-server-linux-amd64.zip
rm -rf amd64
elif [ "${ARCH}" = "armv7l" ] ; then
rm rustdesk-server-linux-armv7.zip
rm -rf armv7
elif [ "${ARCH}" = "aarch64" ] ; then
rm rustdesk-server-linux-arm64v8.zip
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
echo -ne "Enter your preferred domain/dns address ${NC}: "
read wanip
#check wanip is valid domain
if ! [[ $wanip =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]]; then
    echo -e "${RED}Invalid domain/dns address${NC}"
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
*) echo "invalid option $REPLY";;
esac
done

echo -e "Your IP/DNS Address is ${wanip}"
echo -e "Your public key is ${key}"
