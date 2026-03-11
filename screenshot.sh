#!/bin/bash
# =============================================================
# Mac スクリーンショット → iPhone 写真 自動同期セットアップ
# =============================================================
# このスクリプトを一度実行するだけで、以降は普段通り ⌘⇧3 / ⌘⇧4 / ⌘⇧5 で
# スクショを撮るだけで自動的にiPhoneの写真に同期されます。
#
# 仕組み:
#   1. macOSのスクショ保存先をiCloud Drive内に変更
#   2. launchd (WatchPaths) でフォルダを監視
#   3. 新しい画像が保存されると写真アプリに自動インポート
#
# セットアップ:
#   chmod +x screenshot.sh
#   ./screenshot.sh setup
#
# セットアップ解除:
#   ./screenshot.sh unsetup
# =============================================================

ICLOUD_SCREENSHOTS="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Screenshots"
IMPORT_SCRIPT="$HOME/.local/bin/import-screenshot-to-photos.sh"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.user.screenshot-to-photos.plist"
IMPORTED_LOG="$HOME/.local/share/screenshot-imports.log"

setup() {
    echo "=== スクリーンショット → iPhone 写真 自動同期セットアップ ==="
    echo ""

    # 1. iCloud Drive内にスクショフォルダを作成
    echo "1/4 iCloud Drive内にスクショフォルダを作成..."
    mkdir -p "$ICLOUD_SCREENSHOTS"
    echo "     → $ICLOUD_SCREENSHOTS"

    # 2. macOSのスクショ保存先を変更
    echo "2/4 macOSのスクショ保存先を変更..."
    defaults write com.apple.screencapture location "$ICLOUD_SCREENSHOTS"
    killall SystemUIServer 2>/dev/null
    echo "     → スクショ保存先をiCloud Driveに変更しました"

    # 3. インポートスクリプトを作成
    echo "3/4 インポートスクリプトを作成..."
    mkdir -p "$(dirname "$IMPORT_SCRIPT")"
    mkdir -p "$(dirname "$IMPORTED_LOG")"
    touch "$IMPORTED_LOG"

    cat > "$IMPORT_SCRIPT" << 'SCRIPT'
#!/bin/bash
# スクショフォルダ内の新しい画像をクリップボードにコピー＆写真アプリにインポート
SCREENSHOT_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Screenshots"
LOG_FILE="$HOME/.local/share/screenshot-imports.log"

sleep 3

newest=""
newest_time=0

for file in "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg "$SCREENSHOT_DIR"/*.jpeg; do
    [ -f "$file" ] || continue

    if grep -qxF "$file" "$LOG_FILE" 2>/dev/null; then
        continue
    fi

    # 最新ファイルを特定
    file_time=$(stat -f %m "$file" 2>/dev/null || echo 0)
    if [ "$file_time" -gt "$newest_time" ]; then
        newest="$file"
        newest_time="$file_time"
    fi

    # 写真アプリにインポート
    osascript -e "
        tell application \"Photos\"
            activate
            delay 1
            import POSIX file \"$file\"
        end tell
    " 2>&1

    if [ $? -eq 0 ]; then
        echo "$file" >> "$LOG_FILE"
        echo "$(date): Imported $file"
    else
        echo "$(date): FAILED to import $file"
    fi
done

# 最新のスクショをクリップボードにコピー
if [ -n "$newest" ]; then
    osascript -e "set the clipboard to (read (POSIX file \"$newest\") as «class PNGf»)" 2>&1
    echo "$(date): Copied to clipboard: $newest"
fi
SCRIPT
    chmod +x "$IMPORT_SCRIPT"
    echo "     → $IMPORT_SCRIPT"

    # 4. launchd エージェントを作成・登録
    echo "4/4 launchd エージェント（フォルダ監視）を登録..."

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
    echo "これで普段通り ⌘⇧3 / ⌘⇧4 / ⌘⇧5 でスクショを撮ると:"
    echo "  1. iCloud Drive/Screenshots に保存"
    echo "  2. 5秒ごとに新しいスクショを自動検知"
    echo "  3. クリップボードにコピー＋写真アプリにインポート → iPhoneに同期"
    echo ""
    echo "※ iCloud写真がオンになっていることを確認してください"
    echo "  (設定 → Apple ID → iCloud → 写真)"
    echo ""
    echo "テスト: スクショを撮って数秒待ち、写真アプリを確認してください"
    echo "ログ: cat /tmp/screenshot-to-photos.log"
}

unsetup() {
    echo "=== セットアップ解除 ==="

    # launchd エージェントをアンロード・削除
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
    rm -f "$LAUNCHD_PLIST"
    echo "✔ launchd エージェントを削除しました"

    # スクショ保存先をデフォルト(デスクトップ)に戻す
    defaults write com.apple.screencapture location "$HOME/Desktop"
    killall SystemUIServer 2>/dev/null
    echo "✔ スクショ保存先をデスクトップに戻しました"

    # インポートスクリプトを削除
    rm -f "$IMPORT_SCRIPT"
    echo "✔ インポートスクリプトを削除しました"

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="

    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    if launchctl list | grep -q "com.user.screenshot-to-photos"; then
        echo "launchd監視: ✔ 実行中"
    else
        echo "launchd監視: ✗ 停止中"
    fi

    if [ -f "$IMPORTED_LOG" ]; then
        local count
        count=$(wc -l < "$IMPORTED_LOG" | tr -d ' ')
        echo "インポート済み: ${count}枚"
    fi

    if [ -f /tmp/screenshot-to-photos.err ]; then
        local errors
        errors=$(cat /tmp/screenshot-to-photos.err)
        if [ -n "$errors" ]; then
            echo ""
            echo "--- エラーログ ---"
            tail -5 /tmp/screenshot-to-photos.err
        fi
    fi
}

# メイン処理
case "${1:-status}" in
    setup)
        setup
        ;;
    unsetup)
        unsetup
        ;;
    status)
        status
        ;;
    *)
        echo "使い方:"
        echo "  ./screenshot.sh setup    → セットアップ（初回のみ）"
        echo "  ./screenshot.sh unsetup  → セットアップ解除"
        echo "  ./screenshot.sh status   → 現在の設定確認"
        ;;
esac
