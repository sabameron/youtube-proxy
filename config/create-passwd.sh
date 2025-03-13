#!/bin/bash

# Squidプロキシ用パスワードファイル生成スクリプト

# エラー発生時に停止
set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ヘルパー関数: ログ出力
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# パスワードファイルの場所
PASSWD_FILE="/etc/squid/passwd"

# htpasswdコマンドがインストールされているか確認
if ! command -v htpasswd &> /dev/null; then
    log_error "htpasswdコマンドが見つかりません。apache2-utilsをインストールします。"
    apt-get update -qq
    apt-get install -y apache2-utils
    log_info "apache2-utilsがインストールされました。"
fi

# ユーザー名の入力
read -p "プロキシのユーザー名を入力してください [proxy]: " username
username=${username:-proxy}

# パスワードの入力
read -s -p "パスワードを入力してください: " password
echo
read -s -p "パスワードを再入力してください: " password_confirm
echo

# パスワードの確認
if [ "$password" != "$password_confirm" ]; then
    log_error "パスワードが一致しません。処理を中止します。"
    exit 1
fi

# パスワードファイルを作成・更新
if [ -f "$PASSWD_FILE" ]; then
    # 既存のユーザーを更新
    htpasswd -b "$PASSWD_FILE" "$username" "$password"
    log_info "ユーザー '$username' のパスワードが更新されました。"
else
    # 新規ファイル作成
    htpasswd -bc "$PASSWD_FILE" "$username" "$password"
    log_info "パスワードファイルが作成され、ユーザー '$username' が追加されました。"
fi

# パーミッション設定
chown proxy:proxy "$PASSWD_FILE"
chmod 640 "$PASSWD_FILE"

log_info "Squidパスワードファイルの設定が完了しました。"
log_info "ユーザー名: $username"
log_info "パスワードファイル: $PASSWD_FILE"

# Squidの再起動が必要
if systemctl is-active --quiet squid; then
    if read -p "Squidを再起動しますか？ [y/N] " -n 1 -r && [[ $REPLY =~ ^[Yy]$ ]]; then
        echo
        systemctl restart squid
        log_info "Squidが再起動されました。"
    else
        echo
        log_info "Squidの再起動がスキップされました。手動で再起動してください。"
    fi
fi
