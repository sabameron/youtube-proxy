#!/bin/bash

# YouTubeプロキシデータベースバックアップスクリプト
# 用途: SQLiteデータベースのバックアップを作成する
# crontabに追加する: 0 2 * * * /path/to/backup-db.sh

# エラー発生時に停止
set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ロガー設定
LOG_TAG="youtube-proxy-backup"

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

# バックアップディレクトリ
BACKUP_DIR="/var/backups/youtube-proxy"

# バックアップファイル名（日付付き）
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILE="$BACKUP_DIR/youtube-proxy-db-$TIMESTAMP.sqlite"

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

# バックアップディレクトリの作成
mkdir -p "$BACKUP_DIR" || {
    log_error "バックアップディレクトリの作成に失敗しました: $BACKUP_DIR"
    exit 1
}

# バックアップの作成
log_info "データベースをバックアップしています: $DB_FILE → $BACKUP_FILE"
sqlite3 "$DB_FILE" ".backup '$BACKUP_FILE'" || {
    log_error "データベースのバックアップに失敗しました。"
    exit 1
}

# パーミッション設定
chown creater:creater "$BACKUP_FILE"
chmod 640 "$BACKUP_FILE"

# 古いバックアップの削除（30日以上前のもの）
log_info "30日以上前の古いバックアップを削除しています..."
find "$BACKUP_DIR" -name "youtube-proxy-db-*.sqlite" -type f -mtime +30 -delete

# バックアップの圧縮
if command -v gzip &> /dev/null; then
    log_info "バックアップを圧縮しています..."
    gzip -9 "$BACKUP_FILE" || log_error "バックアップの圧縮に失敗しました。"
    BACKUP_FILE="$BACKUP_FILE.gz"
fi

# バックアップのリスト表示
BACKUP_COUNT=$(find "$BACKUP_DIR" -name "youtube-proxy-db-*.sqlite*" | wc -l)
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')

log_info "バックアップが完了しました: $BACKUP_FILE"
log_info "バックアップの合計: $BACKUP_COUNT ファイル ($BACKUP_SIZE)"
