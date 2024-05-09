#!/bin/bash

set -eu pipefail

# verification de l'exécution en root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

OS=$(uname -m)

# Variables
PATH_CONFIG="./config"
PATH_WG="/etc/wireguard"
PATH_ZBX="/etc/zabbix"
PATH_SERVICE="/etc/systemd/system"

if [ "$OS" == "armv7l" ]; then
    REPO_ZBX="https://repo.zabbix.com/zabbix/6.4/raspbian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
    REPO_PROM="https://github.com/grafana/loki/releases/download/v2.9.5/promtail-linux-arm.zip"
    PATH_PROM="/usr/local/bin/promtail-linux-arm"
elif [ "$OS" == "x86_64" ]; then
    REPO_ZBX="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
    REPO_PROM="https://github.com/grafana/loki/releases/download/v2.9.6/promtail-linux-amd64.zip"
    PATH_PROM="/usr/local/bin/promtail-linux-amd64"
else
    REPO_ZBX=""
    REPO_PROM=""
    PATH_PROM=""
fi

repo_download () {
    wget -q --show-progress -O $PWD/repo_zbx $REPO_ZBX
    wget -q --show-progress -O $PWD/promtail-linux $REPO_PROM
    apt install -y ./repo_zbx && apt update
    apt install -y wireguard zabbix-proxy-sqlite3 zabbix-agent syslog-ng
}

install_wireguard () {
    # Génération de la clé privée
    wg genkey > $PATH_WG/private.key
    chmod go= $PATH_WG/private.key 

    # Génération de la clé publique
    cat $PATH_WG/private.key | wg pubkey > $PATH_WG/public.key

    # Transfert de la configuration WG
    cat $PATH_CONFIG/wireguard.conf > $PATH_WG/wg0.conf

    # Insère la clé privée dans le fichier de config
    privkey=$(cat $PATH_WG/private.key)
    pubkey=$(cat $PATH_WG/public.key)
    sed -i "3c\PrivateKey = $privkey" $PATH_WG/wg0.conf
    sed -i "9c\PublicKey = $pubkey" $PATH_WG/wg0.conf
}

install_zbx_proxy () {
    # Création de la DB et de l'utilisateur Zabbix
    touch /etc/zabbix/zbx_db.sql

    # Intégration de la PSK Zabbix
    #openssl rand -hex 32 > $PATH_ZBX/zabbix_proxy.psk
    #chmod a=r $PATH_ZBX/zabbix_proxy.psk
    #chown root:zabbix $PATH_ZBX/zabbix_proxy.psk

    # Remplacement de la configuration
    cat $PATH_CONFIG/zbx_proxy.conf > $PATH_ZBX/zabbix_proxy.conf
}

install_zbx_agent () {
    # Remplacement de la configuration
    cat $PATH_CONFIG/zbx_agent.conf > $PATH_ZBX/zabbix_agentd.conf 
}

install_promtail () {
    # Extraction du binaire
    unzip $PWD/promtail-linux -d /usr/local/bin/
    chmod a+x $PATH_PROM

    # Création d'un utilisateur système
    useradd --system promtail
    usermod -aG adm promtail

    # Remplacement des configurations
    cat << EOF > $PATH_SERVICE/promtail.service
[Unit]
Description=Promtail service
After=network.target

[Service]
Type=simple
User=promtail
ExecStart=$PATH_PROM -config.file /usr/local/bin/config-promtail.yml

[Install]
WantedBy=multi-user.target
EOF
    cat $PATH_CONFIG/promtail.conf.yml > /usr/local/bin/config-promtail.yml
}

install_syslog () {
    # Active rsyslog au démarrage
    systemctl enable syslog-ng

    # Création de la configuration Rsyslog
    cat $PATH_CONFIG/syslog-ng.conf > /etc/syslog-ng.d/syslog-ng2.conf
}

starting () {
    # Start wireguard
    wg-quick up wg0
    systemctl enable wg-quick@wg0.service

    # Start zabbix proxy
    systemctl start zabbix-proxy
    systemctl enable zabbix-proxy

    # Start zabbix agent
    systemctl start zabbix-agent
    systemctl enable zabbix-agent

    # Start rsyslog
    systemctl start syslog-ng
    systemctl enable syslog-ng

    # Start promtail
    systemctl start promtail.service
    systemctl enable promtail.service
}

main () {
    functions=(repo_download install_wireguard install_zbx_proxy install_zbx_agent install_promtail install_syslog starting)

    for func in "${functions[@]}"; do 
        # Run the function in background
        $func &

        # Capture the PID of the background process
        pid=$!

        # Wait for the background process to finish
        wait $pid

        # Check the exit status of the background process
        if [ $? -eq 0 ]; then
            echo "V - $func ran successfully"
        else
            echo "X - $func encountered an error"
            exit 1
        fi
    done
    echo "Script ended successfully"
}

apt update & apt upgrade -y
apt install -y sudo wget curl nano unzip systemctl iproute2
main