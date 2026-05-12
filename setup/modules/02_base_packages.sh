#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 02_base_packages.sh - 基本パッケージのインストール
# =============================================================================

echo "[INFO] 基本パッケージのインストールを開始します..."

DEBIAN_FRONTEND=noninteractive apt-get update -qq

DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git \
  zip \
  unzip \
  curl \
  wget \
  ca-certificates \
  gnupg \
  lsb-release \
  jq

echo "[INFO] インストール済みバージョン:"
echo "         git    : $(git --version)"
echo "         curl   : $(curl --version | head -1)"
echo "         jq     : $(jq --version)"

echo "[INFO] 基本パッケージのインストール完了。"
