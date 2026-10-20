'use strict';

const fs = require('fs');
const {test, expect} = require('playwright/test');

const fieldId = process.env.RCFM_FIELD_ID;

async function login(page) {
  await page.goto('/login');
  await page.locator('#username').fill('admin');
  await page.locator('#password').fill('admin');
  await Promise.all([
    page.waitForURL(function(url) { return !url.pathname.endsWith('/login'); }),
    page.locator('input[type="submit"]').click()
  ]);
}

async function saveAndReload(page) {
  const responsePromise = page.waitForResponse(function(response) {
    return response.request().method() === 'PUT' &&
      response.url().includes('/custom_field_manager/custom_fields/');
  });
  await Promise.all([
    page.waitForNavigation({waitUntil: 'networkidle'}),
    page.locator('.rcfm-save').click()
  ]);
  const response = await responsePromise;
  expect(response.ok()).toBeTruthy();
}

test.describe.serial('custom field manager browser behavior', function() {
  test.beforeEach(async function({page}) {
    if (!fieldId) {
      throw new Error('RCFM_FIELD_ID is required');
    }
    await login(page);
  });

  test('groups controls by purpose and keeps commit actions in a predictable position', async function({page}) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});

    const selectionBar = page.locator('.rcfm-selection-bar');
    const statePanel = page.locator('.rcfm-operation-panel--state');
    const movePanel = page.locator('.rcfm-operation-panel--move');
    const commitBar = page.locator('.rcfm-commit-bar');
    await expect(selectionBar).toBeVisible();
    await expect(statePanel).toBeVisible();
    await expect(movePanel).toBeVisible();
    await expect(commitBar).toBeVisible();
    await expect(commitBar.locator('.rcfm-save')).toHaveText('Save changes');
    await expect(commitBar.locator('.rcfm-reset')).toHaveText('Discard changes');

    const selectionBox = await selectionBar.boundingBox();
    const stateBox = await statePanel.boundingBox();
    const moveBox = await movePanel.boundingBox();
    const deleteBox = await statePanel.locator('.rcfm-delete-selected').boundingBox();
    const deactivateBox = await statePanel.locator('.rcfm-deactivate-selected').boundingBox();
    const saveBox = await commitBar.locator('.rcfm-save').boundingBox();
    const resetBox = await commitBar.locator('.rcfm-reset').boundingBox();
    expect(selectionBox.y).toBeLessThan(stateBox.y);
    expect(stateBox.x).toBeLessThan(moveBox.x);
    expect(deactivateBox.y).toBeLessThan(deleteBox.y);
    expect(resetBox.x).toBeLessThan(saveBox.x);

    await page.locator('.rcfm-enumerations tbody tr').nth(0).locator('.rcfm-active').uncheck();
    await expect(page.locator('.rcfm-manager')).toHaveClass(/rcfm-dirty/);
    const saveBackground = await commitBar.locator('.rcfm-save').evaluate(function(element) {
      return window.getComputedStyle(element).backgroundColor;
    });
    const resetBackground = await commitBar.locator('.rcfm-reset').evaluate(function(element) {
      return window.getComputedStyle(element).backgroundColor;
    });
    expect(saveBackground).not.toBe(resetBackground);
    await commitBar.locator('.rcfm-reset').click();

    await page.setViewportSize({width: 1044, height: 834});
    const mediumStateBox = await statePanel.boundingBox();
    const mediumDeleteBox = await statePanel.locator('.rcfm-delete-selected').boundingBox();
    expect(mediumDeleteBox.x).toBeGreaterThanOrEqual(mediumStateBox.x);
    expect(mediumDeleteBox.x + mediumDeleteBox.width).toBeLessThanOrEqual(
      mediumStateBox.x + mediumStateBox.width
    );
    await expect(commitBar.locator('.rcfm-undo')).not.toHaveClass(/icon/);
    await expect(commitBar.locator('.rcfm-redo')).not.toHaveClass(/icon/);
    const undoIcon = await commitBar.locator('.rcfm-undo').evaluate(function(element) {
      return window.getComputedStyle(element, '::before').content;
    });
    const redoIcon = await commitBar.locator('.rcfm-redo').evaluate(function(element) {
      return window.getComputedStyle(element, '::before').content;
    });
    expect(undoIcon).toBe('"↶"');
    expect(redoIcon).toBe('"↷"');

    await page.setViewportSize({width: 720, height: 900});
    const narrowStateBox = await statePanel.boundingBox();
    const narrowMoveBox = await movePanel.boundingBox();
    expect(Math.abs(narrowStateBox.x - narrowMoveBox.x)).toBeLessThan(2);
    expect(narrowStateBox.y).toBeLessThan(narrowMoveBox.y);
    await expect(commitBar).toHaveCSS('position', 'static');
  });

  test('supports staged edit, undo, redo, move, add, save, and CSV preview', async function({page}, testInfo) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    const rows = page.locator('.rcfm-enumerations tbody tr');
    await expect(rows).toHaveCount(3);

    const firstActive = rows.nth(0).locator('.rcfm-active');
    await firstActive.uncheck();
    await expect(page.locator('.rcfm-save')).toBeEnabled();
    await page.locator('.rcfm-undo').click();
    await expect(rows.nth(0).locator('.rcfm-active')).toBeChecked();
    await page.locator('.rcfm-redo').click();
    await expect(rows.nth(0).locator('.rcfm-active')).not.toBeChecked();
    await page.locator('.rcfm-reset').click();
    await expect(rows.nth(0).locator('.rcfm-active')).toBeChecked();

    await rows.nth(0).locator('.rcfm-edit').click();
    await rows.nth(0).locator('.rcfm-name-input').fill('Browser renamed');
    await rows.nth(0).locator('.rcfm-name-input').press('Enter');

    await rows.nth(0).locator('.rcfm-select').check();
    await expect(page.locator('.rcfm-selection-count')).toHaveText('1 selected');
    const targetName = await rows.nth(2).locator('.rcfm-enumeration-name').textContent();
    await page.locator('.rcfm-target').fill(targetName);
    await page.locator('input[name="rcfm_enumeration_move_side"][value="after"]').check();
    await page.locator('.rcfm-move-selected').click();

    await page.locator('.rcfm-bulk-add summary').click();
    await page.locator('.rcfm-bulk-add-input').fill('Browser added 1\nBrowser added 2');
    await page.locator('.rcfm-add-lines').click();
    await expect(rows).toHaveCount(5);

    await page.locator('.rcfm-csv-import summary').click();
    await expect(page.locator('.rcfm-csv-template')).toHaveAttribute('href', /template=1/);
    await page.locator('.rcfm-csv-preview-button').click();
    await expect(page.locator('.rcfm-error')).toContainText('There are unsaved changes');
    await saveAndReload(page);

    await expect(page.locator('.rcfm-enumeration-name')).toContainText([
      'Browser value B',
      'Browser value C',
      'Browser renamed',
      'Browser added 1',
      'Browser added 2'
    ]);

    const exportPath = await page.locator('.rcfm-csv-export').getAttribute('href');
    const response = await page.request.get(exportPath);
    expect(response.ok()).toBeTruthy();
    const csvPath = testInfo.outputPath('round-trip.csv');
    fs.writeFileSync(csvPath, await response.body());
    await page.locator('.rcfm-csv-import summary').click();
    await page.locator('.rcfm-csv-file').setInputFiles(csvPath);
    await page.locator('.rcfm-csv-preview-button').click();
    await expect(page.locator('.rcfm-csv-preview')).toBeVisible();
    await expect(page.locator('.rcfm-csv-diffs tbody tr')).toHaveCount(0);
    await expect(page.locator('.rcfm-csv-apply-button')).toBeVisible();
  });

  test('chooses a duplicate-name destination by its current position', async function({page}) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    const rows = page.locator('.rcfm-enumerations tbody tr');
    await expect(rows).toHaveCount(5);

    for (let index = 0; index < 2; index += 1) {
      await rows.nth(index).locator('.rcfm-edit').click();
      await rows.nth(index).locator('.rcfm-name-input').fill('Duplicate destination');
      await rows.nth(index).locator('.rcfm-name-input').press('Enter');
    }

    const sourceId = await rows.nth(4).getAttribute('data-rcfm-client-id');
    await rows.nth(4).locator('.rcfm-select').check();
    await expect(page.locator('.rcfm-target-list option').nth(0)).toHaveAttribute(
      'value',
      /Duplicate destination — current position 1 \(#\d+\)/
    );
    await page.locator('.rcfm-target').fill('Duplicate destination');
    await page.locator('.rcfm-move-selected').click();

    const candidates = page.locator('.rcfm-target-candidates');
    await expect(candidates).toBeVisible();
    await expect(candidates.locator('.rcfm-target-candidate')).toHaveCount(2);
    await expect(candidates.locator('.rcfm-target-candidate').nth(0)).toContainText(
      'Duplicate destination — current position 1'
    );

    await rows.nth(0).locator('.rcfm-select').check();
    await page.locator('.rcfm-move-selected').click();
    await expect(candidates.locator('.rcfm-target-candidate').nth(0)).toBeDisabled();
    await expect(candidates.locator('.rcfm-target-candidate').nth(0)).toContainText('(selected)');
    await expect(candidates.locator('.rcfm-target-candidate').nth(1)).toBeEnabled();
    await candidates.locator('.rcfm-target-candidate').nth(1).click();
    await expect(candidates).toBeHidden();
    await expect(rows.nth(1)).toHaveAttribute('data-rcfm-client-id', sourceId);

    await page.locator('.rcfm-select-all').click();
    await page.locator('.rcfm-move-selected').click();
    await expect(candidates).toBeHidden();
    await expect(page.locator('.rcfm-error')).toContainText(
      'The destination cannot be one of the selected items.'
    );

    await page.locator('.rcfm-reset').click();
    await expect(page.locator('.rcfm-save')).toBeDisabled();
    await expect(page.locator('.rcfm-error')).toBeHidden();
  });

  test('clears obsolete errors after the user corrects or undoes an action', async function({page}) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    const rows = page.locator('.rcfm-enumerations tbody tr');
    await page.locator('.rcfm-deactivate-selected').click();
    await expect(page.locator('.rcfm-error')).toContainText('Select one or more items.');
    await rows.nth(0).locator('.rcfm-select').check();
    await expect(page.locator('.rcfm-error')).toBeHidden();
    await page.locator('.rcfm-move-selected').click();
    await expect(page.locator('.rcfm-error')).toContainText('Enter a destination name.');
    await page.locator('.rcfm-target').fill('Browser value B');
    await expect(page.locator('.rcfm-error')).toBeHidden();
    await page.locator('.rcfm-clear-selection').click();

    await page.locator('.rcfm-bulk-add summary').click();
    await page.locator('.rcfm-add-lines').click();
    await expect(page.locator('.rcfm-error')).toContainText('Value names cannot be blank.');

    await page.locator('.rcfm-bulk-add-input').fill('Corrected value');
    await page.locator('.rcfm-add-lines').click();
    await expect(page.locator('.rcfm-error')).toBeHidden();
    await expect(rows).toHaveCount(6);

    await page.locator('.rcfm-undo').click();
    await expect(page.locator('.rcfm-error')).toBeHidden();
    await expect(rows).toHaveCount(5);
    await expect(page.locator('.rcfm-save')).toBeDisabled();
  });

  test('shows an explicit conflict and applies a safe merge only after confirmation', async function({page, context}) {
    const otherPage = await context.newPage();
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    await otherPage.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});

    const firstPageRow = page.locator('.rcfm-enumerations tbody tr').nth(0);
    await firstPageRow.locator('.rcfm-edit').click();
    await firstPageRow.locator('.rcfm-name-input').fill('Changed by first administrator');
    await firstPageRow.locator('.rcfm-name-input').press('Enter');
    await saveAndReload(page);

    const secondPageRow = otherPage.locator('.rcfm-enumerations tbody tr').nth(1);
    await secondPageRow.locator('.rcfm-active').uncheck();
    const conflictResponse = otherPage.waitForResponse(function(response) {
      return response.request().method() === 'PUT' &&
        response.url().includes('/custom_field_manager/custom_fields/');
    });
    await otherPage.locator('.rcfm-save').click();
    expect((await conflictResponse).status()).toBe(409);
    await expect(otherPage.locator('.rcfm-conflict')).toBeVisible();
    await expect(otherPage.locator('.rcfm-conflict-merge')).toBeVisible();

    await Promise.all([
      otherPage.waitForNavigation({waitUntil: 'networkidle'}),
      otherPage.locator('.rcfm-conflict-merge').click()
    ]);
    await expect(otherPage.locator('.rcfm-enumeration-name').nth(0)).toHaveText('Changed by first administrator');
    await expect(otherPage.locator('.rcfm-active').nth(1)).not.toBeChecked();
  });

  test('supports custom-field bulk move, undo, redo, and reset', async function({page}) {
    await page.goto('/custom_fields?tab=GroupCustomField', {waitUntil: 'networkidle'});
    const manager = page.locator('.rcfm-manager').filter({has: page.locator('input[name="field_type"][value="GroupCustomField"]')});
    const source = manager.locator('tr[data-rcfm-id="' + fieldId + '"]');
    const target = manager.locator('tr[data-rcfm-id]').filter({hasText: 'RCFM browser target'});
    await manager.locator('.rcfm-target').fill('RCFM browser target');
    await manager.locator('.rcfm-move-selected').click();
    await expect(manager.locator('.rcfm-error')).toContainText('Select one or more items');
    await source.locator('.rcfm-select').check();
    await expect(manager.locator('.rcfm-error')).toBeHidden();
    await expect(manager.locator('.rcfm-selection-count')).toHaveText('1 selected');
    await manager.locator('.rcfm-target').fill('RCFM browser target');
    await manager.locator('input[type="radio"][value="after"]').check();
    await manager.locator('.rcfm-move-selected').click();
    await expect(manager.locator('.rcfm-save')).toBeEnabled();
    await manager.locator('.rcfm-undo').click();
    await expect(manager.locator('.rcfm-save')).toBeDisabled();
    await manager.locator('.rcfm-redo').click();
    await expect(manager.locator('.rcfm-save')).toBeEnabled();
    await manager.locator('.rcfm-reset').click();
    await expect(manager.locator('.rcfm-save')).toBeDisabled();
  });
});
