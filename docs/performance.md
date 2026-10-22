# 10,000-Item Performance Test

[日本語](performance.ja.md)

> This English document is the canonical record. The Japanese translation, [`performance.ja.md`](performance.ja.md), is provided for reference only. If the two differ, this document takes precedence.

## Purpose and method

The [specification](specification.md) sets a target of 10,000 or more values per list. This test verifies that target with every value name present in the DOM, without pagination or virtual scrolling.

Measurements were taken on 2026-10-20 in the following environment:

- Redmine 7.0.2
- Ruby 4.0.6, Rails 8.1.4
- SQLite (test environment)
- Google Chrome 155.0.8059.85, headless, driven by Playwright
- macOS (Darwin 27.0.0), ARM64
- A Key/value list with 10,000 values

Prepare the data and run the browser benchmark with the following scripts. Start Redmine in the test environment so that it is reachable at `RCFM_BASE_URL`, then run the scripts from the Redmine root directory. Install Playwright in the plugin directory beforehand with `npm install` (and `npx playwright install chromium` when using Playwright's bundled Chromium). The benchmark signs in as `admin` / `admin`.

```sh
RAILS_ENV=test bundle exec rails runner \
  plugins/redmine_custom_field_manager/test/performance/prepare_10000.rb

RCFM_FIELD_ID=<ID printed by the previous command> \
RCFM_BASE_URL=http://127.0.0.1:3210 \
RCFM_CHROME_PATH=<Chrome executable; omit to use Playwright's bundled Chromium> \
node plugins/redmine_custom_field_manager/test/performance/benchmark_10000.js
```

## Results

| Operation | Measured |
|---|---:|
| Initial page load | 3.381 s |
| DOM rows / plain-text names | 10,000 / 10,000 |
| Sortable initialization | 6.229 s |
| Real D&D from the first row to the last | 5.231 s |
| Bulk move from the first row to the last by destination name | 17.082 s |
| Saving the order of 10,000 values and reloading | 45.167 s |
| Sortable initialization after saving (included in the previous row) | 5.832 s |
| CSV export (excluding the wait for re-initialization) | 0.396–0.482 s |
| Update preview of the same CSV | 1.293–1.315 s |
| Restore preview | 4.195–4.774 s |
| Chrome JS heap | approx. 97–115 MB |
| Browser JavaScript errors | 0 |

On the server side alone, parsing the 10,000-row CSV took 0.135 s and planning the differences took 0.230 s. According to the Rails log, saving the order took about 0.7–0.8 s and rendering the list HTML took about 1.1–2.5 s. The long response times are therefore caused mainly by re-laying out the 10,000-row table in headless Chrome, re-initializing Sortable, and garbage collection, rather than by server processing.

## Assessment

- Showing all 10,000 values as plain text that browser find can search, D&D, saving, CSV, and restore preview all completed without removing any functionality.
- No hard limit is placed on the number of values.
- Bulk moves and re-rendering after saving involve long waits, so no specific response time is guaranteed. These operations depend heavily on device performance and the browser.
- Server-side updates use bulk SQL statements in batches of 500 rows, avoiding 10,000 individual updates.

These results were measured in a development environment using SQLite and a single process. They do not guarantee the values on production databases or users' devices. Measure again for each release and whenever support for a new Redmine series is added.
