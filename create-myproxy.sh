#!/bin/bash

# create-myproxy.sh
# YouTube専用プロキシサーバー構築スクリプト
# 用途: 特定のYouTube動画IDのみ閲覧可能なプロキシの構築
# 作成日: 2025-03-13

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
    echo "┃  YouTube Selective Proxy - Safe Access Installation   ┃"
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

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件を確認しています..."
    
    # Ubuntuコンテナ確認
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "このスクリプトはUbuntuコンテナでのみ実行できます。"
        exit 1
    fi
    
    # クリエイターユーザーの存在確認
    if ! id "creater" &>/dev/null; then
        log_error "createrユーザーが存在しません。先にユーザーを作成してください。"
        exit 1
    fi
    
    # スクリプトディレクトリの確認
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ ! -d "$SCRIPT_DIR/html" ] || [ ! -d "$SCRIPT_DIR/config" ] || [ ! -d "$SCRIPT_DIR/service" ]; then
        log_error "必要なディレクトリ構造が見つかりません。"
        log_error "スクリプトと同じディレクトリに html, config, service ディレクトリが必要です。"
        exit 1
    fi
    
    log_info "前提条件を満たしています。"
}

# 必要なパッケージのインストール
install_packages() {
    log_info "必要なパッケージをインストールしています..."
    
    # 必要なパッケージをアップデート
    apt-get update -qq || {
        log_error "パッケージリストのアップデートに失敗しました。"
        exit 1
    }
    
    # 必要なパッケージをインストール
    apt-get install -y squid apache2 nodejs npm sqlite3 certbot python3-certbot-apache curl wget build-essential || {
        log_error "パッケージのインストールに失敗しました。"
        exit 1
    }
    
    log_info "パッケージのインストールが完了しました。"
}

# Squidプロキシの設定
configure_squid() {
    log_info "Squidプロキシを設定しています..."
    
    # バックアップ作成
    if [ -f /etc/squid/squid.conf ]; then
        cp /etc/squid/squid.conf /etc/squid/squid.conf.bak
        log_info "既存のSquid設定ファイルをバックアップしました。"
    fi
    
    # 設定ファイルをコピー
    cp "$SCRIPT_DIR/config/squid.conf" /etc/squid/squid.conf || {
        log_error "Squid設定ファイルのコピーに失敗しました。"
        exit 1
    }
    
    # アクセス制御ファイルをコピー
    cp "$SCRIPT_DIR/config/youtube_whitelist.txt" /etc/squid/youtube_whitelist.txt || {
        log_error "ホワイトリストファイルのコピーに失敗しました。"
        exit 1
    }
    
    # パーミッション設定
    chown proxy:proxy /etc/squid/youtube_whitelist.txt
    chmod 644 /etc/squid/youtube_whitelist.txt
    
    # Squidを再起動
    systemctl restart squid || {
        log_error "Squidの再起動に失敗しました。"
        log_error "ログを確認: journalctl -u squid"
        exit 1
    }
    
    # 自動起動を有効化
    systemctl enable squid || {
        log_warn "Squidの自動起動設定に失敗しました。"
    }
    
    log_info "Squidプロキシの設定が完了しました。"
}

# Webアプリケーションのセットアップ
setup_webapp() {
    log_info "Webアプリケーションをセットアップしています..."
    
    # Webアプリディレクトリ作成
    mkdir -p /var/www/youtube-proxy || {
        log_error "Webアプリディレクトリの作成に失敗しました。"
        exit 1
    }
    
    # アプリケーションファイルコピー
    cp -r "$SCRIPT_DIR/html/"* /var/www/youtube-proxy/ || {
        log_error "HTMLファイルのコピーに失敗しました。"
        exit 1
    }
    
    # Nodeアプリケーションのインストール
    cd /var/www/youtube-proxy || {
        log_error "Webアプリディレクトリに移動できません。"
        exit 1
    }
    
    npm install || {
        log_error "Node.jsの依存関係のインストールに失敗しました。"
        exit 1
    }
    
    # サービスファイルをコピー
    cp "$SCRIPT_DIR/service/youtube-proxy.service" /etc/systemd/system/ || {
        log_error "サービスファイルのコピーに失敗しました。"
        exit 1
    }
    
    # サービスを有効化
    systemctl daemon-reload
    systemctl enable youtube-proxy || {
        log_warn "Webアプリサービスの自動起動設定に失敗しました。"
    }
    
    # サービスを開始
    systemctl start youtube-proxy || {
        log_error "Webアプリサービスの開始に失敗しました。"
        log_error "ログを確認: journalctl -u youtube-proxy"
        exit 1
    }
    
    log_info "Webアプリケーションのセットアップが完了しました。"
}

# Apache逆プロキシの設定
configure_apache() {
    log_info "Apache逆プロキシを設定しています..."
    
    # 設定ファイルをコピー
    cp "$SCRIPT_DIR/config/youtube-proxy.conf" /etc/apache2/sites-available/ || {
        log_error "Apache設定ファイルのコピーに失敗しました。"
        exit 1
    }
    
    # モジュールを有効化
    a2enmod proxy proxy_http headers rewrite ssl || {
        log_error "Apacheモジュールの有効化に失敗しました。"
        exit 1
    }
    
    # サイトを有効化
    a2ensite youtube-proxy || {
        log_error "Apache仮想ホストの有効化に失敗しました。"
        exit 1
    }
    
    # Apacheを再起動
    systemctl restart apache2 || {
        log_error "Apacheの再起動に失敗しました。"
        log_error "ログを確認: journalctl -u apache2"
        exit 1
    }
    
    log_info "Apache逆プロキシの設定が完了しました。"
}

# ファイアウォールの設定
setup_firewall() {
    log_info "ファイアウォールを設定しています..."
    
    # UFWがインストールされているか確認
    if ! command -v ufw &> /dev/null; then
        apt-get install -y ufw || {
            log_warn "UFWのインストールに失敗しました。ファイアウォール設定をスキップします。"
            return
        }
    fi
    
    # UFWを有効化
    ufw allow 22/tcp || log_warn "SSH許可ルールの追加に失敗しました。"
    ufw allow 80/tcp || log_warn "HTTP許可ルールの追加に失敗しました。"
    ufw allow 443/tcp || log_warn "HTTPS許可ルールの追加に失敗しました。"
    ufw allow 3128/tcp || log_warn "Squidプロキシ許可ルールの追加に失敗しました。"
    
    # 自動でyesと応答
    echo "y" | ufw enable || {
        log_warn "ファイアウォールの有効化に失敗しました。"
    }
    
    log_info "ファイアウォールの設定が完了しました。"
}

# 接続テスト
test_connectivity() {
    log_info "接続テストを実行しています..."
    
    # Squidプロキシが実行中か確認
    if ! systemctl is-active --quiet squid; then
        log_error "Squidプロキシが実行されていません。"
        exit 1
    fi
    
    # Webアプリケーションが実行中か確認
    if ! systemctl is-active --quiet youtube-proxy; then
        log_error "Webアプリケーションが実行されていません。"
        exit 1
    fi
    
    # Apacheが実行中か確認
    if ! systemctl is-active --quiet apache2; then
        log_error "Apacheが実行されていません。"
        exit 1
    fi
    
    # ネットワーク接続をテスト
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    log_info "接続テストが完了しました。"
    log_info "プロキシサーバーが ${SERVER_IP}:3128 で実行されています。"
    log_info "管理インターフェースが http://${SERVER_IP}/youtube-proxy で利用可能です。"
}

# テストガイド表示
show_test_guide() {
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${BLUE}=== テスト方法 ===${NC}"
    echo -e "1. ブラウザのプロキシ設定で以下を指定:"
    echo -e "   - HTTPプロキシ: ${SERVER_IP}"
    echo -e "   - ポート: 3128"
    echo -e "   - ユーザー名とパスワード: 設定した認証情報"
    echo
    echo -e "2. YouTube (https://www.youtube.com) にアクセスしてみてください。"
    echo -e "   ブロックページが表示されるはずです。"
    echo
    echo -e "3. 特定の動画URLをリクエストするには、ブロックページの申請ボタンを使用します。"
    echo
    echo -e "4. 管理画面は以下でアクセスできます:"
    echo -e "   http://${SERVER_IP}/youtube-proxy"
    echo
    echo -e "5. テストが完了したら q キーを押してください。"
    
    # ユーザーからの入力を待機
    read -n 1 -s -r -p "テストが完了したら q キーを押してください..." key
    
    if [ "$key" = "q" ]; then
        log_info "テストが完了しました。"
    fi
}

# 完了メッセージ表示
show_completion() {
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${GREEN}=== セットアップ完了 ===${NC}"
    echo -e "YouTube選択プロキシが正常にセットアップされました。"
    echo
    echo -e "${YELLOW}プロキシサーバー情報:${NC}"
    echo -e "- プロキシアドレス: ${SERVER_IP}"
    echo -e "- プロキシポート: 3128"
    echo -e "- 管理インターフェース: http://${SERVER_IP}/youtube-proxy"
    echo
    echo -e "${YELLOW}初期認証情報:${NC}"
    echo -e "- ユーザー名: admin"
    echo -e "- パスワード: (設定したパスワード)"
    echo
    echo -e "${YELLOW}ブラウザの設定方法:${NC}"
    echo -e "Chrome: 設定 > 詳細設定 > システム > プロキシ設定を開く > 手動プロキシ設定"
    echo -e "Firefox: 設定 > ネットワーク設定 > 手動でプロキシを設定する"
    echo
    echo -e "${YELLOW}注意:${NC}"
    echo -e "1. プロキシパスワードは安全に保管してください。"
    echo -e "2. 定期的にログをチェックして不審なアクセスがないか確認してください。"
    echo -e "   - Squidログ: /var/log/squid/access.log"
    echo -e "   - アプリログ: journalctl -u youtube-proxy"
    echo
    echo -e "${GREEN}セットアップが正常に完了しました！${NC}"
}

# メイン実行関数
main() {
    show_logo
    
    # 前提条件確認
    check_prerequisites
    
    # インストール前の確認
    if ! confirm "YouTubeセレクティブプロキシのインストールを開始しますか？"; then
        log_info "インストールがキャンセルされました。"
        exit 0
    fi
    
    # 手順実行
    install_packages
    configure_squid
    setup_webapp
    configure_apache
    setup_firewall
    test_connectivity
    
    # テストガイド表示
    show_test_guide
    
    # 完了
    show_completion
}

# スクリプト実行
main
