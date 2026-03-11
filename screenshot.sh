#!/bin/bash
# =============================================================
# Mac スクリーンショット → クリップボード自動コピー & iPhone同期
# =============================================================
# セットアップ:  chmod +x screenshot.sh && ./screenshot.sh setup
# セットアップ解除:  ./screenshot.sh unsetup
# =============================================================

CLIP_WATCHER="$HOME/.local/bin/screenshot-clipboard-watcher.sh"
CLIP_PLIST="$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist"
IMPORT_SCRIPT="$HOME/.local/bin/import-screenshot-to-photos.sh"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.user.screenshot-to-photos.plist"
IMPORTED_LOG="$HOME/.local/share/screenshot-imports.log"

setup() {
    echo "=== スクリーンショット自動コピー & iPhone同期 セットアップ ==="
    echo ""

    local screenshot_dir
    screenshot_dir=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
    screenshot_dir="${screenshot_dir/#\~/$HOME}"

    echo "1/3 スクショ保存先を確認..."
    echo "     → $screenshot_dir"
    mkdir -p "$screenshot_dir"

    # ========== 旧リソースの掃除 ==========
    osascript -e 'tell application "ScreenshotClipboardCopy" to quit' 2>/dev/null
    osascript -e '
        tell application "System Events"
            try
                delete login item "ScreenshotClipboardCopy"
            end try
        end tell
    ' 2>/dev/null
    rm -rf "$HOME/Applications/ScreenshotClipboardCopy.app"
    rm -f "$HOME/.local/bin/copy-image-to-clipboard.js"
    launchctl unload "$CLIP_PLIST" 2>/dev/null
    osascript -e 'tell application "System Events" to try
        delete folder action "Screenshot Clipboard Copy"
    end try' 2>/dev/null
    rm -f "$HOME/Library/Scripts/Folder Action Scripts/Screenshot Clipboard Copy.scpt"
    # 既存のウォッチャーを停止
    pkill -f "screenshot-clipboard-watcher" 2>/dev/null

    # ========== 2. クリップボードウォッチャースクリプト ==========
    echo "2/3 クリップボードウォッチャーを作成..."
    mkdir -p "$(dirname "$CLIP_WATCHER")"

    cat > "$CLIP_WATCHER" << WATCHEOF
#!/bin/bash
# スクリーンショットフォルダを監視し、新しいファイルをクリップボードにコピー
SCREENSHOT_DIR="$screenshot_dir"
LAST_FILE=""

while true; do
    newest=\$(ls -t "\$SCREENSHOT_DIR"/*.png "\$SCREENSHOT_DIR"/*.jpg 2>/dev/null | head -1)

    if [ -n "\$newest" ] && [ "\$newest" != "\$LAST_FILE" ]; then
        LAST_FILE="\$newest"
        # JXA + NSPasteboard でクリップボードにコピー（特殊文字不要）
        /usr/bin/osascript -l JavaScript -e "ObjC.import('AppKit'); var img = \\\$.NSImage.alloc.initWithContentsOfFile('\$newest'); if (!img.isNil()) { var pb = \\\$.NSPasteboard.generalPasteboard; pb.clearContents; pb.writeObjects(\\\$.NSArray.arrayWithObject(img)); }" 2>> /tmp/screenshot-clipboard.err
    fi

    sleep 0.5
done
WATCHEOF
    chmod +x "$CLIP_WATCHER"
    echo "     → $CLIP_WATCHER"

    # launchd plist（Aquaセッション限定でGUIアクセス保証）
    cat > "$CLIP_PLIST" << CLIPPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.screenshot-clipboard</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$CLIP_WATCHER</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>/tmp/screenshot-clipboard.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/screenshot-clipboard.err</string>
</dict>
</plist>
CLIPPLIST
    launchctl load "$CLIP_PLIST"
    echo "     → launchd に登録（Aquaセッション、0.5秒間隔）"

    # ========== 3. 写真アプリインポート ==========
    echo "3/3 写真アプリインポート用 launchd を登録..."
    mkdir -p "$(dirname "$IMPORT_SCRIPT")"
    mkdir -p "$(dirname "$IMPORTED_LOG")"
    touch "$IMPORTED_LOG"

    cat > "$IMPORT_SCRIPT" << SCRIPT
#!/bin/bash
SCREENSHOT_DIR="$screenshot_dir"
LOG_FILE="$IMPORTED_LOG"

for file in "\$SCREENSHOT_DIR"/*.png "\$SCREENSHOT_DIR"/*.jpg "\$SCREENSHOT_DIR"/*.jpeg; do
    [ -f "\$file" ] || continue
    if grep -qxF "\$file" "\$LOG_FILE" 2>/dev/null; then
        continue
    fi
    echo "\$(date): Found new screenshot: \$file"
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
    <integer>3</integer>
    <key>StandardOutPath</key>
    <string>/tmp/screenshot-to-photos.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/screenshot-to-photos.err</string>
</dict>
</plist>
PLIST
    launchctl load "$LAUNCHD_PLIST"

    echo ""
    echo "=== セットアップ完了 ==="
    echo "⌘⇧3 / ⌘⇧4 / ⌘⇧5 でスクショを撮ると:"
    echo "  1. $screenshot_dir に保存"
    echo "  2. 0.5秒以内にクリップボードに自動コピー（⌘V で貼り付け可能）"
    echo "  3. 3秒以内に写真アプリにインポート → iPhoneに同期"
    echo ""
    echo "※ Dockにアプリは表示されません"
    echo "※ ログイン時に自動起動します"
}

unsetup() {
    echo "=== セットアップ解除 ==="

    # クリップボードウォッチャー
    launchctl unload "$CLIP_PLIST" 2>/dev/null
    pkill -f "screenshot-clipboard-watcher" 2>/dev/null
    rm -f "$CLIP_PLIST" "$CLIP_WATCHER"
    echo "  クリップボードウォッチャーを削除しました"

    # 旧 AppleScript アプリ
    osascript -e 'tell application "ScreenshotClipboardCopy" to quit' 2>/dev/null
    osascript -e '
        tell application "System Events"
            try
                delete login item "ScreenshotClipboardCopy"
            end try
        end tell
    ' 2>/dev/null
    rm -rf "$HOME/Applications/ScreenshotClipboardCopy.app"
    rm -f "$HOME/.local/bin/copy-image-to-clipboard.js"

    # 写真インポート
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
    rm -f "$LAUNCHD_PLIST" "$IMPORT_SCRIPT"
    echo "  写真インポートを削除しました"

    # Folder Action
    osascript -e 'tell application "System Events" to try
        delete folder action "Screenshot Clipboard Copy"
    end try' 2>/dev/null
    rm -f "$HOME/Library/Scripts/Folder Action Scripts/Screenshot Clipboard Copy.scpt"

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="

    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    if pgrep -f "screenshot-clipboard-watcher" > /dev/null 2>&1; then
        echo "クリップボードコピー: 実行中（0.5秒間隔）"
    else
        echo "クリップボードコピー: 停止中"
    fi

    if launchctl list 2>/dev/null | grep -q "com.user.screenshot-to-photos"; then
        echo "写真インポート: 実行中"
    else
        echo "写真インポート: 停止中"
    fi

    if [ -f "$IMPORTED_LOG" ]; then
        local count
        count=$(wc -l < "$IMPORTED_LOG" | tr -d ' ')
        echo "インポート済み: ${count}枚"
    fi

    echo ""
    echo "--- 最新ログ ---"
    tail -5 /tmp/screenshot-clipboard.log 2>/dev/null || echo "(クリップボードログなし)"
    echo "---"
    tail -5 /tmp/screenshot-to-photos.log 2>/dev/null || echo "(写真インポートログなし)"
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
