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

async function confirmReset(page, scope) {
  let message = '';
  page.once('dialog', function(dialog) {
    message = dialog.message();
    return dialog.accept();
  });
  await (scope || page).locator('.rcfm-reset').click();
  return message;
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

    const selectionTools = page.locator('.rcfm-enumeration-selection-tools');
    const selectionBar = selectionTools.locator('> summary.rcfm-selection-bar');
    const list = page.locator('.rcfm-enumerations');
    const singleAdd = page.locator('.rcfm-single-add');
    const statePanel = page.locator('.rcfm-operation-panel--state');
    const movePanel = page.locator('.rcfm-operation-panel--move');
    const utilities = page.locator('.rcfm-enumeration-utilities');
    const commitBar = page.locator('.rcfm-commit-bar');
    const unsavedNotice = page.locator('.rcfm-unsaved-notice');
    await expect(page.locator('.rcfm-add-one-input')).not.toBeFocused();
    expect(await page.evaluate(function() { return window.scrollY; })).toBe(0);
    await expect(page.locator('.rcfm-introduction')).toHaveText(
      'After you add or edit a choice, a Save changes button appears at the bottom of the page. Press it to make your changes final.'
    );
    await expect(list).toBeVisible();
    await expect(list).toHaveCSS('overflow', 'visible');
    await expect(list.locator('thead th').nth(0).locator('> span').first()).toHaveText('Select');
    await expect(list.locator('thead th').nth(0)).toHaveCSS('position', 'sticky');
    await expect(list.locator('thead th').nth(0)).toHaveCSS('top', '0px');
    await expect(page.locator('#wrapper')).toHaveCSS('overflow', 'clip');
    await expect(page.locator('#content')).toHaveCSS('overflow-x', 'visible');
    await expect(singleAdd).toBeVisible();
    await expect(singleAdd.locator('label')).toHaveText('New choice');
    await expect(selectionBar).toBeVisible();
    await expect(selectionTools).not.toHaveAttribute('open', '');
    await expect(statePanel).toBeHidden();
    await expect(movePanel).toBeHidden();
    await selectionBar.click();
    await expect(selectionTools).toHaveAttribute('open', '');
    await expect(statePanel).toBeVisible();
    await expect(movePanel).toBeVisible();
    await expect(movePanel).not.toHaveAttribute('open', '');
    await expect(movePanel.locator('summary')).toContainText('Move to a destination');
    await expect(utilities.locator('details')).toHaveCount(2);
    await expect(utilities.locator('details').nth(0)).not.toHaveAttribute('open', '');
    await expect(utilities.locator('details').nth(1)).not.toHaveAttribute('open', '');
    await expect(commitBar).toBeVisible();
    await expect(commitBar.locator('.rcfm-commit-controls')).toBeHidden();
    await expect(unsavedNotice).toBeHidden();
    await expect(commitBar.locator('.rcfm-save')).toHaveText('Save changes');
    await expect(commitBar.locator('.rcfm-reset')).toHaveText('Discard all unsaved changes');
    await expect(commitBar.locator('.rcfm-undo')).toHaveAttribute('title', 'Undo the most recent unsaved action.');

    const listBox = await list.boundingBox();
    const singleAddBox = await singleAdd.boundingBox();
    const selectionBox = await selectionBar.boundingBox();
    const stateBox = await statePanel.boundingBox();
    const moveBox = await movePanel.boundingBox();
    const deleteBox = await statePanel.locator('.rcfm-delete-selected').boundingBox();
    const deactivateBox = await statePanel.locator('.rcfm-deactivate-selected').boundingBox();
    const utilitiesBox = await utilities.boundingBox();
    expect(listBox.y).toBeLessThan(singleAddBox.y);
    expect(singleAddBox.y).toBeLessThan(selectionBox.y);
    expect(selectionBox.y).toBeLessThan(stateBox.y);
    expect(stateBox.x).toBeLessThan(moveBox.x);
    expect(stateBox.y).toBeLessThan(utilitiesBox.y);
    expect(deactivateBox.y).toBeLessThan(deleteBox.y);

    await page.setViewportSize({width: 1280, height: 360});
    await page.locator('.rcfm-enumerations tbody tr').nth(0).locator('.rcfm-active').uncheck();
    await expect(page.locator('.rcfm-manager')).toHaveClass(/rcfm-dirty/);
    await expect(commitBar.locator('.rcfm-commit-controls')).toBeVisible();
    await expect(unsavedNotice).toBeVisible();
    const noticeBox = await unsavedNotice.boundingBox();
    expect(noticeBox.y).toBeGreaterThanOrEqual(0);
    expect(noticeBox.y + noticeBox.height).toBeLessThanOrEqual(360);
    await unsavedNotice.locator('.rcfm-review-changes').click();
    await expect(commitBar.locator('.rcfm-save')).toBeFocused();
    const saveBox = await commitBar.locator('.rcfm-save').boundingBox();
    const resetBox = await commitBar.locator('.rcfm-reset').boundingBox();
    expect(resetBox.x).toBeLessThan(saveBox.x);
    const saveBackground = await commitBar.locator('.rcfm-save').evaluate(function(element) {
      return window.getComputedStyle(element).backgroundColor;
    });
    const resetBackground = await commitBar.locator('.rcfm-reset').evaluate(function(element) {
      return window.getComputedStyle(element).backgroundColor;
    });
    expect(saveBackground).not.toBe(resetBackground);
    let resetMessage = '';
    page.once('dialog', function(dialog) {
      resetMessage = dialog.message();
      return dialog.dismiss();
    });
    await commitBar.locator('.rcfm-reset').click();
    expect(resetMessage).toContain('Discard all additions, edits, and reorderings');
    await expect(unsavedNotice).toBeVisible();
    resetMessage = await confirmReset(page, commitBar);
    expect(resetMessage).toContain('Discard all additions, edits, and reorderings');
    await expect(unsavedNotice).toBeHidden();
    await page.setViewportSize({width: 1280, height: 720});
    await page.evaluate(function() { window.scrollTo(0, 0); });

    await page.setViewportSize({width: 1044, height: 834});
    const mediumToolsBox = await selectionTools.boundingBox();
    const mediumStateBox = await statePanel.boundingBox();
    const mediumMoveBox = await movePanel.boundingBox();
    const mediumDeleteBox = await statePanel.locator('.rcfm-delete-selected').boundingBox();
    expect(mediumDeleteBox.x).toBeGreaterThanOrEqual(mediumStateBox.x);
    expect(mediumDeleteBox.x + mediumDeleteBox.width).toBeLessThanOrEqual(
      mediumStateBox.x + mediumStateBox.width
    );
    expect(mediumMoveBox.x + mediumMoveBox.width).toBeLessThanOrEqual(
      mediumToolsBox.x + mediumToolsBox.width
    );
    await expect(commitBar).toHaveCSS('flex-direction', 'column');
    await expect(commitBar.locator('.rcfm-save')).toHaveCSS('white-space', 'nowrap');
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

    await page.setViewportSize({width: 1280, height: 360});
    await list.locator('tbody').evaluate(function(tbody) {
      const sourceRows = Array.from(tbody.children);
      for (let copy = 0; copy < 12; copy += 1) {
        sourceRows.forEach(function(row) { tbody.appendChild(row.cloneNode(true)); });
      }
    });
    await list.locator('tbody tr').nth(20).scrollIntoViewIfNeeded();
    const stickyHeaderBox = await list.locator('thead th').nth(0).boundingBox();
    expect(Math.abs(stickyHeaderBox.y)).toBeLessThan(2);
  });

  test('supports staged edit, undo, redo, move, add, save, and CSV preview', async function({page}, testInfo) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    const rows = page.locator('.rcfm-enumerations tbody tr');
    await expect(rows).toHaveCount(3);
    await page.locator('.rcfm-enumeration-selection-tools > summary').click();
    await page.locator('.rcfm-bulk-move summary').click();

    const firstActive = rows.nth(0).locator('.rcfm-active');
    await firstActive.uncheck();
    await expect(page.locator('.rcfm-save')).toBeEnabled();
    await page.locator('.rcfm-undo').click();
    await expect(page.locator('.rcfm-redo')).toBeFocused();
    await expect(page.locator('.rcfm-history-feedback')).toHaveText('Undid deactivating 1 item(s).');
    await expect(rows.nth(0).locator('.rcfm-active')).toBeChecked();
    await page.locator('.rcfm-redo').click();
    await expect(page.locator('.rcfm-undo')).toBeFocused();
    await expect(page.locator('.rcfm-history-feedback')).toHaveText('Redid deactivating 1 item(s).');
    await expect(rows.nth(0).locator('.rcfm-active')).not.toBeChecked();
    await confirmReset(page);
    await expect(rows.nth(0).locator('.rcfm-active')).toBeChecked();

    const singleAddInput = page.locator('.rcfm-add-one-input');
    await rows.nth(1).evaluate(function(row) { row.dataset.rcfmRenderMarker = 'preserved'; });
    await singleAddInput.fill('Browser added one');
    await singleAddInput.press('Enter');
    await expect(rows).toHaveCount(4);
    await expect(rows.nth(1)).toHaveAttribute('data-rcfm-render-marker', 'preserved');
    await expect(rows.nth(3).locator('.rcfm-enumeration-name')).toHaveText('Browser added one');
    await expect(singleAddInput).toHaveValue('');
    await singleAddInput.fill('Temporary button addition');
    await page.locator('.rcfm-add-one').click();
    await expect(rows).toHaveCount(5);
    await page.locator('.rcfm-undo').click();
    await expect(rows).toHaveCount(4);

    await rows.nth(1).evaluate(function(row) { row.dataset.rcfmRenderMarker = 'preserved'; });
    await rows.nth(0).locator('.rcfm-edit').click();
    await rows.nth(0).locator('.rcfm-name-input').fill('Browser renamed');
    await expect(rows.nth(0).locator('.rcfm-apply-edit')).toHaveText('Apply edit');
    await expect(rows.nth(0).locator('.rcfm-cancel-edit')).toHaveText('Cancel');
    await rows.nth(0).locator('.rcfm-apply-edit').click();
    await expect(rows.nth(0).locator('.rcfm-edit')).toBeFocused();
    await expect(rows.nth(1)).toHaveAttribute('data-rcfm-render-marker', 'preserved');

    await rows.nth(0).locator('.rcfm-select').check();
    await expect(page.locator('.rcfm-selection-count')).toHaveText('1 selected');
    await expect(page.locator('.rcfm-sticky-selection-count')).toBeVisible();
    await expect(page.locator('.rcfm-sticky-selection-count')).toHaveText('1 selected');
    const targetName = await rows.nth(2).locator('.rcfm-enumeration-name').textContent();
    await page.locator('.rcfm-target').fill(targetName);
    await page.locator('input[name="rcfm_enumeration_move_side"][value="after"]').check();
    await page.locator('.rcfm-move-selected').click();
    await expect(page.locator('.rcfm-status')).toContainText('1 moved');

    await page.locator('.rcfm-bulk-add summary').click();
    await page.locator('.rcfm-bulk-add-input').fill('Browser added 1\nBrowser added 2');
    await page.locator('.rcfm-add-lines').click();
    await expect(rows).toHaveCount(6);

    await page.locator('.rcfm-csv-import summary').click();
    await expect(page.locator('.rcfm-csv-template')).toHaveAttribute('href', /template=1/);
    await page.locator('.rcfm-csv-preview-button').click();
    await expect(page.locator('.rcfm-error')).toContainText('There are unsaved changes');
    await saveAndReload(page);

    await expect(page.locator('.rcfm-enumeration-name')).toContainText([
      'Browser value B',
      'Browser value C',
      'Browser renamed',
      'Browser added one',
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

  test('requires an explicit action to apply a name edit and leaves IME Enter alone', async function({page}) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    const row = page.locator('.rcfm-enumerations tbody tr').nth(0);
    const originalName = await row.locator('.rcfm-enumeration-name').textContent();

    await row.locator('.rcfm-edit').click();
    const input = row.locator('.rcfm-name-input');
    await input.fill('かな');
    await input.dispatchEvent('compositionstart', {data: 'かな'});
    await input.dispatchEvent('keydown', {
      key: 'Enter',
      code: 'Enter',
      keyCode: 229,
      isComposing: true
    });
    await input.dispatchEvent('compositionend', {data: 'かな'});
    await expect(input).toBeVisible();
    await expect(input).toHaveValue('かな');
    await expect(page.locator('.rcfm-save')).toBeDisabled();

    await input.press('Enter');
    await expect(input).toBeVisible();
    await expect(page.locator('.rcfm-save')).toBeDisabled();
    await page.locator('.rcfm-introduction').click();
    await expect(input).toBeVisible();

    await row.locator('.rcfm-apply-edit').click();
    await expect(row.locator('.rcfm-enumeration-name')).toHaveText('かな');
    await expect(page.locator('.rcfm-save')).toBeEnabled();
    await confirmReset(page);
    await expect(row.locator('.rcfm-enumeration-name')).toHaveText(originalName);

    await row.locator('.rcfm-edit').click();
    await row.locator('.rcfm-name-input').fill('取り消す名称');
    await row.locator('.rcfm-cancel-edit').click();
    await expect(row.locator('.rcfm-enumeration-name')).toHaveText(originalName);
    await expect(page.locator('.rcfm-save')).toBeDisabled();
  });

  test('chooses a duplicate-name destination by its current position', async function({page}) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    const rows = page.locator('.rcfm-enumerations tbody tr');
    await expect(rows).toHaveCount(6);
    await page.locator('.rcfm-enumeration-selection-tools > summary').click();
    await page.locator('.rcfm-bulk-move summary').click();

    for (let index = 0; index < 2; index += 1) {
      await rows.nth(index).locator('.rcfm-edit').click();
      await rows.nth(index).locator('.rcfm-name-input').fill('Duplicate destination');
      await rows.nth(index).locator('.rcfm-apply-edit').click();
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
    await expect(page.locator('.rcfm-move-error')).toContainText(
      'The destination cannot be one of the selected items.'
    );

    await confirmReset(page);
    await expect(page.locator('.rcfm-save')).toBeDisabled();
    await expect(page.locator('.rcfm-error')).toBeHidden();
  });

  test('clears obsolete errors after the user corrects or undoes an action', async function({page}) {
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    const rows = page.locator('.rcfm-enumerations tbody tr');
    const singleAddInput = page.locator('.rcfm-add-one-input');
    await page.locator('.rcfm-add-one').click();
    await expect(page.locator('#rcfm-add-one-error')).toContainText('Value names cannot be blank.');
    await expect(singleAddInput).toHaveAttribute('aria-invalid', 'true');
    await expect(singleAddInput).not.toHaveAttribute('maxlength');
    await expect(page.locator('.rcfm-error')).toBeHidden();
    const singleAddBox = await singleAddInput.boundingBox();
    const singleAddErrorBox = await page.locator('#rcfm-add-one-error').boundingBox();
    expect(singleAddErrorBox.y).toBeGreaterThanOrEqual(singleAddBox.y + singleAddBox.height);
    await singleAddInput.fill('😀'.repeat(60));
    await expect(page.locator('#rcfm-add-one-error')).toBeHidden();
    await expect(singleAddInput).not.toHaveAttribute('aria-invalid', 'true');
    await page.locator('.rcfm-add-one').click();
    await expect(rows.last().locator('.rcfm-enumeration-name')).toHaveText('😀'.repeat(60));
    await page.locator('.rcfm-undo').click();
    await singleAddInput.fill('😀'.repeat(61));
    await page.locator('.rcfm-add-one').click();
    await expect(page.locator('#rcfm-add-one-error')).toContainText('Value names cannot exceed 60 characters.');
    await singleAddInput.fill('Corrected single value');
    await expect(page.locator('#rcfm-add-one-error')).toBeHidden();

    const originalName = await rows.nth(0).locator('.rcfm-enumeration-name').textContent();
    await rows.nth(0).locator('.rcfm-edit').click();
    const inlineNameInput = rows.nth(0).locator('.rcfm-name-input');
    await expect(inlineNameInput).not.toHaveAttribute('maxlength');
    await inlineNameInput.fill('');
    await rows.nth(0).locator('.rcfm-apply-edit').click();
    await expect(rows.nth(0).locator('.rcfm-field-error')).toContainText('Value names cannot be blank.');
    await expect(inlineNameInput).toHaveAttribute('aria-invalid', 'true');
    await inlineNameInput.fill('Cancelled inline edit');
    await inlineNameInput.press('Escape');
    await expect(rows.nth(0).locator('.rcfm-enumeration-name')).toHaveText(originalName);
    await expect(rows.nth(0).locator('.rcfm-edit')).toBeFocused();
    await expect(page.locator('.rcfm-save')).toBeDisabled();

    await page.locator('.rcfm-enumeration-selection-tools > summary').click();
    await page.locator('.rcfm-bulk-move summary').click();
    await page.locator('.rcfm-deactivate-selected').click();
    await expect(page.locator('.rcfm-error')).toContainText('Select one or more items.');
    await rows.nth(0).locator('.rcfm-select').check();
    await expect(page.locator('.rcfm-error')).toBeHidden();
    await page.locator('.rcfm-move-selected').click();
    const moveError = page.locator('.rcfm-move-error');
    const moveTarget = page.locator('.rcfm-target');
    await expect(moveError).toContainText('Enter a destination name.');
    await expect(moveTarget).toBeFocused();
    await expect(moveTarget).toHaveAttribute('aria-invalid', 'true');
    const moveTargetBox = await moveTarget.boundingBox();
    const moveErrorBox = await moveError.boundingBox();
    expect(moveErrorBox.y).toBeGreaterThanOrEqual(moveTargetBox.y + moveTargetBox.height);
    await moveTarget.fill('Browser value');
    await expect(moveError).toBeHidden();
    await page.locator('.rcfm-move-selected').click();
    const matchingTargets = page.locator('.rcfm-target-candidates');
    await expect(matchingTargets).toBeVisible();
    await expect(matchingTargets.locator('.rcfm-target-candidate')).toHaveCount(2);
    await expect(matchingTargets.locator('.rcfm-target-candidate:not(:disabled)').first()).toBeFocused();
    await page.locator('.rcfm-clear-selection').click();

    await page.locator('.rcfm-bulk-add summary').click();
    await page.locator('.rcfm-add-lines').click();
    await expect(page.locator('#rcfm-bulk-add-error')).toContainText('Value names cannot be blank.');
    await expect(page.locator('.rcfm-bulk-add-input')).toHaveAttribute('aria-invalid', 'true');

    await page.locator('.rcfm-bulk-add-input').fill('Corrected value');
    await page.locator('.rcfm-add-lines').click();
    await expect(page.locator('#rcfm-bulk-add-error')).toBeHidden();
    await expect(page.locator('.rcfm-bulk-add-input')).not.toHaveAttribute('aria-invalid', 'true');
    await expect(rows).toHaveCount(7);

    await page.locator('.rcfm-undo').click();
    await expect(page.locator('.rcfm-error')).toBeHidden();
    await expect(rows).toHaveCount(6);
    await expect(page.locator('.rcfm-save')).toBeDisabled();
  });

  test('shows an explicit conflict and applies a safe merge only after confirmation', async function({page, context}) {
    const otherPage = await context.newPage();
    await page.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});
    await otherPage.goto('/custom_fields/' + fieldId + '/enumerations', {waitUntil: 'networkidle'});

    const firstPageRow = page.locator('.rcfm-enumerations tbody tr').nth(0);
    await firstPageRow.locator('.rcfm-edit').click();
    await firstPageRow.locator('.rcfm-name-input').fill('Changed by first administrator');
    await firstPageRow.locator('.rcfm-apply-edit').click();
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

  test('supports custom-field bulk move, undo, redo, reset, and unambiguous single-row deletion', async function({page}) {
    await page.goto('/custom_fields?tab=GroupCustomField', {waitUntil: 'networkidle'});
    const manager = page.locator('.rcfm-manager').filter({has: page.locator('input[name="field_type"][value="GroupCustomField"]')});
    const source = manager.locator('tr[data-rcfm-id="' + fieldId + '"]');
    const target = manager.locator('tr[data-rcfm-id]').filter({hasText: 'RCFM browser target'});
    const commitControls = manager.locator('.rcfm-commit-controls');
    const unsavedNotice = manager.locator('.rcfm-unsaved-notice');
    const moveError = manager.locator('.rcfm-move-error');
    const targetInput = manager.locator('.rcfm-target');
    await expect(manager.locator('.rcfm-selection-bar')).toHaveCount(0);
    await expect(
      manager.locator('table.custom_fields thead th').first().locator('> span').first()
    ).toHaveText('Move');
    await expect(manager.locator('table.custom_fields thead th').first()).toHaveCSS('position', 'sticky');
    await expect(manager.locator('.rcfm-sticky-selection-count')).toBeHidden();
    await expect(commitControls).toBeHidden();
    await expect(unsavedNotice).toBeHidden();
    const tableBox = await manager.locator('table.custom_fields').boundingBox();
    const bulkMoveBox = await manager.locator('.rcfm-custom-field-bulk-tools').boundingBox();
    expect(tableBox).not.toBeNull();
    expect(bulkMoveBox).not.toBeNull();
    expect(tableBox.y).toBeLessThan(bulkMoveBox.y);
    await expect(source.locator('.rcfm-select')).toHaveAttribute('aria-label', /for moving/);
    await expect(source.locator('.rcfm-delete-custom-field')).toHaveAttribute(
      'data-confirm',
      /Other checked fields will not be deleted/
    );

    await page.setViewportSize({width: 375, height: 812});
    await expect(manager.locator('table.custom_fields thead')).toBeHidden();
    await expect(target.locator('td.rcfm-field-format')).toBeHidden();
    await expect(target.locator('td.rcfm-field-required')).toBeHidden();
    await expect(target.locator('td.name')).toBeVisible();
    await expect(target.locator('.rcfm-delete-custom-field')).toBeVisible();
    const narrowNameBox = await target.locator('td.name').boundingBox();
    expect(narrowNameBox.width).toBeGreaterThan(200);
    const narrowWidth = await page.evaluate(function() {
      return {
        viewport: document.documentElement.clientWidth,
        page: document.documentElement.scrollWidth
      };
    });
    expect(narrowWidth.page).toBeLessThanOrEqual(narrowWidth.viewport);
    await page.setViewportSize({width: 1280, height: 720});

    await manager.locator('.rcfm-bulk-move summary').click();
    await targetInput.fill('RCFM browser target');
    await manager.locator('.rcfm-move-selected').click();
    await expect(moveError).toContainText('Select one or more items');
    await expect(moveError).toBeFocused();
    await source.locator('.rcfm-select').check();
    await expect(moveError).toBeHidden();
    await expect(manager.locator('.rcfm-bulk-move-count')).toHaveText('1 selected');
    await expect(manager.locator('.rcfm-sticky-selection-count')).toBeVisible();
    await expect(manager.locator('.rcfm-sticky-selection-count')).toHaveText('1 selected');
    await expect(manager.locator('.rcfm-move-selected-label')).toHaveText('Move 1 selected');
    await targetInput.fill('');
    await manager.locator('.rcfm-move-selected').click();
    await expect(moveError).toContainText('Enter a destination name.');
    await expect(targetInput).toBeFocused();
    await expect(targetInput).toHaveAttribute('aria-invalid', 'true');
    await targetInput.fill('browser target');
    await expect(moveError).toBeHidden();
    await expect(targetInput).not.toHaveAttribute('aria-invalid', 'true');
    await manager.locator('input[type="radio"][value="after"]').check();
    await manager.locator('.rcfm-move-selected').click();
    const targetCandidates = manager.locator('.rcfm-target-candidates');
    await expect(targetCandidates).toBeVisible();
    await expect(targetCandidates.locator('.rcfm-target-candidate')).toHaveCount(1);
    await expect(targetCandidates.locator('.rcfm-target-candidate')).toBeFocused();
    await targetCandidates.locator('.rcfm-target-candidate').click();
    await expect(manager.locator('.rcfm-status')).toHaveText('Unsaved: 1 item(s) moved');
    await expect(manager.locator('.rcfm-save')).toBeEnabled();
    await expect(commitControls).toBeVisible();
    await expect(unsavedNotice).toBeVisible();
    await unsavedNotice.locator('.rcfm-review-changes').click();
    await expect(manager.locator('.rcfm-save')).toBeFocused();
    await manager.locator('.rcfm-undo').click();
    await expect(manager.locator('.rcfm-redo')).toBeFocused();
    await expect(manager.locator('.rcfm-history-feedback')).toHaveText('Undid moving 1 item(s).');
    await expect(unsavedNotice).toBeHidden();
    await expect(manager.locator('.rcfm-save')).toBeDisabled();
    await manager.locator('.rcfm-redo').click();
    await expect(manager.locator('.rcfm-undo')).toBeFocused();
    await expect(manager.locator('.rcfm-history-feedback')).toHaveText('Redid moving 1 item(s).');
    await expect(unsavedNotice).toBeVisible();
    await expect(manager.locator('.rcfm-save')).toBeEnabled();

    await page.locator('#tab-UserCustomField').click();
    await expect(page).toHaveURL(/tab=UserCustomField/);
    await page.locator('#tab-GroupCustomField').click();
    await expect(page).toHaveURL(/tab=GroupCustomField/);
    await expect(manager.locator('.rcfm-status')).toHaveText('Unsaved: 1 item(s) moved');
    await expect(manager.locator('.rcfm-save')).toBeEnabled();

    const customFieldResetMessage = await confirmReset(page, manager);
    expect(customFieldResetMessage).toContain('Discard all additions, edits, and reorderings');
    await expect(manager.locator('.rcfm-save')).toBeDisabled();

    await source.locator('.rcfm-select').check();
    let confirmMessage = '';
    page.once('dialog', function(dialog) {
      confirmMessage = dialog.message();
      return dialog.accept();
    });
    await Promise.all([
      page.waitForNavigation({waitUntil: 'networkidle'}),
      target.locator('.rcfm-delete-custom-field').click()
    ]);
    expect(confirmMessage).toContain('RCFM browser target');
    expect(confirmMessage).toContain('Other checked fields will not be deleted');
    await expect(page.locator('tr[data-rcfm-id="' + fieldId + '"]')).toBeVisible();
    await expect(page.locator('tr[data-rcfm-name="RCFM browser target"]')).toHaveCount(0);

    await page.getByRole('link', {name: 'Change history'}).click();
    await expect(
      page.locator('table.list tbody tr').filter({hasText: 'Custom field deletion'}).first()
    ).toBeVisible();
  });
});
