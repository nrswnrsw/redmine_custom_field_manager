# Implementation Notes

[日本語](implementation.ja.md)

> This English document is the canonical version. The Japanese translation, [`implementation.ja.md`](implementation.ja.md), is provided for reference only. If the two differ, this document takes precedence.

This document records the technical approach used to meet the requirements in [`specification.md`](specification.md). Where they differ, the specification takes precedence for product behavior.

## Baseline

The implementation is based on a comparison of the source code of Redmine 7.0.2, 6.1.5, and 6.0.11, the officially maintained versions as of 2026-10-20. In all of these series, `CustomField` positions are managed per STI subclass (custom field type), and `CustomFieldEnumeration` positions are managed per custom field.

## Replacing the screens

The plugin relies on the standard mechanism by which Redmine's plugin loader adds a plugin's `app/views` to the front of the view search path. Redmine core files are not modified. The existing links to create, edit, copy, and delete custom fields are retained.

## Saving and concurrency control

- Edits on the screen are kept in the browser, and the database is not updated until an explicit save.
- Each save request includes the SHA-256 digest of the complete snapshot taken when editing started.
- When saving, the server locks the revision row of the target scope, then the target records, and recalculates the digest.
- Rails model callbacks apply the same revision-locking order to Redmine's standard save paths.
- A `CustomValue` locks the relevant revision only when it is created, when its value or custom field changes, or when it is destroyed, because only these changes can affect whether a value is in use. Just before saving, it verifies under the lock that the referenced value still exists, so that a deletion racing with the creation of a reference cannot leave an orphaned reference.
- If the digests differ, nothing is written, and the server returns HTTP 409 with the current server state.
- The conflict screen shows the differences among the state when editing started, the user's edit, and the current server state. A three-way merge proposal is returned only when the server's changes and the user's changes do not conflict, and nothing is saved until an administrator confirms it.
- A merge or forced overwrite is resubmitted with the server digest that the administrator reviewed, and that digest is checked again under the same lock just before committing. If the target has changed again, the server returns 409 again.
- The order and its history are committed in the same database transaction.

Custom-field order, conflict locks, and digests are handled per custom field type. Saving within one type tab never updates the positions of fields of another type.

## History

Each history entry stores the target scope, operation, operator, before and after digests, and a reversible diff. A snapshot of the entire target is stored for the first entry and every 20th entry. The history list does not select the large JSON columns; they are loaded only for the detail view and restores.

When selected history entries, or entries older than a specified date and time, are deleted, only the first remaining entry immediately after each deleted range is converted to a self-contained snapshot, within the same transaction. Automatic pruning by retention period or maximum number of generations uses the same process. Because only the boundaries of the diff chain are converted, the remaining history stays restorable without expanding every remaining entry.

The diff JSON and snapshot JSON columns can store histories for 10,000-item lists, which exceed 64 KiB, without loss. On MySQL and MariaDB, the migration expands them to `LONGTEXT`; PostgreSQL and SQLite already use a large `TEXT` type. This column-expansion migration is irreversible, because shrinking the columns could truncate stored data.

Restores always cover the entire target. Custom-field order is restored only when the set of IDs in the history matches the current set, and only the order is restored; names and other attributes are left unchanged. A Key/value list is restored, including names, active states, and order, only when every ID in the history still exists. If values that exist only in the current state must be deleted, their usage is checked again immediately before saving. If the same IDs cannot be restored safely, the entire restore is aborted.

## CSV

- Exported CSV files are UTF-8 with a BOM and carry a schema version. A metadata row identifying the origin is written even for an empty list.
- A cell that could be evaluated as a formula is prefixed with an apostrophe, and a dedicated flag column lets a re-import restore the original value.
- Updates from the same instance and the same field keep existing IDs. A nonexistent ID is an error.
- For CSVs from another instance, matching IDs are never used. Only mappings between source IDs and local IDs that an administrator has confirmed are stored and reused.
- CSV parsing, difference planning, and the final application are separate steps. When applying, the server regenerates the plan from the CSV and the administrator's choices, and re-verifies both the preview digest and the digest taken when editing started.

## Bulk updates

After validation, the names, active states, and positions of existing records are updated with `CASE` expressions using quoted values, in batches of 500. Deletions are also performed per set of IDs, so moving 10,000 items never issues 10,000 individual `UPDATE` statements. Updates, history, and mappings are committed in the same transaction.

The browser keeps every name in the DOM as ordinary text. Virtual scrolling is not used because it would conflict with the browser find requirement. The performance test method and measured results are recorded in [`performance.md`](performance.md).

## Verification scope

- Automated tests run on Redmine 7.0.2, 6.1.5, and 6.0.11, combined with SQLite, MySQL 8.4, MariaDB 11.4, and PostgreSQL 17.
- On MySQL, MariaDB, and PostgreSQL, tests use real transactions and separate database connections to cover both orderings of a race between deleting a value and creating a saved value that uses it. SQLite has no row-level locking, so only these two tests are skipped there.
- On Redmine 7.0.2, Playwright tests in a real browser cover editing, Undo/Redo, bulk moves, saving, CSV preview, conflicts between two open pages, and safe merges.
- Conflict protection is not guaranteed for direct database updates or for unknown plugins that deliberately bypass model callbacks.
