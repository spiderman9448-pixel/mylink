# スクリーンショット → iPhone 写真 自動同期

## セットアップ（初回のみ）

```bash
chmod +x screenshot.sh
./screenshot.sh setup
```

これだけで完了。以降は普段通り **⌘⇧3** / **⌘⇧4** / **⌘⇧5** でスクショを撮ると、自動的にiPhoneの写真に同期されます。

## 仕組み

1. macOSのスクショ保存先を `iCloud Drive/Screenshots` に変更
2. **launchd (WatchPaths)** がフォルダの変更を自動検知
3. 新しいスクショを写真アプリにインポート
4. iCloud Photos経由でiPhoneに同期

## コマンド

```bash
./screenshot.sh setup    # セットアップ（初回のみ）
./screenshot.sh status   # 現在の設定・動作状況を確認
./screenshot.sh unsetup  # セットアップ解除（デスクトップ保存に戻す）
```

## トラブルシューティング

```bash
# 動作ログを確認
cat /tmp/screenshot-to-photos.log

# エラーログを確認
cat /tmp/screenshot-to-photos.err

# launchd が動いているか確認
launchctl list | grep screenshot-to-photos
```

## 前提条件

- macOS上で実行
- iCloud Photosが有効（設定 → Apple ID → iCloud → 写真）
- 初回実行時に写真アプリへのアクセス許可を「許可」する
