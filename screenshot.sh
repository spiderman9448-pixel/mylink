#!/bin/bash
# =============================================================
# Mac スクリーンショット → クリップボード自動コピー & iPhone同期
# =============================================================
# セットアップ:  chmod +x screenshot.sh && ./screenshot.sh setup
# セットアップ解除:  ./screenshot.sh unsetup
# =============================================================

CLIP_HELPER="$HOME/.local/bin/copy-image-to-clipboard.js"
CLIP_SCRIPT="$HOME/.local/bin/clipboard-screenshot.sh"
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

    # 3. launchd WatchPaths でクリップボード即時コピー
    echo "3/4 クリップボード即時コピー（WatchPaths）を設定..."
    mkdir -p "$(dirname "$CLIP_SCRIPT")"

    # 旧 AppleScript アプリがあれば終了・削除
    osascript -e 'tell application "ScreenshotClipboardCopy" to quit' 2>/dev/null
    osascript -e '
        tell application "System Events"
            try
                delete login item "ScreenshotClipboardCopy"
            end try
        end tell
    ' 2>/dev/null
    rm -rf "$HOME/Applications/ScreenshotClipboardCopy.app"

    # クリップボードコピースクリプト
    cat > "$CLIP_SCRIPT" << 'CLIPEOF'
#!/bin/bash
# WatchPaths から呼ばれる。新しいスクショを即座にクリップボードにコピー。
SCREENSHOT_DIR="__SCREENSHOT_DIR__"
HELPER="__CLIP_HELPER__"
STATE_FILE="/tmp/.screenshot-clipboard-last"

# 最新ファイルを取得
newest=$(ls -t "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg 2>/dev/null | head -1)
[ -z "$newest" ] && exit 0

# 前回コピー済みなら何もしない
last=$(cat "$STATE_FILE" 2>/dev/null)
[ "$newest" = "$last" ] && exit 0

# ファイルが書き込み中の場合に備えて少し待つ（スクショ保存完了まで）
sleep 0.3

# クリップボードにコピー
/usr/bin/osascript -l JavaScript "$HELPER" "$newest"
echo "$newest" > "$STATE_FILE"
CLIPEOF
    # プレースホルダーを置換
    sed -i '' "s|__SCREENSHOT_DIR__|$screenshot_dir|g" "$CLIP_SCRIPT"
    sed -i '' "s|__CLIP_HELPER__|$CLIP_HELPER|g" "$CLIP_SCRIPT"
    chmod +x "$CLIP_SCRIPT"

    # launchd plist（WatchPaths で即時検知）
    launchctl unload "$CLIP_PLIST" 2>/dev/null
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
        <string>$CLIP_SCRIPT</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$screenshot_dir</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/screenshot-clipboard.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/screenshot-clipboard.err</string>
</dict>
</plist>
CLIPPLIST
    launchctl load "$CLIP_PLIST"
    echo "     → WatchPaths で $screenshot_dir を監視中（即時検知）"

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
    echo "  2. 即座にクリップボードに自動コピー（⌘V で貼り付け可能）"
    echo "  3. 3秒以内に写真アプリにインポート → iPhoneに同期"
    echo ""
    echo "※ launchd で自動監視（ログイン時に自動起動）"
}

unsetup() {
    echo "=== セットアップ解除 ==="

    # 旧 AppleScript アプリの掃除
    osascript -e 'tell application "ScreenshotClipboardCopy" to quit' 2>/dev/null
    osascript -e '
        tell application "System Events"
            try
                delete login item "ScreenshotClipboardCopy"
            end try
        end tell
    ' 2>/dev/null
    rm -rf "$HOME/Applications/ScreenshotClipboardCopy.app"

    # クリップボード WatchPaths エージェント
    launchctl unload "$CLIP_PLIST" 2>/dev/null
    rm -f "$CLIP_PLIST" "$CLIP_SCRIPT"
    echo "  クリップボードコピーを削除しました"

    # 写真インポート エージェント
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
    rm -f "$LAUNCHD_PLIST" "$IMPORT_SCRIPT" "$CLIP_HELPER"
    echo "  写真インポートを削除しました"

    # Folder Action の残りも掃除
    osascript -e 'tell application "System Events" to try
        delete folder action "Screenshot Clipboard Copy"
    end try' 2>/dev/null
    rm -f "$HOME/Library/Scripts/Folder Action Scripts/Screenshot Clipboard Copy.scpt"
    rm -f /tmp/.screenshot-clipboard-last

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="

    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    if launchctl list 2>/dev/null | grep -q "com.user.screenshot-clipboard"; then
        echo "クリップボードコピー: 実行中（WatchPaths即時検知）"
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
