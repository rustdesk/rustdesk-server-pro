#!/bin/bash

# shellcheck disable=2034,2059,2164
true
# see https://github.com/koalaman/shellcheck/wiki/Directive

# This script will do the following to install RustDesk Server Pro
# 1. Install some dependencies
# 2. Setup UFW firewall if available
# 3. Create 2 folders /var/lib/rustdesk-server and /var/log/rustdesk-server ("$RUSTDESK_LOG_DIR")
# 4. Download and extract RustDesk Pro Services to the above folder
# 5. Create systemd services for hbbs and hbbr
# 6. If you choose Domain, it will install Nginx and Certbot, allowing the API to be available on port 443 (https) and get an SSL certificate over port 80, it is automatically renewed

##################################################################################################################

if [[ "$EUID" -ne 0 ]]
then
    echo "Sorry, you are not root. You now have two options:"
    echo
    echo "1. Use SUDO directly:"
    echo "   a) :~$ sudo bash install.sh"
    echo
    echo "2. Become ROOT and then type your command:"
    echo "   a) :~$ sudo -i"
    echo "   b) :~# bash install.sh"
    echo
    echo "More information can be found here: https://unix.stackexchange.com/a/3064"
    exit 1
fi

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

# Setup prereqs for server
# Common named prereqs
PREREQ=(curl wget unzip tar whiptail)
PREREQDEB=(dnsutils ufw)
PREREQRPM=(bind-utils)
PREREQARCH=(bind)

echo "Installing prerequisites"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]
then
    apt-get update
    apt-get install -y "${PREREQ[@]}" "${PREREQDEB[@]}"
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ]
then
# openSUSE 15.4 fails to run the relay service and hangs waiting for it
# Needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    yum update -y
    yum install -y "${PREREQ[@]}" "${PREREQRPM[@]}" # git
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]
then
    pacman -Syu
    pacman -S "${PREREQ[@]}" "${PREREQARCH[@]}"
else
    echo "Unsupported OS!"
    # Here you could ask the user for permission to try and install anyway
    # If they say yes, then do the install
    # If they say no, exit the script
    exit 1
fi

# Download the lib file
if ! curl -fSL https://raw.githubusercontent.com/rustdesk/rustdesk-server-pro/main/lib.sh -o lib.sh
then
    echo "Failed to download the lib.sh file. Please try again"
    exit 1
fi

# shellcheck disable=2034,2059,2164
true
# shellcheck source=lib.sh
source lib.sh

# Select user for installation
msg_box "Rustdesk needs to be installed as root, but you can still do some parts as an unprivileged user.
Running with an unprivileged user enhances security, and is recommended."

if yesno_box_yes "Do you want to use an unprivileged user where it's possible?"
then
    while :
    do
        RUSTDESK_USER=$(input_box_flow "Please enter the name of your non-root user:")
        if ! id "$RUSTDESK_USER"
        then
            msg_box "We couldn't find $RUSTDESK_USER on the system, are you sure it's correct?
Please try again."
        else
            break
        fi
    done

    run_as_non_root_user() {
        sudo -u "$RUSTDESK_USER" "$@";
    }

   chown "$RUSTDESK_USER":"$RUSTDESK_USER" lib.sh
fi

# Output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]
then
    print_text_in_color "$ICyan" "OS: $OS"
    print_text_in_color "$ICyan" "VER: $VER"
    print_text_in_color "$ICyan" "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Setting up firewall
ufw allow 21115:21119/tcp
ufw allow 22/tcp
ufw allow 21116/udp

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

# Make folder /var/log/rustdesk-server/
if [ ! -d "$RUSTDESK_LOG_DIR" ]
then
    print_text_in_color "$IGreen" "Creating $RUSTDESK_LOG_DIR"
    install -d -m 700 "$RUSTDESK_LOG_DIR"
    # Set permissions
    if [ -n "$RUSTDESK_USER" ]
    then
         chown -R "$RUSTDESK_USER":"$RUSTDESK_USER" "$RUSTDESK_LOG_DIR"
    fi
fi

# Setup systemd to launch hbbs
if [ ! -f "/etc/systemd/system/rustdesk-hbbs.service" ]
then
    touch "/etc/systemd/system/rustdesk-hbbs.service"
    if [ -n "$RUSTDESK_USER" ]
    then
    cat << HBBS_RUSTDESK_SERVICE > "/etc/systemd/system/rustdesk-hbbs.service"
[Unit]
Description=RustDesk Signal Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbs
WorkingDirectory=$RUSTDESK_INSTALL_DIR
User=${RUSTDESK_USER}
Group=${RUSTDESK_USER}
Restart=always
StandardOutput=append:$RUSTDESK_LOG_DIR/hbbs.log
StandardError=append:$RUSTDESK_LOG_DIR/hbbs.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
HBBS_RUSTDESK_SERVICE
else
    cat << HBBS_RUSTDESK_SERVICE > "/etc/systemd/system/rustdesk-hbbs.service"
[Unit]
Description=RustDesk Signal Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbs
WorkingDirectory=$RUSTDESK_INSTALL_DIR
User=root
Group=root
Restart=always
StandardOutput=append:$RUSTDESK_LOG_DIR/hbbs.log
StandardError=append:$RUSTDESK_LOG_DIR/hbbs.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
HBBS_RUSTDESK_SERVICE
    fi
fi

# Setup systemd to launch hbbr
if [ ! -f "/etc/systemd/system/rustdesk-hbbr.service" ]
then
    touch "/etc/systemd/system/rustdesk-hbbr.service"
    if [ -n "$RUSTDESK_USER" ]
    then
    cat << HBBR_RUSTDESK_SERVICE > "/etc/systemd/system/rustdesk-hbbr.service"
[Unit]
Description=RustDesk Relay Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbr
WorkingDirectory=$RUSTDESK_INSTALL_DIR
User=${RUSTDESK_USER}
Group=${RUSTDESK_USER}
Restart=always
StandardOutput=append:$RUSTDESK_LOG_DIR/hbbr.log
StandardError=append:$RUSTDESK_LOG_DIR/hbbr.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
HBBR_RUSTDESK_SERVICE
else
    cat << HBBR_RUSTDESK_SERVICE > "/etc/systemd/system/rustdesk-hbbr.service"
[Unit]
Description=RustDesk Relay Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbr
WorkingDirectory=$RUSTDESK_INSTALL_DIR
User=root
Group=root
Restart=always
StandardOutput=append:$RUSTDESK_LOG_DIR/hbbr.log
StandardError=append:$RUSTDESK_LOG_DIR/hbbr.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
HBBR_RUSTDESK_SERVICE
    fi
fi

# Enable services
# HBBR
systemctl enable rustdesk-hbbr.service
systemctl start rustdesk-hbbr.service
# HBBS
systemctl enable rustdesk-hbbs.service
systemctl start rustdesk-hbbs.service

while :
do
    if ! systemctl status rustdesk-hbbr.service | grep "Active: active (running)"
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

choice=$(whiptail --title "Rustdesk installation script" --menu \
"Choose your preferred option, IP or DNS/Domain:

DNS = Setup Rustdesk with TLS and your own domain
IP  = You don't have a domain, only plain IP
$MENU_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"DNS" "(e.g. rustdesk.example.com)" \
"IP" "($WANIP4)" 3>&1 1>&2 2>&3)

case "$choice" in
    "DNS")
        # Enter domain
        while :
        do
            RUSTDESK_DOMAIN=$(input_box_flow "Please enter your domain, e.g. rustdesk.example.com")
            DIG=$(dig +short "${RUSTDESK_DOMAIN}" @resolver1.opendns.com)
            if ! [[ "$RUSTDESK_DOMAIN" =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]]
            then
                msg_box "$RUSTDESK_DOMAIN is an invalid domain/DNS address! Please try again."
            else
                break
            fi
        done

        # Check if DNS are forwarded correctly
        if dig +short "$RUSTDESK_DOMAIN" @resolver1.opendns.com | grep -q "$WANIP4"
        then
            print_text_in_color "$IGreen" "DNS seems correct when checking with dig!"
        else
        msg_box "DNS lookup failed with dig. The external IP ($WANIP4) \
address of this server is not the same as the A-record ($DIG).
Please check your DNS settings! Maybe the domain hasn't propagated?
Please check https://www.whatsmydns.net/#A/${RUSTDESK_DOMAIN} if the IP seems correct."
            exit 1
        fi


        print_text_in_color "$IGreen" "Installing Nginx"
        if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]
        then
            if yesno_box_yes "We use Certbot to generate the free TLS certificate from Let's Encrypt.
The default behavior of installing Certbot is to use the snap package which auto updates, and provides the latest version of Certbot. If you don't like snap packages, you can opt out now and we'll use regular (old) deb packages instead.

Do you want to install Certbot with snap? (recommended)"
            then
                apt-get install nginx -y
                apt-get install snapd -y
                snap install certbot --classic
            else
                apt-get install nginx -y
                apt-get install python3-certbot-nginx -y
            fi
        elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ]
        then
            # openSUSE 15.4 fails to run the relay service and hangs waiting for it
            # Needs more work before it can be enabled
            # || [ "${UPSTREAM_ID}" = "suse" ]
            yum -y install nginx
            yum -y install python3-certbot-nginx
        elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]
        then
           pacman -S install nginx
           pacman -S install python3-certbot-nginx
        else
           msg_box "Sorry, your OS is unsupported"
            if ! yesno_box_no "It might work anyway though... Do you want to give it a shot?"
            then
                exit 1
            fi
        fi

        if [ ! -f "/etc/nginx/sites-available/rustdesk.conf" ]
        then
            rm -f "/etc/nginx/sites-available/rustdesk.conf"
            rm -f "/etc/nginx/sites-enabled/rustdesk.conf"
            touch "/etc/nginx/sites-available/rustdesk.conf"
            cat << NGINX_RUSTDESK_CONF > "/etc/nginx/sites-available/rustdesk.conf"
server {
  server_name ${RUSTDESK_DOMAIN};
      location / {
           proxy_set_header        X-Real-IP       \$remote_addr;
           proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:21114/;
      }
}
NGINX_RUSTDESK_CONF
        fi

        # Remove the default Nginx configs
        rm -f /etc/nginx/sites-available/default
        rm -f /etc/nginx/sites-enabled/default

        # Enable the Nginx config file
        if [ ! -f /etc/nginx/sites-enabled/rustdesk.conf ]
        then
            ln -s /etc/nginx/sites-available/rustdesk.conf /etc/nginx/sites-enabled/rustdesk.conf
        fi

        # Enable firewall rules for the domain
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw enable
        ufw reload

        # Generate the certifictae
        if ! certbot --nginx --cert-name "${RUSTDESK_DOMAIN}" --key-type ecdsa --renew-by-default --no-eff-email --agree-tos --server https://acme-v02.api.letsencrypt.org/directory -d "${RUSTDESK_DOMAIN}"
        then
            msg_box "Sorry, the TLS certificate for $RUSTDESK_DOMAIN failed to generate!
Please check that port 80/443 are correctly port forwarded, and that the DNS record points to this servers IP.

Please try again."
            exit
        fi
    ;;
    "IP")
        ufw allow 21114/tcp
        ufw enable
        ufw reload
    ;;
    *)
    ;;
esac

# Display final info!
if [ -n "$RUSTDESK_DOMAIN" ]
then
    msg_box "
Your Public Key is:
$PUBLICKEY
Your DNS Address is:
$RUSTDESK_DOMAIN

Please login at https://$RUSTDESK_DOMAIN"
Default User/Pass: admin/test1234
else
    msg_box "
Your Public Key is:
$PUBLICKEY
Your IP Address is:
$WANIP4

Please login at http://$WANIP4:21114"
Default User/Pass: admin/test1234
fi

print_text_in_color "$IGreen" "Cleaning up..."
rm -f rustdesk-server-linux-"${ACTUAL_TAR_NAME}".zip
rm -rf "${ACTUAL_TAR_NAME}"
rm -f lib.sh
