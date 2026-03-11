#!/bin/bash
# =============================================================
# Mac スクリーンショット → iPhone 写真 自動同期セットアップ
# =============================================================
# このスクリプトを一度実行するだけで、以降は普段通り ⌘⇧3 / ⌘⇧4 / ⌘⇧5 で
# スクショを撮るだけで自動的にiPhoneの写真に同期されます。
#
# 仕組み:
#   1. macOSのスクショ保存先をiCloud Drive内に変更
#   2. そのフォルダにフォルダアクションを設定
#   3. 新しい画像が保存されるたびに写真アプリに自動インポート
#
# セットアップ:
#   chmod +x screenshot.sh
#   ./screenshot.sh setup
#
# セットアップ解除:
#   ./screenshot.sh unsetup
# =============================================================

ICLOUD_SCREENSHOTS="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Screenshots"
FOLDER_ACTION_SCRIPT="$HOME/Library/Scripts/Folder Action Scripts/ImportToPhotos.scpt"

setup() {
    echo "=== スクリーンショット → iPhone 写真 自動同期セットアップ ==="
    echo ""

    # 1. iCloud Drive内にスクショフォルダを作成
    echo "1/3 iCloud Drive内にスクショフォルダを作成..."
    mkdir -p "$ICLOUD_SCREENSHOTS"
    echo "     → $ICLOUD_SCREENSHOTS"

    # 2. macOSのスクショ保存先を変更
    echo "2/3 macOSのスクショ保存先を変更..."
    defaults write com.apple.screencapture location "$ICLOUD_SCREENSHOTS"
    killall SystemUIServer 2>/dev/null
    echo "     → スクショ保存先をiCloud Driveに変更しました"

    # 3. フォルダアクション用AppleScriptを作成＆設定
    echo "3/3 フォルダアクション（写真アプリ自動インポート）を設定..."
    mkdir -p "$(dirname "$FOLDER_ACTION_SCRIPT")"

    # AppleScriptをコンパイルして保存
    osacompile -o "$FOLDER_ACTION_SCRIPT" <<'APPLESCRIPT'
on adding folder items to theFolder after receiving theFiles
    tell application "Photos"
        activate
        delay 1
        repeat with aFile in theFiles
            set fileName to name of (info for aFile)
            if fileName ends with ".png" or fileName ends with ".jpg" or fileName ends with ".jpeg" then
                try
                    import {aFile}
                end try
            end if
        end repeat
    end tell
end adding folder items to
APPLESCRIPT

    if [ $? -ne 0 ]; then
        echo "     ⚠ AppleScriptのコンパイルに失敗しました"
        return 1
    fi

    # フォルダアクションをフォルダに紐付け
    osascript <<ATTACH
        tell application "System Events"
            set folder actions enabled to true
            try
                set fa to make new folder action with properties {name:"Screenshots Auto Import", path:"$ICLOUD_SCREENSHOTS"}
            on error
                set fa to folder action "Screenshots Auto Import"
            end try
            try
                make new script of fa with properties {name:"ImportToPhotos.scpt", POSIX path:"$FOLDER_ACTION_SCRIPT"}
            end try
        end tell
ATTACH

    if [ $? -eq 0 ]; then
        echo "     → フォルダアクションを設定しました"
    else
        echo "     ⚠ フォルダアクションの設定に失敗しました"
        echo "     → 手動設定: Finderで右クリック → サービス → フォルダアクション設定"
        return 1
    fi

    echo ""
    echo "=== セットアップ完了 ==="
    echo "これで普段通り ⌘⇧3 / ⌘⇧4 / ⌘⇧5 でスクショを撮ると:"
    echo "  1. iCloud Drive/Screenshots に保存"
    echo "  2. 写真アプリに自動インポート"
    echo "  3. iCloud Photos経由でiPhoneに同期"
    echo ""
    echo "※ iCloud写真がオンになっていることを確認してください"
    echo "  (設定 → Apple ID → iCloud → 写真)"
}

unsetup() {
    echo "=== セットアップ解除 ==="

    # スクショ保存先をデフォルト(デスクトップ)に戻す
    defaults write com.apple.screencapture location "$HOME/Desktop"
    killall SystemUIServer 2>/dev/null
    echo "✔ スクショ保存先をデスクトップに戻しました"

    # フォルダアクションを削除
    osascript <<'DETACH'
        tell application "System Events"
            try
                delete folder action "Screenshots Auto Import"
            end try
        end tell
DETACH
    echo "✔ フォルダアクションを削除しました"

    # スクリプトファイルを削除
    rm -f "$FOLDER_ACTION_SCRIPT"
    echo "✔ AppleScriptを削除しました"

    echo ""
    echo "=== 解除完了 ==="
}

status() {
    echo "=== 現在の設定状況 ==="
    local current_location
    current_location=$(defaults read com.apple.screencapture location 2>/dev/null || echo "(デフォルト: デスクトップ)")
    echo "スクショ保存先: $current_location"

    if [ -f "$FOLDER_ACTION_SCRIPT" ]; then
        echo "フォルダアクション: ✔ 設定済み"
    else
        echo "フォルダアクション: ✗ 未設定"
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
