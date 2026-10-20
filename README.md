# Redmine Custom Field Manager

Redmine のカスタムフィールドと Key/value list を、大量データでも安全に管理するためのプラグインです。

製品動作の基準は [`docs/specification.md`](docs/specification.md) です。`0.1.0` では次を提供します。

- 標準カスタムフィールド一覧の全件表示、保存前D&D、複数選択移動、Undo/Redo
- Key/value list の名称・有効状態・順序・追加・削除・一括操作
- 使用中または既定値になっている選択肢の削除防止と原子的保存
- CSV出力、追加・更新・全件同期インポート、保存前プレビュー
- 別Redmine環境からの候補確認と確認済みマッピングの再利用
- 同時編集の差分表示、安全な場合の統合案、明示的な強制上書き
- 差分＋定期スナップショット履歴、対象全体の復元、保持期間／世代数、手動削除

## 対応対象

- Redmine 7.0.x
- Redmine 6.1.x
- Redmine 6.0.x

## 開発版の導入

1. このリポジトリを Redmine の `plugins/redmine_custom_field_manager` に配置します。
2. Redmine ルートでプラグインのマイグレーションを実行します。

   ```sh
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

3. Redmine を再起動します。

本番環境へ導入する前に、必ずデータベースのバックアップを取得してください。

## 操作

プラグインは Redmine 標準の「管理」→「カスタムフィールド」と Key/value list の選択肢画面を置き換えます。編集はブラウザ内に留まり、「保存」を押すまでDBへ反映されません。

CSVインポートは選択肢画面の「CSVエクスポート・インポート」から行います。

- 追加: CSV各行を新規選択肢として末尾へ追加します。
- 更新・追加: 同一環境では内部IDを維持して更新し、IDのない行を追加します。
- 全件同期: CSVにない使用中項目を無効化し、未使用項目は削除／無効化を選択できます。

別環境のCSVではIDをそのまま更新に使いません。候補との対応または新規作成を管理者が確認した後にだけ適用し、その対応を次回以降に再利用します。

変更履歴はカスタムフィールド管理画面の「変更履歴」から確認・復元・削除できます。保存期間と最大世代数は「管理」→「プラグイン」→本プラグインの「設定」で指定します。どちらも空欄なら無期限です。

## テスト

Redmine ルートから実行します。

```sh
bundle exec rake redmine:plugins:test NAME=redmine_custom_field_manager RAILS_ENV=test
```

GitHub Actions は Redmine 7.0.2、6.1.5、6.0.11 を公式配布物のSHA-256検証後に試験します。10,000件のブラウザ性能試験については [`docs/performance.md`](docs/performance.md) を参照してください。

## ライセンス

ライセンスは正式リリースまでに確定します。現時点で、リポジトリの公開は第三者への利用・改変・再配布許諾を意味しません。
