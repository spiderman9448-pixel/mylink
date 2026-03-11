#!/bin/bash
# =============================================================
# Mac スクリーンショット → クリップボード自動コピー & iPhone同期
# =============================================================
# セットアップ:  chmod +x screenshot.sh && ./screenshot.sh setup
# セットアップ解除:  ./screenshot.sh unsetup
# =============================================================

CLIP_HELPER="$HOME/.local/bin/copy-image-to-clipboard.js"
CLIP_APP="$HOME/Applications/ScreenshotClipboardCopy.app"
IMPORT_SCRIPT="$HOME/.local/bin/import-screenshot-to-photos.sh"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.user.screenshot-to-photos.plist"
IMPORTED_LOG="$HOME/.local/share/screenshot-imports.log"

setup() {
    echo "=== スクリーンショット自動コピー & iPhone同期 セットアップ ==="
    echo ""

    local screenshot_dir
    screenshot_dir=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
    screenshot_dir="${screenshot_dir/#\~/$HOME}"

    echo "1/4 スクショ保存先を確認..."
    echo "     → $screenshot_dir"
    mkdir -p "$screenshot_dir"

    # 2. JXA クリップボードヘルパー
    echo "2/4 クリップボードヘルパーを作成..."
    mkdir -p "$(dirname "$CLIP_HELPER")"
    cat > "$CLIP_HELPER" << 'JSEOF'
ObjC.import('AppKit');
ObjC.import('Foundation');
function run(argv) {
    var path = argv[0];
    var image = $.NSImage.alloc.initWithContentsOfFile(path);
    if (image.isNil()) {
        return "FAIL: could not load image";
    }
    var pb = $.NSPasteboard.generalPasteboard;
    pb.clearContents;
    pb.writeObjects($.NSArray.arrayWithObject(image));
    return "OK";
}
JSEOF
    echo "     → $CLIP_HELPER"

    # 3. Stay-open AppleScript アプリ（0.5秒ポーリング、GUIコンテキスト）
    echo "3/4 クリップボード自動コピーアプリを作成..."
    mkdir -p "$(dirname "$CLIP_APP")"

    # 旧リソースの掃除
    osascript -e 'tell application "ScreenshotClipboardCopy" to quit' 2>/dev/null
    sleep 1
    osascript -e '
        tell application "System Events"
            try
                delete login item "ScreenshotClipboardCopy"
            end try
        end tell
    ' 2>/dev/null
    rm -rf "$CLIP_APP"
    # 旧 WatchPaths / Folder Action の掃除
    launchctl unload "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist" 2>/dev/null
    rm -f "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist"
    rm -f "$HOME/.local/bin/clipboard-screenshot.sh"
    osascript -e 'tell application "System Events" to try
        delete folder action "Screenshot Clipboard Copy"
    end try' 2>/dev/null
    rm -f "$HOME/Library/Scripts/Folder Action Scripts/Screenshot Clipboard Copy.scpt"

    local tmp_as
    tmp_as=$(mktemp /tmp/clip-app.XXXXXX.applescript)
    cat > "$tmp_as" << ASEOF
property lastModDate : 0

on idle
    set screenshotDir to "$screenshot_dir"
    set helperPath to "$CLIP_HELPER"

    try
        set newestFile to do shell script "ls -t " & quoted form of screenshotDir & "/*.png " & quoted form of screenshotDir & "/*.jpg 2>/dev/null | head -1"
        if newestFile is "" then return 0.5

        set modDate to (do shell script "stat -f %m " & quoted form of newestFile) as number

        if modDate > lastModDate then
            set lastModDate to modDate
            do shell script "/usr/bin/osascript -l JavaScript " & quoted form of helperPath & " " & quoted form of newestFile
        end if
    end try

    return 0.5
end idle
ASEOF
    osacompile -s -o "$CLIP_APP" "$tmp_as"
    rm -f "$tmp_as"

    open "$CLIP_APP"
    echo "     → $CLIP_APP（起動済み、0.5秒間隔で監視）"

    osascript -e "
        tell application \"System Events\"
            try
                delete login item \"ScreenshotClipboardCopy\"
            end try
            make login item at end with properties {path:\"$CLIP_APP\", hidden:true}
        end tell
    " 2>/dev/null
    echo "     → ログイン時に自動起動するよう設定"

    # 4. launchd（写真アプリインポート用）
    echo "4/4 写真アプリインポート用 launchd を登録..."
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
    echo "※ ScreenshotClipboardCopy.app がDockに表示されます"
    echo "※ ログイン時に自動起動します"
}

unsetup() {
    echo "=== セットアップ解除 ==="

    osascript -e 'tell application "ScreenshotClipboardCopy" to quit' 2>/dev/null
    osascript -e '
        tell application "System Events"
            try
                delete login item "ScreenshotClipboardCopy"
            end try
        end tell
    ' 2>/dev/null
    rm -rf "$CLIP_APP"
    echo "  クリップボードコピーアプリを削除しました"

    # 旧 WatchPaths / Folder Action の掃除
    launchctl unload "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist" 2>/dev/null
    rm -f "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist"
    rm -f "$HOME/.local/bin/clipboard-screenshot.sh"
    osascript -e 'tell application "System Events" to try
        delete folder action "Screenshot Clipboard Copy"
    end try' 2>/dev/null
    rm -f "$HOME/Library/Scripts/Folder Action Scripts/Screenshot Clipboard Copy.scpt"

    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
    rm -f "$LAUNCHD_PLIST" "$IMPORT_SCRIPT" "$CLIP_HELPER"
    echo "  写真インポートを削除しました"

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="

    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    if pgrep -f "ScreenshotClipboardCopy" > /dev/null 2>&1; then
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
    tail -5 /tmp/screenshot-to-photos.log 2>/dev/null || echo "(ログなし)"
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
