# Mac Automator / ショートカット設定ガイド

## 方法1: シェルスクリプトを直接使う

```bash
# 実行権限を付与
chmod +x screenshot.sh

# 全画面スクリーンショット
./screenshot.sh

# 範囲選択
./screenshot.sh area

# ウィンドウ選択
./screenshot.sh window

# 10秒間隔で繰り返し撮影
./screenshot.sh loop 10
```

## 方法2: macOS ショートカットApp で自動化

1. **ショートカット.app** を開く
2. 新規ショートカットを作成
3. 「シェルスクリプトを実行」アクションを追加
4. スクリプト欄に以下を入力:

```bash
/path/to/screenshot.sh
```

5. キーボードショートカットを割り当て（例: ⌘⇧5 の代替）

## 方法3: launchd で定期実行

`~/Library/LaunchAgents/com.user.screenshot.plist` を作成:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.screenshot</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/path/to/screenshot.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

有効化:
```bash
launchctl load ~/Library/LaunchAgents/com.user.screenshot.plist
```

停止:
```bash
launchctl unload ~/Library/LaunchAgents/com.user.screenshot.plist
```
