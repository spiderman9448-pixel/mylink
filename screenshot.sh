#!/bin/bash
# =============================================================
# Mac スクリーンショット → クリップボード自動コピー & iPhone同期
# =============================================================
# セットアップ:  chmod +x screenshot.sh && ./screenshot.sh setup
# セットアップ解除:  ./screenshot.sh unsetup
# =============================================================

CLIP_HELPER="$HOME/.local/bin/copy-image-to-clipboard.js"
FOLDER_ACTION_SCRIPT="$HOME/Library/Scripts/Folder Action Scripts/Screenshot Clipboard Copy.scpt"
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

    # 3. Folder Action でクリップボード即時コピー（FinderのGUIコンテキスト）
    echo "3/4 Folder Action でクリップボード即時コピーを設定..."

    # 旧リソースの掃除
    osascript -e 'tell application "ScreenshotClipboardCopy" to quit' 2>/dev/null
    osascript -e '
        tell application "System Events"
            try
                delete login item "ScreenshotClipboardCopy"
            end try
        end tell
    ' 2>/dev/null
    rm -rf "$HOME/Applications/ScreenshotClipboardCopy.app"
    # 旧 WatchPaths エージェントの掃除
    launchctl unload "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist" 2>/dev/null
    rm -f "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist"
    rm -f "$HOME/.local/bin/clipboard-screenshot.sh"

    # Folder Action スクリプトを作成
    mkdir -p "$HOME/Library/Scripts/Folder Action Scripts"
    local helper_path="$CLIP_HELPER"

    # AppleScript を Folder Action として作成
    # on adding folder items to: Finder がファイル追加時に即座に呼ぶ
    osascript -e "
        set scptText to \"on adding folder items to thisFolder after receiving addedItems\" & linefeed & ¬
            \"    repeat with addedItem in addedItems\" & linefeed & ¬
            \"        set filePath to POSIX path of addedItem\" & linefeed & ¬
            \"        if filePath ends with \\\".png\\\" or filePath ends with \\\".jpg\\\" then\" & linefeed & ¬
            \"            do shell script \\\"/usr/bin/osascript -l JavaScript \" & quoted form of \"$helper_path\" & \" \" & \"\\\" & quoted form of filePath\" & linefeed & ¬
            \"        end if\" & linefeed & ¬
            \"    end repeat\" & linefeed & ¬
            \"end adding folder items to\"

        set scptFile to POSIX file \"$FOLDER_ACTION_SCRIPT\"
        set scptObj to (run script \"tell application \\\"Script Editor\\\"
            set doc to make new document with properties {text:\" & quoted form of scptText & \"}
            compile doc
            save doc as \\\"compiled script\\\" in file (POSIX file \\\"$FOLDER_ACTION_SCRIPT\\\" as text)
            close doc
        end tell\")
    " 2>/dev/null

    # osacompile でフォールバック
    if [ ! -f "$FOLDER_ACTION_SCRIPT" ]; then
        local tmp_as
        tmp_as=$(mktemp /tmp/folder-action.XXXXXX.applescript)
        cat > "$tmp_as" << FAEOF
on adding folder items to thisFolder after receiving addedItems
    repeat with addedItem in addedItems
        set filePath to POSIX path of addedItem
        if filePath ends with ".png" or filePath ends with ".jpg" then
            do shell script "/usr/bin/osascript -l JavaScript " & quoted form of "$helper_path" & " " & quoted form of filePath
        end if
    end repeat
end adding folder items to
FAEOF
        osacompile -o "$FOLDER_ACTION_SCRIPT" "$tmp_as"
        rm -f "$tmp_as"
    fi

    # Folder Action をスクショフォルダにアタッチ
    osascript -e "
        tell application \"System Events\"
            try
                delete folder action \"Screenshot Clipboard Copy\"
            end try
        end tell
    " 2>/dev/null

    osascript -e "
        tell application \"System Events\"
            set fa to make new folder action with properties {name:\"Screenshot Clipboard Copy\", path:\"$screenshot_dir\"}
            make new script at end of scripts of fa with properties {name:\"Screenshot Clipboard Copy.scpt\", path:\"$FOLDER_ACTION_SCRIPT\"}
            set folder actions enabled to true
        end tell
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "     → Folder Action を $screenshot_dir にアタッチ済み（即時検知）"
    else
        echo "     → 警告: Folder Action のアタッチに失敗。手動で設定が必要かもしれません"
    fi

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

    # 旧 WatchPaths エージェントの掃除
    launchctl unload "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist" 2>/dev/null
    rm -f "$HOME/Library/LaunchAgents/com.user.screenshot-clipboard.plist"
    rm -f "$HOME/.local/bin/clipboard-screenshot.sh"

    # Folder Action の削除
    osascript -e '
        tell application "System Events"
            try
                delete folder action "Screenshot Clipboard Copy"
            end try
        end tell
    ' 2>/dev/null
    rm -f "$FOLDER_ACTION_SCRIPT"
    rm -f "$CLIP_HELPER"
    echo "  クリップボードコピー（Folder Action）を削除しました"

    # 写真インポート エージェント
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
    rm -f "$LAUNCHD_PLIST" "$IMPORT_SCRIPT"
    echo "  写真インポートを削除しました"

    rm -f /tmp/.screenshot-clipboard-last

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="

    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    if [ -f "$FOLDER_ACTION_SCRIPT" ]; then
        echo "クリップボードコピー: Folder Action 設定済み（即時検知）"
    else
        echo "クリップボードコピー: 未設定"
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
