# seragl.io サーバーセットアップ ガイド

Ubuntu 26.04 LTS (Resolute Raccoon / カーネル 7.0) 向けの自動セットアップスクリプトです。

## セットアップ内容

| モジュール | 内容 |
|-----------|------|
| `00_preflight.sh` | OS バージョン確認・前提チェック・`unattended-upgrades` 停止 |
| `01_locale_tz.sh` | ロケール `en_US.UTF-8`・タイムゾーン `Asia/Tokyo` |
| `02_base_packages.sh` | git / curl / jq 等の基本パッケージ |
| `03_security.sh` | Dirty Frag 緩和策・SSH hardening・ufw・fail2ban |
| `04_docker.sh` | Docker CE（公式リポジトリ） |
| `05_tailscale.sh` | Tailscale（WireGuard VPN） |
| `06_forgejo.sh` | Forgejo（Docker Compose） |
| `07_cloudflare_dns.sh` | Cloudflare DNS 自動更新（cron 5分ごと） |
| `08_zabbix.sh` | Zabbix（Docker Compose） |
| `09_caddy.sh` | Caddy リバースプロキシ（Cloudflare Origin Certificate） |

---

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone <this-repo> ~/UbuntuSetup
cd ~/UbuntuSetup/setup
```

### 2. `.env` の準備

```bash
cp .env.sample .env
nano .env    # 各項目に実際の値を入力する
```

#### 最低限必須の項目

| 変数 | 説明 | 取得先 |
|------|------|--------|
| `CF_API_TOKEN` | Cloudflare API Token | [Cloudflare ダッシュボード](https://dash.cloudflare.com/profile/api-tokens) |
| `CF_ZONE_ID` | Cloudflare Zone ID | ダッシュボード → seragl.io → 右サイドバー |
| `FORGEJO_SECRET_KEY` | Forgejo 内部シークレットキー | `openssl rand -hex 32` で生成 |
| `ZABBIX_DB_PASSWORD` | Zabbix DB パスワード | `openssl rand -base64 24` で生成 |
| `TAILSCALE_AUTHKEY` | Tailscale 認証キー（任意） | [Tailscale 管理画面](https://login.tailscale.com/admin/settings/keys) |

### 3. Cloudflare Origin Certificate の発行と配置（Caddy 起動前に必須）

Caddy は Cloudflare Origin Certificate を使用します。**セットアップスクリプト実行前または実行後・Caddy 起動前に**以下の手順で証明書を配置してください。

#### 3-1. 証明書の発行

1. [Cloudflare ダッシュボード](https://dash.cloudflare.com) にログイン
2. `seragl.io` → **SSL/TLS** → **Origin Server** を開く
3. **Create Certificate** をクリック
4. 以下の設定で発行:
   - Private key type: `RSA (2048)`
   - Hostnames: `seragl.io`, `*.seragl.io`
   - Certificate Validity: `15 years`
5. 発行された **Origin Certificate**（PEM 形式）と **Private Key** を手元にコピーしておく

#### 3-2. 証明書ファイルの配置

```bash
# 証明書ディレクトリを作成
sudo mkdir -p /etc/caddy/certs
sudo chown root:caddy /etc/caddy/certs
sudo chmod 750 /etc/caddy/certs

# 証明書ファイルを配置（発行した PEM を貼り付け）
sudo nano /etc/caddy/certs/origin.pem
sudo chmod 644 /etc/caddy/certs/origin.pem

# 秘密鍵ファイルを配置（発行した Private Key を貼り付け）
sudo nano /etc/caddy/certs/origin.key
sudo chmod 600 /etc/caddy/certs/origin.key

# Cloudflare Origin CA Root を証明書に連結
curl -so /tmp/cf-origin-ca.pem \
  https://developers.cloudflare.com/ssl/static/origin_ca_ecc_root.pem
sudo sh -c 'cat /tmp/cf-origin-ca.pem >> /etc/caddy/certs/origin.pem'
```

#### 3-3. Cloudflare SSL/TLS モードの設定

1. Cloudflare ダッシュボード → `seragl.io` → **SSL/TLS** → **Overview**
2. **Full (Strict)** を選択する

> ⚠️ **Flexible** や **Full（非 Strict）** に設定すると中間者攻撃のリスクがあります。必ず **Full (Strict)** を使用してください。

### 4. セットアップスクリプトの実行

```bash
cd ~/UbuntuSetup/setup
sudo bash setup.sh
```

証明書を事前配置した場合は Caddy まで自動起動します。
証明書が未配置の場合は `09_caddy.sh` が警告を出してスキップされます（後から手動で起動可能）。

---

## 事後手動設定

### 1. Tailscale 認証（`TAILSCALE_AUTHKEY` 未設定の場合）

```bash
sudo tailscale up
```

ブラウザでの認証が促された場合は表示された URL にアクセスしてください。

### 2. DNS 初回反映確認

```bash
sudo /usr/local/bin/cf-dns-update.sh
cat /var/log/cf-dns-update.log
```

### 3. Caddy の手動起動（証明書を後から配置した場合）

```bash
# 証明書配置後に実行
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl start caddy
sudo systemctl status caddy
```

### 4. Cloudflare Proxy の確認

Cloudflare ダッシュボード → `seragl.io` → **DNS** にて、以下のレコードが **Proxied**（オレンジ雲）になっていることを確認:

- `git.seragl.io` → A レコード
- `zbx.seragl.io` → A レコード

### 5. Forgejo 初期設定

1. `https://git.seragl.io` にアクセス
2. **初回インストール画面**で管理者アカウントを作成:
   - 管理者ユーザー名、メールアドレス、パスワードを設定
3. `.env` の `FORGEJO_ADMIN_USER` / `FORGEJO_ADMIN_EMAIL` を参考に設定

### 6. Zabbix 初期パスワード変更

1. `https://zbx.seragl.io` にアクセス
2. 初期ログイン情報: **ユーザー名**: `Admin` / **パスワード**: `zabbix`
3. ログイン後、速やかにパスワードを変更してください

---

## サービス URL

| サービス | URL |
|---------|-----|
| Forgejo (Git) | https://git.seragl.io |
| Zabbix (監視) | https://zbx.seragl.io |

---

## セキュリティ構成

### ファイアウォール（ufw）

| ポート | プロトコル | 用途 |
|-------|-----------|------|
| 22 | TCP | SSH |
| 80 | TCP | HTTP（Caddy が HTTPS へリダイレクト） |
| 443 | TCP | HTTPS（Caddy） |
| 41641 | UDP | Tailscale (WireGuard) |
| 3000 | TCP | **拒否**（Forgejo は Caddy 経由のみ） |
| 8080 | TCP | **拒否**（Zabbix は Caddy 経由のみ） |

### Dirty Frag 緩和策

Ubuntu 26.04 カーネル 7.0 に対する脆弱性（CVE-2026-43284 / CVE-2026-43500）の緩和策として、`esp4` / `esp6` / `rxrpc` カーネルモジュールを無効化しています。

- IPsec (ESP) は使用不可になりますが、**Tailscale (WireGuard)** は影響を受けません
- 設定ファイル: `/etc/modprobe.d/dirtyfrag.conf`

---

## 運用メモ

### DNS 更新ログの確認

```bash
tail -f /var/log/cf-dns-update.log
```

### Docker コンテナの確認

```bash
# Forgejo
cd /opt/forgejo && docker compose ps
docker compose logs forgejo

# Zabbix
cd /opt/zabbix && docker compose ps
docker compose logs zabbix-web
```

### Caddy のログ確認

```bash
journalctl -u caddy -f
tail -f /var/log/caddy/git.seragl.io.log
tail -f /var/log/caddy/zbx.seragl.io.log
```

### Tailscale の状態確認

```bash
tailscale status
tailscale ip
```

---

## ファイル構成

```
setup/
├── setup.sh                  # メインスクリプト
├── .env.sample               # 環境変数サンプル（Git 管理対象）
├── .env                      # 実際の秘密情報（.gitignore で除外）
├── .gitignore
├── modules/
│   ├── 00_preflight.sh
│   ├── 01_locale_tz.sh
│   ├── 02_base_packages.sh
│   ├── 03_security.sh
│   ├── 04_docker.sh
│   ├── 05_tailscale.sh
│   ├── 06_forgejo.sh
│   ├── 07_cloudflare_dns.sh
│   ├── 08_zabbix.sh
│   └── 09_caddy.sh
└── README.md
```

---

## 参考リンク

- [Forgejo Docker インストール](https://forgejo.org/docs/latest/admin/installation-docker/)
- [Zabbix Docker ドキュメント](https://www.zabbix.com/documentation/current/en/manual/installation/containers)
- [Tailscale Linux インストール](https://tailscale.com/kb/1031/install-linux)
- [Cloudflare API v4](https://developers.cloudflare.com/api/)
- [Cloudflare Origin Certificate](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Caddy インストール（APT）](https://caddyserver.com/docs/install#debian-ubuntu-raspbian)
