# Redmine Custom Field Manager

[日本語](README.ja.md)

Redmine Custom Field Manager is a Redmine plugin for safely managing custom-field order and large Key/value lists. It keeps Redmine's familiar administration screens and adds staged bulk editing, CSV import and export, conflict handling, and restorable history.

Version `1.0.0` is the first stable release. This English README is the canonical project overview and operating guide; [`docs/specification.md`](docs/specification.md) remains the source of truth for product behavior.

## What changes after installation

The plugin enhances **Administration → Custom fields** instead of adding a separate management area.

- Every custom field is shown in one list and can be reordered by drag and drop or by multi-selection.
- Reordering and Key/value list edits stay in the browser until you press **Save changes**. **Undo**, **Redo**, **Discard all unsaved changes**, and a warning when leaving the page with unsaved changes are available.
- Redmine's create, edit, copy, and delete actions remain available. Deleting a custom field is still an immediate, single-row action and is clearly separated from selecting rows to move.
- A single staged editor lets you rename, activate, deactivate, reorder, add (one at a time or in bulk), and safely delete Key/value list values.
- Key/value lists can be exported to CSV and imported in append, update, or full-synchronization mode, with a preview before anything is written.
- Concurrent edits are detected. Instead of silently overwriting another administrator's work, the plugin shows the state when editing started, your changes, and the current server state.
- Every successful save is recorded in a change history. You can preview and then restore an entire field order or Key/value list. Custom-field deletions are also recorded for audit, but cannot be restored by the plugin.

The screenshots below were taken on Redmine 7.0 with the Japanese locale. Labels may differ depending on the Redmine version and the selected language.

### Staged custom-field ordering

- Drag individual rows, or select one or more rows and open the collapsed **Move to a destination** panel directly below the list. The panel works the same way for one row or many.
- Destinations are chosen by name. If several fields share a name, clickable choices labeled with their current list positions appear, so you never need to know or enter an internal ID. IDs are shown only as supplementary information.
- Checkboxes are used only to select rows to move; per-row actions are in a separate column.
- The unsaved counter shows the smallest number of rows that must move to produce the new order. Moving the last of 100 fields to the top counts as one move, not 100 changed positions.
- **Delete this field** immediately deletes only that row's field. The confirmation names the field, states that other checked rows are not affected, and warns that the field, its choices, and its saved values will be deleted and cannot be restored by this plugin.

![Staged custom-field ordering](docs/images/custom-field-ordering.png)

### Key/value list manager

- The value list comes first. The **New choice** field directly below it adds one value at a time.
- **Selected item actions** follow the list and are collapsed by default.
- **Add multiple values** and **CSV export/import** sit further down as compact, collapsed tools for occasional use.
- Inline renaming, activation, deactivation, deletion, drag and drop, and multi-selection are available.
- Values marked with a lock icon show why they cannot be deleted.
- Before you save, the summary shows how many values will be added, updated, deleted, and moved. All changes are saved in a single transaction, so nothing is ever partially saved.

![Staged Key/value list editing](docs/images/enumeration-manager.png)

### Change history and restore

- Open **Change history** from either enhanced screen to review recorded saves, preview restoring an entire target, or delete old history.
- Custom-field deletion entries show the deleted field and how many values and choices were removed, for audit only. No restore action is offered for them because restoring would not be safe.
- History is kept indefinitely by default. You can limit it by age or by number of generations in the plugin settings.

![Change history](docs/images/change-history.png)

## Data safety

Installing the plugin does not rewrite existing custom fields, enumeration IDs, or stored custom values. Its migrations create only plugin-owned `rcfm_*` tables for revisions, history, instance metadata, and confirmed cross-instance import mappings.

Normal saves intentionally update Redmine's standard custom-field and enumeration records, while preserving existing IDs. A value that is currently in use, or set as a default, cannot be deleted; the whole save is rejected rather than partially applied. Reordering, bulk edits, imports, and restores are committed in the same transaction as their history records.

Removing or disabling the plugin does not remove Redmine's standard custom fields, enumerations, or values already stored on issues and other objects. The plugin-owned `rcfm_*` tables are left in place and ignored by Redmine, so history is not destroyed accidentally. Do not blindly roll the plugin's migrations back to version zero: the current history-column expansion is intentionally irreversible because shrinking the column could truncate stored snapshots. Back up the database and have a database administrator review any permanent removal of the plugin-owned tables.

## Supported versions

- Redmine 7.0.x
- Redmine 6.1.x
- Redmine 6.0.x

CI currently tests Redmine 7.0.2, 6.1.5, and 6.0.11 on SQLite, MySQL 8.4, MariaDB 11.4, and PostgreSQL 17. Newly released Redmine series are supported only after compatibility testing.

## Installation

### Install

1. Back up the Redmine database.
2. Place this repository at `plugins/redmine_custom_field_manager` under the Redmine root. Keep the directory name `redmine_custom_field_manager`.
3. From the Redmine root, run:

   ```sh
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

4. Restart Redmine.
5. Sign in as an administrator and open **Administration → Custom fields**.

### Update

1. Back up the Redmine database. Do this before every production update.
2. Stop Redmine.
3. Replace the plugin files.
4. Run the same migration command as for installation.
5. Start Redmine.

## Usage

### Reorder custom fields

1. Open **Administration → Custom fields** and select a field-type tab.
2. Drag a row to its new position, or select one or more rows and open **Move to a destination** below the list.
   - Field names are ordinary text on the page, so browser find (`Ctrl+F` / `⌘+F`) works even in large lists.
3. Enter the destination field name, choose **Before** or **After**, and click **Move N selected**.
   - If several fields share the destination name, click the choice identified by its current list position.
4. Review the pending order. Use **Undo**, **Redo**, or **Discard all unsaved changes** if needed.
5. Click **Save changes** to commit the complete order for that field type.

### Edit a Key/value list

1. Open **Administration → Custom fields**, open a custom field whose format is **Key/value list**, and click **Edit** next to **Possible values**.
2. Edit the values.
   - Add one value at a time with **New choice** directly below the list, or several at once with **Add multiple values** (one value per line).
   - Rename, activate, deactivate, or delete values inline, and reorder them by drag and drop.
   - To act on several values at once, select them and open **Selected item actions**.
   - Values that are already in use cannot be deleted. Deactivate them instead.
3. Review the pending changes. Use **Undo**, **Redo**, or **Discard all unsaved changes** if needed.
4. Click **Save changes**. Nothing is written until you do.
   - Usage is checked again immediately before saving. If a value has come into use in the meantime, the entire save is stopped and nothing is partially written.

### Import or export CSV

1. Save or discard any changes on the Key/value list editor first. CSV operations always use the saved database state.
2. Expand **CSV export/import**.
3. To export, click **Export the current list as CSV**. To start a new file, click **Download an empty CSV template**, which contains the correct columns and metadata for the current field.
4. To import, choose a CSV file and an import mode:
   - **Append** creates a new value for every CSV data row.
   - **Update and add** updates values whose IDs come from this Redmine instance and adds rows without a local ID.
   - **Full synchronization** also handles local values missing from the CSV. Values in use can only be deactivated; unused values can be deleted or deactivated.
5. Click **Preview import** and review the differences. Every import requires this preview.
   - IDs in a CSV exported from another Redmine instance are never treated as local IDs. Confirm a suggested mapping or choose to create a new value; confirmed mappings are reused by later imports.
6. Click **Apply this import** to save the changes.

### Resolve concurrent edits

1. If another administrator saved the same target first, your next save opens a conflict panel. Your unsaved changes are kept.
2. Compare the state when editing started, your edit, and the current server state.
3. Choose one of the following:
   - **Continue editing**: return to your unsaved changes.
   - **Discard and reload**: drop your changes and load the current server state.
   - **Review and save merge proposal**: save the proposed three-way merge. This appears only when a safe merge exists, and a merge is never applied unless you choose it.
   - **Force overwrite with my changes**: explicitly replace the server state with your version. Deletion safeguards still apply.

### Review and restore history

1. Click **Change history** on either enhanced screen.
2. Click **View** on an entry. Targets, operations, and before/after values are shown with readable labels; raw JSON is kept in the collapsed **Technical details (JSON)** section.
3. Click **Preview restore** to see the differences, including active/inactive state.
4. Click **Restore entire target**. The whole target is restored, not individual changes, and the restore itself is recorded in history.
   - If the target changed after the preview, or the restore would require an unsafe deletion, the entire restore is rejected.

### Manage history retention

- **Limit retention automatically**: open **Administration → Plugins**, click **Configure** for Redmine Custom Field Manager, set **Retention days**, **Maximum generations per target**, or both, and click **Apply**. A blank field means no limit.
- **Delete history manually**: on the **Change history** page, select entries and click **Delete**, or use **Delete histories by date**.

## Development and testing

Run the plugin test suite from the root of a Redmine installation that contains this plugin:

```sh
bundle exec rake redmine:plugins:test NAME=redmine_custom_field_manager RAILS_ENV=test
```

The GitHub Actions matrix also runs row-lock concurrency tests against real MySQL, MariaDB, and PostgreSQL databases, plus Playwright browser tests on Redmine 7.0.2. See [`docs/implementation.md`](docs/implementation.md) for implementation notes and [`docs/performance.md`](docs/performance.md) for the recorded 10,000-item benchmark.

## License

Copyright (C) 2026 Narusawa

This project is licensed under the GNU General Public License version 2 or any later version (`GPL-2.0-or-later`). See [`LICENSE`](LICENSE) for the full license text.
