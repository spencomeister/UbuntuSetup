#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 03_security.sh - セキュリティ設定
#   - Dirty Frag 緩和策（CVE-2026-43284 / CVE-2026-43500）
#   - SSH ハードニング
#   - fail2ban
#   - ufw ファイアウォール
# =============================================================================

echo "[INFO] セキュリティ設定を開始します..."

# --------------------------------------------------------------------------
# Dirty Frag 緩和策（CVE-2026-43284 / CVE-2026-43500）
# カーネル 7.0 時点でパッチなし → esp4/esp6/rxrpc モジュールを無効化
# --------------------------------------------------------------------------
echo "[INFO] Dirty Frag 緩和策を適用します..."

cat > /etc/modprobe.d/dirtyfrag.conf <<'EOF'
# Dirty Frag (CVE-2026-43284 / CVE-2026-43500) 緩和策
# esp4/esp6 を無効化すると IPsec (ESP) は使用不可になる
# Tailscale は WireGuard ベースのため影響なし
install esp4 /bin/false
install esp6 /bin/false
install rxrpc /bin/false
EOF

rmmod esp4 2>/dev/null || true
rmmod esp6 2>/dev/null || true
rmmod rxrpc 2>/dev/null || true
echo 3 > /proc/sys/vm/drop_caches

echo "[INFO] Dirty Frag 緩和策を適用しました。（esp4/esp6/rxrpc を無効化）"
echo "[WARN] IPsec (ESP) は使用不可になりました。Tailscale (WireGuard) への影響はありません。"

# --------------------------------------------------------------------------
# SSH ハードニング
# --------------------------------------------------------------------------
echo "[INFO] SSH ハードニングを適用します..."

mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
# パスワード認証を無効化（公開鍵認証のみ許可）
PasswordAuthentication no
ChallengeResponseAuthentication no

# root ログインを禁止
PermitRootLogin no

# その他のセキュリティ強化
X11Forwarding no
AllowTcpForwarding no
MaxAuthTries 3
LoginGraceTime 30
EOF

# 設定ファイルの構文チェック
sshd -t && systemctl reload sshd
echo "[INFO] SSH ハードニング完了。"

# --------------------------------------------------------------------------
# fail2ban のインストールと SSH jail の有効化
# --------------------------------------------------------------------------
echo "[INFO] fail2ban をインストールします..."

DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban

# jail.local が存在しない場合のみ作成（冪等性）
if [[ ! -f /etc/fail2ban/jail.local ]]; then
  cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
EOF
  echo "[INFO] fail2ban jail.local を作成しました。"
else
  echo "[INFO] fail2ban jail.local は既に存在します。スキップします。"
fi

systemctl enable --now fail2ban
echo "[INFO] fail2ban の設定完了。"

# --------------------------------------------------------------------------
# ufw ファイアウォール設定
# --------------------------------------------------------------------------
echo "[INFO] ufw を設定します..."

DEBIAN_FRONTEND=noninteractive apt-get install -y ufw

# デフォルトポリシー
ufw --force default deny incoming
ufw --force default allow outgoing

# 許可するポート
ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP (Caddy - Cloudflare Proxy redirect)'
ufw allow 443/tcp   comment 'HTTPS (Caddy)'
ufw allow 41641/udp comment 'Tailscale WireGuard'

# Caddy 経由のみアクセス可 - 直接公開しない
ufw deny 3000/tcp   comment 'Forgejo direct (Caddy経由のみ許可)'
ufw deny 8080/tcp   comment 'Zabbix direct (Caddy経由のみ許可)'

# ufw 有効化（SSH 接続が切れないよう --force を使用）
ufw --force enable

echo "[INFO] ufw 設定完了。"
ufw status verbose

echo "[INFO] セキュリティ設定完了。"
