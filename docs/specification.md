# Redmine Custom Field Manager — Product Specification

[日本語](specification.ja.md)

- Repository / plugin ID: `redmine_custom_field_manager`
- Status: **Functional requirements finalized and implemented (verification ongoing)**
- Specification baseline date: 2026-10-20
- Scope: Custom-field administration screens for Redmine administrators

> This English document is the canonical specification. The Japanese translation, [`specification.ja.md`](specification.ja.md), is provided for reference only. If the two differ, this document takes precedence.

> This document defines the agreed product behavior. Candidate implementation approaches and items that require measurement are kept separately in Section 12, "Technical design and verification items". The data integrity of existing Redmine installations takes priority over usability and performance.

## 1. Purpose and scope

The plugin improves Redmine's standard custom-field administration without impairing existing functionality. In particular, it provides drag and drop for environments with a large number of items, bulk operations on multiple selected items, bulk editing of Key/value lists, CSV import and export, confirmation of concurrent-edit conflicts, and change history with restore.

It covers the following two areas:

1. **Custom field list**: manages the order of the custom fields themselves.
2. **Key/value lists**: manages the values registered in custom fields whose format is `Key/value list`.

The plugin **replaces** Redmine's standard administration screens; it does not add a separate advanced administration screen alongside them. All operations and administrative features available in the standard screens are retained.

In this document, a **value** is an entry in a Key/value list, and a **saved value** is a custom-field value stored on an issue or another object.

## 2. Supported environments and basic principles

- All **stable Redmine series that the Redmine project officially maintains** are supported. As of the baseline date, these are **7.0.x, 6.1.x, and 6.0.x**. Development versions and end-of-life series are not supported.
- Support for a new Redmine series is added after compatibility testing. A newly released version that has not been verified is not unconditionally supported.
- The plugin can be installed and updated without directly modifying Redmine core files.
- The plugin follows Redmine's standard administrator permissions, CSRF protection, and input validation. Administrative operations, CSV import and export, forced overwrites on conflict, and history restore and deletion are restricted to Redmine administrators.
- Existing field IDs and value IDs, and their correspondence with saved values on issues and other objects, are protected.
- Partial saves that silently accept inconsistencies are not allowed. If a save fails, all of its changes are rolled back and the result is shown to the user.

## 3. Common editing operations

### 3.1 Display and reordering

- Lists show **all items** by default. No pagination or limit on the number of displayed items is imposed.
- Item names are present in the DOM as ordinary text so that they can be found with the browser's built-in find (`Ctrl+F` / `⌘+F`).
- Lists do not have their own search box or search filter.
- Conventional drag and drop (D&D) is retained, and items can be moved to any position in the list. Scrolling while dragging in a long list is supported.
- One or more items can be selected, and the selected items can be reordered at once.
- The destination for selected items is specified by **entering an item name and searching for candidates**, then choosing to move the items before or after that item. If the name is unique, the name alone is enough; entering an internal ID is never required. A drop-down that only lets users scroll through a large number of items is not used.
- If several items share the same name, candidates labeled with their current list positions are shown on the page, and the user confirms the destination by clicking one. Internal IDs are used only as supplementary information and for internal identification; users are never required to know or enter them. Candidates that are themselves being moved are marked as "selected" and cannot be chosen. If every candidate is being moved, an error explains why.
- When selected items are moved, their relative order is preserved.
- During bulk operations, the number of selected items is shown in the column header, which stays visible while scrolling through a long list. If the selection is kept after an operation, the same indicator makes it clear that items are still selected.
- The number of unsaved moves is shown as the **minimum number of moved items**, derived from the relative order before and after the change, rather than as the number of rows whose absolute position changed. Items whose positions shifted only because of additions or deletions are not counted as moves.
- Controls are grouped by purpose. Item selection comes first among the list controls; actions on selected items and moves form a separate group; Undo/Redo, Discard, and Save are placed together in a confirmation bar at the end of the list. **Save** is given the strongest visual emphasis as the committing action, and **Delete** is set apart from the regular actions in its group to indicate that it is destructive.

### 3.2 Saving and undoing

- D&D, bulk moves, and other edits are **not sent to the server until the Save button is pressed**.
- The standard D&D auto-save is not performed on these enhanced screens.
- The screen indicates when there are unsaved changes and provides **Save, Discard all, Undo, and Redo**.
- Labels distinguish step-by-step Undo/Redo from resetting to the baseline state. The English UI uses "Undo", "Redo", and "Discard all unsaved changes"; the Japanese UI uses 「1つ戻す」, 「1つやり直す」, and 「未保存の変更をすべて破棄」. After an Undo or Redo, the affected operation is announced, and keyboard focus stays on the same button if it can be used again, or otherwise moves to the other one. "Discard all unsaved changes" runs only after confirmation.
- Users can review the edited result and the differences before saving.
- Users are warned when leaving the page with unsaved changes.
- Duplicate submissions and duplicate operations are prevented while saving. A failed save is never reported as successful.

## 4. Custom field list

- Redmine's standard tabs for each custom field type and the standard field management features are retained.
- Selecting fields, D&D, multi-selection, destination selection by name search, saving, and undoing are supported.
- The selection-based move is placed directly below the custom field list as "Move to a destination" and is collapsed by default. It works for one or many fields, and when expanded it explains the steps: select the fields, enter the destination, and choose before or after. The checkboxes in the custom field list are clearly labeled as selecting fields to move and are kept distinct from per-row actions.
- If no field exactly matches the destination, candidates that contain the entered text are shown near the input field. If there are no candidates either, the error is associated with the input field and focus returns to it.
- Processing the order only within the displayed type tab could affect other types, so the server saves an order that is **consistent with Redmine core's position management rules**.
- Standard administration features other than ordering, such as creating, editing, and deleting individual fields, are not lost.
- Deleting a custom field from its row is presented as an **immediate single-field operation** that does not affect other checked fields. The confirmation states the field's name and ID, the impact on its saved values and Key/value list values, that the deletion runs immediately without waiting for "Save changes", and that it cannot be restored from history.
- Users do not lose track of unsaved changes when switching type tabs or leaving the page.

## 5. Key/value lists

### 5.1 List and editing

- All values are shown, and they can be moved to any position by D&D as before.
- The column header stays at the top of the screen while scrolling so that the "Select" and "Active" checkboxes remain identifiable.
- The value list is shown first, followed by single-value addition, selected item actions, and then bulk addition and CSV, in that order. As with the selection-based move in the custom field list, selected item actions are collapsed by default. Bulk addition and CSV are also collapsed by default as compact auxiliary tools for occasional use.
- Values are normally displayed as **lightweight text rows**. Clicking a name or its edit button switches only that row to an input field.
- Even when there are many values, the page initially shows the top of the list and its description, and does not automatically scroll to the add field at the bottom.
- While a name is being edited, "Apply edit" and "Cancel" are clearly shown. Pressing Enter alone does not commit the edit, so it does not interfere with confirming conversions in Japanese input methods (IME).
- A committed edit is not sent to the server until the Save button is pressed.
- Renaming, adding, reordering, activating and deactivating, and deleting values are supported.
- **Single-value addition**: as in the standard screen, a single value name can be entered and added. The addition is staged like any other edit and is subject to Save, Discard, and Undo/Redo.
- Selected values can be moved, activated or deactivated, and deleted in bulk.
- **Bulk addition**: multiple values can be pasted, one per line, and added. The input is validated before the values are added.
- The internal ID of each value is protected. Renaming or reordering never reassigns IDs.

### 5.2 Deletion and protection of existing data

- **Values in use cannot be deleted**; they can only be deactivated.
- For a value that cannot be deleted, the reason (in use, or set as a default) is shown both in the list and in a tooltip.
- **Unused values can be either deleted or deactivated.**
- The same restrictions apply to bulk deletion, CSV full synchronization, and history restore.
- Usage is checked again when saving. Even if a value was unused when editing started, it is not deleted if it is in use at save time.
- Whether a value is in use is determined according to the reference rules of the supported Redmine versions, including custom-field usage outside issues and default values.
- If the changes being saved include a value that cannot be deleted, the reason is shown and **the entire operation is aborted**. The value is never silently deactivated instead, and nothing is partially saved. The only exception is values missing from the CSV in full synchronization, which follow the user's choice described in Section 6.3.

## 6. CSV export and import

CSV operations are based on the saved state. If there are unsaved changes on the page, a message asks the user to save or discard them first, and no import preview is started.

### 6.1 Export

- All values of the target Key/value list are exported to CSV in their current order.
- An empty CSV template containing the current target information and the column structure can be downloaded.
- The export includes at least each value's **internal ID, name, active state, and position**.
- Identifying information for the source environment and the target field is included so that the origin of the file is clear even after it is brought into a different Redmine environment.
- Character encoding, quoting, line breaks, duplicate names, and similar issues are handled safely, and the output can be imported again.

### 6.2 Import modes

- **Append mode**: adds new values.
- **Update and add mode**: updates the names, active states, and positions of existing values, and can also add new rows.
- **Full synchronization mode**: adds, updates, and reorders values based on the CSV, and can also delete or deactivate existing values that are not in the CSV.
- Values missing from the CSV are deleted or deactivated **only when full synchronization mode is explicitly selected**.
- An import **previews the differences before saving**: additions, renames, reorderings, activations and deactivations, and deletions.
- Invalid data, duplicate IDs, nonexistent IDs, ambiguous mappings, and similar problems are reported as errors. Nothing is updated automatically while the situation is ambiguous.

### 6.3 Values missing from the CSV in full synchronization

- **In use**: can only be deactivated. Deletion is not allowed.
- **Unused**: can be either deleted or deactivated.
- For unused values, a default of "delete" or "deactivate" can be set for all of them at once and then changed for individual values as needed.
- The affected values and the final action for each can be reviewed before saving.
- Usage is checked again immediately before saving, and the entire operation is aborted if any condition is violated.

### 6.4 Import between different environments

- **Migration between different Redmine environments is supported.**
- Internal IDs are not assumed to match between environments. Existing values are never updated based on matching IDs alone.
- Candidates such as values with the same name are presented, and the import proceeds only after **an administrator confirms the mapping to existing values**. Values that are not mapped can be added as new values.
- When a mapping is ambiguous, for example because several values share the same name, the administrator must always confirm it.
- To handle second and later imports safely, confirmed mappings are designed to be identifiable and reusable. IDs from another environment are never reproduced as-is in the database.

## 7. Concurrent editing and conflict resolution

### 7.1 Conflict detection

- The baseline state at the time the administration screen was opened is retained.
- If another administrator saves the target data first, **the next save detects the conflict**.
- The comparison covers not only display names but also IDs, positions, active states, additions, and deletions.
- Conflicts are detected in appropriate independent units: the overall order of custom fields, and the value edits of each Key/value list.
- **Conflict detection and writing are performed atomically on the server** so that two simultaneous saves cannot both succeed incorrectly.
- Changes made through Redmine's standard administration paths are also covered by conflict protection. The plugin does not claim, without verification, that it can fully control writes made directly to the database or by unknown third-party plugins.

### 7.2 Conflict confirmation screen

When a conflict occurs, **a confirmation screen is always shown instead of merging or overwriting automatically**. The user can review the current server state, their own edits, and the differences between them.

The following options are provided:

1. **Continue editing**: keep your changes without saving.
2. **Discard and reload**: discard your changes and return to the latest server state.
3. **Review and save merge proposal**: shown only when the changes can be merged safely. The merge proposal is previewed and saved only after an explicit confirmation.
4. **Force overwrite with my changes**: shows a warning and the differences, and saves only after an explicit action by the administrator.

- Even when a merge is possible, nothing is saved without the user's confirmation.
- A forced overwrite **cannot bypass data-protection constraints**. For example, deleting values in use remains prohibited.
- If the target state changes again just before a merge or overwrite is confirmed, the user is returned to the conflict confirmation.
- Simultaneous saves, failures, and timeouts never leave partial saves, and the result is reported accurately.

## 8. Change history and restore

### 8.1 History

- Each save records a history entry from which the target, date and time, operator, and changes can be traced.
- Incremental (diff) history is combined with periodic snapshots to reduce both the database load of normal operations and the size of the history.
- The history list shows lightweight metadata first and loads detailed data only when needed.
- In history details, long lists of changes are collapsed with their count shown, and the reconstructed state of the entire target is also collapsed, so that the restore controls and the summary are not pushed below long tables.
- The history list, details, and restore preview do not show internal keys or raw operation codes as primary content. Instead, they show target names, operation names, names, positions, and active/inactive states in human-readable form. Raw data is available only as collapsed technical information.
- Saved data and its history are committed together and remain consistent with each other.
- When a custom field is deleted through Redmine's standard path, the target, the operator, and the numbers of deleted saved values and Key/value list values are also recorded as an audit history entry. If recording the history fails, the deletion is rolled back as well.
- Custom-field deletion history is for auditing only and is never presented as if the deleted field, its saved values, or its Key/value list values could be restored.

### 8.2 Restore

- The **entire target is restored to its state at the selected point in history**.
- "Selective reversal", which undoes only individual changes, is not provided.
- The restore target is either the custom field order or a specified Key/value list. Unrelated settings are not rolled back.
- A restore is preceded by a difference preview and a conflict check. The restore itself is also recorded in history.
- If restoring would require deleting a value in use, or if the original IDs cannot be restored safely, **the entire restore is aborted** and the reason is shown.
- Partial restores are not performed.

### 8.3 History retention and manual deletion

- The **retention period and the maximum number of generations** can be configured in the plugin settings.
- The default is **unlimited retention**.
- History entries can be deleted manually, either one at a time or by selecting several.
- History older than a specified date and time can be deleted in bulk. Before deletion, the user confirms the affected entries and the impact.
- Deleting history does not change the current settings.
- Dependencies between incremental history and snapshots are maintained. History is reconstructed, or deletion is restricted, so that **the remaining history can still be restored** after deletion.

## 9. Performance and usability

- The performance design and verification target is **10,000 or more values per list**. No hard limit is placed on the number of values.
- Showing all items, browser find, and free D&D are not abandoned for the sake of performance.
- Unnecessary text input fields and expensive D&D initialization are avoided. Values are displayed primarily as lightweight text rows.
- Everyday operations such as renaming, adding, changing the active state, and deleting update the DOM only around the changed rows and avoid unnecessarily re-rendering every row.
- Updates sent to the server are limited to differences wherever possible, and unchanged records are not updated needlessly.
- Save time, rendering time, D&D initialization, long-distance moves, memory usage, CSV import and export, and restore are load-tested at the 10,000-item scale.
- Practical responsiveness is **verified by measurement**. No specific processing-time guarantee is considered verified at this point. Measured results are recorded in [`performance.md`](performance.md).
- Virtual scrolling, which removes off-screen items from the DOM, conflicts with the browser find requirement and is therefore not adopted lightly.

## 10. Security and data integrity

- These features are implemented as administration functions that only administrators can read and write.
- Authorization, input validation, and CSRF protection are applied to every server-side update.
- Invalid data in CSV imports, oversized requests, CSV formula injection, and similar threats are taken into account.
- Additions, updates, deletions, reorderings, and restores are **saved atomically** per unit.
- Other users' changes are never lost unintentionally on conflict, including when operations run concurrently with Redmine's standard edit screens, API, and other paths.
- On conflict, only a forced overwrite explicitly chosen by an administrator is allowed, and that operation is also recorded in history.
- Removing or disabling the plugin does not corrupt Redmine's standard custom fields or the values stored on existing issues.

## 11. Acceptance criteria (key scenarios)

1. Custom fields can be dragged and dropped manually, and several other fields can be moved in bulk. The database order does not change before saving and matches the specified order after saving.
2. In a list that shows all items, 200 or more values can be dragged and dropped without being forced to switch pages. Names on the page can be found with the browser's built-in find.
3. Load tests of rendering, D&D, saving, and CSV operations are run against a list of 10,000 items, and the results and the test environment are recorded.
4. The list is displayed as plain text, and an input field appears only when a particular value is being edited.
5. Multiple values separated by line breaks can be added at once, and invalid data partway through does not cause a partial save.
6. A CSV can update names, active states, and positions while preserving existing IDs.
7. CSV full synchronization can delete or deactivate values missing from the CSV. **Values in use cannot be deleted**, and an action can be chosen for unused values.
8. When importing a CSV from another environment, the administrator can confirm mappings to existing candidates, and values are never updated incorrectly just because their IDs happen to match.
9. When two administrators edit the same target and one saves first, the later save always shows the conflict confirmation. Even when the changes can be merged, they are not merged automatically, and a forced overwrite requires explicit confirmation.
10. Simultaneous saves, communication failures, and database errors leave no incomplete updates in settings or history.
11. A past state can be restored for the entire target, and the restore is aborted safely if it would require deleting a value in use or another unsafe change.
12. The history retention period and number of generations can be configured, history can be deleted manually, and the remaining history stays restorable after deletion.
13. Compatibility tests covering at least administrative operations, saving, CSV, conflicts, and restore are run on every currently maintained Redmine series.

## 12. Technical design and verification items (open implementation details)

The following are **not unresolved product requirements but items to be decided and established through code and tests**. They are reconsidered as specification issues only if achieving them would require changing agreed behavior.

- How to replace views on Redmine 6.0, 6.1, and 7.0, how to integrate with the standard create, update, and delete paths, and how to handle view conflicts with other plugins.
- Transaction isolation and locking design for each database, and behavior when multiple processes or servers save simultaneously.
- A correct implementation of position management across custom field types.
- Origin identification for CSVs from other environments, the storage format for confirmed mappings, and how to avoid collisions with existing IDs when restoring history.
- Redmine's rules for determining whether a value is in use, including constraints from usage outside issues, default values, and references from other plugins.
- Snapshot interval, diff format, compression method, and protection of dependencies when retaining or deleting history.
- Performance optimization of browser rendering and D&D, database updates, and CSV processing at 10,000 or more items.
- The test matrix for each supported database product and Redmine series.

## 13. Decision log

| Q | Decision |
|---|---|
| Q1 | Replace the existing administration screens |
| Q2 | Allow forced overwrite on conflict (requires a warning and an explicit action) |
| Q3 | Support CSV up to and including full synchronization |
| Q4 | Support import between different Redmine environments |
| Q5 | Support bulk deletion of values |
| Q6 | Set 10,000 or more values per list as the performance target |
| Q7 | Support all officially maintained stable Redmine series |
| Q8 | Between environments, present candidates and require the administrator to confirm mappings |
| Q9 | Values in use cannot be deleted, only deactivated |
| Q10 | Always show a confirmation screen on conflict. Never save automatically, even when a safe merge proposal is available |
| Q11 | Values missing from the CSV: only deactivation if in use; a choice between deletion and deactivation if unused |
| Q12 | Keep a history of saves and allow restoring past states |
| Q13 | Configurable retention period and number of generations (unlimited by default), plus manual history deletion |
| Q14 | Only restore the state of the entire target. Undoing specific changes is out of scope |
| Q15 | No list-specific search: show all items and rely on browser find. Destination search is retained |
| Q16 | Value names are plain text, with an input field only while editing |

## 14. Technical references

- [Redmine download page and version support policy](https://www.redmine.org/projects/redmine/wiki/download)
- [Redmine Plugin Internals](https://www.redmine.org/projects/redmine/wiki/Plugin_Internals)
- [Redmine Plugin FAQ](https://www.redmine.org/projects/redmine/wiki/Plugin_FAQ)
- [Redmine 7.0.2 / 6.1.5 release announcements](https://www.redmine.org/news)

These external resources provide technical background and do not take precedence over the finalized product requirements in this document. The implementation is checked against the Redmine source code of each supported series.
