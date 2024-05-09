# Installation du proxy du Zabbix Proxy

## Sommaire
- [Prérequis](#prérequis)
- [Installation via Docker](#proxy-via-docker)
- [Installation via Shell Script](#proxy-via-shell-script)

## Prérequis
- Installer docker + ajouter l'utilisateur local au groupe Docker
- Configurer une IP statique

## Proxy via Docker
### Configuration
1. Générer les clés publiques et privées
```bash
mkdir wireguard

# Generate privatekey
docker run --rm -i masipcat/wireguard-go wg genkey > ./wireguard/privatekey

# Generate publickey from privatekey
docker run --rm -i masipcat/wireguard-go wg pubkey < ./wireguard/privatekey > ./wireguard/publickey
```
2. Créer la configuration du tunnel dans `./wireguard/wg0.conf` et modifier les champs suivants :
```text
[Interface]
Address = 10.0.0.1                  # IP du client dans le tunnel
PrivateKey = XXXXXXX                # Générer automatiquement par le conteneur
ListenPort = 51820

[Peer]
PublicKey = XXXXXXXX                # Clé publique du serveur
AllowedIPs = 10.0.0.X/XX            # IP du serveur dans le tunnel
Endpoint = XXX.XXX.XXX.XXX:51820    # IP publique du serveur
PersistentKeepalive = 25
```
> Ne pas oublier d'ajouter le client dans la configuration du serveur

3. Modifier les paramètres du fichier `docker-compose.yml`:

| Section | zbx-proxy | 
|--|--|
| ZBX_HOSTNAME | donner le nom du proxy entré dans Zabbix |
| ZBX_SERVER_HOST | IP Wireguard du serveur |

| Section | zbx-agent | 
|--|--|
| group_add | Id du groupe docker sur la machine hote |
| Volumes | Changer `<path_to_docker_run>` par le chemin exact du socket docker de la machine hote |

4. Modifier les paramètres du fichier `promtail-config.yaml` :
- Paramètre `url`: remplacer `XXX.XXX.XXX.XXX` par l'IP Wireguard du server
- Paramètre `proxy`: donner le nom du proxy entré dans Zabbix

5. Relancer les conteneurs
```bash
docker-compose up -d
```

---

## Proxy via shell script
### Configuration
Avant de lancer le script, les fichiers présents dans le dossier `./config` doivent être configuré :
- wireguard.conf
Ce fichier contient la configuration du tunnel entre le proxy et le serveur de monitoring

```conf
# Interface de l'agent
[Interface]
Private= <champ rempli automatiquement par le script>
ListenPort = 51820         
Address = 10.0.0.0/32 # IP du proxy dans le tunnel

# Connexion au serveur
[Peer]
PublicKey = <clé publique du serveur de monitoring>
Endpoint = <ip publique du serveur>:51820
AllowedIPs = 10.0.0.X/32 # IP du serveur dans le tunnel
PersistentKeepalive = 20 # secondes
```

- zbx_proxy.conf
Ce fichier contient la configuration du proxy. Les éléments suivants doivent être modifiés :

```conf
proxyMode=1 # configuration en mode passif
Hostname=NomProxy # doit être le même que celui inscrit dans le serveur
Server=<ip> # IP tunnel Wireguard du serveur de monitoring
EnableRemoteCommands=1
LogRemoteCommands=1
DBName=/etc/zabbix/zbx_db.sql
# Seulement si le tunnel doit être chiffré
#TLSConnect=psk
#TLSAccept=psk
#TLSPSKIdentity=NomPSK
#TLSPSKFile=<chemin vers PSK>
```

- zbx_agent.conf
Ce fichier contient la configuration de l'agent installé sur le proxy. Les éléments suivants doivent être modifiés :

```conf
Server=127.0.0.1 # Afin de se connecter au proxy
Hostname=NomProxy # doit être le même que celui inscrit dans le serveur
```

- promtail.conf.yml
Ce fichier contient la configuration de promtail capable de normaliser les logs Rsyslog et les transmettre vers le serveur Loki. Les éléments suivants doivent être modifiés :

```yml
clients:
  - url: http://XXX.XXX.XXX.XXX:3100/loki/api/v1/push # Renseigner l'adresse IP tunnel Wireguard du serveur

proxy: nom_proxy # le nom du proxy renseigner dans la configuration zbx_proxy -> permettra de filtrer les logs
```

- promtail.service et rsyslog.conf
Ces fichiers n'ont pas besoin d'être modifiés

### Lancement du script
Le script doit être lancé avec l'utilisateur Root (ou en sudo) afin d'apporter les modifications au système.

```bash
sudo chmod +x ./proxy_install.sh
sudo ./proxy_install.sh
```