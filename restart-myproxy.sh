#!/bin/bash

# restart-myproxy.sh
# YouTube専用プロキシサーバー再起動スクリプト
# 作成日: 2025-03-23

# sudo権限チェック
if [ "$(id -u)" -ne 0 ]; then
    echo "このスクリプトはroot権限で実行する必要があります。"
    echo "sudo bash $0 $* を実行してください。"
    exit 1
fi

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# ロゴ表示
show_logo() {
    echo -e "${BLUE}"
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo "┃  YouTube Selective Proxy - Service Restart Utility   ┃"
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    echo -e "${NC}"
}

# サービス停止
stop_services() {
    log_info "サービスを停止しています..."
    
    # Apache停止
    log_info "Apache Webサーバーを停止しています..."
    systemctl stop apache2 || log_warn "Apacheの停止に失敗しました。"
    
    # Webアプリ停止
    log_info "YouTube Proxy Webアプリケーションを停止しています..."
    systemctl stop youtube-proxy || log_warn "Webアプリケーションの停止に失敗しました。"
    
    # Squid停止
    log_info "Squidプロキシサーバーを停止しています..."
    systemctl stop squid || log_warn "Squidの停止に失敗しました。"
    
    log_info "全てのサービスを停止しました。"
}

# サービス起動
start_services() {
    log_info "サービスを起動しています..."
    
    # Squid起動
    log_info "Squidプロキシサーバーを起動しています..."
    systemctl start squid || {
        log_error "Squidの起動に失敗しました。"
        log_error "ログを確認: journalctl -u squid"
    }
    
    # 少し待機
    sleep 2
    
    # Webアプリ起動
    log_info "YouTube Proxy Webアプリケーションを起動しています..."
    systemctl start youtube-proxy || {
        log_error "Webアプリケーションの起動に失敗しました。"
        log_error "ログを確認: journalctl -u youtube-proxy"
    }
    
    # 少し待機
    sleep 2
    
    # Apache起動
    log_info "Apache Webサーバーを起動しています..."
    systemctl start apache2 || {
        log_error "Apacheの起動に失敗しました。"
        log_error "ログを確認: journalctl -u apache2"
    }
    
    log_info "全てのサービスを起動しました。"
}

# サービスステータス確認
check_services() {
    echo -e "\n${BLUE}=== サービスステータス ===${NC}"
    
    # Squidステータス
    if systemctl is-active --quiet squid; then
        echo -e "✅ Squidプロキシサーバー: ${GREEN}実行中${NC}"
    else
        echo -e "❌ Squidプロキシサーバー: ${RED}停止${NC}"
    fi
    
    # Webアプリステータス
    if systemctl is-active --quiet youtube-proxy; then
        echo -e "✅ YouTube Proxyアプリ: ${GREEN}実行中${NC}"
    else
        echo -e "❌ YouTube Proxyアプリ: ${RED}停止${NC}"
    fi
    
    # Apacheステータス
    if systemctl is-active --quiet apache2; then
        echo -e "✅ Apache Webサーバー: ${GREEN}実行中${NC}"
    else
        echo -e "❌ Apache Webサーバー: ${RED}停止${NC}"
    fi
    
    echo -e "\n${YELLOW}ポート待ち受け状況:${NC}"
    # ポート待ち受け状態を表示
    netstat -tulpn | grep -E "(3128|80|443|3000)" || echo -e "${RED}待ち受けポートが見つかりません${NC}"
    
    echo
}

# メイン実行関数
main() {
    show_logo
    
    # 現在のステータスを表示
    log_info "現在のサービスステータスを確認しています..."
    check_services
    
    # 再起動処理
    log_info "システム再起動を開始します..."
    stop_services
    
    # 少し待機
    sleep 3
    
    start_services
    
    # 少し待機
    sleep 3
    
    # 最終ステータスの確認
    log_info "再起動後のサービスステータスを確認しています..."
    check_services
    
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${GREEN}=== 再起動完了 ===${NC}"
    echo -e "YouTube選択プロキシサーバーの再起動が完了しました。"
    echo
    echo -e "${YELLOW}プロキシサーバー情報:${NC}"
    echo -e "- プロキシアドレス: ${SERVER_IP}"
    echo -e "- プロキシポート: 3128"
    echo -e "- 管理インターフェース: http://${SERVER_IP}/youtube-proxy"
    echo
    log_info "問題が発生した場合は、各サービスのログを確認してください。"
    echo -e "- Squidログ: /var/log/squid/access.log"
    echo -e "- Webアプリログ: journalctl -u youtube-proxy"
    echo -e "- Apacheログ: /var/log/apache2/error.log"
    echo
}

# スクリプト実行
main "$@"