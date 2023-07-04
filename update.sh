#!/bin/bash

# Get Username
uname=$(whoami) # not used btw .. yet

# Get current release version
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }' | sed 's/-.*//')
RDCURRENT=$(/usr/bin/rustdesk-server/hbbr --version | sed -r 's/hbbr (.*)-.*/\1/')

if [ $RDLATEST == $RDCURRENT ]; then
    echo "Same version no need to update."
    exit 0
fi

sudo systemctl stop rustdeskhbbs.service
sudo systemctl stop rustdeskhbbr.service
sleep 20

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


if ! [ -e /var/lib/rustdesk-server/  ]; then
        echo "No directory /var/lib/rustdesk-server/ found. No update of rustdesk possible (use install.sh script ?) "
        exit 4
else
        :
fi

cd /var/lib/rustdesk-server/
rm -rf static/

echo "Upgrading Rustdesk Server"
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

sudo systemctl start rustdeskhbbs.service
sudo systemctl start rustdeskhbbr.service

while ! [[ $CHECK_RUSTDESK_READY ]]; do
  CHECK_RUSTDESK_READY=$(sudo systemctl status rustdeskhbbr.service | grep "Active: active (running)")
  echo -ne "Rustdesk Relay not ready yet...${NC}\n"
  sleep 3
done

echo -e "Updates are complete"
