'use strict';

const {chromium} = require('playwright');
const fs = require('fs');

(async function() {
  const baseUrl = process.env.RCFM_BASE_URL || 'http://127.0.0.1:3210';
  const fieldId = process.env.RCFM_FIELD_ID;
  const skipMutation = process.env.RCFM_SKIP_MUTATION === '1';
  const skipDnd = process.env.RCFM_SKIP_DND === '1';
  if (!fieldId) {
    throw new Error('RCFM_FIELD_ID is required');
  }

  const launchOptions = {headless: true};
  if (process.env.RCFM_CHROME_PATH) {
    launchOptions.executablePath = process.env.RCFM_CHROME_PATH;
  }
  const browser = await chromium.launch(launchOptions);
  const page = await browser.newPage();
  page.setDefaultTimeout(180000);
  const metrics = {};
  const pageErrors = [];
  page.on('pageerror', function(error) { pageErrors.push(error.message); });

  await page.goto(baseUrl + '/login');
  await page.locator('#username').fill('admin');
  await page.locator('#password').fill('admin');
  await Promise.all([
    page.waitForURL(function(url) { return !url.pathname.endsWith('/login'); }),
    page.locator('input[type="submit"]').click()
  ]);

  let started = Date.now();
  await page.goto(baseUrl + '/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
  metrics.page_load_ms = Date.now() - started;
  metrics.dom_rows = await page.locator('.rcfm-enumerations tbody tr').count();
  metrics.text_nodes = await page.locator('.rcfm-enumeration-name').count();
  metrics.dnd_initialization_ms = await page.evaluate(function() {
    const entry = performance.getEntriesByName('rcfm-enumerations-init').pop();
    return entry ? entry.duration : null;
  });

  if (!skipMutation) {
    if (!skipDnd) {
      started = Date.now();
      await page.locator('.rcfm-enumerations tbody tr').first().locator('.rcfm-sort-handle').dragTo(
        page.locator('.rcfm-enumerations tbody tr').last().locator('.rcfm-sort-handle'),
        {timeout: 120000}
      );
      metrics.dnd_long_distance_ms = Date.now() - started;
      await page.evaluate(function() {
        window.jQuery('.rcfm-reset').trigger('click');
      });
    }

    metrics.long_distance_move_ms = await page.evaluate(function() {
      const startedAt = performance.now();
      const rows = document.querySelectorAll('.rcfm-enumerations tbody tr');
      const checkbox = rows[0].querySelector('.rcfm-select');
      checkbox.checked = true;
      window.jQuery(checkbox).trigger('change');
      const last = rows[rows.length - 1];
      const targetName = last.querySelector('.rcfm-enumeration-name').textContent;
      const targetId = last.querySelector('.rcfm-record-id').textContent.replace('#', '');
      document.querySelector('.rcfm-target').value = targetName + ' (#' + targetId + ')';
      document.querySelector('input[name="rcfm_enumeration_move_side"][value="before"]').checked = true;
      window.jQuery('.rcfm-move-selected').trigger('click');
      return performance.now() - startedAt;
    });
    metrics.rows_after_move = await page.locator('.rcfm-enumerations tbody tr').count();

    started = Date.now();
    const saveResult = await Promise.all([
      page.waitForResponse(function(response) {
        return response.request().method() === 'PUT' && response.url().includes('/custom_field_manager/custom_fields/');
      }),
      page.waitForNavigation({waitUntil: 'networkidle', timeout: 120000}),
      page.evaluate(function() { window.jQuery('.rcfm-save').trigger('click'); })
    ]);
    const saveResponse = saveResult[0];
    if (!saveResponse.ok()) {
      throw new Error('save failed: ' + saveResponse.status());
    }
    await page.waitForFunction(function() {
      return performance.getEntriesByName('rcfm-enumerations-init').length > 0;
    }, null, {timeout: 180000});
    metrics.save_and_reload_ms = Date.now() - started;
    metrics.post_save_dnd_initialization_ms = await page.evaluate(function() {
      const entry = performance.getEntriesByName('rcfm-enumerations-init').pop();
      return entry ? entry.duration : null;
    });
  }
  process.stderr.write('browser-stage: ' + JSON.stringify(metrics) + '\n');

  started = Date.now();
  const exportPath = await page.locator('.rcfm-csv-export').getAttribute('href');
  const exportResponse = await page.request.get(baseUrl + exportPath);
  if (!exportResponse.ok()) {
    throw new Error('CSV export failed: ' + exportResponse.status());
  }
  const csvPath = '/tmp/rcfm-performance-10000.csv';
  fs.writeFileSync(csvPath, await exportResponse.body());
  metrics.csv_export_ms = Date.now() - started;

  started = Date.now();
  await page.locator('.rcfm-csv-file').setInputFiles(csvPath);
  const previewResponse = await Promise.all([
    page.waitForResponse(function(response) {
      return response.request().method() === 'POST' && response.url().includes('/import/preview');
    }, {timeout: 120000}),
    page.evaluate(function() { window.jQuery('.rcfm-csv-preview-button').trigger('click'); })
  ]).then(function(values) { return values[0]; });
  if (!previewResponse.ok()) {
    throw new Error('CSV preview failed: ' + previewResponse.status() + ' ' + await previewResponse.text());
  }
  await page.waitForFunction(function() {
    const preview = document.querySelector('.rcfm-csv-preview');
    const error = document.querySelector('.rcfm-error');
    return (preview && !preview.hidden) || (error && !error.hidden);
  }, null, {timeout: 120000});
  const importError = await page.locator('.rcfm-error').evaluate(function(element) {
    return element.hidden ? '' : element.textContent;
  });
  if (importError) {
    throw new Error('CSV preview UI failed: ' + importError + '; page errors: ' + pageErrors.join(' | '));
  }
  metrics.csv_preview_ms = Date.now() - started;
  metrics.csv_diff_rows = await page.locator('.rcfm-csv-diffs tbody tr').count();

  metrics.used_js_heap_bytes = await page.evaluate(function() {
    return performance.memory ? performance.memory.usedJSHeapSize : null;
  });

  started = Date.now();
  await page.goto(baseUrl + '/custom_field_manager/history', {waitUntil: 'networkidle'});
  await page.locator('.rcfm-history-list tbody tr').first().locator('a.icon-magnifier').click();
  await page.locator('form[action$="/restore/preview"] input[type="submit"]').click();
  await page.waitForLoadState('networkidle');
  metrics.restore_preview_ms = Date.now() - started;
  metrics.restore_diff_rows = await page.locator('table.list tbody tr').count();
  metrics.page_errors = pageErrors;

  process.stdout.write(JSON.stringify(metrics, null, 2) + '\n');
  await browser.close();
})().catch(function(error) {
  process.stderr.write(error.stack + '\n');
  process.exitCode = 1;
});
