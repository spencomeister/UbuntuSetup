#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 01_locale_tz.sh - ロケール・タイムゾーン設定
# =============================================================================

echo "[INFO] ロケール・タイムゾーン設定を開始します..."

# --------------------------------------------------------------------------
# locales パッケージのインストール
# --------------------------------------------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get install -y locales

# --------------------------------------------------------------------------
# en_US.UTF-8 ロケールの生成
# --------------------------------------------------------------------------
if locale -a 2>/dev/null | grep -q "^en_US\.utf8$"; then
  echo "[INFO] en_US.UTF-8 ロケールは既に存在します。"
else
  echo "[INFO] en_US.UTF-8 ロケールを生成します..."
  locale-gen en_US.UTF-8
fi

# --------------------------------------------------------------------------
# /etc/default/locale の設定
# --------------------------------------------------------------------------
echo "[INFO] /etc/default/locale を設定します..."
cat > /etc/default/locale <<'EOF'
LANG=en_US.UTF-8
LANGUAGE=en_US:en
LC_ALL=en_US.UTF-8
EOF

update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# 現在のシェルセッションに即時反映
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

echo "[INFO] ロケール設定完了: $(locale | grep LANG)"

# --------------------------------------------------------------------------
# タイムゾーン設定
# --------------------------------------------------------------------------
CURRENT_TZ="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
if [[ "${CURRENT_TZ}" == "Asia/Tokyo" ]]; then
  echo "[INFO] タイムゾーンは既に Asia/Tokyo に設定されています。"
else
  echo "[INFO] タイムゾーンを Asia/Tokyo に設定します..."
  timedatectl set-timezone Asia/Tokyo
fi

echo "[INFO] タイムゾーン確認: $(timedatectl show --property=Timezone --value)"
echo "[INFO] ロケール・タイムゾーン設定完了。"
