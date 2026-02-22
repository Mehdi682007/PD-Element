#!/usr/bin/env bash
set -uo pipefail

#############################################
# Matrix Stack Manager - v1.5
# Telegram: https://t.me/MYoutub
# YouTube:  https://www.youtube.com/@ParsDigital
#############################################

LOG_FILE="/var/log/matrix_stack_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

CONFIG_FILE="/etc/matrix-stack.conf"
VERSION="1.5"

read -r -d '' ASCII_BANNER <<'BANNER'
╔════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                                                                ║
║   _______  ______              _______  _        _______  _______  _______  _       _________  ║
║  (  ____ )(  __  \            (  ____ \( \      (  ____ \(       )(  ____ \( (    /|\__   __/  ║
║  | (    )|| (  \  )           | (    \/| (      | (    \/| () () || (    \/|  \  ( |   ) (     ║
║  | (____)|| |   ) |   _____   | (__    | |      | (__    | || || || (__    |   \ | |   | |     ║
║  |  _____)| |   | |  (_____)  |  __)   | |      |  __)   | |(_)| ||  __)   | (\ \) |   | |     ║
║  | (      | |   ) |           | (      | |      | (      | |   | || (      | | \   |   | |     ║
║  | )      | (__/  )           | (____/\| (____/\| (____/\| )   ( || (____/\| )  \  |   | |     ║
║  |/       (______/            (_______/(_______/(_______/|/     \|(_______/|/    )_)   )_(     ║
║                                                                                                ║
╚════════════════════════════════════════════════════════════════════════════════════════════════╝


BANNER


#############################################
# Helpers
#############################################

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Please run this script as ROOT (sudo -i)."
    exit 1
  fi
}

print_header() {
  clear || true
  echo "$ASCII_BANNER"
  echo "🚀 Matrix Stack Manager v${VERSION}"
  echo "🔗 Telegram: https://t.me/MYoutub"
  echo "📺 YouTube : https://www.youtube.com/@ParsDigital"
  echo "📝 Log file: ${LOG_FILE}"
  echo
}

pause() {
  read -rp "Press Enter to continue..." _
}

save_config() {
  local HS_DOMAIN="$1"
  local ELEMENT_DOMAIN="$2"
  local BASE_DOMAIN="$3"
  local PUBLIC_IP="$4"
  local LE_EMAIL="$5"

  mkdir -p "$(dirname "${CONFIG_FILE}")"
  cat > "${CONFIG_FILE}" <<EOF
HS_DOMAIN=${HS_DOMAIN}
ELEMENT_DOMAIN=${ELEMENT_DOMAIN}
BASE_DOMAIN=${BASE_DOMAIN}
PUBLIC_IP=${PUBLIC_IP}
LE_EMAIL=${LE_EMAIL}
EOF
}

load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
    return 0
  fi
  return 1
}

ensure_pkg() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    apt update
    apt install -y "$pkg"
  fi
}

ensure_sqlite_installed() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "📦 Installing sqlite3..."
    apt update
    apt install -y sqlite3
  fi
}

restart_services() {
  systemctl restart matrix-synapse || true
  systemctl restart coturn || true
  systemctl reload nginx || true
}

detect_arch() {
  uname -m
}

#############################################
# Install / Reinstall
#############################################

install_stack() {
  print_header
  echo "🧩 === Matrix + Element + TURN Installer (Install Mode) ==="
  echo

  read -rp "🌐 Enter Matrix homeserver domain (e.g. chat.example.com): " HS_DOMAIN
  read -rp "🧭 Enter Element Web domain (e.g. app.example.com): " ELEMENT_DOMAIN
  read -rp "🏠 Enter base domain for .well-known (e.g. example.com): " BASE_DOMAIN
  read -rp "📌 Enter server public IP (e.g. 1.2.3.4): " PUBLIC_IP
  read -rp "✉️  Enter email for Let's Encrypt notifications: " LE_EMAIL

  if [[ -z "${HS_DOMAIN}" || -z "${ELEMENT_DOMAIN}" || -z "${BASE_DOMAIN}" || -z "${PUBLIC_IP}" || -z "${LE_EMAIL}" ]]; then
    echo "❌ All fields are required. Aborting install."
    pause
    return 1
  fi

  echo
  echo "===== INSTALL CONFIGURATION SUMMARY ====="
  echo "Matrix Homeserver:    ${HS_DOMAIN}"
  echo "Element Web:          ${ELEMENT_DOMAIN}"
  echo "Base Domain:          ${BASE_DOMAIN}"
  echo "Public IP:            ${PUBLIC_IP}"
  echo "Let's Encrypt Email:  ${LE_EMAIL}"
  echo "========================================="
  echo
  read -rp "✅ Continue with installation? (y/n): " CONFIRM
  if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "❎ Install aborted."
    pause
    return 1
  fi

  save_config "${HS_DOMAIN}" "${ELEMENT_DOMAIN}" "${BASE_DOMAIN}" "${PUBLIC_IP}" "${LE_EMAIL}"

  export DEBIAN_FRONTEND=noninteractive

  echo
  echo "📦 [1/12] Updating system & installing dependencies..."
  apt update
  apt install -y \
    ca-certificates curl wget gnupg lsb-release \
    nginx certbot python3-certbot-nginx \
    coturn debconf-utils sqlite3 jq

  echo "➕ [2/12] Adding Matrix Synapse repository..."
  if [[ ! -f /usr/share/keyrings/matrix-org-archive-keyring.gpg ]]; then
    wget -qO /usr/share/keyrings/matrix-org-archive-keyring.gpg \
      https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
  fi

  echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/matrix-org.list

  apt update

  echo "⚙️  [3/12] Pre-configuring Synapse (debconf)..."
  echo "matrix-synapse matrix-synapse/server-name string ${HS_DOMAIN}" | debconf-set-selections
  echo "matrix-synapse matrix-synapse/report-stats boolean false"      | debconf-set-selections

  echo "⬇️  [4/12] Installing Synapse..."
  apt install -y matrix-synapse-py3

  echo "🔒 [5/12] Requesting SSL certificates (certbot standalone)..."
  systemctl stop nginx || true

  certbot certonly --standalone \
    --non-interactive --agree-tos \
    -m "${LE_EMAIL}" \
    -d "${HS_DOMAIN}" \
    -d "${ELEMENT_DOMAIN}" \
    -d "${BASE_DOMAIN}"

  systemctl start nginx

  echo "🧾 [6/12] Configuring Synapse registration..."
  REG_SECRET=$(openssl rand -hex 32)
  cat > /etc/matrix-synapse/conf.d/registration.yaml <<EOF
enable_registration: true
enable_registration_without_verification: true
registration_shared_secret: "${REG_SECRET}"
EOF

  echo "📦 [6.1/12] Configuring Synapse media defaults (upload size)..."
  # Default upload cap (can be changed from menu later)
  cat > /etc/matrix-synapse/conf.d/media.yaml <<EOF
max_upload_size: 50M
EOF

  echo "📞 [7/12] Configuring TURN for Synapse..."
  TURN_SECRET=$(openssl rand -hex 32)
  cat > /etc/matrix-synapse/conf.d/turn.yaml <<EOF
turn_uris:
  - "turn:${HS_DOMAIN}:3478?transport=udp"
  - "turns:${HS_DOMAIN}:5349?transport=tcp"

turn_shared_secret: "${TURN_SECRET}"
turn_user_lifetime: 86400000
turn_allow_guests: true
EOF

  echo "🛰️  [8/12] Configuring coturn..."
  if grep -q "^TURNSERVER_ENABLED" /etc/default/coturn 2>/dev/null; then
    sed -i 's/^TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
  else
    echo "TURNSERVER_ENABLED=1" >> /etc/default/coturn
  fi

  cat > /etc/turnserver.conf <<EOF
syslog
no-rfc5780
no-stun-backward-compatibility
response-origin-only-with-rfc5780

listening-port=3478
tls-listening-port=5349

listening-ip=${PUBLIC_IP}
relay-ip=${PUBLIC_IP}
external-ip=${PUBLIC_IP}

realm=${HS_DOMAIN}
server-name=${HS_DOMAIN}
fingerprint

cert=/etc/letsencrypt/live/${HS_DOMAIN}/fullchain.pem
pkey=/etc/letsencrypt/live/${HS_DOMAIN}/privkey.pem

use-auth-secret
static-auth-secret=${TURN_SECRET}

min-port=49160
max-port=49200

total-quota=100
bps-capacity=0

no-loopback-peers
no-multicast-peers

verbose
EOF

  if command -v ufw >/dev/null 2>&1; then
    echo "🔥 Opening firewall ports (UFW)..."
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
    ufw allow 3478/udp || true
    ufw allow 3478/tcp || true
    ufw allow 5349/tcp || true
    ufw allow 49160:49200/udp || true
  fi

  echo "🔄 [9/12] Restarting TURN and Synapse..."
  systemctl restart coturn
  systemctl restart matrix-synapse

  echo "🧩 [10/12] Installing Element Web..."
  mkdir -p /var/www
  cd /var/www

  # Stable default; update from menu later.
  ELEMENT_VERSION="1.12.7"
  wget -O element.tar.gz "https://github.com/element-hq/element-web/releases/download/v${ELEMENT_VERSION}/element-v${ELEMENT_VERSION}.tar.gz"
  rm -rf element || true
  tar -xvf element.tar.gz
  mv "element-v${ELEMENT_VERSION}" element
  rm element.tar.gz

  echo "🛠️  [11/12] Creating Element config.json..."
  cat > /var/www/element/config.json <<EOF
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "https://${HS_DOMAIN}",
      "server_name": "${HS_DOMAIN}"
    }
  },
  "disable_custom_urls": false,
  "disable_guests": true,
  "brand": "Element"
}
EOF

  echo "🌍 [12/12] Creating Nginx virtual hosts..."

  # MATRIX vhost
  cat > /etc/nginx/sites-available/matrix.conf <<EOF
server {
    listen 80;
    server_name ${HS_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${HS_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${HS_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${HS_DOMAIN}/privkey.pem;

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/matrix.conf /etc/nginx/sites-enabled/matrix.conf

  # ELEMENT vhost
  cat > /etc/nginx/sites-available/element.conf <<EOF
server {
    listen 80;
    server_name ${ELEMENT_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${ELEMENT_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${HS_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${HS_DOMAIN}/privkey.pem;

    root /var/www/element;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/element.conf /etc/nginx/sites-enabled/element.conf

  # WELL-KNOWN vhost
  cat > /etc/nginx/sites-available/wellknown.conf <<EOF
server {
    listen 80;
    server_name ${BASE_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${BASE_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${HS_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${HS_DOMAIN}/privkey.pem;

    location = /.well-known/matrix/client {
        add_header Content-Type application/json;
        return 200 '{"m.homeserver":{"base_url":"https://${HS_DOMAIN}"}}';
    }

    location = /.well-known/matrix/server {
        add_header Content-Type application/json;
        return 200 '{"m.server":"${HS_DOMAIN}:443"}';
    }

    location / {
        return 404;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/wellknown.conf /etc/nginx/sites-enabled/wellknown.conf

  rm -f /etc/nginx/sites-enabled/default || true

  nginx -t
  systemctl reload nginx

  echo
  echo "========================================="
  echo "✅ INSTALLATION COMPLETE"
  echo "-----------------------------------------"
  echo "Matrix Server: https://${HS_DOMAIN}"
  echo "Element Web:   https://${ELEMENT_DOMAIN}"
  echo "Well-known:    https://${BASE_DOMAIN}"
  echo
  echo "Registration Secret: ${REG_SECRET}"
  echo "TURN Secret:        ${TURN_SECRET}"
  echo "Log file:           ${LOG_FILE}"
  echo "Arch:               $(detect_arch)"
  echo "========================================="
  echo

  pause
}

#############################################
# User Management
#############################################

create_admin_user() {
  print_header
  echo "👑 === Create ADMIN user ==="
  echo "Command:"
  echo "  register_new_matrix_user -c /etc/matrix-synapse/conf.d/registration.yaml -a http://localhost:8008"
  echo
  register_new_matrix_user \
    -c /etc/matrix-synapse/conf.d/registration.yaml \
    -a \
    http://localhost:8008
  pause
}

create_normal_user() {
  print_header
  echo "👤 === Create NORMAL user ==="
  echo "Command:"
  echo "  register_new_matrix_user -c /etc/matrix-synapse/conf.d/registration.yaml --no-admin http://localhost:8008"
  echo
  register_new_matrix_user \
    -c /etc/matrix-synapse/conf.d/registration.yaml \
    --no-admin \
    http://localhost:8008
  pause
}

create_user_random_password() {
  print_header
  echo "🎲 === Create user with RANDOM password ==="
  echo "This will generate a strong password and print it at the end."
  echo
  if ! load_config; then
    echo "⚠️  Config not found at ${CONFIG_FILE}. Run Install first."
    pause
    return 1
  fi

  read -rp "Enter username (localpart, e.g. vahid): " LOCALPART
  if [[ -z "${LOCALPART}" ]]; then
    echo "❌ Username is required."
    pause
    return 1
  fi

  echo "Choose role:"
  echo "1) Normal user"
  echo "2) Admin user"
  read -rp "Choose [1-2]: " ROLE

  local PASS
  PASS="$(openssl rand -base64 18 | tr -d '\n' | tr -d '=' | tr '/+' 'Aa')"

  # Use temp password file to avoid exposing password in process list
  local TMPPASS
  TMPPASS="$(mktemp)"
  printf "%s" "${PASS}" > "${TMPPASS}"

  if [[ "${ROLE}" == "2" ]]; then
    register_new_matrix_user \
      -u "${LOCALPART}" \
      --password-file "${TMPPASS}" \
      -a \
      -c /etc/matrix-synapse/conf.d/registration.yaml \
      http://localhost:8008
    echo
    echo "✅ Created ADMIN user:"
  else
    register_new_matrix_user \
      -u "${LOCALPART}" \
      --password-file "${TMPPASS}" \
      --no-admin \
      -c /etc/matrix-synapse/conf.d/registration.yaml \
      http://localhost:8008
    echo
    echo "✅ Created NORMAL user:"
  fi

  rm -f "${TMPPASS}" || true

  echo "MXID:     @${LOCALPART}:${HS_DOMAIN}"
  echo "Password: ${PASS}"
  echo
  echo "Tip: Save this password now."
  pause
}

reactivate_user() {
  print_header
  echo "♻️  === Reactivate existing user (set new password) ==="
  echo "Tip: If the user was deactivated, this will re-enable it."
  echo "Command uses --exists-ok."
  echo
  echo "Choose reactivation type:"
  echo "1) Reactivate as NORMAL user"
  echo "2) Reactivate as ADMIN user"
  echo "3) Back"
  read -rp "Choose [1-3]: " ROPT

  case "${ROPT}" in
    1)
      register_new_matrix_user \
        --exists-ok \
        -c /etc/matrix-synapse/conf.d/registration.yaml \
        --no-admin \
        http://localhost:8008
      ;;
    2)
      register_new_matrix_user \
        --exists-ok \
        -c /etc/matrix-synapse/conf.d/registration.yaml \
        -a \
        http://localhost:8008
      ;;
    3) ;;
    *) echo "Invalid option." ;;
  esac

  pause
}

#############################################
# User Listing / Deactivation
#############################################

list_users() {
  print_header
  echo "📋 === List users (SQLite) ==="
  ensure_sqlite_installed

  if [[ -f /var/lib/matrix-synapse/homeserver.db ]]; then
    echo "Format: MXID | admin(1/0) | deactivated(1/0)"
    echo "-------------------------------------------"
    sqlite3 /var/lib/matrix-synapse/homeserver.db \
      "SELECT name || ' | ' || admin || ' | ' || deactivated FROM users ORDER BY name;"
  else
    echo "❌ Database not found at /var/lib/matrix-synapse/homeserver.db"
    echo "If you use Postgres, you need psql-based listing."
    pause
    return 1
  fi

  pause
}

deactivate_user() {
  print_header
  echo "🚫 === Deactivate user (safe) ==="
  echo "This will:"
  echo " - Set deactivated=1"
  echo " - Clear password_hash"
  echo "It does NOT hard-delete messages/rooms (recommended)."
  echo
  read -rp "Enter full MXID (e.g. @user:example.com): " MXID

  if [[ -z "${MXID}" ]]; then
    echo "❌ MXID is required."
    pause
    return 1
  fi

  ensure_sqlite_installed
  if [[ ! -f /var/lib/matrix-synapse/homeserver.db ]]; then
    echo "❌ Database not found at /var/lib/matrix-synapse/homeserver.db"
    pause
    return 1
  fi

  read -rp "Are you sure you want to deactivate ${MXID}? (y/n): " CONFIRM
  if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Cancelled."
    pause
    return 0
  fi

  sqlite3 /var/lib/matrix-synapse/homeserver.db \
    "UPDATE users SET deactivated=1, password_hash=NULL WHERE name='${MXID}';"

  echo "✅ User ${MXID} has been deactivated."
  echo "Tip: Use Reactivate to enable it again and set a new password."
  pause
}

#############################################
# Upload limits management
#############################################

set_upload_limits() {
  print_header
  echo "📦 === Upload Limits Manager ==="
  echo "This option will set BOTH:"
  echo " - Nginx client_max_body_size (Matrix vhost)"
  echo " - Synapse max_upload_size"
  echo
  echo "Enter size in MB (e.g. 500, 2000, 5000)."
  read -rp "Upload limit (MB): " LIMIT_MB

  if [[ -z "${LIMIT_MB}" || ! "${LIMIT_MB}" =~ ^[0-9]+$ ]]; then
    echo "❌ Please enter a numeric value (MB)."
    pause
    return 1
  fi

  local LIMIT_NGINX="${LIMIT_MB}M"
  local LIMIT_SYNAPSE="${LIMIT_MB}M"

  if ! load_config; then
    echo "⚠️  Config not found at ${CONFIG_FILE}."
    echo "Run Install first so domains are known."
    pause
    return 1
  fi

  echo "✅ Setting Nginx upload limit to: ${LIMIT_NGINX}"
  if [[ -f /etc/nginx/sites-available/matrix.conf ]]; then
    if grep -q "client_max_body_size" /etc/nginx/sites-available/matrix.conf; then
      sed -i "s/client_max_body_size.*/client_max_body_size ${LIMIT_NGINX};/g" /etc/nginx/sites-available/matrix.conf
    else
      sed -i "/ssl_certificate_key/a\\
\\
    client_max_body_size ${LIMIT_NGINX};\\
" /etc/nginx/sites-available/matrix.conf
    fi
  else
    echo "❌ /etc/nginx/sites-available/matrix.conf not found."
    pause
    return 1
  fi

  echo "✅ Setting Synapse upload limit to: ${LIMIT_SYNAPSE}"
  mkdir -p /etc/matrix-synapse/conf.d
  cat > /etc/matrix-synapse/conf.d/media.yaml <<EOF
max_upload_size: ${LIMIT_SYNAPSE}
EOF

  echo "🔄 Reloading services..."
  nginx -t
  systemctl reload nginx
  systemctl restart matrix-synapse

  echo "🎉 Done! Upload limits updated."
  echo "Nginx:   client_max_body_size ${LIMIT_NGINX}"
  echo "Synapse: max_upload_size ${LIMIT_SYNAPSE}"
  echo
  echo "Tip: Hard refresh Element Web (Ctrl+Shift+R) if you still see old limits."
  pause
}

#############################################
# Toggle registration ON/OFF
#############################################

toggle_registration() {
  print_header
  echo "🧾 === Toggle Registration (ON/OFF) ==="
  echo "If OFF: users cannot sign up in Element (web/mobile)."
  echo "You can still create users via this script."
  echo

  if [[ ! -f /etc/matrix-synapse/conf.d/registration.yaml ]]; then
    echo "❌ /etc/matrix-synapse/conf.d/registration.yaml not found."
    pause
    return 1
  fi

  local current="unknown"
  if grep -q "^enable_registration:" /etc/matrix-synapse/conf.d/registration.yaml; then
    current="$(grep "^enable_registration:" /etc/matrix-synapse/conf.d/registration.yaml | awk '{print $2}' | tr -d '\r')"
  fi

  echo "Current enable_registration: ${current}"
  echo
  echo "1) Turn ON registration"
  echo "2) Turn OFF registration"
  echo "3) Back"
  read -rp "Choose [1-3]: " opt

  case "${opt}" in
    1)
      if grep -q "^enable_registration:" /etc/matrix-synapse/conf.d/registration.yaml; then
        sed -i 's/^enable_registration:.*/enable_registration: true/' /etc/matrix-synapse/conf.d/registration.yaml
      else
        printf "\nenable_registration: true\n" >> /etc/matrix-synapse/conf.d/registration.yaml
      fi
      ;;
    2)
      if grep -q "^enable_registration:" /etc/matrix-synapse/conf.d/registration.yaml; then
        sed -i 's/^enable_registration:.*/enable_registration: false/' /etc/matrix-synapse/conf.d/registration.yaml
      else
        printf "\nenable_registration: false\n" >> /etc/matrix-synapse/conf.d/registration.yaml
      fi
      ;;
    3) ;;
    *) echo "Invalid option." ;;
  esac

  systemctl restart matrix-synapse || true
  echo "✅ Updated. Synapse restarted."
  pause
}

#############################################
# Call Diagnostics (TURN/WebRTC troubleshooting)
#############################################

call_diagnostics() {
  print_header
  echo "📞 === Call Diagnostics (TURN/WebRTC) ==="
  echo

  if ! load_config; then
    echo "⚠️  Config not found at ${CONFIG_FILE}. Some checks will be limited."
  fi

  ensure_pkg coturn
  ensure_pkg curl
  ensure_pkg iproute2

  echo "🧠 Services:"
  systemctl is-active --quiet coturn && echo "✅ coturn: active" || echo "❌ coturn: NOT active"
  systemctl is-active --quiet matrix-synapse && echo "✅ matrix-synapse: active" || echo "❌ matrix-synapse: NOT active"
  echo

  echo "🧷 TURN ports listening (server-side):"
  ss -lunpt | grep -E ':(3478|5349)\b' || echo "❌ Not listening on 3478/5349 (check coturn config/service)."
  echo

  echo "🧾 TURN configuration summary:"
  if [[ -f /etc/turnserver.conf ]]; then
    echo "----- /etc/turnserver.conf (important lines) -----"
    grep -E '^(listening-port|tls-listening-port|listening-ip|relay-ip|external-ip|realm|server-name|min-port|max-port|use-auth-secret|static-auth-secret|cert=|pkey=)' /etc/turnserver.conf || true
    echo "--------------------------------------------------"
  else
    echo "❌ /etc/turnserver.conf not found."
  fi
  echo

  echo "🔥 Firewall quick check (UFW if available):"
  if command -v ufw >/dev/null 2>&1; then
    ufw status verbose || true
    echo
    echo "Expected UFW rules (at minimum):"
    echo " - 3478/udp, 3478/tcp, 5349/tcp"
    echo " - 49160:49200/udp (TURN relay ports)"
  else
    echo "⚠️  UFW not installed. If you use cloud firewall, check it there."
    echo "Required ports:"
    echo " - UDP 3478"
    echo " - TCP 3478"
    echo " - TCP 5349"
    echo " - UDP 49160-49200 (relay ports)"
  fi
  echo

  echo "🌐 Public reachability (informational):"
  if [[ -n "${PUBLIC_IP:-}" ]]; then
    echo "Public IP set in config: ${PUBLIC_IP}"
  else
    echo "Public IP not loaded from config."
  fi
  echo

  echo "🧪 Synapse TURN config file:"
  if [[ -f /etc/matrix-synapse/conf.d/turn.yaml ]]; then
    cat /etc/matrix-synapse/conf.d/turn.yaml
  else
    echo "❌ /etc/matrix-synapse/conf.d/turn.yaml not found."
  fi
  echo

  echo "🧪 Matrix client endpoint (if domain known):"
  if [[ -n "${HS_DOMAIN:-}" ]]; then
    if curl -fsS "https://${HS_DOMAIN}/_matrix/client/versions" >/dev/null 2>&1; then
      echo "✅ https://${HS_DOMAIN}/_matrix/client/versions OK"
    else
      echo "❌ Cannot reach https://${HS_DOMAIN}/_matrix/client/versions"
      echo "   This can also break call setup in clients."
    fi
  else
    echo "⚠️  HS_DOMAIN not known (run Install first)."
  fi
  echo

  echo "📜 Recent coturn logs (last 80 lines):"
  journalctl -u coturn -n 80 --no-pager || true
  echo

  echo "📌 If calls stay on 'Connecting', the most common cause is:"
  echo " - UDP relay ports are blocked (49160-49200/udp) in server firewall OR cloud firewall."
  echo " - Or external-ip is wrong (NAT scenario)."
  echo
  echo "Tip: Try a test call, then immediately run this diagnostics and check for:"
  echo " - 'allocation timeout' in coturn logs."
  echo

  pause
}

#############################################
# Health Check
#############################################

health_check() {
  print_header
  echo "🔎 === Health Check ==="
  echo

  if ! load_config; then
    echo "⚠️  Config not found at ${CONFIG_FILE}. Some URL checks will be skipped."
  fi

  echo "🧠 Services:"
  systemctl is-active --quiet matrix-synapse && echo "✅ matrix-synapse: active" || echo "❌ matrix-synapse: NOT active"
  systemctl is-active --quiet nginx && echo "✅ nginx: active" || echo "❌ nginx: NOT active"
  systemctl is-active --quiet coturn && echo "✅ coturn: active" || echo "❌ coturn: NOT active"
  echo

  echo "🌐 Nginx config test:"
  if nginx -t >/dev/null 2>&1; then
    echo "✅ nginx -t OK"
  else
    echo "❌ nginx -t FAILED"
    nginx -t || true
  fi
  echo

  if [[ -n "${HS_DOMAIN:-}" ]]; then
    echo "🧪 Matrix client API:"
    if curl -fsS "https://${HS_DOMAIN}/_matrix/client/versions" >/dev/null 2>&1; then
      echo "✅ https://${HS_DOMAIN}/_matrix/client/versions OK"
    else
      echo "❌ Cannot reach https://${HS_DOMAIN}/_matrix/client/versions"
    fi
    echo
  fi

  if [[ -n "${BASE_DOMAIN:-}" ]]; then
    echo "🧪 .well-known:"
    if curl -fsS "https://${BASE_DOMAIN}/.well-known/matrix/client" >/dev/null 2>&1; then
      echo "✅ https://${BASE_DOMAIN}/.well-known/matrix/client OK"
    else
      echo "❌ Cannot reach https://${BASE_DOMAIN}/.well-known/matrix/client"
    fi
    echo
  fi

  echo "🧷 Listening ports (quick view):"
  ss -lntup | grep -E '(:80|:443|:8008|:3478|:5349)\b' || echo "⚠️  No expected ports found (or ss output restricted)."
  echo

  echo "🔐 Certbot certificates (if present):"
  if command -v certbot >/dev/null 2>&1; then
    certbot certificates 2>/dev/null | sed -n '1,120p' || true
  else
    echo "⚠️  certbot not installed."
  fi

  pause
}

#############################################
# Fix Wizard (common issues)
#############################################

fix_wizard() {
  print_header
  echo "🧰 === Fix Wizard (common issues) ==="
  echo "This tries to fix:"
  echo " - Missing Nginx symlinks"
  echo " - Default site enabled"
  echo " - coturn disabled"
  echo " - Reload/restart services"
  echo

  if grep -q "^TURNSERVER_ENABLED" /etc/default/coturn 2>/dev/null; then
    sed -i 's/^TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
  else
    echo "TURNSERVER_ENABLED=1" >> /etc/default/coturn
  fi

  [[ -f /etc/nginx/sites-available/matrix.conf ]] && ln -sf /etc/nginx/sites-available/matrix.conf /etc/nginx/sites-enabled/matrix.conf || true
  [[ -f /etc/nginx/sites-available/element.conf ]] && ln -sf /etc/nginx/sites-available/element.conf /etc/nginx/sites-enabled/element.conf || true
  [[ -f /etc/nginx/sites-available/wellknown.conf ]] && ln -sf /etc/nginx/sites-available/wellknown.conf /etc/nginx/sites-enabled/wellknown.conf || true

  rm -f /etc/nginx/sites-enabled/default || true

  echo "✅ Running nginx -t ..."
  nginx -t || true

  echo "🔄 Restarting services..."
  systemctl restart coturn || true
  systemctl restart matrix-synapse || true
  systemctl reload nginx || true

  echo "✅ Fix Wizard done."
  pause
}

#############################################
# Backup / Restore
#############################################

backup_server() {
  print_header
  echo "💾 === Backup Server ==="
  echo

  local backup_dir="/root/matrix-backups"
  mkdir -p "${backup_dir}"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local out="${backup_dir}/matrix-backup-${ts}.tar.gz"

  echo "Include /etc/letsencrypt in backup?"
  echo "1) Yes"
  echo "2) No"
  read -rp "Choose [1-2]: " inc

  local paths=(
    "/etc/matrix-synapse"
    "/etc/nginx/sites-available"
    "/etc/nginx/sites-enabled"
    "/etc/turnserver.conf"
    "/var/lib/matrix-synapse"
    "${CONFIG_FILE}"
  )

  if [[ "${inc}" == "1" ]]; then
    paths+=("/etc/letsencrypt")
  fi

  echo "Creating backup: ${out}"
  tar -czf "${out}" "${paths[@]}" 2>/dev/null || tar -czf "${out}" "${paths[@]}"

  echo "✅ Backup created:"
  echo "${out}"
  pause
}

restore_backup() {
  print_header
  echo "♻️  === Restore Backup ==="
  echo

  local backup_dir="/root/matrix-backups"
  if [[ ! -d "${backup_dir}" ]]; then
    echo "❌ Backup directory not found: ${backup_dir}"
    pause
    return 1
  fi

  echo "Available backups:"
  ls -1 "${backup_dir}"/*.tar.gz 2>/dev/null || { echo "❌ No backups found."; pause; return 1; }
  echo
  read -rp "Enter full path to backup file: " file

  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "❌ Backup file not found."
    pause
    return 1
  fi

  echo "⚠️  This will overwrite current config/files."
  read -rp "Are you sure you want to restore? (y/n): " CONFIRM
  if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Cancelled."
    pause
    return 0
  fi

  echo "Stopping services..."
  systemctl stop matrix-synapse || true
  systemctl stop coturn || true
  systemctl stop nginx || true

  echo "Extracting backup..."
  tar -xzf "${file}" -C /

  echo "Testing nginx config..."
  nginx -t || true

  echo "Starting services..."
  systemctl start nginx || true
  systemctl restart coturn || true
  systemctl restart matrix-synapse || true

  echo "✅ Restore complete."
  pause
}

#############################################
# Update Element Web
#############################################

update_element_web() {
  print_header
  echo "⬆️  === Update Element Web ==="
  echo

  if ! load_config; then
    echo "⚠️  Config not found at ${CONFIG_FILE}. You can still update Element files."
  fi

  ensure_pkg jq
  ensure_pkg curl
  ensure_pkg wget

  echo "Choose Element version:"
  echo "1) Enter version manually (recommended)"
  echo "2) Use latest (GitHub API)"
  echo "3) Back"
  read -rp "Choose [1-3]: " opt

  local ver=""
  case "${opt}" in
    1)
      read -rp "Enter version (example: 1.12.7): " ver
      ;;
    2)
      echo "Fetching latest version..."
      local tag
      tag="$(curl -fsS https://api.github.com/repos/element-hq/element-web/releases/latest | jq -r '.tag_name')"
      if [[ -z "${tag}" || "${tag}" == "null" ]]; then
        echo "❌ Could not fetch latest version."
        pause
        return 1
      fi
      ver="${tag#v}"
      echo "Latest: ${ver}"
      ;;
    3) return 0 ;;
    *) echo "Invalid option."; pause; return 1 ;;
  esac

  if [[ -z "${ver}" ]]; then
    echo "❌ Version is required."
    pause
    return 1
  fi

  local url="https://github.com/element-hq/element-web/releases/download/v${ver}/element-v${ver}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"
  echo "Downloading: ${url}"
  if ! wget -O "${tmp}/element.tar.gz" "${url}"; then
    echo "❌ Download failed. Check version exists or try manual version."
    rm -rf "${tmp}" || true
    pause
    return 1
  fi

  echo "Extracting..."
  tar -xvf "${tmp}/element.tar.gz" -C "${tmp}" >/dev/null

  local extracted="${tmp}/element-v${ver}"
  if [[ ! -d "${extracted}" ]]; then
    echo "❌ Unexpected archive content. Folder not found: ${extracted}"
    rm -rf "${tmp}" || true
    pause
    return 1
  fi

  echo "Preserving existing config.json (if any)..."
  if [[ -f /var/www/element/config.json ]]; then
    cp /var/www/element/config.json "${tmp}/config.json.backup"
  fi

  echo "Replacing /var/www/element..."
  rm -rf /var/www/element
  mv "${extracted}" /var/www/element

  if [[ -f "${tmp}/config.json.backup" ]]; then
    mv "${tmp}/config.json.backup" /var/www/element/config.json
  fi

  rm -rf "${tmp}" || true

  systemctl reload nginx || true
  echo "✅ Element updated to v${ver}."
  pause
}

#############################################
# Full Uninstall / Purge
#############################################

full_uninstall() {
  print_header
  echo "🧨 === FULL UNINSTALL / PURGE ==="
  echo "This will REMOVE:"
  echo " - Synapse"
  echo " - Nginx"
  echo " - coturn"
  echo " - Element files"
  echo " - Matrix configs and database"
  echo
  echo "⚠️  This is destructive."
  read -rp "Type DELETE to continue: " confirm
  if [[ "${confirm}" != "DELETE" ]]; then
    echo "Cancelled."
    pause
    return 0
  fi

  echo "Stopping services..."
  systemctl stop matrix-synapse || true
  systemctl stop coturn || true
  systemctl stop nginx || true

  echo "Removing packages..."
  apt purge -y matrix-synapse-py3 coturn nginx certbot python3-certbot-nginx || true
  apt autoremove -y || true

  echo "Removing files..."
  rm -rf /etc/matrix-synapse /var/lib/matrix-synapse || true
  rm -f /etc/turnserver.conf /etc/default/coturn || true
  rm -rf /var/www/element || true
  rm -f /etc/nginx/sites-available/matrix.conf /etc/nginx/sites-available/element.conf /etc/nginx/sites-available/wellknown.conf || true
  rm -f /etc/nginx/sites-enabled/matrix.conf /etc/nginx/sites-enabled/element.conf /etc/nginx/sites-enabled/wellknown.conf || true
  rm -f "${CONFIG_FILE}" || true

  echo "Optional: remove Let's Encrypt certificates?"
  echo "1) Yes (delete /etc/letsencrypt)"
  echo "2) No"
  read -rp "Choose [1-2]: " opt
  if [[ "${opt}" == "1" ]]; then
    rm -rf /etc/letsencrypt || true
  fi

  echo "✅ Uninstall complete."
  pause
}

#############################################
# Main menu
#############################################

main_menu() {
  while true; do
    print_header
    echo "====== Matrix Stack Manager ======"
    echo "1)  🧩 Install / Reinstall Matrix + Element + TURN"
    echo "2)  👑 Create admin user (interactive)"
    echo "3)  👤 Create normal user (interactive)"
    echo "4)  🎲 Create user with RANDOM password (auto)"
    echo "5)  ♻️ Reactivate user (exists-ok)"
    echo "6)  📋 List users"
    echo "7)  🚫 Deactivate user (safe)"
    echo "8)  📦 Set upload limits (Nginx + Synapse)"
    echo "9)  🧾 Toggle registration ON/OFF"
    echo "10) 🔎 Health Check"
    echo "11) 🧰 Fix Wizard (auto-fix common issues)"
    echo "12) 💾 Backup server"
    echo "13) ♻️ Restore backup"
    echo "14) 📞 Call Diagnostics (TURN/WebRTC)"
    echo "15) ⬆️  Update Element Web"
    echo "16) 🧨 Full uninstall / purge"
    echo "17) 🚪 Exit"
    echo "=================================="
    read -rp "Choose an option [1-17]: " CHOICE

    case "${CHOICE}" in
      1)  install_stack ;;
      2)  create_admin_user ;;
      3)  create_normal_user ;;
      4)  create_user_random_password ;;
      5)  reactivate_user ;;
      6)  list_users ;;
      7)  deactivate_user ;;
      8)  set_upload_limits ;;
      9)  toggle_registration ;;
      10) health_check ;;
      11) fix_wizard ;;
      12) backup_server ;;
      13) restore_backup ;;
      14) call_diagnostics ;;
      15) update_element_web ;;
      16) full_uninstall ;;
      17) echo "Bye."; exit 0 ;;
      *)  echo "Invalid option."; sleep 1 ;;
    esac
  done
}

require_root
main_menu
