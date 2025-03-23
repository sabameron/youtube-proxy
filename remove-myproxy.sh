#!/bin/bash

# remove-myproxy.sh
# YouTube専用プロキシサーバー削除スクリプト
# 用途: create-myproxy.shで構築したプロキシを完全に削除
# 作成日: 2025-03-23

# sudo権限チェック
if [ "$(id -u)" -ne 0 ]; then
    echo "このスクリプトはroot権限で実行する必要があります。"
    echo "sudo bash $0 $* を実行してください。"
    exit 1
fi

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
    echo -e "${RED}"
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo "┃  YouTube Selective Proxy - Uninstallation Script    ┃"
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

# ヘルパー関数: ユーザー確認
confirm() {
    read -r -p "$1 [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# サービス停止と無効化
stop_services() {
    log_info "サービスを停止しています..."
    
    # YouTube-proxyサービスの停止と無効化
    if systemctl is-active --quiet youtube-proxy 2>/dev/null; then
        systemctl stop youtube-proxy || log_warn "YouTube-proxyサービスの停止に失敗しました"
        systemctl disable youtube-proxy || log_warn "YouTube-proxyサービスの無効化に失敗しました"
        log_info "YouTube-proxyサービスを停止しました"
    else
        log_info "YouTube-proxyサービスは実行されていません"
    fi
    
    # Squidサービスの停止と無効化
    if systemctl is-active --quiet squid 2>/dev/null; then
        systemctl stop squid || log_warn "Squidサービスの停止に失敗しました"
        systemctl disable squid || log_warn "Squidサービスの無効化に失敗しました"
        log_info "Squidサービスを停止しました"
    else
        log_info "Squidサービスは実行されていません"
    fi
    
    # Apacheの設定を元に戻す
    if [ -f /etc/apache2/sites-enabled/youtube-proxy.conf ]; then
        a2dissite youtube-proxy || log_warn "Apache仮想ホストの無効化に失敗しました"
        systemctl reload apache2 || log_warn "Apacheの再読み込みに失敗しました"
        log_info "Apacheの設定を元に戻しました"
    fi
}

# ファイルとディレクトリの削除
remove_files() {
    log_info "ファイルとディレクトリを削除しています..."
    
    # サービスファイル削除
    if [ -f /etc/systemd/system/youtube-proxy.service ]; then
        rm -f /etc/systemd/system/youtube-proxy.service || log_warn "サービスファイルの削除に失敗しました"
        systemctl daemon-reload
        log_info "サービスファイルを削除しました"
    fi
    
    # Apacheの設定ファイル削除
    if [ -f /etc/apache2/sites-available/youtube-proxy.conf ]; then
        rm -f /etc/apache2/sites-available/youtube-proxy.conf || log_warn "Apache設定ファイルの削除に失敗しました"
        log_info "Apache設定ファイルを削除しました"
    fi
    
    # Squidの設定ファイル削除と復元
    if [ -f /etc/squid/squid.conf.bak ]; then
        mv /etc/squid/squid.conf.bak /etc/squid/squid.conf || log_warn "Squid設定ファイルの復元に失敗しました"
        log_info "Squidの設定ファイルを元に戻しました"
    fi
    
    # Webアプリケーションディレクトリ削除
    if [ -d /var/www/youtube-proxy ]; then
        rm -rf /var/www/youtube-proxy || log_warn "Webアプリケーションディレクトリの削除に失敗しました"
        log_info "Webアプリケーションディレクトリを削除しました"
    fi
    
    # ホワイトリストファイルとディレクトリ削除
    if [ -d /var/lib/youtube-proxy ]; then
        rm -rf /var/lib/youtube-proxy || log_warn "ホワイトリストディレクトリの削除に失敗しました"
        log_info "ホワイトリストディレクトリを削除しました"
    fi
    
    # キャッシュファイル削除
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    CACHE_FILE="$SCRIPT_DIR/install-progress.cache"
    if [ -f "$CACHE_FILE" ]; then
        rm -f "$CACHE_FILE" || log_warn "キャッシュファイルの削除に失敗しました"
        log_info "インストール進行状況キャッシュを削除しました"
    fi
}

# ファイアウォール設定の削除
remove_firewall_rules() {
    log_info "ファイアウォールルールを削除しています..."
    
    # UFWが有効かどうかを確認
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        # Squidプロキシポートのルールを削除
        ufw delete allow 3128/tcp &>/dev/null || log_warn "Squidプロキシポートのルール削除に失敗しました"
        log_info "Squidプロキシポートのファイアウォールルールを削除しました"
    else
        log_info "UFWが有効になっていないか、インストールされていません"
    fi
}

# ユーザー設定の削除
remove_user_settings() {
    log_info "ユーザー設定を削除しています..."
    
    # createrユーザーのsquidグループからの削除
    if id -nG creater 2>/dev/null | grep -qw "proxy"; then
        gpasswd -d creater proxy 2>/dev/null || log_warn "createrユーザーのsquidグループからの削除に失敗しました"
        log_info "createrユーザーをproxyグループから削除しました"
    fi
    
    # www-dataユーザーのcreaterグループからの削除
    if id -nG www-data 2>/dev/null | grep -qw "creater"; then
        gpasswd -d www-data creater 2>/dev/null || log_warn "www-dataユーザーのcreaterグループからの削除に失敗しました"
        log_info "www-dataユーザーをcreaterグループから削除しました"
    fi
}

# パッケージのアンインストール
uninstall_packages() {
    log_info "パッケージをアンインストールしています..."
    
    # パッケージの削除
    apt-get purge -y squid apache2 nodejs npm sqlite3 || {
        log_warn "パッケージの削除に失敗しました"
        return 1
    }
    
    # 不要な依存関係の削除
    apt-get autoremove -y || log_warn "不要な依存関係の削除に失敗しました"
    
    log_info "パッケージのアンインストールが完了しました"
}

# メイン実行関数
main() {
    show_logo
    
    echo -e "${YELLOW}警告:${NC} このスクリプトはYouTube専用プロキシサーバーをシステムから完全に削除します。"
    echo -e "この操作は${RED}元に戻せません${NC}。"
    echo
    
    if ! confirm "YouTube専用プロキシサーバーを削除しますか？"; then
        log_info "アンインストールがキャンセルされました。"
        exit 0
    fi
    
    # パッケージも削除するか確認
    remove_packages=false
    if confirm "インストールされたパッケージ(squid, apache2, nodejs, npm, sqlite3)も削除しますか？"; then
        remove_packages=true
    fi
    
    # サービスの停止
    stop_services
    
    # ファイルとディレクトリの削除
    remove_files
    
    # ファイアウォール設定の削除
    remove_firewall_rules
    
    # ユーザー設定の削除
    remove_user_settings
    
    # パッケージのアンインストール（選択した場合のみ）
    if [ "$remove_packages" = true ]; then
        uninstall_packages
    else
        log_info "パッケージは保持されます"
    fi
    
    log_info "アンインストールが完了しました！"
    echo
    echo -e "${GREEN}YouTube専用プロキシサーバーが正常に削除されました。${NC}"
    echo -e "システムから全ての関連コンポーネントが削除されました。"
}

# スクリプト実行
main "$@"