#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 07_cloudflare_dns.sh - Cloudflare DNS レコード管理スクリプトの設置
#   - /usr/local/bin/cf-dns-update.sh を配置
#   - /etc/default/seragl-env に .env をコピー（root 専用 600）
#   - /etc/cron.d/cf-dns-update を設定（5分ごと）
#   - logrotate 設定
# =============================================================================

echo "[INFO] Cloudflare DNS 管理スクリプトを設置します..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
CF_DNS_SCRIPT="/usr/local/bin/cf-dns-update.sh"
SERAGL_ENV="/etc/default/seragl-env"
LOG_FILE="/var/log/cf-dns-update.log"

# --------------------------------------------------------------------------
# .env の内容を /etc/default/seragl-env にコピー（root のみ読み取り可）
# --------------------------------------------------------------------------
echo "[INFO] /etc/default/seragl-env に環境変数を配置します..."
install -m 600 -o root -g root "${ENV_FILE}" "${SERAGL_ENV}"
echo "[INFO] ${SERAGL_ENV} を配置しました（パーミッション: 600）。"

# --------------------------------------------------------------------------
# /usr/local/bin/cf-dns-update.sh を配置
# --------------------------------------------------------------------------
echo "[INFO] /usr/local/bin/cf-dns-update.sh を配置します..."

cat > "${CF_DNS_SCRIPT}" <<'CF_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# cf-dns-update.sh - Cloudflare DNS A レコード自動更新スクリプト
# 対象ドメイン: git.seragl.io, zbx.seragl.io
# 実行方法: cron（/etc/cron.d/cf-dns-update）から5分ごとに実行
# =============================================================================

LOG_FILE="/var/log/cf-dns-update.log"
ENV_FILE="/etc/default/seragl-env"
CF_API="https://api.cloudflare.com/client/v4"
DOMAINS=("git.seragl.io" "zbx.seragl.io")

log() {
  local level="$1"
  local message="$2"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [${level}] ${message}" >> "${LOG_FILE}"
}

# --------------------------------------------------------------------------
# 環境変数の読み込み
# --------------------------------------------------------------------------
if [[ ! -f "${ENV_FILE}" ]]; then
  log "ERROR" "${ENV_FILE} が見つかりません。"
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

if [[ -z "${CF_API_TOKEN:-}" ]] || [[ -z "${CF_ZONE_ID:-}" ]]; then
  log "ERROR" "CF_API_TOKEN または CF_ZONE_ID が未設定です。"
  exit 1
fi

# --------------------------------------------------------------------------
# 現在のグローバル IP を取得
# --------------------------------------------------------------------------
CURRENT_IP="$(curl -sf --max-time 10 https://api.ipify.org 2>/dev/null)" || {
  log "ERROR" "IP アドレスの取得に失敗しました（api.ipify.org への接続エラー）。"
  exit 1
}

if [[ -z "${CURRENT_IP}" ]]; then
  log "ERROR" "取得した IP アドレスが空です。"
  exit 1
fi

log "INFO" "現在の IP アドレス: ${CURRENT_IP}"

# --------------------------------------------------------------------------
# 各ドメインの A レコードを upsert
# --------------------------------------------------------------------------
for DOMAIN in "${DOMAINS[@]}"; do

  # 既存レコードを検索
  RESPONSE="$(curl -sf --max-time 10 \
    -X GET \
    "${CF_API}/zones/${CF_ZONE_ID}/dns_records?type=A&name=${DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" 2>/dev/null)" || {
    log "ERROR" "${DOMAIN}: Cloudflare API への接続に失敗しました。"
    continue
  }

  RECORD_ID="$(echo "${RESPONSE}" | jq -r '.result[0].id // empty' 2>/dev/null || true)"
  CURRENT_RECORD_IP="$(echo "${RESPONSE}" | jq -r '.result[0].content // empty' 2>/dev/null || true)"

  if [[ -n "${RECORD_ID}" ]]; then
    # IP が変わっていない場合はスキップ
    if [[ "${CURRENT_RECORD_IP}" == "${CURRENT_IP}" ]]; then
      log "INFO" "${DOMAIN}: IP に変更なし（${CURRENT_IP}）。スキップします。"
      continue
    fi

    # 既存レコードを更新（PUT）
    RESULT="$(curl -sf --max-time 10 \
      -X PUT \
      "${CF_API}/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data-raw "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${CURRENT_IP}\",\"ttl\":1,\"proxied\":true}" \
      2>/dev/null)" || {
      log "ERROR" "${DOMAIN}: レコードの更新リクエストに失敗しました。"
      continue
    }

    SUCCESS="$(echo "${RESULT}" | jq -r '.success' 2>/dev/null || echo 'false')"
    if [[ "${SUCCESS}" == "true" ]]; then
      log "INFO" "${DOMAIN}: A レコードを ${CURRENT_RECORD_IP} → ${CURRENT_IP} に更新しました（ID: ${RECORD_ID}）。"
    else
      ERRORS="$(echo "${RESULT}" | jq -c '.errors' 2>/dev/null || echo '[]')"
      log "ERROR" "${DOMAIN}: レコードの更新が失敗しました。エラー: ${ERRORS}"
    fi
  else
    # 新規レコードを作成（POST）
    RESULT="$(curl -sf --max-time 10 \
      -X POST \
      "${CF_API}/zones/${CF_ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data-raw "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${CURRENT_IP}\",\"ttl\":1,\"proxied\":true}" \
      2>/dev/null)" || {
      log "ERROR" "${DOMAIN}: レコードの作成リクエストに失敗しました。"
      continue
    }

    SUCCESS="$(echo "${RESULT}" | jq -r '.success' 2>/dev/null || echo 'false')"
    if [[ "${SUCCESS}" == "true" ]]; then
      log "INFO" "${DOMAIN}: A レコードを ${CURRENT_IP} で新規作成しました。"
    else
      ERRORS="$(echo "${RESULT}" | jq -c '.errors' 2>/dev/null || echo '[]')"
      log "ERROR" "${DOMAIN}: レコードの作成が失敗しました。エラー: ${ERRORS}"
    fi
  fi

done

log "INFO" "DNS 更新処理が完了しました。"
CF_SCRIPT

chmod 755 "${CF_DNS_SCRIPT}"
echo "[INFO] ${CF_DNS_SCRIPT} を配置しました。"

# --------------------------------------------------------------------------
# ログファイルの作成
# --------------------------------------------------------------------------
touch "${LOG_FILE}"
chmod 640 "${LOG_FILE}"

# --------------------------------------------------------------------------
# cron ジョブの設定（5分ごと）
# --------------------------------------------------------------------------
echo "[INFO] cron ジョブを設定します: /etc/cron.d/cf-dns-update"
cat > /etc/cron.d/cf-dns-update <<'EOF'
# Cloudflare DNS A レコード自動更新（5分ごと）
# /etc/default/seragl-env から CF_API_TOKEN / CF_ZONE_ID を読み込んで実行
*/5 * * * * root . /etc/default/seragl-env && /usr/local/bin/cf-dns-update.sh >> /var/log/cf-dns-update.log 2>&1
EOF

chmod 644 /etc/cron.d/cf-dns-update
echo "[INFO] cron ジョブを設定しました。"

# --------------------------------------------------------------------------
# logrotate の設定
# --------------------------------------------------------------------------
echo "[INFO] logrotate を設定します..."
cat > /etc/logrotate.d/cf-dns-update <<'EOF'
/var/log/cf-dns-update.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF

echo "[INFO] logrotate を設定しました。"

# --------------------------------------------------------------------------
# 動作確認（初回実行）
# --------------------------------------------------------------------------
echo "[INFO] cf-dns-update.sh を初回実行します..."
. "${SERAGL_ENV}" && bash "${CF_DNS_SCRIPT}" || {
  echo "[WARN] 初回 DNS 更新に失敗しました。ログを確認してください: ${LOG_FILE}"
}

echo "[INFO] Cloudflare DNS 管理スクリプトの設置完了。"
echo "[INFO] ログ: ${LOG_FILE}"
