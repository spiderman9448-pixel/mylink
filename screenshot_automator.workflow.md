# スクリーンショット → iPhone 写真 自動同期

## セットアップ（初回のみ）

```bash
chmod +x screenshot.sh
./screenshot.sh setup
```

これだけで完了です。以降は普段通り **⌘⇧3** / **⌘⇧4** / **⌘⇧5** でスクショを撮ると、自動的にiPhoneの写真に同期されます。

## 仕組み

1. macOSのスクショ保存先を `iCloud Drive/Screenshots` に変更
2. フォルダアクションで新しい画像を検知
3. 写真アプリに自動インポート
4. iCloud Photos経由でiPhoneに同期

## その他のコマンド

```bash
# 現在の設定を確認
./screenshot.sh status

# セットアップ解除（デスクトップ保存に戻す）
./screenshot.sh unsetup
```

## 前提条件

- macOS上で実行
- iCloud Photosが有効（設定 → Apple ID → iCloud → 写真）
- 初回セットアップ時にアクセス許可のダイアログが出たら「許可」を選択
