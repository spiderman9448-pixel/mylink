#!/bin/bash
# =============================================================
# Mac スクリーンショット → iPhone 写真 自動同期セットアップ
# =============================================================
# スクショの保存先は変更しません（既存の設定をそのまま使用）
#
# セットアップ:
#   chmod +x screenshot.sh
#   ./screenshot.sh setup
#
# セットアップ解除:
#   ./screenshot.sh unsetup
# =============================================================

CLIP_HELPER="$HOME/.local/bin/copy-image-to-clipboard.js"
FOLDER_ACTION_SCRIPT="$HOME/Library/Scripts/Folder Action Scripts/Screenshot Clipboard Copy.scpt"
IMPORT_SCRIPT="$HOME/.local/bin/import-screenshot-to-photos.sh"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.user.screenshot-to-photos.plist"
IMPORTED_LOG="$HOME/.local/share/screenshot-imports.log"

setup() {
    echo "=== スクリーンショット → iPhone 写真 自動同期セットアップ ==="
    echo ""

    # スクショ保存先を取得
    local screenshot_dir
    screenshot_dir=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
    screenshot_dir="${screenshot_dir/#\~/$HOME}"

    echo "1/5 スクショ保存先を確認..."
    echo "     → $screenshot_dir"
    mkdir -p "$screenshot_dir"

    # 2. クリップボードヘルパー（JXA）を作成
    echo "2/5 クリップボードヘルパーを作成..."
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

    # 3. Folder Action を作成（GUIコンテキストでクリップボードコピー）
    echo "3/5 Folder Action を作成（クリップボード自動コピー）..."
    mkdir -p "$(dirname "$FOLDER_ACTION_SCRIPT")"

    # AppleScript を一時ファイルに書いてコンパイル
    local tmp_as
    tmp_as=$(mktemp /tmp/folder-action.XXXXXX.applescript)
    cat > "$tmp_as" << ASEOF
on adding folder items to this_folder after receiving added_items
    set helperPath to "$CLIP_HELPER"
    repeat with added_item in added_items
        set posixPath to POSIX path of added_item
        try
            do shell script "/usr/bin/osascript -l JavaScript " & quoted form of helperPath & " " & quoted form of posixPath
        end try
    end repeat
end adding folder items to
ASEOF
    osacompile -o "$FOLDER_ACTION_SCRIPT" "$tmp_as"
    rm -f "$tmp_as"
    echo "     → $FOLDER_ACTION_SCRIPT"

    # Folder Action をスクショフォルダに紐付け
    osascript << ATTACHEOF
tell application "System Events"
    set folder actions enabled to true

    -- 既存の同名アクションがあれば削除
    try
        delete folder action "Screenshot Clipboard Copy"
    end try

    -- 新規作成して紐付け
    set newAction to make new folder action with properties {name:"Screenshot Clipboard Copy", path:"$screenshot_dir"}
    set scriptFile to POSIX file "$FOLDER_ACTION_SCRIPT" as alias
    make new script at end of scripts of newAction with properties {name:"Screenshot Clipboard Copy", path:scriptFile}
end tell
ATTACHEOF

    if [ $? -eq 0 ]; then
        echo "     → Folder Action をスクショフォルダに登録しました"
    else
        echo "     ⚠ Folder Action の登録に失敗（手動設定が必要かもしれません）"
    fi

    # 4. インポートスクリプトを作成（Photos取り込みのみ、クリップボードはFolder Actionが担当）
    echo "4/5 インポートスクリプトを作成（写真アプリ用）..."
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

    # 5. launchd エージェント（写真アプリインポート用）
    echo "5/5 launchd エージェント（5秒ポーリング）を登録..."
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
    echo "  2. Folder Action で即座にクリップボードにコピー（⌘V で貼り付け可能）"
    echo "  3. 5秒以内に写真アプリにインポート → iPhoneに同期"
    echo ""
    echo "※ スクショ保存先は変更しません"
    echo "※ iCloud写真がオンになっていることを確認してください"
    echo ""
    echo "ログ: cat /tmp/screenshot-to-photos.log"
}

unsetup() {
    echo "=== セットアップ解除 ==="

    # Folder Action を解除
    osascript -e '
    tell application "System Events"
        try
            delete folder action "Screenshot Clipboard Copy"
        end try
    end tell
    ' 2>/dev/null
    rm -f "$FOLDER_ACTION_SCRIPT"
    echo "  Folder Action を削除しました"

    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
    rm -f "$LAUNCHD_PLIST"
    echo "  launchd エージェントを削除しました"

    rm -f "$IMPORT_SCRIPT"
    rm -f "$CLIP_HELPER"
    echo "  スクリプトを削除しました"

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="

    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    # Folder Action 状態
    local fa_status
    fa_status=$(osascript -e 'tell application "System Events" to get folder actions enabled' 2>/dev/null)
    echo "Folder Action: $fa_status"

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
