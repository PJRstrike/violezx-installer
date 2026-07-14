#!/bin/bash
#
# ============================================================================
#  VIOLEZX AUTO INSTALLER
#  Panel + Wings + Admin account + Node (allocation) + Nest/Egg import
# ============================================================================
#
#  Target OS : Ubuntu 22.04 / 24.04 (fresh server, run as root)
#  Author    : generated for you, review before running on production
#
#  Semua instruksi (yang dulunya di README) sekarang ada di dalam script ini.
#  Jalankan:  ./install.sh --help   untuk lihat semua caranya lewat bash.
#
# ============================================================================

set -euo pipefail

usage() {
cat <<'USAGE'
============================================================
 VIOLEZX AUTO INSTALLER - bantuan / cara pakai
============================================================

APA YANG DILAKUKAN SCRIPT INI
  1. Install Nginx, MariaDB, Redis, PHP 8.3, Composer, Docker
  2. Download & konfigurasi Panel (branding: VIOLEZX)
  3. Bikin database + migrate/seed
  4. Bikin akun admin otomatis (password random, dicetak di akhir)
  5. Install Wings (daemon node)
  6. Lewat Application API Panel, otomatis bikin:
       - Location
       - Node "violezx-node01" (Wings langsung dinyalakan -> node hijau)
       - Allocation (blok IP:PORT)
       - Nest "Violezx Bots" + import Egg WhatsApp Bot (sudah di-embed
         langsung di dalam script ini, dari mambo.json yang kamu upload)

CARA PAKAI - LOKAL (file sudah ada di server)
  1. Edit bagian CONFIG di bawah script ini (minimal FQDN).
  2. chmod +x install.sh
  3. sudo ./install.sh 2>&1 | tee install.log
  4. Tunggu ±5-15 menit. Kredensial admin muncul di akhir dan tersimpan
     di /root/violezx-install-summary.txt
  5. Buka http://FQDN (atau https:// kalau USE_LETSENCRYPT="true")

CARA PAKAI - SATU BARIS (bash <(curl ...), style Bangsano/themeinstaller)
  Karena egg json sudah di-embed di dalam install.sh (bukan file terpisah
  lagi), script ini SUDAH single-file dan bisa langsung dijalankan lewat
  curl tanpa perlu download folder/zip. Caranya:

  1. Upload isi install.sh ke repo GitHub kamu sendiri, misal:
       github.com/USERNAME/violezx-installer -> file install.sh di branch main
  2. Ambil raw URL-nya, contoh formatnya persis seperti punyamu:
       https://raw.githubusercontent.com/USERNAME/violezx-installer/refs/heads/main/install.sh
  3. Jalankan di server (sebagai root):
       bash <(curl -s https://raw.githubusercontent.com/USERNAME/violezx-installer/refs/heads/main/install.sh)
     Kalau butuh ubah CONFIG (FQDN dll) dulu tanpa edit file di GitHub,
     download dulu baru jalankan:
       curl -s -o install.sh https://raw.githubusercontent.com/USERNAME/violezx-installer/refs/heads/main/install.sh
       nano install.sh   # edit FQDN, ADMIN_EMAIL, dst
       chmod +x install.sh && sudo ./install.sh
  4. Alternatif tanpa bikin repo penuh: paste install.sh ke GitHub Gist
     (gist.github.com -> New gist -> paste -> Create public gist), lalu
     pakai raw URL gist itu dengan cara yang sama.

  CATATAN: --help ini (dan help.sh) tetap bisa dipanggil lewat curl juga:
       bash <(curl -s RAW_URL) --help

CARA TEST TANPA VPS
  Kamu tetap butuh 1 mesin Linux (VM juga boleh), karena Wings butuh Docker
  + akses root. Beberapa opsi gratis:

  A) VirtualBox/VMware + Vagrant
       vagrant init ubuntu/jammy64
       vagrant up && vagrant ssh
       sudo su -
     Aktifkan nested virtualization (VT-x) di setting VM (wajib untuk Docker).
     Set FQDN ke IP VM (mis. 192.168.56.10), USE_LETSENCRYPT="false", lalu
     jalankan install.sh seperti biasa (lokal atau lewat curl, dua-duanya
     jalan sama karena scriptnya sudah self-contained).

  B) Multipass (macOS/Linux) atau Hyper-V (Windows)
       multipass launch 22.04 --name violezx --cpus 2 --memory 4G --disk 20G
       multipass shell violezx

  C) Cloud gratis/trial (kalau mau test SSL/domain asli)
       Oracle Cloud Always Free / GCP / AWS free tier / trial DO-Vultr.

  CATATAN: Node akan tetap hijau selama Wings jalan dan bisa connect ke
  Panel API - ini TIDAK butuh domain publik, IP lokal VM sudah cukup.
  Domain publik + SSL cuma dibutuhkan kalau mau akses Panel dari internet.

GANTI EGG / NEST
  - Egg json ada di dalam install.sh, di antara baris "cat > ... <<'EGGJSON'"
    dan "EGGJSON" (cari dengan: grep -n EGGJSON install.sh). Ganti isinya
    dengan egg lain (format export Pterodactyl: Admin > Nests > Egg > Export).
  - Ubah NEST_NAME di bagian CONFIG kalau mau nama nest lain.

KEAMANAN
  - Simpan /root/violezx-install-summary.txt di tempat aman lalu hapus dari
    server setelah dicatat.
  - API key otomatis yang dipakai script ini punya akses penuh - setelah
    instalasi selesai, revoke lewat Admin Area > Application API di Panel
    kalau tidak dipakai lagi untuk automation lain.
  - Ganti password admin setelah login pertama kali.
  - Kalau host di repo publik, JANGAN taruh password/secret asli di CONFIG;
    biarkan default random generation yang sudah ada di script ini.
============================================================
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

# ---------------------------------------------------------------------------
# CONFIG - edit these
# ---------------------------------------------------------------------------
BRAND_NAME="Violezx"
FQDN="panel.violezx.com"          # domain pointing at this server, or its public IP
USE_LETSENCRYPT="false"           # "true" only if FQDN is a real domain with DNS set up
ADMIN_EMAIL="admin@violezx.com"
ADMIN_USERNAME="violezx"
ADMIN_FIRSTNAME="Violezx"
ADMIN_LASTNAME="Admin"

NODE_NAME="violezx-node01"
NODE_IP="$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')"
NODE_PORT_RANGE_START=25565
NODE_PORT_RANGE_END=25595         # 30 allocations created by default

NEST_NAME="Violezx Bots"
NEST_DESCRIPTION="Auto-imported nest for Violezx WhatsApp bot eggs"

PANEL_DIR="/var/www/pterodactyl"
WEBSERVER_USER="www-data"

# ---------------------------------------------------------------------------
# Internal - random secrets (do not edit)
# ---------------------------------------------------------------------------
DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c20)"
ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c16)"
SUMMARY_FILE="/root/violezx-install-summary.txt"

log() { echo -e "\n\033[1;32m==> [${BRAND_NAME}] $1\033[0m"; }

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo bash install.sh)"; exit 1
fi

log "Writing embedded egg (mambo.json) to temp file"
EGG_JSON_PATH="$(mktemp /tmp/violezx-egg-XXXXXX.json)"
cat > "$EGG_JSON_PATH" <<'EGGJSON'
{
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO",
    "meta": {
        "version": "PTDL_v2",
        "update_url": null
    },
    "exported_at": "2026-05-22T13:14:50+07:00",
    "name": "Bot Whatsap",
    "author": "zakkixploit@gmail.com",
    "description": null,
    "features": null,
    "docker_images": {
        "ghcr.io/parkervcp/yolks:nodejs_24": "ghcr.io/parkervcp/yolks:nodejs_24",
        "ghcr.io/parkervcp/yolks:nodejs_23": "ghcr.io/parkervcp/yolks:nodejs_23",
        "ghcr.io/parkervcp/yolks:nodejs_22": "ghcr.io/parkervcp/yolks:nodejs_22",
        "ghcr.io/parkervcp/yolks:nodejs_21": "ghcr.io/parkervcp/yolks:nodejs_21",
        "ghcr.io/parkervcp/yolks:nodejs_20": "ghcr.io/parkervcp/yolks:nodejs_20",
        "ghcr.io/parkervcp/yolks:nodejs_19": "ghcr.io/parkervcp/yolks:nodejs_19",
        "ghcr.io/parkervcp/yolks:nodejs_18": "ghcr.io/parkervcp/yolks:nodejs_18",
        "ghcr.io/parkervcp/yolks:nodejs_17": "ghcr.io/parkervcp/yolks:nodejs_17",
        "ghcr.io/parkervcp/yolks:nodejs_16": "ghcr.io/parkervcp/yolks:nodejs_16",
        "ghcr.io/parkervcp/yolks:nodejs_15": "ghcr.io/parkervcp/yolks:nodejs_15",
        "ghcr.io/parkervcp/yolks:nodejs_14": "ghcr.io/parkervcp/yolks:nodejs_14",
        "ghcr.io/parkervcp/yolks:nodejs_13": "ghcr.io/parkervcp/yolks:nodejs_13",
        "ghcr.io/parkervcp/yolks:nodejs_12": "ghcr.io/parkervcp/yolks:nodejs_12",
        "ghcr.io/parkervcp/yolks:nodejs_11": "ghcr.io/parkervcp/yolks:nodejs_11",
        "ghcr.io/parkervcp/yolks:nodejs_10": "ghcr.io/parkervcp/yolks:nodejs_10",
        "ghcr.io/parkervcp/yolks:nodejs_9": "ghcr.io/parkervcp/yolks:nodejs_9",
        "ghcr.io/parkervcp/yolks:nodejs_8": "ghcr.io/parkervcp/yolks:nodejs_8",
        "ghcr.io/parkervcp/yolks:nodejs_7": "ghcr.io/parkervcp/yolks:nodejs_7",
        "ghcr.io/parkervcp/yolks:nodejs_6": "ghcr.io/parkervcp/yolks:nodejs_6",
        "ghcr.io/parkervcp/yolks:nodejs_5": "ghcr.io/parkervcp/yolks:nodejs_5",
        "ghcr.io/parkervcp/yolks:nodejs_4": "ghcr.io/parkervcp/yolks:nodejs_4",
        "ghcr.io/parkervcp/yolks:nodejs_3": "ghcr.io/parkervcp/yolks:nodejs_3",
        "ghcr.io/parkervcp/yolks:nodejs_2": "ghcr.io/parkervcp/yolks:nodejs_2",
        "ghcr.io/parkervcp/yolks:nodejs_1": "ghcr.io/parkervcp/yolks:nodejs_1"
    },
    "file_denylist": [],
    "startup": "if [[ -d .git ]] && [[ {{AUTO_UPDATE}} == \"1\" ]]; then git pull; fi; if [[ ! -z ${NODE_PACKAGES} ]]; then /usr/local/bin/npm install ${NODE_PACKAGES}; fi; if [[ ! -z ${UNNODE_PACKAGES} ]]; then /usr/local/bin/npm uninstall ${UNNODE_PACKAGES}; fi; if [ -f /home/container/package.json ]; then /usr/local/bin/npm install; fi;  if [[ ! -z ${CUSTOM_ENVIRONMENT_VARIABLES} ]]; then      vars=$(echo ${CUSTOM_ENVIRONMENT_VARIABLES} | tr \";\" \"\\n\");      for line in $vars;     do export $line;     done fi;  /usr/local/bin/${CMD_RUN};",
    "config": {
        "files": "{}",
        "startup": "{\r\n    \"done\": \"running\"\r\n}",
        "logs": "{}",
        "stop": "^^C"
    },
    "scripts": {
        "installation": {
            "script": "#!/bin/bash\r\n# NodeJS App Installation Script\r\n#\r\n# Server Files: /mnt/server\r\napt update\r\napt install -y git curl jq file unzip make gcc g++ python python-dev libtool\r\n\r\nmkdir -p /mnt/server\r\ncd /mnt/server\r\n\r\nif [ \"${USER_UPLOAD}\" == \"true\" ] || [ \"${USER_UPLOAD}\" == \"1\" ]; then\r\n    echo -e \"assuming user knows what they are doing have a good day.\"\r\n    exit 0\r\nfi\r\n\r\n## add git ending if it's not on the address\r\nif [[ ${GIT_ADDRESS} != *.git ]]; then\r\n    GIT_ADDRESS=${GIT_ADDRESS}.git\r\nfi\r\n\r\nif [ -z \"${USERNAME}\" ] && [ -z \"${ACCESS_TOKEN}\" ]; then\r\n    echo -e \"using anon api call\"\r\nelse\r\n    GIT_ADDRESS=\"https://${USERNAME}:${ACCESS_TOKEN}@$(echo -e ${GIT_ADDRESS} | cut -d/ -f3-)\"\r\nfi\r\n\r\n## pull git js repo\r\nif [ \"$(ls -A /mnt/server)\" ]; then\r\n    echo -e \"/mnt/server directory is not empty.\"\r\n    if [ -d .git ]; then\r\n        echo -e \".git directory exists\"\r\n        if [ -f .git/config ]; then\r\n            echo -e \"loading info from git config\"\r\n            ORIGIN=$(git config --get remote.origin.url)\r\n        else\r\n            echo -e \"files found with no git config\"\r\n            echo -e \"closing out without touching things to not break anything\"\r\n            exit 10\r\n        fi\r\n    fi\r\n\r\n    if [ \"${ORIGIN}\" == \"${GIT_ADDRESS}\" ]; then\r\n        echo \"pulling latest from github\"\r\n        git pull\r\n    fi\r\nelse\r\n    echo -e \"/mnt/server is empty.\\ncloning files into repo\"\r\n    if [ -z ${BRANCH} ]; then\r\n        echo -e \"cloning default branch\"\r\n        git clone ${GIT_ADDRESS} .\r\n    else\r\n        echo -e \"cloning ${BRANCH}'\"\r\n        git clone --single-branch --branch ${BRANCH} ${GIT_ADDRESS} .\r\n    fi\r\n\r\nfi\r\n\r\necho \"Installing nodejs packages\"\r\nif [[ ! -z ${NODE_PACKAGES} ]]; then\r\n    /usr/local/bin/npm install ${NODE_PACKAGES}\r\nfi\r\n\r\nif [ -f /mnt/server/package.json ]; then\r\n    /usr/local/bin/npm install --production\r\nfi\r\n\r\necho -e \"install complete\"\r\nexit 0",
            "container": "node:14-buster-slim",
            "entrypoint": "bash"
        }
    },
    "variables": [
        {
            "name": "Git Repo Address",
            "description": "GitHub Repo to clone\r\n\r\nI.E. https://github.com/user_name/repo_name",
            "env_variable": "GIT_ADDRESS",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Install Branch",
            "description": "The branch to install.",
            "env_variable": "BRANCH",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Git Username",
            "description": "Username to auth with git.",
            "env_variable": "USERNAME",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Git Access Token",
            "description": "Password to use with git.\r\n\r\nIt's best practice to use a Personal Access Token.\r\nhttps://github.com/settings/tokens\r\nhttps://gitlab.com/-/profile/personal_access_tokens",
            "env_variable": "ACCESS_TOKEN",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Command Run",
            "description": "The command to start the bot",
            "env_variable": "CMD_RUN",
            "default_value": "npm start",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string",
            "field_type": "text"
        }
    ]
}
EGGJSON

# ---------------------------------------------------------------------------
# 1. Dependencies
# ---------------------------------------------------------------------------
log "Installing base dependencies"
apt update -y
apt install -y software-properties-common curl apt-transport-https ca-certificates \
  gnupg lsb-release unzip git tar jq cron

log "Adding PHP 8.3 + MariaDB + Redis repos"
LSB_CODENAME="$(lsb_release -cs)"
add-apt-repository -y ppa:ondrej/php
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
apt update -y

log "Installing PHP, Nginx, MariaDB, Redis, Composer"
apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,sqlite3} \
  nginx mariadb-server redis-server

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

systemctl enable --now mariadb redis-server php8.3-fpm nginx cron

# ---------------------------------------------------------------------------
# 2. Database
# ---------------------------------------------------------------------------
log "Creating database + panel user"
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# ---------------------------------------------------------------------------
# 3. Panel download + install
# ---------------------------------------------------------------------------
log "Downloading Panel"
mkdir -p "$PANEL_DIR"
cd "$PANEL_DIR"
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzf panel.tar.gz --strip-components=1
rm panel.tar.gz
chmod -R 755 storage/* bootstrap/cache

cp .env.example .env
composer install --no-dev --optimize-autoloader --no-interaction

php artisan key:generate --force

log "Configuring .env (database + mail + app settings)"
php artisan p:environment:setup \
  --author="${ADMIN_EMAIL}" \
  --url="http://${FQDN}" \
  --app-name="${BRAND_NAME}" \
  --timezone="Asia/Jakarta" \
  --cache="redis" \
  --session="redis" \
  --queue="redis" \
  --redis-host="localhost" \
  --redis-pass="null" \
  --redis-port="6379" \
  --settings-ui=true \
  --no-interaction

php artisan p:environment:database \
  --host="127.0.0.1" \
  --port="3306" \
  --database="panel" \
  --username="pterodactyl" \
  --password="${DB_PASSWORD}" \
  --no-interaction

log "Running migrations + seeders"
php artisan migrate --seed --force

log "Creating admin account"
php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USERNAME}" \
  --name-first="${ADMIN_FIRSTNAME}" \
  --name-last="${ADMIN_LASTNAME}" \
  --password="${ADMIN_PASSWORD}" \
  --admin=1 \
  --no-interaction

chown -R ${WEBSERVER_USER}:${WEBSERVER_USER} "$PANEL_DIR"/*

log "Setting up cron + queue worker"
( crontab -l 2>/dev/null; echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1" ) | crontab -

cat > /etc/systemd/system/pteroq.service <<'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now pteroq.service

log "Configuring Nginx vhost"
cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${FQDN};
    root ${PANEL_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

if [[ "$USE_LETSENCRYPT" == "true" ]]; then
  log "Requesting Let's Encrypt certificate"
  apt install -y certbot python3-certbot-nginx
  certbot --nginx -d "${FQDN}" --non-interactive --agree-tos -m "${ADMIN_EMAIL}" || \
    echo "Certbot failed - continuing on plain HTTP, fix DNS and rerun certbot manually"
fi

# ---------------------------------------------------------------------------
# 4. Application API key (used by this script to talk to the Panel API)
# ---------------------------------------------------------------------------
log "Generating an Application API key via tinker"
API_KEY="$(php artisan tinker --execute="
\$s = app(\Pterodactyl\Services\Api\KeyCreationService::class);
\$m = \$s->setKeyType(\Pterodactyl\Models\ApiKey::TYPE_APPLICATION)->handle(
  ['user_id' => 1, 'allowed_ips' => []],
  ['r_servers'=>3,'r_nodes'=>3,'r_allocations'=>3,'r_users'=>3,'r_locations'=>3,'r_nests'=>3,'r_eggs'=>3]
);
echo \$m->identifier . \$m->token;
" | tail -n1 | tr -d '[:space:]')"

PANEL_URL="http://${FQDN}"
if [[ "$USE_LETSENCRYPT" == "true" ]]; then PANEL_URL="https://${FQDN}"; fi

api() {
  # api METHOD PATH [json_body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -s -X "$method" "${PANEL_URL}/api/application${path}" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -s -X "$method" "${PANEL_URL}/api/application${path}" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Accept: application/json"
  fi
}

# ---------------------------------------------------------------------------
# 5. Location + Node + Allocations via API
# ---------------------------------------------------------------------------
log "Creating Location"
LOCATION_RESP="$(api POST /locations '{"short":"main","long":"Default Location"}')"
LOCATION_ID="$(echo "$LOCATION_RESP" | jq -r '.attributes.id')"

log "Creating Node"
NODE_RESP="$(api POST /nodes "$(jq -n \
  --arg name "$NODE_NAME" \
  --arg fqdn "$FQDN" \
  --argjson location_id "$LOCATION_ID" \
  '{
    name: $name,
    location_id: $location_id,
    fqdn: $fqdn,
    scheme: "http",
    behind_proxy: false,
    memory: 4096,
    memory_overallocate: 0,
    disk: 51200,
    disk_overallocate: 0,
    daemon_base: "/var/lib/pterodactyl/volumes",
    daemon_sftp: 2022,
    daemon_listen: 8080,
    upload_size: 100
  }')")"
NODE_ID="$(echo "$NODE_RESP" | jq -r '.attributes.id')"

log "Creating Allocations (${NODE_PORT_RANGE_START}-${NODE_PORT_RANGE_END} on ${NODE_IP})"
PORTS_JSON="$(jq -n --arg s "$NODE_PORT_RANGE_START" --arg e "$NODE_PORT_RANGE_END" \
  '[range(($s|tonumber); ($e|tonumber)+1)]')"
api POST "/nodes/${NODE_ID}/allocations" "$(jq -n \
  --arg ip "$NODE_IP" --argjson ports "$PORTS_JSON" \
  '{ip: $ip, ports: ($ports | map(tostring))}')" > /dev/null

# ---------------------------------------------------------------------------
# 6. Nest + Egg import (uses eggs/egg-whatsapp-bot.json, i.e. mambo.json)
# ---------------------------------------------------------------------------
log "Creating Nest"
NEST_RESP="$(api POST /nests "$(jq -n --arg name "$NEST_NAME" --arg desc "$NEST_DESCRIPTION" \
  '{name: $name, description: $desc}')")"
NEST_ID="$(echo "$NEST_RESP" | jq -r '.attributes.id')"

log "Importing Egg from ${EGG_JSON_PATH}"
curl -s -X POST "${PANEL_URL}/api/application/nests/${NEST_ID}/eggs/import" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Accept: application/json" \
  -F "file=@${EGG_JSON_PATH};type=application/json" > /dev/null

# ---------------------------------------------------------------------------
# 7. Wings install + auto-config from the node we just created
# ---------------------------------------------------------------------------
log "Installing Docker"
curl -sSL https://get.docker.com/ | sh
systemctl enable --now docker

log "Installing Wings binary"
mkdir -p /etc/pterodactyl
ARCH="amd64"
[[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
curl -Lo /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}"
chmod u+x /usr/local/bin/wings

log "Fetching Wings config from Panel and enabling the node"
CONFIG_RESP="$(api GET "/nodes/${NODE_ID}/configuration")"
echo "$CONFIG_RESP" > /etc/pterodactyl/config.yml.json
# Panel returns YAML-shaped JSON; convert cleanly with a tiny python helper
python3 - <<PYEOF
import json, yaml
with open('/etc/pterodactyl/config.yml.json') as f:
    data = json.load(f)
with open('/etc/pterodactyl/config.yml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False)
PYEOF
rm -f /etc/pterodactyl/config.yml.json

cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now wings

sleep 5
systemctl is-active --quiet wings && NODE_STATUS="Wings is running - node should show green in a few seconds" \
  || NODE_STATUS="Wings failed to start - check: journalctl -u wings -e"

# ---------------------------------------------------------------------------
# 8. Summary
# ---------------------------------------------------------------------------
cat > "$SUMMARY_FILE" <<EOF
========================================
 ${BRAND_NAME} install finished
========================================
Panel URL      : ${PANEL_URL}
Admin username : ${ADMIN_USERNAME}
Admin email    : ${ADMIN_EMAIL}
Admin password : ${ADMIN_PASSWORD}

Database password (pterodactyl user): ${DB_PASSWORD}

Node           : ${NODE_NAME} (id ${NODE_ID}) @ ${NODE_IP}
Allocations    : ${NODE_PORT_RANGE_START}-${NODE_PORT_RANGE_END}
Nest           : ${NEST_NAME} (id ${NEST_ID}) - egg imported from mambo.json

Wings status   : ${NODE_STATUS}

Application API key used for setup (keep secret, or revoke it in
Admin > API from the Panel once you no longer need it):
${API_KEY}
========================================
EOF

log "DONE - summary saved to ${SUMMARY_FILE}"
rm -f "$EGG_JSON_PATH" 2>/dev/null || true
cat "$SUMMARY_FILE"
