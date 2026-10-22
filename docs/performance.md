# 10,000-Item Performance Test

[日本語](performance.ja.md)

> This English document is the canonical record. The Japanese translation, [`performance.ja.md`](performance.ja.md), is provided for reference only. If the two differ, this document takes precedence.

## Purpose and method

The [specification](specification.md) sets a target of 10,000 or more values per list. This test verifies that target with every value name present in the DOM, without pagination or virtual scrolling. It also compares standard Redmine with the plugin so that administrators can evaluate the performance impact before installing it.

Measurements were taken on 2026-10-22 in the following environment:

- Redmine 7.0.2
- Ruby 4.0.6, Rails 8.1.4
- SQLite (test environment)
- Google Chrome 156.0.8078.48, headless, driven by Playwright 1.62.1
- macOS 27.0.1 (Darwin 27.0.0), ARM64
- A Key/value list with 10,000 values

The standard and plugin variants used the same Redmine checkout, database, custom field, browser, and hardware. Redmine was first started without the plugin and then restarted with the plugin. Each comparison was run three times. The table reports the median followed by the minimum–maximum range. The extended plugin benchmark was run once.

## Running the benchmarks

Prepare the data while the plugin is installed. Start Redmine in the test environment so that it is reachable at `RCFM_BASE_URL`. The benchmarks sign in as `admin` / `admin`.

```sh
RAILS_ENV=test bundle exec rails runner \
  plugins/redmine_custom_field_manager/test/performance/prepare_10000.rb
```

For the standard measurement, stop Redmine, move the plugin outside Redmine's `plugins` directory, restart Redmine, and invoke the comparison script from the plugin repository checkout:

```sh
RCFM_FIELD_ID=<ID printed by the preparation command> \
RCFM_BASE_URL=http://127.0.0.1:3210 \
RCFM_VARIANT=standard \
RCFM_RUNS=3 \
RCFM_CHROME_PATH=<Chrome executable; omit to use Playwright's bundled Chromium> \
node /path/to/redmine_custom_field_manager/test/performance/compare_standard_10000.js
```

For the plugin measurement, restore the plugin directory, restart Redmine, and run:

```sh
RCFM_FIELD_ID=<ID printed by the preparation command> \
RCFM_BASE_URL=http://127.0.0.1:3210 \
RCFM_VARIANT=plugin \
RCFM_RUNS=3 \
RCFM_CHROME_PATH=<Chrome executable; omit to use Playwright's bundled Chromium> \
node plugins/redmine_custom_field_manager/test/performance/compare_standard_10000.js
```

The extended plugin-only benchmark is run with:

```sh
RCFM_FIELD_ID=<ID printed by the preparation command> \
RCFM_BASE_URL=http://127.0.0.1:3210 \
RCFM_CHROME_PATH=<Chrome executable; omit to use Playwright's bundled Chromium> \
node plugins/redmine_custom_field_manager/test/performance/benchmark_10000.js
```

Install Playwright in the plugin directory beforehand with `npm install` (and `npx playwright install chromium` when using Playwright's bundled Chromium).

## Standard Redmine comparison

| Measurement | Standard Redmine | With plugin |
|---|---:|---:|
| List and Sortable ready | 78.885 s (78.702–80.265) | 21.920 s (21.808–22.304) |
| DOM elements | 150,191 | 240,340 |
| Input elements | 40,008 | 20,021 |
| DOM rows / names | 10,000 / 10,000 | 10,000 / 10,000 |
| Real D&D from the first row to the last | 9.034 s (8.805–9.037) | 13.070 s (12.894–13.270) |
| Saving the order and reloading | 95.620 s (87.244–96.291) | 28.899 s (28.257–28.948) |
| Chrome JS heap before D&D | 43.5 MB (42.5–44.5) | 74.1 MB (74.0–74.3) |
| Browser JavaScript errors | 0 | 0 |

> **Long-distance move note:** “Real D&D” means physically dragging the first row's handle to the last row. It is retained and measured to verify compatibility with standard Redmine. For a practical long-distance move in a 10,000-item list, the plugin also provides the checkbox-based workflow: select the items, enter the destination name, choose before or after, and click Move. The extended benchmark measured that client-side move operation at 4.984 s; saving is a separate operation.

In this environment, the plugin shortened the median time until the list was ready by about 72% and the median save-and-reload time by about 70%. It rendered about half as many input elements because value names are normally displayed as text and edited on demand.

The tradeoff is higher client-side cost for the plugin's selection controls, bulk actions, staged changes, undo, and other management features. It produced about 60% more DOM elements, used about 70% more JavaScript heap before D&D, and the measured long-distance D&D took about 45% longer than standard Redmine. These percentages describe this environment, not guaranteed improvements or limits.

## Extended plugin results

The existing plugin-only benchmark exercises additional operations. Its initial navigation measurement does not wait for the same full Sortable-ready condition as the comparison above, so those two page timings should not be compared directly.

| Operation | Measured |
|---|---:|
| Initial navigation | 3.168 s |
| DOM rows / plain-text names | 10,000 / 10,000 |
| Sortable initialization | 4.365 s |
| Real D&D from the first row to the last | 11.125 s |
| Bulk move from the first row to the last by destination name | 4.984 s |
| Saving the order of 10,000 values and reloading | 29.264 s |
| Sortable initialization after saving (included in the previous row) | 4.907 s |
| CSV export (excluding the wait for re-initialization) | 0.321 s |
| Update preview of the same CSV | 0.672 s |
| Restore preview | 3.163 s |
| Chrome JS heap | approx. 116.3 MB |
| Browser JavaScript errors | 0 |

## Assessment

- Both variants completed full rendering, real long-distance D&D, saving, and reloading with exactly 10,000 rows and names and no browser JavaScript errors.
- In this measurement, the plugin substantially reduced the two longest waits: initial readiness and saving/reloading.
- The plugin's extra management features increase DOM size and memory use, and long-distance D&D was slower. This cost should be considered on memory-constrained or low-performance client devices.
- The extended benchmark also completed bulk move, CSV export and preview, and restore preview without removing any functionality.
- No hard limit is placed on the number of values. Specific response times are not guaranteed because browser and device performance have a large effect.
- Server-side updates use bulk SQL statements in batches of 500 rows, avoiding 10,000 individual updates.

These results were measured in a development environment using SQLite and a single process. They do not guarantee values on production databases, concurrent production workloads, other browsers, or users' devices. Measure again for each release and whenever support for a new Redmine series is added.
