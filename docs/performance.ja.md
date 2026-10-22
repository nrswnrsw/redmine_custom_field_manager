# 10,000件性能試験

[English](performance.md)

> この文書は参照用の日本語訳である。正本は英語版の [`performance.md`](performance.md) であり、内容に差異がある場合は英語版を優先する。

## 目的と方法

[仕様書](specification.ja.md)では、1リストあたり10,000件以上を性能目標としている。この試験では、ページネーションや仮想スクロールを使わず、全名称がDOMに存在する状態でこの目標を検証する。

2026-10-20に次の環境で実測した。

- Redmine 7.0.2
- Ruby 4.0.6、Rails 8.1.4
- SQLite（test環境）
- Google Chrome 155.0.8059.85（Headless、Playwrightで操作）
- macOS（Darwin 27.0.0）、ARM64
- 10,000件の選択肢を持つKey/value list

データの準備とブラウザでの計測には、次のスクリプトを使う。Redmineをtest環境で起動して `RCFM_BASE_URL` でアクセスできる状態にしてから、Redmineのルートディレクトリで実行する。事前にプラグインのディレクトリで `npm install` を実行してPlaywrightをインストールしておく（Playwright同梱のChromiumを使う場合は `npx playwright install chromium` も実行する）。ベンチマークは `admin` / `admin` でログインする。

```sh
RAILS_ENV=test bundle exec rails runner \
  plugins/redmine_custom_field_manager/test/performance/prepare_10000.rb

RCFM_FIELD_ID=<前のコマンドで出力されたID> \
RCFM_BASE_URL=http://127.0.0.1:3210 \
RCFM_CHROME_PATH=<Chromeの実行ファイル（Playwright同梱のChromiumを使う場合は省略）> \
node plugins/redmine_custom_field_manager/test/performance/benchmark_10000.js
```

## 実測結果

| 操作 | 実測 |
|---|---:|
| 初回ページ読み込み | 3.381秒 |
| DOMの行数／通常テキストの名称数 | 10,000／10,000 |
| Sortable初期化 | 6.229秒 |
| 先頭行から末尾行への実際のD&D | 5.231秒 |
| 移動先の名称指定による先頭行から末尾行への一括移動 | 17.082秒 |
| 10,000件の並び順の保存と再読み込み | 45.167秒 |
| 保存後のSortable初期化（前の行に含まれる） | 5.832秒 |
| CSV出力（再初期化の待ち時間を除く） | 0.396〜0.482秒 |
| 同一CSVの更新プレビュー | 1.293〜1.315秒 |
| 復元プレビュー | 4.195〜4.774秒 |
| Chrome JSヒープ | 約97〜115MB |
| ブラウザJavaScriptエラー | 0件 |

サーバー単体では、10,000行のCSVの解析に0.135秒、差分計画の作成に0.230秒かかった。Railsのログでは、並び順の保存が約0.7〜0.8秒、一覧HTMLの生成が約1.1〜2.5秒だった。したがって、長い応答時間の主な要因はサーバー処理ではなく、Headless Chrome上での10,000行のテーブルの再レイアウト、Sortableの再初期化、GCである。

## 判定

- ブラウザ内検索が可能な通常テキストによる10,000件の全件表示、D&D、保存、CSV、復元プレビューは、いずれの機能も削らずに完走した。
- 登録件数のハード上限は設けていない。
- 一括移動と保存後の再描画は待ち時間が長いため、具体的な応答時間は保証しない。これらは端末性能とブラウザの影響を特に大きく受ける。
- サーバー側の更新は500件単位の一括SQLで行い、10,000回の個別更新を避けている。

この記録はSQLite・単一プロセスの開発環境での実測値であり、本番DBや利用者の端末での値を保証するものではない。リリースごと、および対応するRedmine系列を追加するたびに再計測する。
