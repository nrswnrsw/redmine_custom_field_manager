# 10,000件性能試験

## 目的と方法

仕様書の1リスト10,000件目標に対し、ページネーションや仮想スクロールを使わず全名称がDOMに存在する状態を検証する。

2026-10-20に次の環境で実測した。

- Redmine 7.0.2
- Ruby 4.0.6、Rails 8.1.4
- SQLite（test環境）
- Google Chrome 155.0.8059.85、Headless、Playwright
- macOS Darwin 27.0.0、ARM64
- Key/value list 10,000件

準備とブラウザ計測は次のスクリプトを使う。

```sh
RAILS_ENV=test bundle exec rails runner \
  plugins/redmine_custom_field_manager/test/performance/prepare_10000.rb

RCFM_FIELD_ID=<出力されたID> \
RCFM_BASE_URL=http://127.0.0.1:3210 \
RCFM_CHROME_PATH=<Chrome実行ファイル（Playwright同梱版を使う場合は省略）> \
node plugins/redmine_custom_field_manager/test/performance/benchmark_10000.js
```

## 実測結果

| 操作 | 実測 |
|---|---:|
| 初回ページ読み込み | 3.381秒 |
| DOM行／通常テキスト名称 | 10,000／10,000 |
| Sortable初期化 | 6.229秒 |
| 先頭から末尾への実D&D | 5.231秒 |
| 名称指定による先頭から末尾への一括移動 | 17.082秒 |
| 10,000件順序保存＋再読み込み | 45.167秒 |
| 保存後のSortable初期化（上記に内包） | 5.832秒 |
| CSV出力（再初期化待ちを分離後） | 0.396〜0.482秒 |
| 同一CSVの更新プレビュー | 1.293〜1.315秒 |
| 復元プレビュー | 4.195〜4.774秒 |
| Chrome JSヒープ | 約97〜115MB |
| ブラウザJavaScriptエラー | 0件 |

サーバー単体ではCSV 10,000行の解析が0.135秒、差分計画が0.230秒だった。並び替え保存のRailsログは約0.7〜0.8秒、一覧HTML生成は約1.1〜2.5秒であり、長い応答の主因はHeadless Chrome上の10,000行テーブル再レイアウト、Sortable再初期化、GCである。

## 判定

- 10,000件の全件表示、ブラウザ内検索可能な通常テキスト、D&D、保存、CSV、復元プレビューは機能を廃止せず完走した。
- 登録件数のハード上限は設けていない。
- 一括移動と保存後再描画は待ち時間が長いため、具体的な応答時間保証は行わない。特に端末性能とブラウザの影響が大きい。
- サーバー更新は500件単位の一括SQLにし、個別10,000回更新は回避した。

この記録はSQLite／単一プロセスの開発環境における実測であり、本番DBや利用者端末での値を保証するものではない。リリースごと、および対応Redmine系列追加時に再計測する。
