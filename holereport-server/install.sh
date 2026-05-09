#!/bin/bash
# HoleReport Server Installer
# Tested on Ubuntu 20.04 / 22.04 / 24.04 and Debian 11/12
# Run as root: sudo bash install.sh

set -e

SITE_DIR="/var/www/holereport"
APACHE_CONF="/etc/apache2/sites-available/holereport.conf"
LOG_FILE="/tmp/holereport_install.log"
PG_DB="holereport"
PG_USER="holereport"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run with sudo: sudo bash install.sh"

echo ""
echo "═══════════════════════════════════════════"
echo "  HoleReport Server Installer"
echo "═══════════════════════════════════════════"
echo ""

# ── 1. Packages ────────────────────────────────────────────────────────────────
info "Updating package list…"
apt-get update -qq >> "$LOG_FILE" 2>&1

info "Installing Apache + PHP + PostgreSQL…"
apt-get install -y -qq \
    apache2 \
    php libapache2-mod-php php-gd php-json php-pgsql \
    postgresql postgresql-client \
    >> "$LOG_FILE" 2>&1

# ── 2. Enable Apache modules ──────────────────────────────────────────────────
info "Enabling Apache modules…"
a2enmod rewrite headers expires php* >> "$LOG_FILE" 2>&1

# ── 3. Generate secrets ───────────────────────────────────────────────────────
API_KEY='api-key'
DB_PASS='db-pass'
info "Generated API key"
info "Generated database password"

echo "$API_KEY" > /root/holereport_api_key.txt
chmod 600 /root/holereport_api_key.txt
warn "API key saved to /root/holereport_api_key.txt"

# ── 4. PostgreSQL setup ────────────────────────────────────────────────────────
info "Starting PostgreSQL…"
systemctl enable postgresql >> "$LOG_FILE" 2>&1
systemctl start  postgresql >> "$LOG_FILE" 2>&1

info "Creating database user and database…"
sudo -u postgres psql -v ON_ERROR_STOP=1 >> "$LOG_FILE" 2>&1 << PGEOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${PG_USER}') THEN
    CREATE USER ${PG_USER} WITH PASSWORD '${DB_PASS}';
  ELSE
    ALTER USER ${PG_USER} WITH PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
PGEOF

sudo -u postgres psql -v ON_ERROR_STOP=1 >> "$LOG_FILE" 2>&1 << PGEOF
SELECT 'CREATE DATABASE ${PG_DB} OWNER ${PG_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${PG_DB}') \gexec
GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USER};
PGEOF

info "Creating database schema…"
sudo -u postgres psql -d "$PG_DB" -v ON_ERROR_STOP=1 >> "$LOG_FILE" 2>&1 << PGEOF

CREATE TABLE IF NOT EXISTS users (
    id          SERIAL PRIMARY KEY,
    device_id   VARCHAR(36) UNIQUE NOT NULL,
    first_seen  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    photo_count INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS photos (
    id            SERIAL PRIMARY KEY,
    uuid          VARCHAR(36) UNIQUE NOT NULL,
    user_id       INT REFERENCES users(id) ON DELETE SET NULL,
    filename      VARCHAR(255) NOT NULL,
    original_name VARCHAR(255),
    size_bytes    BIGINT,
    mime_type     VARCHAR(64),
    latitude      DOUBLE PRECISION,
    longitude     DOUBLE PRECISION,
    altitude      DOUBLE PRECISION,
    address       TEXT,
    photo_date    TIMESTAMPTZ,
    measurements  JSONB,
    device_note   TEXT,
    uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_photos_user_id    ON photos(user_id);
CREATE INDEX IF NOT EXISTS idx_photos_uploaded_at ON photos(uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_device_id   ON users(device_id);

CREATE TABLE IF NOT EXISTS districts (
    id          SERIAL PRIMARY KEY,
    slug        VARCHAR(64) UNIQUE NOT NULL,
    name        VARCHAR(128) NOT NULL,
    name_en     VARCHAR(128),
    color       VARCHAR(16) NOT NULL DEFAULT '#3b82f6',
    coordinates JSONB NOT NULL,
    city        VARCHAR(128) NOT NULL DEFAULT 'Haskovo',
    sort_order  INT NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_districts_city ON districts(city);

-- Seed default Haskovo districts (skip if already present)
INSERT INTO districts (slug, name, name_en, color, coordinates, city, sort_order) VALUES
  ('center', 'Център',  'Center',  '#3b82f6',
   '[[41.9420,25.5430],[41.9420,25.5650],[41.9300,25.5650],[41.9300,25.5430]]', 'Haskovo', 1),
  ('orfey',  'Орфей',   'Orfey',   '#10b981',
   '[[41.9300,25.5430],[41.9300,25.5600],[41.9200,25.5600],[41.9200,25.5430]]', 'Haskovo', 2),
  ('kuba',   'Куба',    'Kuba',    '#f59e0b',
   '[[41.9420,25.5650],[41.9420,25.5800],[41.9300,25.5800],[41.9300,25.5650]]', 'Haskovo', 3),
  ('mladost','Младост', 'Mladost', '#8b5cf6',
   '[[41.9300,25.5600],[41.9300,25.5800],[41.9150,25.5800],[41.9150,25.5600]]', 'Haskovo', 4),
  ('aida',   'Аида',    'Aida',    '#ef4444',
   '[[41.9500,25.5430],[41.9500,25.5650],[41.9420,25.5650],[41.9420,25.5430]]', 'Haskovo', 5)
ON CONFLICT (slug) DO NOTHING;

GRANT ALL ON ALL TABLES    IN SCHEMA public TO ${PG_USER};
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${PG_USER};
PGEOF

# ── 5. Copy files ──────────────────────────────────────────────────────────────
info "Installing files to $SITE_DIR…"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$SITE_DIR"/{public,api,uploads/thumbs}

cp -r "$SCRIPT_DIR/public/." "$SITE_DIR/public/"
cp -r "$SCRIPT_DIR/api/."    "$SITE_DIR/api/"

# ── 6. Permissions ─────────────────────────────────────────────────────────────
info "Setting permissions…"
chown -R www-data:www-data "$SITE_DIR"
chmod -R 755 "$SITE_DIR"
chmod -R 775 "$SITE_DIR/uploads"
find "$SITE_DIR/public" -type f -exec chmod 644 {} \;
find "$SITE_DIR/api"    -type f -exec chmod 644 {} \;

# ── 8. Apache config ───────────────────────────────────────────────────────────
info "Writing Apache config…"
cat > "$APACHE_CONF" << APACHECONF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $SITE_DIR/public

    Alias /uploads $SITE_DIR/uploads
    Alias /api     $SITE_DIR/api

    <Directory $SITE_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <Directory $SITE_DIR/uploads>
        Options -Indexes -ExecCGI
        AllowOverride None
        Require all granted
        php_flag engine off
    </Directory>

    <Directory $SITE_DIR/api>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>

    php_value upload_max_filesize 30M
    php_value post_max_size 35M
    php_value max_execution_time 120
    php_value memory_limit 128M

    ErrorLog \${APACHE_LOG_DIR}/holereport_error.log
    CustomLog \${APACHE_LOG_DIR}/holereport_access.log combined
</VirtualHost>
APACHECONF

info "Enabling site…"
a2ensite holereport >> "$LOG_FILE" 2>&1
a2dissite 000-default >> "$LOG_FILE" 2>&1 || true

# ── 9. PHP upload settings ─────────────────────────────────────────────────────
info "Configuring PHP upload limits…"
PHP_INI=$(php -r "echo php_ini_loaded_file();")
if [[ -f "$PHP_INI" ]]; then
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 30M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 35M/' "$PHP_INI"
fi

# ── 10. Restart Apache ─────────────────────────────────────────────────────────
info "Restarting Apache…"
systemctl restart apache2

# ── 11. Firewall ───────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow 80/tcp  >> "$LOG_FILE" 2>&1 || true
    ufw allow 443/tcp >> "$LOG_FILE" 2>&1 || true
    info "Firewall: opened ports 80 and 443"
fi

# ── Done ────────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "═══════════════════════════════════════════"
echo -e "  ${GREEN}Installation complete!${NC}"
echo "═══════════════════════════════════════════"
echo ""
echo -e "  Web gallery:  ${YELLOW}http://$SERVER_IP/${NC}"
echo -e "  Upload API:   ${YELLOW}http://$SERVER_IP/api/upload.php${NC}"
echo -e "  Users API:    ${YELLOW}http://$SERVER_IP/api/users.php${NC}"
echo -e "  API Key:      ${YELLOW}$API_KEY${NC}"
echo ""
echo "  Update your iPhone app with:"
echo "    SERVER_URL = \"http://$SERVER_IP\""
echo "    API_KEY    = \"$API_KEY\""
echo ""
echo "  PostgreSQL:"
echo "    Database:  $PG_DB"
echo "    User:      $PG_USER"
echo "    Password:  $DB_PASS"
echo ""
echo "  (API key saved to /root/holereport_api_key.txt)"
echo "═══════════════════════════════════════════"
echo ""
