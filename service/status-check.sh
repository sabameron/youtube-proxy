#!/bin/bash

# YouTube Selective Proxyステータス確認スクリプト
# 用途: プロキシサービスの状態を確認し、問題があれば通知する

# エラー発生時に停止
set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ロゴ表示
show_logo() {
    echo -e "${BLUE}"
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo "┃  YouTube Selective Proxy - System Status Check        ┃"
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    echo -e "${NC}"
}

# ヘルパー関数: ログ出力
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# サービスステータスを確認する関数
check_service() {
    local service_name="$1"
    echo -e "\n${YELLOW}=== $service_name サービスの確認 ===${NC}"
    
    if systemctl is-active --quiet "$service_name"; then
        echo -e "ステータス: ${GREEN}実行中${NC}"
        systemctl status "$service_name" | grep -E "Active:|Main PID:" | sed 's/^/  /'
    else
        echo -e "ステータス: ${RED}停止${NC}"
        systemctl status "$service_name" | grep -E "Active:|Failed:" | sed 's/^/  /'
        log_error "$service_name サービスが実行されていません。"
        log_info "開始コマンド: sudo systemctl start $service_name"
    fi
}

# ポートを確認する関数
check_port() {
    local port="$1"
    local service_name="$2"
    echo -e "\n${YELLOW}=== ポート $port ($service_name) の確認 ===${NC}"
    
    if netstat -tuln | grep -q ":$port "; then
        echo -e "ステータス: ${GREEN}リッスン中${NC}"
        netstat -tuln | grep ":$port " | sed 's/^/  /'
    else
        echo -e "ステータス: ${RED}クローズド${NC}"
        log_error "ポート $port が開いていません。$service_name が正しく起動しているか確認してください。"
    fi
}

# ファイルの存在を確認する関数
check_file() {
    local file_path="$1"
    local file_desc="$2"
    echo -e "\n${YELLOW}=== $file_desc の確認 ===${NC}"
    
    if [ -f "$file_path" ]; then
        echo -e "ステータス: ${GREEN}存在します${NC}"
        ls -la "$file_path" | sed 's/^/  /'
        
        # ファイルサイズを確認
        local file_size=$(du -h "$file_path" | cut -f1)
        echo "  サイズ: $file_size"
        
        # 最終更新日時を確認
        local last_modified=$(stat -c "%y" "$file_path")
        echo "  最終更新: $last_modified"
    else
        echo -e "ステータス: ${RED}存在しません${NC}"
        log_error "$file_path が見つかりません。"
    fi
}

# ディスク使用量を確認する関数
check_disk_usage() {
    echo -e "\n${YELLOW}=== ディスク使用量の確認 ===${NC}"
    
    df -h / | sed 's/^/  /'
    
    # 警告レベルの確認
    local usage_percent=$(df / | grep / | awk '{ print $5}' | sed 's/%//')
    if [ "$usage_percent" -gt 90 ]; then
        log_error "ディスク使用量が $usage_percent% と危険水準です。"
    elif [ "$usage_percent" -gt 80 ]; then
        log_warn "ディスク使用量が $usage_percent% と警告水準です。"
    else
        log_info "ディスク使用量は $usage_percent% と正常です。"
    fi
}

# メモリ使用量を確認する関数
check_memory_usage() {
    echo -e "\n${YELLOW}=== メモリ使用量の確認 ===${NC}"
    
    free -h | sed 's/^/  /'
    
    # 警告レベルの確認
    local memory_used=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
    if [ "$memory_used" -gt 90 ]; then
        log_error "メモリ使用量が約 $memory_used% と危険水準です。"
    elif [ "$memory_used" -gt 80 ]; then
        log_warn "メモリ使用量が約 $memory_used% と警告水準です。"
    else
        log_info "メモリ使用量は約 $memory_used% と正常です。"
    fi
}

# ログファイルを確認する関数
check_logs() {
    local log_file="$1"
    local log_desc="$2"
    local lines="${3:-10}"
    
    echo -e "\n${YELLOW}=== $log_desc の最近のログ ($lines 行) ===${NC}"
    
    if [ -f "$log_file" ]; then
        echo -e "ログファイル: ${GREEN}$log_file${NC}"
        tail -n "$lines" "$log_file" | sed 's/^/  /'
        
        # エラーの確認
        local error_count=$(grep -i "error\|exception\|fatal" "$log_file" | wc -l)
        if [ "$error_count" -gt 0 ]; then
            log_warn "ログに $error_count 件のエラーが見つかりました。"
            grep -i "error\|exception\|fatal" "$log_file" | tail -5 | sed 's/^/  /'
        else
            log_info "ログにエラーは見つかりませんでした。"
        fi
    else
        echo -e "ステータス: ${RED}ログファイルが存在しません${NC}"
        log_error "$log_file が見つかりません。"
    fi
}

# メイン関数
main() {
    show_logo
    
    # システムの基本情報
    echo -e "${YELLOW}=== システム情報 ===${NC}"
    echo "ホスト名: $(hostname)"
    echo "IPアドレス: $(hostname -I | awk '{print $1}')"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo "カーネル: $(uname -r)"
    echo "稼働時間: $(uptime -p)"
    
    # サービス状態の確認
    check_service "squid"
    check_service "apache2"
    check_service "youtube-proxy"
    
    # ポートの確認
    check_port "3128" "Squidプロキシ"
    check_port "80" "Webサーバー"
    check_port "3000" "YouTubeプロキシアプリ"
    
    # 重要ファイルの確認
    check_file "/etc/squid/squid.conf" "Squid設定ファイル"
    check_file "/etc/squid/youtube_whitelist.txt" "YouTubeホワイトリストファイル"
    check_file "/var/www/youtube-proxy/database.sqlite" "アプリデータベース"
    
    # リソース使用状況
    check_disk_usage
    check_memory_usage
    
    # ログの確認
    check_logs "/var/log/squid/access.log" "Squidアクセスログ"
    check_logs "/var/log/apache2/youtube-proxy-access.log" "Apache アクセスログ"
    check_logs "/var/log/syslog" "システムログ" 5
    
    echo -e "\n${GREEN}=== ステータスチェック完了 ===${NC}"
    echo "問題が検出された場合は対応してください。"
    echo "ヘルプが必要な場合は管理者に連絡するか、プロジェクトのドキュメントを参照してください。"
}

# スクリプト実行
main
