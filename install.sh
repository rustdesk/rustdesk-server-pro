#!/bin/bash

# shellcheck disable=SC2034
true
# see https://github.com/koalaman/shellcheck/wiki/Directive

# This script will do the following to install RustDesk Server Pro
# 1. Install some dependencies
# 2. Setup UFW firewall if available
# 3. Create 2 folders /var/lib/rustdesk-server and /var/log/rustdesk-server ("$RUSTDESK_LOG_DIR")
# 4. Download and extract RustDesk Pro Services to the above folder
# 5. Create systemd services for hbbs and hbbr
# 6. If you choose Domain, it will install Nginx and Certbot, allowing the API to be available on port 443 (https) and get an SSL certificate over port 80, it is automatically renewed

# Get username
usern=$(whoami)
# Not used?
admintoken=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)
export admintoken

ARCH=$(uname -m)

# Identify OS
if [ -f /etc/os-release ]
then
    # freedesktop.org and systemd
    # shellcheck source=/dev/null
    source /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    UPSTREAM_ID=${ID_LIKE,,}

    # Fallback to ID_LIKE if ID was not 'ubuntu' or 'debian'
    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]
    then
        UPSTREAM_ID="$(echo "${ID_LIKE,,}" | sed s/\"//g | cut -d' ' -f1)"
    fi

elif type lsb_release >/dev/null 2>&1
then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]
then
    # For some versions of Debian/Ubuntu without lsb_release command
    # shellcheck source=/dev/null
    source /etc/os-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]
then
    # Older Debian, Ubuntu, etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSE-release ]
then
    # Older SuSE, etc.
    OS=SuSE
    VER=$(cat /etc/SuSE-release)
elif [ -f /etc/redhat-release ]
then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi

# shellcheck source=lib.sh
source ./lib.sh

# Output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]
then
    print_text_in_color "$ICyan" "OS: $OS"
    print_text_in_color "$ICyan" "VER: $VER"
    print_text_in_color "$ICyan" "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Setup prereqs for server
# Common named prereqs
PREREQ=(curl wget unzip tar whiptail)
PREREQDEB=(dnsutils ufw)
PREREQRPM=(bind-utils)
PREREQARCH=(bind)

print_text_in_color "$IGreen" "Installing prerequisites"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]
then
    sudo apt-get update
    sudo apt-get install -y "${PREREQ[@]}" "${PREREQDEB[@]}" # git
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ]
then
# openSUSE 15.4 fails to run the relay service and hangs waiting for it
# Needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    sudo yum update -y
    sudo yum install -y "${PREREQ[@]}" "${PREREQRPM[@]}" # git
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]
then
    sudo pacman -Syu
    sudo pacman -S "${PREREQ[@]}" "${PREREQARCH[@]}"
else
    print_text_in_color "$IRed" "Unsupported OS"
    # Here you could ask the user for permission to try and install anyway
    # If they say yes, then do the install
    # If they say no, exit the script
    exit 1
fi

# Setting up firewall
sudo ufw allow 21115:21119/tcp
sudo ufw allow 22/tcp
sudo ufw allow 21116/udp
sudo ufw enable

# Download latest version of RustDesk
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }')

# Download, extract, and move Rustdesk in place
if [ -n "${ARCH}" ]
then
    # If not /var/lib/rustdesk-server/ ($RUSTDESK_INSTALL_DIR) exists we can assume this is a fresh install. If it exists though, we can't move it and it will produce an error
    if [ ! -d "$RUSTDESK_INSTALL_DIR" ]
    then
        print_text_in_color "$IGreen" "Installing RustDesk Server..."
        # Create dir
        sudo mkdir -p "$RUSTDESK_INSTALL_DIR"
        if [ -d "$RUSTDESK_INSTALL_DIR" ]
        then
            cd "$RUSTDESK_INSTALL_DIR"
            # Set permissions
            sudo chown "${usern}" -R "$RUSTDESK_INSTALL_DIR"
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
        mv "${ACTUAL_TAR_NAME}"/static "$RUSTDESK_INSTALL_DIR"
        sudo mv "${ACTUAL_TAR_NAME}"/hbbr /usr/bin/
        sudo mv "${ACTUAL_TAR_NAME}"/hbbs /usr/bin/
        rm -rf "$RUSTDESK_INSTALL_DIR"/"${ACTUAL_TAR_NAME}"/
        rm -rf rustdesk-server-linux-"${ACTUAL_TAR_NAME}".tar.gz
        sudo chmod +x /usr/bin/hbbs
        sudo chmod +x /usr/bin/hbbr
    else
        print_text_in_color "$IGreen" "Rustdesk server already installed."
    fi
else
    msg_box "Sorry, we can't figure out your distro, this script will now exit.
Please report this to: https://github.com/rustdesk/rustdesk-server-pro/issues"
    exit 1
fi

# Make folder /var/log/rustdesk-server/
if [ ! -d "$RUSTDESK_LOG_DIR" ]
then
    print_text_in_color "$IGreen" "Creating $RUSTDESK_LOG_DIR"
    sudo mkdir -p "$RUSTDESK_LOG_DIR"
fi
sudo chown "${usern}" -R "$RUSTDESK_LOG_DIR"

# Setup systemd to launch hbbs
if [ ! -f "/etc/systemd/system/rustdesk-hbbs.service" ]
then
    rm -f "/etc/systemd/system/rustdesk-hbbs.service"
    rm -f "/etc/systemd/system/rustdesk-hbbs.service"
    touch "/etc/systemd/system/rustdesk-hbbs.service"
    cat << HBBS_RUSTDESK_SERVICE > "/etc/systemd/system/rustdesk-hbbs.service"
[Unit]
Description=RustDesk Signal Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbs
WorkingDirectory="$RUSTDESK_INSTALL_DIR"
User="${usern}"
Group="${usern}"
Restart=always
StandardOutput=append:"$RUSTDESK_LOG_DIR"/hbbs.log
StandardError=append:"$RUSTDESK_LOG_DIR"/hbbs.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
HBBS_RUSTDESK_SERVICE
fi
sudo systemctl daemon-reload
sudo systemctl enable rustdesk-hbbs.service
sudo systemctl start rustdesk-hbbs.service

# Setup systemd to launch hbbr
if [ ! -f "/etc/systemd/system/rustdesk-hbbr.service" ]
then
    rm -f "/etc/systemd/system/rustdesk-hbbr.service"
    rm -f "/etc/systemd/system/rustdesk-hbbr.service"
    touch "/etc/systemd/system/rustdesk-hbbr.service"
    cat << HBBR_RUSTDESK_SERVICE > "/etc/systemd/system/rustdesk-hbbr.service"
[Unit]
Description=RustDesk Relay Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbr
WorkingDirectory="$RUSTDESK_INSTALL_DIR"
User="${usern}"
Group="${usern}"
Restart=always
StandardOutput=append:"$RUSTDESK_LOG_DIR"/hbbr.log
StandardError=append:"$RUSTDESK_LOG_DIR"/hbbr.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
HBBR_RUSTDESK_SERVICE
fi
sudo systemctl daemon-reload
sudo systemctl enable rustdesk-hbbr.service
sudo systemctl start rustdesk-hbbr.service

while ! [[ $CHECK_RUSTDESK_READY ]]
do
    CHECK_RUSTDESK_READY=$(sudo systemctl status rustdesk-hbbr.service | grep "Active: active (running)")
    echo -ne "Waiting for RustDesk Relay service${NC}\n"
    sleep 2
done

pubname=$(find "$RUSTDESK_INSTALL_DIR" -name "*.pub")
key=$(cat "${pubname}")

echo "Tidying up install"
rm -f rustdesk-server-linux-"${ACTUAL_TAR_NAME}".zip
rm -rf "${ACTUAL_TAR_NAME}"

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
read -r wanip
# Check wanip is valid domain
if ! [[ $wanip =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]]
then
    echo -e "${RED}Invalid domain/DNS address${NC}"
    exit 1
fi

print_text_in_color "$IGreen" "Installing Nginx"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]
then
    if yesno_box_yes "We use Certbot to generate the free TLS certificate from Let's Encrypt.
The default behaviour of installing Certbot is to use the snap package which auto updates, and provides the latest version of Certbot. If you don't like snap packages, you can opt out now and we'll use regular (old) deb packages instead.

Do you want to install Certbot with snap? (recommended)"
    then
        sudo apt-get install nginx -y
        sudo apt-get install snapd -y
        sudo snap install certbot --classic
    else
        sudo apt-get install nginx -y
        sudo apt-get install python3-certbot-nginx -y
    fi
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ]
then
# openSUSE 15.4 fails to run the relay service and hangs waiting for it
# Needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    sudo yum -y install nginx
    sudo yum -y install python3-certbot-nginx
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]
then
    sudo pacman -S install nginx
    sudo pacman -S install python3-certbot-nginx
else
    print_text_in_color "$IRed" "Unsupported OS"
    # Here you could ask the user for permission to try and install anyway
    # If they say yes, then do the install
    # If they say no, exit the script
    exit 1
fi

if [ ! -f "/etc/nginx/sites-available/rustdesk.conf" ]
then
    rm -f "/etc/nginx/sites-available/rustdesk.conf"
    rm -f "/etc/nginx/sites-enabled/rustdesk.conf"
    touch "/etc/nginx/sites-available/rustdesk.conf"
    cat << NGINX_RUSTDESK_CONF > "/etc/nginx/sites-available/rustdesk.conf"
server {
  server_name ${wanip};
      location / {
           proxy_set_header        X-Real-IP       \$remote_addr;
           proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:21114/;
      }
}
NGINX_RUSTDESK_CONF
fi

# Remove the default Nginx configs
sudo rm -f /etc/nginx/sites-available/default
sudo rm -f /etc/nginx/sites-enabled/default

# Enable the Nginx config file
if [ ! -f /etc/nginx/sites-enabled/rustdesk.conf ]
then
    sudo ln -s /etc/nginx/sites-available/rustdesk.conf /etc/nginx/sites-enabled/rustdesk.conf
fi

# Enable firewall rules for the domain
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw reload

# Generate the certifictae
if ! sudo certbot --nginx --cert-name "${wanip}" --key-type ecdsa --renew-by-default --no-eff-email --agree-tos --server https://acme-v02.api.letsencrypt.org/directory -d "${wanip}"
then
    msg_box "Sorry, the TLS certificate for $wanip failed to generate!
Please check that port 80/443 are correctly port forwarded, and that the DNS record points to this servers IP.

Please try again."
    exit
fi

break
;;
*) print_text_in_color "$IRed" "Invalid option $REPLY";;
esac
done

print_text_in_color "$IGreen" "Your IP/DNS Address is:"
print_text_in_color "$ICyan" "$wanip"
print_text_in_color "$IGreen" "Your public key is:"
print_text_in_color "$ICyan" "$key"
