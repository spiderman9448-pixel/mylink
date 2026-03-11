#!/bin/bash
# =============================================================
# Mac スクリーンショット → iPhone 写真 自動同期セットアップ
# =============================================================
# スクショの保存先は変更しません（既存の設定をそのまま使用）
# デスクトップ上の新しいスクショを検知して写真アプリにインポートします
#
# セットアップ:
#   chmod +x screenshot.sh
#   ./screenshot.sh setup
#
# セットアップ解除:
#   ./screenshot.sh unsetup
# =============================================================

IMPORT_SCRIPT="$HOME/.local/bin/import-screenshot-to-photos.sh"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.user.screenshot-to-photos.plist"
IMPORTED_LOG="$HOME/.local/share/screenshot-imports.log"

setup() {
    echo "=== スクリーンショット → iPhone 写真 自動同期セットアップ ==="
    echo ""

    # スクショ保存先を取得
    local screenshot_dir
    screenshot_dir=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
    # チルダを展開
    screenshot_dir="${screenshot_dir/#\~/$HOME}"

    echo "1/3 スクショ保存先を確認..."
    echo "     → $screenshot_dir"
    mkdir -p "$screenshot_dir"

    # 2. インポートスクリプトを作成
    echo "2/3 インポートスクリプトを作成..."
    mkdir -p "$(dirname "$IMPORT_SCRIPT")"
    mkdir -p "$(dirname "$IMPORTED_LOG")"
    touch "$IMPORTED_LOG"

    cat > "$IMPORT_SCRIPT" << SCRIPT
#!/bin/bash
# デスクトップの新しいスクショを写真アプリにインポート
SCREENSHOT_DIR="$screenshot_dir"
LOG_FILE="$IMPORTED_LOG"

for file in "\$SCREENSHOT_DIR"/*.png "\$SCREENSHOT_DIR"/*.jpg "\$SCREENSHOT_DIR"/*.jpeg; do
    [ -f "\$file" ] || continue

    if grep -qxF "\$file" "\$LOG_FILE" 2>/dev/null; then
        continue
    fi

    echo "\$(date): Found new screenshot: \$file"

    # クリップボードにコピー（⌘V で貼り付け可能に）
    CLIP_TYPE="PNGf"
    case "\$file" in
        *.jpg|*.jpeg|*.JPG|*.JPEG) CLIP_TYPE="JPEG" ;;
    esac
    printf 'set the clipboard to (read (POSIX file "%s") as \xC2\xABclass %s\xC2\xBB)\n' "\$file" "\$CLIP_TYPE" | osascript 2>&1
    if [ \$? -eq 0 ]; then
        echo "\$(date): Copied to clipboard: \$file"
    else
        echo "\$(date): Clipboard copy failed: \$file"
    fi

    # 写真アプリにインポート
    osascript -e "
        tell application \"Photos\"
            import POSIX file \"\$file\"
        end tell
    " 2>&1

    if [ \$? -eq 0 ]; then
        echo "\$file" >> "\$LOG_FILE"
        echo "\$(date): Imported \$file"
    else
        echo "\$(date): FAILED to import \$file"
    fi
done
SCRIPT
    chmod +x "$IMPORT_SCRIPT"
    echo "     → $IMPORT_SCRIPT"

    # 3. launchd エージェントを作成・登録
    echo "3/3 launchd エージェント（5秒ポーリング）を登録..."

    # 既存のエージェントがあればアンロード
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null

    cat > "$LAUNCHD_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.screenshot-to-photos</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$IMPORT_SCRIPT</string>
    </array>
    <key>StartInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>/tmp/screenshot-to-photos.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/screenshot-to-photos.err</string>
</dict>
</plist>
PLIST

    launchctl load "$LAUNCHD_PLIST"
    if [ $? -eq 0 ]; then
        echo "     → launchd エージェントを登録しました"
    else
        echo "     ⚠ launchd の登録に失敗しました"
        return 1
    fi

    echo ""
    echo "=== セットアップ完了 ==="
    echo "⌘⇧3 / ⌘⇧4 / ⌘⇧5 でスクショを撮ると:"
    echo "  1. 通常通り $screenshot_dir に保存"
    echo "  2. 5秒以内に自動検知"
    echo "  3. クリップボードに自動コピー（⌘V で貼り付け可能）"
    echo "  4. 写真アプリにインポート → iPhoneに同期"
    echo ""
    echo "※ スクショ保存先は変更しません"
    echo "※ iCloud写真がオンになっていることを確認してください"
    echo ""
    echo "ログ: cat /tmp/screenshot-to-photos.log"
}

unsetup() {
    echo "=== セットアップ解除 ==="

    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
    rm -f "$LAUNCHD_PLIST"
    echo "  launchd エージェントを削除しました"

    rm -f "$IMPORT_SCRIPT"
    echo "  インポートスクリプトを削除しました"

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="

    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    if launchctl list | grep -q "com.user.screenshot-to-photos"; then
        echo "launchd監視: 実行中"
    else
        echo "launchd監視: 停止中"
    fi

    if [ -f "$IMPORTED_LOG" ]; then
        local count
        count=$(wc -l < "$IMPORTED_LOG" | tr -d ' ')
        echo "インポート済み: ${count}枚"
    fi

    echo ""
    echo "--- 最新ログ ---"
    tail -5 /tmp/screenshot-to-photos.log 2>/dev/null || echo "(ログなし)"
    local errors
    errors=$(cat /tmp/screenshot-to-photos.err 2>/dev/null)
    if [ -n "$errors" ]; then
        echo "--- エラー ---"
        tail -5 /tmp/screenshot-to-photos.err
    fi
}

case "${1:-status}" in
    setup)   setup ;;
    unsetup) unsetup ;;
    status)  status ;;
    *)
        echo "使い方:"
        echo "  ./screenshot.sh setup    → セットアップ"
        echo "  ./screenshot.sh unsetup  → 解除"
        echo "  ./screenshot.sh status   → 状態確認"
        ;;
esac
