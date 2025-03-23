#!/bin/bash

# check-proxy-status.sh
# YouTube専用プロキシサーバー状態確認スクリプト
# 用途: プロキシサーバーとWebアプリの動作状態を確認し、ログとして出力
# 作成日: 2025-03-23

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日時を取得
DATE=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M:%S')
DATETIME="${DATE}_${TIME}"

# ログファイルパス
LOG_DIR="/home/nishio/youtube-proxy/logs"
LOG_FILE="${LOG_DIR}/status_check_${DATETIME}.log"

# ロゴ表示
show_logo() {
    echo -e "${BLUE}"
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo "┃  YouTube Selective Proxy - Status Check              ┃"
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    echo -e "${NC}"
}

# ヘルパー関数: ログ出力（画面と同時にログファイルへも書き込み）
log_to_file() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARNING]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "${message}" | tee -a "$LOG_FILE"
            ;;
    esac
}

# ログディレクトリが存在しない場合は作成
ensure_log_directory() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" || {
            echo -e "${RED}[ERROR]${NC} ログディレクトリの作成に失敗しました。"
            exit 1
        }
        chmod 755 "$LOG_DIR"
    fi
}

# ヘッダー情報をログに記録
write_log_header() {
    {
        echo "======================================================"
        echo "YouTube専用プロキシサーバー状態確認レポート"
        echo "実行日時: ${DATE} ${TIME}"
        echo "ホスト名: $(hostname)"
        echo "IPアドレス: $(hostname -I | awk '{print $1}')"
        echo "======================================================"
        echo ""
    } >> "$LOG_FILE"
}

# サービス状態の確認関数
check_service_status() {
    local service_name="$1"
    local service_description="$2"
    
    log_to_file "" "サービスチェック: ${service_description} (${service_name})"
    
    # サービスの存在確認
    if ! systemctl list-unit-files | grep -q "$service_name"; then
        log_to_file "ERROR" "${service_description}のサービス定義が見つかりません。"
        return 1
    fi
    
    # 状態確認
    local service_status=$(systemctl is-active "$service_name")
    local service_enabled=$(systemctl is-enabled "$service_name" 2>/dev/null || echo "無効")
    local service_uptime=$(systemctl show "$service_name" -p ActiveEnterTimestamp | sed 's/ActiveEnterTimestamp=//')
    
    # 開始時間をより人間が読める形式に変換
    if [ -n "$service_uptime" ] && [ "$service_uptime" != "n/a" ]; then
        service_uptime=$(date -d "$service_uptime" '+%Y-%m-%d %H:%M:%S')
    fi
    
    # メモリ使用量の取得
    local memory_usage=$(ps -o pid,rss,command -p $(systemctl show "$service_name" -p MainPID | sed 's/MainPID=//') 2>/dev/null | tail -n 1 | awk '{print $2}')
    if [ -n "$memory_usage" ] && [ "$memory_usage" != "RSS" ]; then
        memory_usage="$(echo "scale=2; $memory_usage / 1024" | bc) MB"
    else
        memory_usage="取得できません"
    fi
    
    # 詳細情報をログに記録
    {
        echo "--- ${service_name}の詳細情報 ---"
        echo "状態: ${service_status}"
        echo "自動起動: ${service_enabled}"
        echo "起動時刻: ${service_uptime}"
        echo "メモリ使用量: ${memory_usage}"
        echo ""
        echo "--- systemctlステータス出力 ---"
        systemctl status "$service_name" --no-pager
        echo ""
    } >> "$LOG_FILE"
    
    if [ "$service_status" = "active" ]; then
        log_to_file "INFO" "${service_description}は正常に実行中です。起動時刻: ${service_uptime}, メモリ: ${memory_usage}"
        return 0
    else
        log_to_file "ERROR" "${service_description}が実行されていません。状態: ${service_status}"
        
        # サービスの詳細情報を取得してログに記録
        {
            echo "--- ${service_name}の最近のログ ---"
            journalctl -u "$service_name" --no-pager -n 50
            echo ""
            
            # 依存関係のチェック
            echo "--- 依存サービスの状態 ---"
            systemctl list-dependencies "$service_name" --no-pager
            echo ""
        } >> "$LOG_FILE"
        
        return 1
    fi
}

# ネットワークポートとコネクションの確認関数
check_network_connections() {
    log_to_file "" "ネットワーク接続状態チェック"
    
    # ポートのリスニング状態を確認
    {
        echo "--- ネットワークリスニングポート一覧 ---"
        ss -tulpn
        echo ""
    } >> "$LOG_FILE"
    
    # 主要ポートをチェック
    local ports=("3128:Squidプロキシ" "80:HTTPサーバー" "443:HTTPSサーバー" "8080:YouTubeプロキシWebアプリ")
    
    for port_info in "${ports[@]}"; do
        local port=$(echo "$port_info" | cut -d':' -f1)
        local service_name=$(echo "$port_info" | cut -d':' -f2)
        
        if ss -tulpn | grep ":${port}" > /dev/null; then
            log_to_file "INFO" "${service_name}はポート${port}で正常にリッスンしています。"
            
            # ポートに関連するプロセス情報
            {
                echo "--- ${port}番ポートのプロセス情報 ---"
                lsof -i:${port} 2>/dev/null || echo "lsofコマンドがインストールされていないか、情報が取得できません。"
                echo ""
            } >> "$LOG_FILE"
            
            # アクティブな接続数を確認
            local connection_count=$(ss -ant | grep ":${port}" | wc -l)
            log_to_file "INFO" "${service_name}(ポート${port})への接続数: ${connection_count}"
        else
            log_to_file "ERROR" "${service_name}はポート${port}でリッスンしていません。"
        fi
    done
    
    # 現在のネットワーク接続状態
    {
        echo "--- アクティブなネットワーク接続TOP20 ---"
        ss -tan | head -n 21
        echo ""
        
        echo "--- ネットワークインターフェース状態 ---"
        ip addr
        echo ""
        
        echo "--- ネットワークルーティングテーブル ---"
        ip route
        echo ""
    } >> "$LOG_FILE"
}

# システムリソースの確認
check_system_resources() {
    log_to_file "" "システムリソースチェック"
    
    # ディスク使用量の確認
    local partitions=("/" "/home" "/var")
    local threshold=90
    
    {
        echo "--- ディスク使用量 ---"
        df -h | head -n 1
        
        for partition in "${partitions[@]}"; do
            if df -h "$partition" &>/dev/null; then
                df -h "$partition" | grep -v "Filesystem"
                
                local usage=$(df -h "$partition" | grep -v Filesystem | awk '{print $5}' | sed 's/%//')
                
                if [ "$usage" -gt "$threshold" ]; then
                    log_to_file "WARN" "${partition}のディスク使用量が${usage}%で、閾値(${threshold}%)を超えています。"
                else
                    log_to_file "INFO" "${partition}のディスク使用量は${usage}%です。"
                fi
            fi
        done
        echo ""
    } >> "$LOG_FILE"
    
    # メモリ使用状況
    {
        echo "--- メモリ使用状況 ---"
        free -h
        echo ""
        
        local total_mem=$(free | grep "Mem:" | awk '{print $2}')
        local used_mem=$(free | grep "Mem:" | awk '{print $3}')
        local usage_percent=$((used_mem * 100 / total_mem))
        
        if [ "$usage_percent" -gt 90 ]; then
            log_to_file "WARN" "メモリ使用量が${usage_percent}%で、高負荷状態です。"
        else
            log_to_file "INFO" "メモリ使用量は${usage_percent}%です。"
        fi
    } >> "$LOG_FILE"
    
    # CPU使用状況
    {
        echo "--- CPU使用状況 ---"
        top -bn1 | head -n 10
        echo ""
        
        # ロードアベレージの確認
        local load=$(uptime | awk -F'[a-z]:' '{ print $2}' | awk '{print $1}' | sed 's/,//')
        local cpu_cores=$(grep -c processor /proc/cpuinfo)
        
        # ロードがコア数を超えているか確認
        if (( $(echo "$load > $cpu_cores" | bc -l) )); then
            log_to_file "WARN" "CPU負荷が高いです。ロードアベレージ: ${load}, CPUコア数: ${cpu_cores}"
        else
            log_to_file "INFO" "CPU負荷は正常です。ロードアベレージ: ${load}, CPUコア数: ${cpu_cores}"
        fi
    } >> "$LOG_FILE"
    
    # システムアップタイム
    {
        echo "--- システム稼働時間 ---"
        uptime
        echo ""
    } >> "$LOG_FILE"
    
    # プロセスリソース使用量TOP5
    {
        echo "--- リソース使用量の多いプロセスTOP5 ---"
        echo "メモリ使用量TOP5:"
        ps aux --sort=-%mem | head -n 6
        echo ""
        echo "CPU使用量TOP5:"
        ps aux --sort=-%cpu | head -n 6
        echo ""
    } >> "$LOG_FILE"
}

# Squidログファイルの確認
check_squid_logs() {
    local log_file="/var/log/squid/access.log"
    local cache_log="/var/log/squid/cache.log"
    
    if [ -f "$log_file" ]; then
        local last_modified=$(stat -c %Y "$log_file")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_modified))
        
        # 最新の10件のアクセスログを取得
        local recent_logs=$(tail -n 10 "$log_file")
        
        # エラーステータスコードのカウント
        local error_count=$(echo "$recent_logs" | grep -c -E "TCP_DENIED|TCP_MISS/4[0-9][0-9]")
        
        log_to_file "INFO" "Squidアクセスログの最終更新は$(date -d @$last_modified '+%Y-%m-%d %H:%M:%S')です。"
        
        if [ "$error_count" -gt 0 ]; then
            log_to_file "WARN" "最近のアクセスログに${error_count}件のエラーまたはブロック記録があります。"
        fi
        
        # ログサンプルをファイルに追加
        {
            echo "--- Squidアクセスログサンプル(最新10件) ---"
            echo "$recent_logs"
            echo ""
            
            # アクセス統計の追加
            echo "--- アクセス統計 ---"
            echo "過去24時間のリクエスト総数: $(grep -c "$(date -d "24 hours ago" "+%Y/%m/%d")" "$log_file")"
            echo "拒否されたリクエスト数: $(grep -c "TCP_DENIED" "$log_file")"
            echo "許可されたリクエスト数: $(grep -c "TCP_MISS/200" "$log_file")"
            echo ""
            
            # キャッシュログも確認
            if [ -f "$cache_log" ]; then
                echo "--- Squidキャッシュログ(最新10件のエラーまたは警告) ---"
                grep -E "WARNING|ERROR|CRITICAL" "$cache_log" | tail -n 10
                echo ""
            fi
        } >> "$LOG_FILE"
    else
        log_to_file "WARN" "Squidアクセスログファイルが見つかりません。"
    fi
}

# Webアプリケーションへの接続テスト
test_webapp_connection() {
    local server_ip=$(hostname -I | awk '{print $1}')
    local webapp_url="http://${server_ip}/youtube-proxy"
    local temp_response="/tmp/webapp_response.tmp"
    
    # curlコマンドがインストールされているか確認
    if ! command -v curl &> /dev/null; then
        log_to_file "WARN" "curlコマンドがインストールされていないため、Webアプリ接続テストをスキップします。"
        return
    fi
    
    log_to_file "INFO" "Webアプリケーション(${webapp_url})への接続をテストしています..."
    
    # レスポンスを取得して一時ファイルに保存
    curl -s -o "$temp_response" -w "%{http_code}|%{time_total}|%{size_download}" "$webapp_url" > /tmp/curl_stats.txt 2>/dev/null
    
    local curl_stats=$(cat /tmp/curl_stats.txt)
    local http_code=$(echo "$curl_stats" | cut -d'|' -f1)
    local response_time=$(echo "$curl_stats" | cut -d'|' -f2)
    local response_size=$(echo "$curl_stats" | cut -d'|' -f3)
    
    # レスポンスの詳細をログに記録
    {
        echo "--- Webアプリ接続テスト詳細 ---"
        echo "URL: ${webapp_url}"
        echo "HTTPステータスコード: ${http_code}"
        echo "応答時間: ${response_time} 秒"
        echo "レスポンスサイズ: ${response_size} バイト"
        
        if [ -f "$temp_response" ]; then
            echo "レスポンスにHTMLフォームが含まれているか: $(grep -c "<form" "$temp_response")"
            echo "ページタイトル: $(grep -o "<title>[^<]*</title>" "$temp_response" | sed 's/<title>//;s/<\/title>//')"
            
            # HTMLの基本構造をチェック
            if grep -q "<html" "$temp_response" && grep -q "</html>" "$temp_response"; then
                echo "HTML構造: 正常"
            else
                echo "HTML構造: 不完全または異常"
            fi
        fi
        echo ""
    } >> "$LOG_FILE"
    
    if [ "$http_code" = "200" ]; then
        log_to_file "INFO" "Webアプリケーションに正常に接続できました。応答時間: ${response_time}秒"
    else
        log_to_file "ERROR" "Webアプリケーションへの接続に失敗しました。HTTPステータスコード: ${http_code}"
        
        # エラーの場合、Apacheエラーログも確認
        {
            echo "--- 関連するApacheエラーログ ---"
            tail -n 20 /var/log/apache2/error.log
            echo ""
        } >> "$LOG_FILE"
    fi
    
    # 一時ファイルを削除
    rm -f "$temp_response" /tmp/curl_stats.txt
}

# ホワイトリストファイルの確認
check_whitelist_file() {
    local whitelist_file="/home/nishio/youtube-proxy/config/youtube_whitelist.txt"
    
    if [ -f "$whitelist_file" ]; then
        local entry_count=$(wc -l < "$whitelist_file")
        local last_modified=$(stat -c %y "$whitelist_file")
        
        log_to_file "INFO" "YouTubeホワイトリストには${entry_count}件のエントリがあります。"
        log_to_file "INFO" "ホワイトリスト最終更新日時: ${last_modified}"
        
        # アクセス権の確認
        local file_perms=$(stat -c %a "$whitelist_file")
        if [ "$file_perms" != "664" ]; then
            log_to_file "WARN" "ホワイトリストファイルのパーミッションが推奨値と異なります (${file_perms})。推奨: 664"
        fi
        
        local file_owner=$(stat -c %U:%G "$whitelist_file")
        if [ "$file_owner" != "proxy:proxy" ]; then
            log_to_file "WARN" "ホワイトリストファイルの所有者が推奨と異なります (${file_owner})。推奨: proxy:proxy"
        fi
    else
        log_to_file "ERROR" "YouTubeホワイトリストファイルが見つかりません。"
    fi
}

# サマリー生成関数
generate_summary() {
    local success_count=0
    local warning_count=$(grep -c "\[WARNING\]" "$LOG_FILE")
    local error_count=$(grep -c "\[ERROR\]" "$LOG_FILE")
    
    # サマリーをログに追加
    {
        echo ""
        echo "======================================================"
        echo "状態確認サマリー"
        echo "======================================================"
        echo "正常: ${success_count}"
        echo "警告: ${warning_count}"
        echo "エラー: ${error_count}"
        echo ""
        
        if [ "$error_count" -gt 0 ]; then
            echo "※ エラーがあります。システム管理者に連絡してください。"
        elif [ "$warning_count" -gt 0 ]; then
            echo "※ 警告があります。注意が必要かもしれません。"
        else
            echo "すべてのサービスが正常に動作しています。"
        fi
        echo "======================================================"
    } >> "$LOG_FILE"
    
    # サマリーを画面にも表示
    if [ "$error_count" -gt 0 ]; then
        echo -e "\n${RED}チェック完了: エラー ${error_count}件, 警告 ${warning_count}件, 正常 ${success_count}件${NC}"
        echo -e "${RED}システムに問題があります。ログファイルを確認してください:${NC} $LOG_FILE"
    elif [ "$warning_count" -gt 0 ]; then
        echo -e "\n${YELLOW}チェック完了: エラー ${error_count}件, 警告 ${warning_count}件, 正常 ${success_count}件${NC}"
        echo -e "${YELLOW}いくつかの警告があります。ログファイルを確認してください:${NC} $LOG_FILE"
    else
        echo -e "\n${GREEN}チェック完了: エラー ${error_count}件, 警告 ${warning_count}件, 正常 ${success_count}件${NC}"
        echo -e "${GREEN}すべてのサービスが正常に動作しています。${NC}"
    fi
    
    echo -e "詳細ログファイル: ${LOG_FILE}"
}

# YouTubeプロキシWebアプリの設定ファイル確認
check_webapp_config() {
    log_to_file "" "== Webアプリケーション設定確認 =="
    
    local config_dir="/home/nishio/youtube-proxy/html/config"
    local config_file="${config_dir}/config.json"
    
    if [ -f "$config_file" ]; then
        log_to_file "INFO" "Webアプリケーション設定ファイルが存在します: ${config_file}"
        
        # 設定ファイルの内容を確認（機密情報を除く）
        {
            echo "--- Webアプリケーション設定 ---"
            # jqがインストールされている場合は整形して表示
            if command -v jq &> /dev/null; then
                cat "$config_file" | jq 'del(.apiKeys, .credentials, .secrets)' 2>/dev/null || cat "$config_file"
            else
                grep -v "apiKey\|password\|secret\|credential" "$config_file" || cat "$config_file"
            fi
            echo ""
            
            # 設定ファイルのパーミッションチェック
            echo "設定ファイルのパーミッション: $(stat -c '%a %U:%G' "$config_file")"
            
            # 最終更新日時
            echo "最終更新日時: $(stat -c '%y' "$config_file")"
            echo ""
        } >> "$LOG_FILE"
    else
        log_to_file "ERROR" "Webアプリケーション設定ファイルが見つかりません: ${config_file}"
    fi
    
    # package.jsonの確認
    local package_file="/home/nishio/youtube-proxy/html/package.json"
    if [ -f "$package_file" ]; then
        {
            echo "--- パッケージ情報 ---"
            grep -A 5 "\"dependencies\"" "$package_file"
            echo ""
            
            # アプリケーションバージョン
            echo "アプリケーションバージョン: $(grep -o "\"version\": \"[^\"]*\"" "$package_file" | cut -d'"' -f4)"
            echo ""
        } >> "$LOG_FILE"
    fi
}

# プロキシアクセス統計の生成
generate_proxy_stats() {
    log_to_file "" "== プロキシアクセス統計 =="
    
    local log_file="/var/log/squid/access.log"
    
    if [ -f "$log_file" ]; then
        # 統計計算
        {
            echo "--- 時間帯別アクセス数 ---"
            echo "時間帯,リクエスト数"
            for hour in {0..23}; do
                hour_fmt=$(printf "%02d" $hour)
                count=$(grep " ${hour_fmt}:" "$log_file" | wc -l)
                echo "${hour_fmt}:00-${hour_fmt}:59,${count}"
            done
            echo ""
            
            echo "--- ドメイン別アクセス数TOP10 ---"
            grep -oE "http[s]?://[^/]*" "$log_file" | sort | uniq -c | sort -nr | head -n 10
            echo ""
            
            echo "--- クライアントIP別アクセス数TOP10 ---"
            awk '{print $3}' "$log_file" | sort | uniq -c | sort -nr | head -n 10
            echo ""
            
            echo "--- HTTPステータスコード分布 ---"
            grep -o "TCP_[^/]*/[0-9][0-9][0-9]" "$log_file" | sort | uniq -c | sort -nr
            echo ""
        } >> "$LOG_FILE"
        
        # 統計サマリー
        local total_requests=$(wc -l < "$log_file")
        local blocked_requests=$(grep -c "TCP_DENIED" "$log_file")
        local youtube_requests=$(grep -c "youtube.com" "$log_file")
        
        log_to_file "INFO" "プロキシ総リクエスト数: ${total_requests}, ブロック数: ${blocked_requests}, YouTube関連: ${youtube_requests}"
    else
        log_to_file "WARN" "Squidアクセスログファイルが見つからないため、統計を生成できません。"
    fi
}

# メイン関数
main() {
    # root権限チェック
    if [ "$(id -u)" -ne 0 ]; then
        echo "このスクリプトはroot権限で実行する必要があります。"
        echo "sudo $0 を実行してください。"
        exit 1
    fi
    
    show_logo
    
    # ログディレクトリを確保
    ensure_log_directory
    
    # ログヘッダーを書き込み
    write_log_header
    
    # 詳細な環境情報を記録
    {
        echo "======================================================"
        echo "システム環境情報"
        echo "======================================================"
        echo "ホスト名: $(hostname)"
        echo "OS情報: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo "カーネルバージョン: $(uname -r)"
        echo "IPアドレス: $(hostname -I)"
        echo "実行ユーザー: $(whoami)"
        echo "チェック実行日時: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================================" 
        echo ""
    } >> "$LOG_FILE"
    
    # サービス状態チェック
    log_to_file "" "== サービス状態チェック =="
    check_service_status "squid" "Squidプロキシサーバー"
    check_service_status "apache2" "Webサーバー\(Apache\)"
    check_service_status "youtube-proxy" "YouTubeプロキシWebアプリケーション"
    
    # ネットワークポートとコネクションチェック
    check_network_connections
    
    # システムリソースチェック
    check_system_resources
    
    # Squidログ確認
    log_to_file "" "== Squidログ分析 =="
    check_squid_logs
    
    # ホワイトリストファイル確認
    log_to_file "" "== ホワイトリスト設定確認 =="
    check_whitelist_file
    
    # Webアプリケーション設定確認
    check_webapp_config
    
    # Webアプリ接続テスト
    log_to_file "" "== Webアプリケーション接続テスト =="
    test_webapp_connection
    
    # プロキシアクセス統計
    generate_proxy_stats
    
    # サマリー生成
    generate_summary
}

# スクリプト実行
main