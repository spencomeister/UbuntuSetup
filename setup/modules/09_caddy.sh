#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 09_caddy.sh - Caddy のインストール・設定
# TLS: Cloudflare Origin Certificate（Let's Encrypt は使用しない）
# Caddyfile: /etc/caddy/Caddyfile
# 証明書格納: /etc/caddy/certs/
# =============================================================================

echo "[INFO] Caddy のインストールを開始します..."

CADDYFILE="/etc/caddy/Caddyfile"
CERTS_DIR="/etc/caddy/certs"
CERT_PEM="${CERTS_DIR}/origin.pem"
CERT_KEY="${CERTS_DIR}/origin.key"
LOG_DIR="/var/log/caddy"

# --------------------------------------------------------------------------
# 依存パッケージのインストール
# --------------------------------------------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  debian-keyring \
  debian-archive-keyring \
  apt-transport-https \
  curl

# --------------------------------------------------------------------------
# Caddy 公式 GPG キーの配置（keyrings 方式）
# --------------------------------------------------------------------------
if [[ ! -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg ]]; then
  echo "[INFO] Caddy 公式 GPG キーを配置します..."
  install -m 0755 -d /etc/apt/keyrings
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  chmod a+r /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
else
  echo "[INFO] Caddy GPG キーは既に存在します。"
fi

# --------------------------------------------------------------------------
# Caddy 公式 APT リポジトリの追加
# --------------------------------------------------------------------------
if [[ ! -f /etc/apt/sources.list.d/caddy-stable.list ]]; then
  echo "[INFO] Caddy 公式 APT リポジトリを追加します..."
  # 公式 deb.txt を取得し、keyring パスを /etc/apt/keyrings/ に差し替えて配置
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sed 's|/usr/share/keyrings/caddy-stable-archive-keyring.gpg|/etc/apt/keyrings/caddy-stable-archive-keyring.gpg|g' \
    > /etc/apt/sources.list.d/caddy-stable.list
else
  echo "[INFO] Caddy APT リポジトリは既に設定されています。"
fi

DEBIAN_FRONTEND=noninteractive apt-get update -qq

# --------------------------------------------------------------------------
# Caddy のインストール
# --------------------------------------------------------------------------
if command -v caddy > /dev/null 2>&1; then
  echo "[INFO] Caddy は既にインストールされています: $(caddy version)"
else
  echo "[INFO] Caddy をインストールします..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
  echo "[INFO] Caddy インストール完了: $(caddy version)"
fi

# --------------------------------------------------------------------------
# 証明書格納ディレクトリの作成・パーミッション設定
# --------------------------------------------------------------------------
echo "[INFO] 証明書ディレクトリを作成します: ${CERTS_DIR}"
mkdir -p "${CERTS_DIR}"
chown root:caddy "${CERTS_DIR}"
chmod 750 "${CERTS_DIR}"

# --------------------------------------------------------------------------
# ログディレクトリの作成
# --------------------------------------------------------------------------
echo "[INFO] ログディレクトリを作成します: ${LOG_DIR}"
mkdir -p "${LOG_DIR}"
chown caddy:caddy "${LOG_DIR}"
chmod 755 "${LOG_DIR}"

# --------------------------------------------------------------------------
# Caddyfile の配置
# --------------------------------------------------------------------------
echo "[INFO] Caddyfile を配置します: ${CADDYFILE}"

cat > "${CADDYFILE}" <<'EOF'
# =============================================================================
# /etc/caddy/Caddyfile
# Cloudflare Proxy (Full Strict) + Origin Certificate 構成
# Let's Encrypt は使用しない（auto_https off）
# =============================================================================

{
    # Cloudflare Origin Certificate を使用するため自動 HTTPS を無効化
    auto_https off
    # 管理エンドポイントをローカルのみに制限
    admin localhost:2019
}

# Forgejo
git.seragl.io {
    tls /etc/caddy/certs/origin.pem /etc/caddy/certs/origin.key

    # Cloudflare の実クライアント IP をログ・アクセス制御に使用
    header_up X-Real-IP {http.request.header.CF-Connecting-IP}

    # Cloudflare Proxy 以外からの直接アクセスを拒否（オプション: CF IP レンジを許可リスト化）
    # 必要に応じて有効化すること（CF IP リストは変動するため cf-dns-update.sh での管理も検討）
    # @not_cf not remote_ip 103.21.244.0/22 103.22.200.0/22 # ... (省略)
    # respond @not_cf "Forbidden" 403

    reverse_proxy localhost:3000 {
        # Forgejo へ接続情報を転送
        header_up Host {host}
        header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
        header_up X-Forwarded-Proto {scheme}
    }

    log {
        output file /var/log/caddy/git.seragl.io.log {
            roll_size 50mb
            roll_keep 7
        }
        format json
    }
}

# Zabbix
zbx.seragl.io {
    tls /etc/caddy/certs/origin.pem /etc/caddy/certs/origin.key

    header_up X-Real-IP {http.request.header.CF-Connecting-IP}

    reverse_proxy localhost:8080 {
        header_up Host {host}
        header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
        header_up X-Forwarded-Proto {scheme}
    }

    log {
        output file /var/log/caddy/zbx.seragl.io.log {
            roll_size 50mb
            roll_keep 7
        }
        format json
    }
}
EOF

echo "[INFO] Caddyfile を配置しました。"

# --------------------------------------------------------------------------
# 証明書ファイルの存在確認
# --------------------------------------------------------------------------
CERTS_READY=true

if [[ ! -f "${CERT_PEM}" ]]; then
  echo "[WARN] 証明書ファイルが見つかりません: ${CERT_PEM}"
  CERTS_READY=false
fi

if [[ ! -f "${CERT_KEY}" ]]; then
  echo "[WARN] 秘密鍵ファイルが見つかりません: ${CERT_KEY}"
  CERTS_READY=false
fi

if [[ "${CERTS_READY}" == "false" ]]; then
  echo "[WARN] Cloudflare Origin Certificate が配置されていないため、Caddy の起動をスキップします。"
  echo "[WARN] 証明書を配置した後、以下のコマンドで Caddy を起動してください:"
  echo "       sudo systemctl start caddy"
  echo ""
  echo "[INFO] 証明書の発行手順は README.md を参照してください。"
  echo "[INFO] 配置先:"
  echo "         証明書: ${CERT_PEM}（パーミッション: 644）"
  echo "         秘密鍵: ${CERT_KEY}（パーミッション: 600）"
  exit 0
fi

# --------------------------------------------------------------------------
# Caddyfile の構文チェック
# --------------------------------------------------------------------------
echo "[INFO] Caddyfile の構文チェックを実行します..."
if caddy validate --config "${CADDYFILE}"; then
  echo "[INFO] Caddyfile の構文チェック OK。"
else
  echo "[ERROR] Caddyfile に構文エラーがあります。内容を確認してください: ${CADDYFILE}"
  exit 1
fi

# --------------------------------------------------------------------------
# Caddy の自動起動有効化と起動
# --------------------------------------------------------------------------
systemctl enable --now caddy

# 証明書が揃っている場合は reload
echo "[INFO] Caddy を reload します..."
systemctl reload caddy

echo "[INFO] Caddy の状態:"
systemctl status caddy --no-pager || true

echo "[INFO] Caddy のインストール・設定完了。"
