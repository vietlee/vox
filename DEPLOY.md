# Deploy VOX lên DigitalOcean

**Domain:** vox.czin.net  
**Server:** Ubuntu 22.04 — user `deploy`  
**Stack:** Puma + Sidekiq + Nginx + PostgreSQL + Redis

---

## BƯỚC 1 — Chuẩn bị local

### 1.1 Điền thông tin thật vào Capistrano

Mở `config/deploy/production.rb`, thay `YOUR_SERVER_IP` bằng IP droplet:
```ruby
server "YOUR_SERVER_IP", user: "deploy", roles: %w[web app db], ...
```

Mở `config/deploy.rb`, thay repo URL:
```ruby
set :repo_url, "git@github.com:YOUR_GITHUB_USERNAME/YOUR_REPO.git"
```

### 1.2 Push code lên GitHub

```bash
git add -A
git commit -m "Add Capistrano deploy config"
git push origin main
```

---

## BƯỚC 2 — Setup server (chạy 1 lần)

### 2.1 SSH vào droplet với quyền root

```bash
ssh root@YOUR_SERVER_IP
```

### 2.2 Chạy server setup script

```bash
# Upload script lên server
scp config/deploy/server_setup.sh root@YOUR_SERVER_IP:/tmp/

# SSH vào và chạy
ssh root@YOUR_SERVER_IP
bash /tmp/server_setup.sh
```

Script sẽ tự động:
- Tạo user `deploy`
- Cài rbenv + Ruby 3.2.2
- Tạo PostgreSQL DB + user (in ra DATABASE_URL — **lưu lại**)
- Cài Redis, Nginx, Certbot, Chromium
- Cấu hình SSL tự động
- Bật firewall

### 2.3 Upload Nginx config

```bash
scp config/nginx/vox.czin.net.conf root@YOUR_SERVER_IP:/etc/nginx/sites-available/vox.czin.net
ssh root@YOUR_SERVER_IP
ln -s /etc/nginx/sites-available/vox.czin.net /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

---

## BƯỚC 3 — Cấu hình .env trên server

SSH với user `deploy`:

```bash
ssh deploy@YOUR_SERVER_IP
mkdir -p /var/www/vox/shared
nano /var/www/vox/shared/.env
```

Dán nội dung sau (điền đầy đủ các giá trị):

```env
RAILS_ENV=production
APP_HOST=vox.czin.net
SECRET_KEY_BASE=          # chạy: openssl rand -hex 64
RAILS_MASTER_KEY=         # nội dung file config/master.key trên máy local

DATABASE_URL=postgresql://vox_user:PASSWORD@localhost/vox_production
REDIS_URL=redis://localhost:6379/0

SMTP_DOMAIN=czin.net
SMTP_USERNAME=your@gmail.com
SMTP_PASSWORD=your_gmail_app_password
MAIL_FROM=no-reply@czin.net

DO_SPACES_KEY=
DO_SPACES_SECRET=
DO_SPACES_REGION=sgp1
DO_SPACES_BUCKET=vox-uploads

ANTHROPIC_API_KEY=

PAYOS_CLIENT_ID=
PAYOS_API_KEY=
PAYOS_CHECKSUM_KEY=

SIDEKIQ_WEB_USERNAME=admin
SIDEKIQ_WEB_PASSWORD=CHANGE_THIS_PASSWORD
```

### Lấy RAILS_MASTER_KEY

```bash
# Trên máy local
cat config/master.key
```

---

## BƯỚC 4 — First deploy từ máy local

```bash
# Kiểm tra kết nối + cấu trúc thư mục
bundle exec cap production deploy:check

# Deploy lần đầu
bundle exec cap production deploy

# Migrate + seed (chỉ lần đầu)
bundle exec cap production deploy:seed
```

---

## BƯỚC 5 — Setup Sidekiq systemd

SSH vào server với quyền root, tạo service:

```bash
cat > /etc/systemd/system/sidekiq-vox.service << 'EOF'
[Unit]
Description=Sidekiq for VOX
After=network.target postgresql.service redis.service

[Service]
Type=notify
WatchdogSec=10
User=deploy
WorkingDirectory=/var/www/vox/current
ExecStart=/home/deploy/.rbenv/bin/rbenv exec bundle exec sidekiq -C config/sidekiq.yml
ExecReload=/bin/kill -TSTP $MAINPID
ExecStop=/bin/kill -TERM $MAINPID
EnvironmentFile=/var/www/vox/shared/.env
Restart=always
RestartSec=5
StandardOutput=append:/var/www/vox/shared/log/sidekiq.log
StandardError=append:/var/www/vox/shared/log/sidekiq.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sidekiq-vox
systemctl start sidekiq-vox
systemctl status sidekiq-vox
```

---

## BƯỚC 6 — Verify

```bash
# Puma đang chạy?
systemctl status puma_vox_1

# Sidekiq đang chạy?
systemctl status sidekiq-vox

# Nginx OK?
nginx -t
curl -I https://vox.czin.net/up

# Logs
tail -f /var/www/vox/current/log/production.log
tail -f /var/www/vox/shared/log/sidekiq.log
```

---

## Deploy thường ngày

```bash
# Từ máy local
git push origin main
bundle exec cap production deploy
```

---

## Troubleshooting

| Vấn đề | Lệnh kiểm tra |
|--------|---------------|
| App lỗi 500 | `tail -100 /var/www/vox/current/log/production.log` |
| Puma không start | `journalctl -u puma_vox_1 -n 50` |
| Sidekiq không chạy | `journalctl -u sidekiq-vox -n 50` |
| Nginx lỗi | `nginx -t` rồi `journalctl -u nginx -n 50` |
| DB connection fail | Kiểm tra `DATABASE_URL` trong `.env` |
| Assets không load | `bundle exec cap production deploy:assets:precompile` |
