'use strict';

const {chromium} = require('playwright');

const variants = {
  standard: {
    rows: '#custom_field_enumerations > li',
    names: '#custom_field_enumerations input[type="text"]',
    handles: '#custom_field_enumerations .sort-handle',
    sortable: '#custom_field_enumerations.ui-sortable',
    save: 'form:has(#custom_field_enumerations) input[type="submit"]'
  },
  plugin: {
    rows: '.rcfm-enumerations tbody > tr',
    names: '.rcfm-enumeration-name',
    handles: '.rcfm-enumerations .rcfm-sort-handle',
    sortable: '.rcfm-enumerations tbody.ui-sortable',
    save: '.rcfm-save'
  }
};

function summarize(runs, key) {
  const values = runs.map(function(run) { return run[key]; }).sort(function(left, right) {
    return left - right;
  });
  return {
    min: values[0],
    median: values[Math.floor(values.length / 2)],
    max: values[values.length - 1]
  };
}

async function dragFirstToLast(page, handlesSelector) {
  const first = page.locator(handlesSelector).first();
  const last = page.locator(handlesSelector).last();
  await first.scrollIntoViewIfNeeded();
  const firstBox = await first.boundingBox();
  if (!firstBox) {
    throw new Error('the first drag handle is not visible');
  }
  await page.mouse.move(firstBox.x + firstBox.width / 2, firstBox.y + firstBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(firstBox.x + firstBox.width / 2, firstBox.y + firstBox.height, {steps: 5});
  await page.evaluate(function() {
    window.scrollTo(0, document.documentElement.scrollHeight);
  });
  await page.waitForTimeout(100);
  const lastBox = await last.boundingBox();
  if (!lastBox) {
    await page.mouse.up();
    throw new Error('the last drag handle is not visible');
  }
  await page.mouse.move(lastBox.x + lastBox.width / 2, lastBox.y + lastBox.height / 2, {steps: 20});
  await page.mouse.up();
}

(async function() {
  const baseUrl = process.env.RCFM_BASE_URL || 'http://127.0.0.1:3210';
  const fieldId = process.env.RCFM_FIELD_ID;
  const variant = process.env.RCFM_VARIANT;
  const runCount = Number(process.env.RCFM_RUNS || '3');
  const selectors = variants[variant];
  if (!fieldId) {
    throw new Error('RCFM_FIELD_ID is required');
  }
  if (!selectors) {
    throw new Error('RCFM_VARIANT must be standard or plugin');
  }
  if (!Number.isInteger(runCount) || runCount < 1 || runCount > 10) {
    throw new Error('RCFM_RUNS must be an integer from 1 to 10');
  }

  const launchOptions = {headless: true};
  if (process.env.RCFM_CHROME_PATH) {
    launchOptions.executablePath = process.env.RCFM_CHROME_PATH;
  }
  const browser = await chromium.launch(launchOptions);
  const context = await browser.newContext();
  const loginPage = await context.newPage();
  loginPage.setDefaultTimeout(600000);
  await loginPage.goto(baseUrl + '/login');
  await loginPage.locator('#username').fill('admin');
  await loginPage.locator('#password').fill('admin');
  await Promise.all([
    loginPage.waitForURL(function(url) { return !url.pathname.endsWith('/login'); }),
    loginPage.locator('input[type="submit"]').click()
  ]);
  await loginPage.close();

  const runs = [];
  for (let runNumber = 1; runNumber <= runCount; runNumber += 1) {
    const page = await context.newPage();
    page.setDefaultTimeout(600000);
    const pageErrors = [];
    page.on('pageerror', function(error) { pageErrors.push(error.message); });

    let started = Date.now();
    await Promise.all([
      page.goto(baseUrl + '/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'domcontentloaded'}),
      page.waitForSelector(selectors.sortable)
    ]);
    const sortableReadyMs = Date.now() - started;
    await page.waitForLoadState('networkidle');
    const pageLoadMs = Date.now() - started;

    const counts = await page.evaluate(function(config) {
      return {
        dom_nodes: document.querySelectorAll('body *').length,
        input_elements: document.querySelectorAll('body input').length,
        rows: document.querySelectorAll(config.rows).length,
        names: document.querySelectorAll(config.names).length,
        used_js_heap_bytes: performance.memory ? performance.memory.usedJSHeapSize : null
      };
    }, selectors);
    if (counts.rows !== 10000 || counts.names !== 10000) {
      throw new Error('expected 10,000 rows and names, got ' + counts.rows + ' rows and ' + counts.names + ' names');
    }

    const firstName = await page.locator(selectors.names).first().inputValue().catch(function() {
      return page.locator(selectors.names).first().textContent();
    });
    started = Date.now();
    await dragFirstToLast(page, selectors.handles);
    const dndLongDistanceMs = Date.now() - started;
    const nameAfterMove = await page.locator(selectors.names).first().inputValue().catch(function() {
      return page.locator(selectors.names).first().textContent();
    });
    if (nameAfterMove === firstName) {
      throw new Error('drag and drop did not move the first row');
    }

    started = Date.now();
    let saveResponse;
    if (variant === 'standard') {
      saveResponse = await Promise.all([
        page.waitForNavigation({waitUntil: 'networkidle', timeout: 600000}),
        page.locator(selectors.save).click()
      ]).then(function(results) { return results[0]; });
    } else {
      const results = await Promise.all([
        page.waitForResponse(function(response) {
          return response.request().method() === 'PUT' &&
            response.url().includes('/custom_field_manager/custom_fields/');
        }, {timeout: 600000}),
        page.waitForNavigation({waitUntil: 'networkidle', timeout: 600000}),
        page.locator(selectors.save).click()
      ]);
      saveResponse = results[0];
    }
    if (!saveResponse || !saveResponse.ok()) {
      throw new Error('save failed' + (saveResponse ? ': ' + saveResponse.status() : ' without a response'));
    }
    await page.waitForSelector(selectors.sortable, {timeout: 600000});
    const saveAndReloadMs = Date.now() - started;

    const metrics = {
      run: runNumber,
      sortable_ready_ms: sortableReadyMs,
      page_load_ms: pageLoadMs,
      dom_nodes: counts.dom_nodes,
      input_elements: counts.input_elements,
      rows: counts.rows,
      names: counts.names,
      dnd_long_distance_ms: dndLongDistanceMs,
      save_and_reload_ms: saveAndReloadMs,
      used_js_heap_bytes: counts.used_js_heap_bytes,
      page_errors: pageErrors
    };
    runs.push(metrics);
    process.stderr.write(variant + ' run ' + runNumber + ': ' + JSON.stringify(metrics) + '\n');
    await page.close();
  }

  const numericKeys = [
    'sortable_ready_ms',
    'page_load_ms',
    'dom_nodes',
    'input_elements',
    'dnd_long_distance_ms',
    'save_and_reload_ms',
    'used_js_heap_bytes'
  ];
  const summary = {};
  numericKeys.forEach(function(key) {
    summary[key] = summarize(runs, key);
  });
  process.stdout.write(JSON.stringify({variant: variant, runs: runs, summary: summary}, null, 2) + '\n');
  await browser.close();
})().catch(function(error) {
  process.stderr.write(error.stack + '\n');
  process.exitCode = 1;
});
