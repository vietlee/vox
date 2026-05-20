#!/bin/bash
# Run this ONCE on a fresh Ubuntu 22.04 droplet as root:
#   curl -sO https://raw.githubusercontent.com/YOUR_REPO/main/config/deploy/server_setup.sh
#   bash server_setup.sh

set -e

RUBY_VERSION="3.2.2"
APP_USER="deploy"
APP_NAME="vox"
DB_NAME="vox_production"
DB_USER="vox_user"
DOMAIN="vox.czin.net"

echo "==> [1/9] System update & base packages"
apt-get update -qq
apt-get install -y -qq \
  build-essential git curl wget gnupg2 \
  libssl-dev libreadline-dev zlib1g-dev \
  libpq-dev libvips-dev \
  postgresql postgresql-contrib \
  redis-server \
  nginx \
  certbot python3-certbot-nginx \
  chromium-browser \
  nodejs npm \
  libgconf-2-4 libatk1.0-0 libatk-bridge2.0-0 \
  libgtk-3-0 libgbm1 libasound2 \
  imagemagick libmagickwand-dev \
  logrotate

echo "==> [2/9] Create deploy user"
if ! id "$APP_USER" &>/dev/null; then
  adduser --disabled-password --gecos "" $APP_USER
  usermod -aG sudo $APP_USER
  # Copy root's authorized_keys so your SSH key works for deploy user too
  mkdir -p /home/$APP_USER/.ssh
  cp /root/.ssh/authorized_keys /home/$APP_USER/.ssh/authorized_keys
  chown -R $APP_USER:$APP_USER /home/$APP_USER/.ssh
  chmod 700 /home/$APP_USER/.ssh
  chmod 600 /home/$APP_USER/.ssh/authorized_keys
fi

echo "==> [3/9] Install rbenv + Ruby $RUBY_VERSION (as $APP_USER)"
sudo -u $APP_USER bash <<RBENV
  export HOME=/home/$APP_USER
  if [ ! -d "\$HOME/.rbenv" ]; then
    git clone https://github.com/rbenv/rbenv.git \$HOME/.rbenv
    echo 'export PATH="\$HOME/.rbenv/bin:\$PATH"' >> \$HOME/.bashrc
    echo 'eval "\$(\$HOME/.rbenv/bin/rbenv init -)"' >> \$HOME/.bashrc
  fi
  if [ ! -d "\$HOME/.rbenv/plugins/ruby-build" ]; then
    git clone https://github.com/rbenv/ruby-build.git \$HOME/.rbenv/plugins/ruby-build
  fi
  export PATH="\$HOME/.rbenv/bin:\$PATH"
  eval "\$(\$HOME/.rbenv/bin/rbenv init -)"
  rbenv install -s $RUBY_VERSION
  rbenv global $RUBY_VERSION
  gem install bundler --no-document
RBENV

echo "==> [4/9] PostgreSQL — create DB and user"
DB_PASSWORD=$(openssl rand -hex 16)
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || echo "User may already exist"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || echo "DB may already exist"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
echo ""
echo "  *** DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME ***"
echo "  (save this to your .env on the server)"
echo ""

echo "==> [5/9] Redis — enable & start"
systemctl enable redis-server
systemctl start redis-server

echo "==> [6/9] App directory"
mkdir -p /var/www/$APP_NAME
chown $APP_USER:$APP_USER /var/www/$APP_NAME

echo "==> [7/9] Nginx — copy config"
cp /tmp/${DOMAIN}.conf /etc/nginx/sites-available/${DOMAIN} 2>/dev/null || echo "  (upload nginx config manually later)"
if [ -f /etc/nginx/sites-available/${DOMAIN} ]; then
  ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
fi

echo "==> [8/9] SSL — Let's Encrypt"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m quocvietlee@gmail.com || echo "  (run certbot manually after DNS propagates)"

echo "==> [9/9] Firewall"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo ""
echo "======================================================"
echo " Server setup complete!"
echo "======================================================"
echo " Next: On your LOCAL machine, run:"
echo "   cap production deploy:check   # verify setup"
echo "   cap production deploy         # first deploy"
echo "   cap production deploy:seed    # seed DB (first time only)"
echo "======================================================"
