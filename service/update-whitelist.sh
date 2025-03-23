#!/bin/bash

# YouTubeホワイトリスト自動更新スクリプト
# 用途: 期限切れのホワイトリストエントリを削除し、Squidを更新する
# crontabに追加する: 0 * * * * /path/to/update-whitelist.sh

# エラー発生時に停止
set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ロガー設定
LOG_TAG="youtube-proxy-whitelist"

# ヘルパー関数: ログ出力
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    logger -t "$LOG_TAG" "$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    logger -t "$LOG_TAG" "ERROR: $1"
}

# データベースファイルのパス
DB_FILE="/var/www/youtube-proxy/database.sqlite"

# ホワイトリストファイルのパス
WHITELIST_FILE="/var/lib/youtube-proxy/youtube_whitelist.txt"

# 必要なパッケージの確認
if ! command -v sqlite3 &> /dev/null; then
    log_error "sqlite3コマンドが見つかりません。"
    exit 1
fi

# データベースファイルの存在確認
if [ ! -f "$DB_FILE" ]; then
    log_error "データベースファイルが見つかりません: $DB_FILE"
    exit 1
fi

# 期限切れエントリをクリーンアップ
log_info "期限切れのホワイトリストエントリを削除しています..."
DELETED_COUNT=$(sqlite3 "$DB_FILE" "DELETE FROM whitelist WHERE expires_at < datetime('now') AND expires_at IS NOT NULL; SELECT changes();")

if [ "$DELETED_COUNT" -gt 0 ]; then
    log_info "$DELETED_COUNT 件の期限切れエントリを削除しました。"
else
    log_info "期限切れエントリはありませんでした。"
fi

# ホワイトリストファイルを更新
log_info "ホワイトリストファイルを更新しています..."
sqlite3 "$DB_FILE" "SELECT video_id FROM whitelist WHERE expires_at > datetime('now') OR expires_at IS NULL;" > "$WHITELIST_FILE.tmp"

# ファイルの内容確認
if [ ! -s "$WHITELIST_FILE.tmp" ]; then
    echo "# YouTube動画IDホワイトリスト - 現在エントリはありません" > "$WHITELIST_FILE.tmp"
    log_info "ホワイトリストは空です。"
else
    ENTRY_COUNT=$(wc -l < "$WHITELIST_FILE.tmp")
    log_info "ホワイトリストには $ENTRY_COUNT 件のエントリがあります。"
fi

# 一時ファイルを本番ファイルに移動
mv "$WHITELIST_FILE.tmp" "$WHITELIST_FILE"
chown proxy:proxy "$WHITELIST_FILE"
chmod 644 "$WHITELIST_FILE"

# Squidを再読み込み
log_info "Squidを再読み込みしています..."
if ! systemctl reload squid; then
    log_error "Squidの再読み込みに失敗しました。"
    log_error "ステータスを確認: systemctl status squid"
    exit 1
fi

log_info "ホワイトリストの更新が完了しました。"
