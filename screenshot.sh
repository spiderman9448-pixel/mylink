#!/bin/bash
# =============================================================
# Mac スクリーンショット自動化スクリプト
# =============================================================
# 使い方:
#   ./screenshot.sh              → 全画面スクショ＋クリップボードにコピー
#   ./screenshot.sh area         → 範囲選択スクショ＋クリップボードにコピー
#   ./screenshot.sh window       → ウィンドウ選択スクショ＋クリップボードにコピー
#   ./screenshot.sh loop 5       → 5秒間隔で全画面スクショを繰り返し撮影
#   ./screenshot.sh loop 5 area  → 5秒間隔で範囲選択スクショを繰り返し撮影
#
# オプション:
#   SAVE_DIR 環境変数でスクショの保存先を変更可能
#     例: SAVE_DIR=~/Pictures ./screenshot.sh
#
# iCloud連携:
#   デフォルトでiCloud Drive内に保存 + 写真アプリにインポートされます
#   iCloud Photosが有効なら、iPhoneの写真にも自動同期されます
# =============================================================

# 保存先ディレクトリ（デフォルト: iCloud Driveのスクリーンショットフォルダ）
ICLOUD_SCREENSHOTS="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Screenshots"
SAVE_DIR="${SAVE_DIR:-$ICLOUD_SCREENSHOTS}"
mkdir -p "$SAVE_DIR"

# タイムスタンプ付きファイル名を生成
generate_filename() {
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    echo "${SAVE_DIR}/screenshot_${timestamp}.png"
}

# スクリーンショットを撮影してクリップボードにコピー
take_screenshot() {
    local mode="$1"
    local filepath
    filepath=$(generate_filename)

    case "$mode" in
        area)
            echo "範囲を選択してください..."
            screencapture -i "$filepath"
            ;;
        window)
            echo "ウィンドウをクリックしてください..."
            screencapture -iW "$filepath"
            ;;
        *)
            # 全画面
            screencapture "$filepath"
            ;;
    esac

    # screencapture がキャンセルされた場合（ファイルが作成されない）
    if [ ! -f "$filepath" ]; then
        echo "スクリーンショットがキャンセルされました"
        return 1
    fi

    # クリップボードにコピー
    osascript -e "set the clipboard to (read (POSIX file \"$filepath\") as «class PNGf»)"

    # 写真アプリにインポート（iCloud Photos経由でiPhoneにも同期される）
    osascript -e "
        tell application \"Photos\"
            import POSIX file \"$filepath\"
        end tell
    " 2>/dev/null && echo "✔ 写真アプリにインポートしました（iPhoneに同期されます）" \
                  || echo "⚠ 写真アプリへのインポートに失敗しました（iCloud Driveには保存済み）"

    echo "✔ 保存: $filepath"
    echo "✔ クリップボードにコピーしました"
    return 0
}

# メイン処理
main() {
    local command="${1:-full}"

    case "$command" in
        area)
            take_screenshot "area"
            ;;
        window)
            take_screenshot "window"
            ;;
        loop)
            local interval="${2:-10}"
            local mode="${3:-full}"
            echo "=== 定期スクリーンショット開始 ==="
            echo "間隔: ${interval}秒 | モード: ${mode}"
            echo "停止するには Ctrl+C を押してください"
            echo ""
            while true; do
                take_screenshot "$mode"
                sleep "$interval"
            done
            ;;
        full|*)
            take_screenshot "full"
            ;;
    esac
}

main "$@"
