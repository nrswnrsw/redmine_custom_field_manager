(function(window, document, $) {
  'use strict';

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function EnumerationManager(form) {
    if (window.performance && window.performance.mark) {
      window.performance.mark('rcfm-enumerations-init-start');
    }
    this.form = $(form);
    this.body = this.form.find('tbody');
    this.items = JSON.parse(this.form.find('.rcfm-items').val());
    this.baseline = clone(this.items);
    this.undoStack = [];
    this.redoStack = [];
    this.selected = {};
    this.editingId = null;
    this.newSequence = 0;
    this.saving = false;
    this.conflict = null;
    this.csvData = null;
    this.csvPreview = null;
    this.bind();
    this.enableSorting();
    this.refresh();
    if (window.performance && window.performance.mark && window.performance.measure) {
      window.performance.mark('rcfm-enumerations-init-end');
      window.performance.measure(
        'rcfm-enumerations-init',
        'rcfm-enumerations-init-start',
        'rcfm-enumerations-init-end'
      );
    }
  }

  EnumerationManager.prototype.findItem = function(clientId) {
    return this.items.find(function(item) {
      return String(item.client_id) === String(clientId);
    });
  };

  EnumerationManager.prototype.commit = function(mutator, render) {
    var before = clone(this.items);
    mutator();
    if (JSON.stringify(before) === JSON.stringify(this.items)) {
      return;
    }
    this.undoStack.push(before);
    this.redoStack = [];
    this.conflict = null;
    this.clearError();
    this.form.find('.rcfm-conflict').prop('hidden', true);
    if (render) {
      this.render();
    }
    this.refresh();
  };

  EnumerationManager.prototype.bind = function() {
    var manager = this;

    this.form.on('change', '.rcfm-select', function() {
      var row = $(this).closest('tr');
      var id = String(row.data('rcfm-client-id'));
      manager.selected[id] = this.checked;
      row.toggleClass('rcfm-selected', this.checked);
      manager.hideTargetCandidates();
      manager.clearError();
      manager.refreshSelection();
    });

    this.form.on('input', '.rcfm-target', function() {
      manager.hideTargetCandidates();
      manager.clearError();
    });

    this.form.on('input', '.rcfm-name-input, .rcfm-bulk-add-input', function() {
      manager.clearError();
    });

    this.form.on('change', '.rcfm-active', function() {
      var checkbox = this;
      var id = String($(checkbox).closest('tr').data('rcfm-client-id'));
      manager.commit(function() {
        manager.findItem(id).active = checkbox.checked;
      }, false);
    });

    this.form.on('click', '.rcfm-edit', function() {
      manager.startEditing(String($(this).closest('tr').data('rcfm-client-id')));
    });

    this.form.on('keydown', '.rcfm-name-input', function(event) {
      if (event.key === 'Enter') {
        event.preventDefault();
        manager.finishEditing(this);
      } else if (event.key === 'Escape') {
        event.preventDefault();
        manager.editingId = null;
        manager.clearError();
        manager.render();
      }
    });

    this.form.on('blur', '.rcfm-name-input', function() {
      manager.finishEditing(this);
    });

    this.form.on('click', '.rcfm-delete', function() {
      var id = String($(this).closest('tr').data('rcfm-client-id'));
      manager.deleteItems([id]);
    });

    this.form.on('click', '.rcfm-restore-item', function() {
      var id = String($(this).closest('tr').data('rcfm-client-id'));
      manager.commit(function() {
        manager.findItem(id).deleted = false;
      }, true);
    });

    this.form.on('click', '.rcfm-select-all', function() {
      manager.body.find('tr:not(.rcfm-deleted) .rcfm-select').prop('checked', true).trigger('change');
    });

    this.form.on('click', '.rcfm-clear-selection', function() {
      manager.selected = {};
      manager.body.find('.rcfm-select').prop('checked', false).trigger('change');
    });

    this.form.on('click', '.rcfm-activate-selected', function() {
      manager.setSelectedActive(true);
    });

    this.form.on('click', '.rcfm-deactivate-selected', function() {
      manager.setSelectedActive(false);
    });

    this.form.on('click', '.rcfm-delete-selected', function() {
      manager.deleteItems(manager.selectedIds());
    });

    this.form.on('click', '.rcfm-move-selected', function() {
      manager.moveSelected();
    });

    this.form.on('click', '.rcfm-target-candidate', function() {
      manager.moveSelected($(this).attr('data-rcfm-target-client-id'));
    });

    this.form.on('click', '.rcfm-add-lines', function() {
      manager.addLines();
    });

    this.form.on('change', 'input[name="rcfm_csv_mode"]', function() {
      var sync = this.value === 'sync' && this.checked;
      manager.form.find('.rcfm-csv-missing-default').prop('hidden', !sync);
      manager.invalidateCsvPreview();
    });

    this.form.on('change', '.rcfm-csv-file, input[name="rcfm_csv_missing_default"]', function() {
      if ($(this).hasClass('rcfm-csv-file')) {
        manager.csvData = null;
      }
      manager.invalidateCsvPreview();
    });

    this.form.on('change', '.rcfm-csv-mapping-choice, .rcfm-csv-missing-action', function() {
      manager.invalidateCsvPreview(true);
    });

    this.form.on('click', '.rcfm-csv-preview-button', function() {
      manager.previewCsvImport();
    });

    this.form.on('click', '.rcfm-csv-apply-button', function() {
      manager.applyCsvImport();
    });

    this.form.on('click', '.rcfm-undo', function() {
      if (!manager.undoStack.length) {
        return;
      }
      manager.redoStack.push(clone(manager.items));
      manager.items = manager.undoStack.pop();
      manager.conflict = null;
      manager.clearError();
      manager.form.find('.rcfm-conflict').prop('hidden', true);
      manager.render();
      manager.refresh();
    });

    this.form.on('click', '.rcfm-redo', function() {
      if (!manager.redoStack.length) {
        return;
      }
      manager.undoStack.push(clone(manager.items));
      manager.items = manager.redoStack.pop();
      manager.conflict = null;
      manager.clearError();
      manager.form.find('.rcfm-conflict').prop('hidden', true);
      manager.render();
      manager.refresh();
    });

    this.form.on('click', '.rcfm-reset', function() {
      manager.undoStack.push(clone(manager.items));
      manager.redoStack = [];
      manager.items = clone(manager.baseline);
      manager.selected = {};
      manager.conflict = null;
      manager.clearError();
      manager.render();
      manager.refresh();
    });

    this.form.on('submit', function(event) {
      event.preventDefault();
      manager.save(false, 'normal');
    });

    this.form.on('click', '.rcfm-conflict-continue', function() {
      manager.form.find('.rcfm-conflict').prop('hidden', true);
    });

    this.form.on('click', '.rcfm-conflict-reload', function() {
      if (window.confirm(manager.form.data('rcfm-confirm-discard'))) {
        window.location.reload();
      }
    });

    this.form.on('click', '.rcfm-conflict-force', function() {
      if (window.confirm(manager.form.data('rcfm-confirm-force'))) {
        manager.save(true, 'force');
      }
    });

    this.form.on('click', '.rcfm-conflict-merge', function() {
      if (!manager.conflict || manager.conflict.merge_proposal === null) {
        return;
      }
      manager.items = clone(manager.conflict.merge_proposal);
      manager.render();
      manager.refresh();
      manager.save(true, 'merge');
    });

    $(window).on('beforeunload.rcfm-enumerations', function(event) {
      if (!manager.saving && manager.isDirty()) {
        event.preventDefault();
        event.returnValue = '';
      }
    });
  };

  EnumerationManager.prototype.enableSorting = function() {
    var manager = this;
    var before = null;
    var draggedRows = [];

    this.body.sortable({
      axis: 'y',
      handle: '.rcfm-sort-handle',
      items: '> tr:not(.rcfm-deleted)',
      scroll: true,
      scrollSensitivity: 80,
      scrollSpeed: 18,
      placeholder: 'rcfm-sort-placeholder',
      start: function(_event, ui) {
        before = clone(manager.items);
        var selected = manager.body.find('.rcfm-select:checked').closest('tr:not(.rcfm-deleted)').toArray();
        draggedRows = selected.indexOf(ui.item[0]) >= 0 ? selected : [ui.item[0]];
        draggedRows.forEach(function(row) {
          if (row !== ui.item[0]) {
            $(row).detach();
          }
        });
      },
      stop: function(_event, ui) {
        if (draggedRows.length > 1) {
          var marker = $('<tr class="rcfm-group-marker"><td></td></tr>');
          marker.insertBefore(ui.item);
          draggedRows.forEach(function(row) {
            marker.before(row);
          });
          marker.remove();
        }
        manager.syncOrderFromDom();
        if (JSON.stringify(before) !== JSON.stringify(manager.items)) {
          manager.undoStack.push(before);
          manager.redoStack = [];
          manager.conflict = null;
          manager.form.find('.rcfm-conflict').prop('hidden', true);
        }
        draggedRows = [];
        manager.refreshTargetList();
        manager.refresh();
      }
    });
  };

  EnumerationManager.prototype.syncOrderFromDom = function() {
    var byId = {};
    this.items.forEach(function(item) {
      byId[String(item.client_id)] = item;
    });
    this.items = this.body.children('tr[data-rcfm-client-id]').map(function() {
      return byId[String($(this).data('rcfm-client-id'))];
    }).get();
  };

  EnumerationManager.prototype.startEditing = function(clientId) {
    this.clearError();
    this.editingId = clientId;
    this.render();
    this.body.find('tr[data-rcfm-client-id="' + clientId + '"] .rcfm-name-input').trigger('focus').trigger('select');
  };

  EnumerationManager.prototype.finishEditing = function(input) {
    var id = String($(input).closest('tr').data('rcfm-client-id'));
    var value = $(input).val().trim();
    if (!this.validName(value)) {
      return;
    }
    this.editingId = null;
    this.commit(function() {
      this.findItem(id).name = value;
    }.bind(this), true);
    if (String(this.findItem(id).name) === value) {
      this.render();
    }
  };

  EnumerationManager.prototype.validName = function(name) {
    if (!name) {
      this.showError(this.form.data('rcfm-name-blank'));
      return false;
    }
    if (Array.from(name).length > 60) {
      this.showError(this.form.data('rcfm-name-too-long'));
      return false;
    }
    return true;
  };

  EnumerationManager.prototype.selectedIds = function() {
    return Object.keys(this.selected).filter(function(id) {
      var item = this.findItem(id);
      return this.selected[id] && item && !item.deleted;
    }, this);
  };

  EnumerationManager.prototype.refreshSelection = function() {
    this.form.find('.rcfm-selection-count').text(
      this.form.data('rcfm-selected-count').replace('__COUNT__', this.selectedIds().length)
    );
  };

  EnumerationManager.prototype.refreshTargetList = function() {
    var manager = this;
    var targetList = this.form.find('.rcfm-target-list').empty();
    this.items.filter(function(item) { return !item.deleted; }).forEach(function(item, index) {
      var targetId = item.id || item.client_id;
      var label = manager.form.data('rcfm-target-candidate')
        .replace('__POSITION__', index + 1)
        .replace('__NAME__', item.name);
      targetList.append($('<option>').val(label + ' (#' + targetId + ')'));
    });
  };

  EnumerationManager.prototype.setSelectedActive = function(active) {
    var ids = this.selectedIds();
    if (!ids.length) {
      this.showError(this.form.data('rcfm-selection-error'));
      return;
    }
    this.clearError();
    this.commit(function() {
      ids.forEach(function(id) {
        var item = this.findItem(id);
        if (item && !item.deleted) {
          item.active = active;
        }
      }, this);
    }.bind(this), true);
  };

  EnumerationManager.prototype.deleteItems = function(ids) {
    if (!ids.length) {
      this.showError(this.form.data('rcfm-selection-error'));
      return;
    }
    var blocked = ids.some(function(id) {
      var item = this.findItem(id);
      return item && item.protected;
    }, this);
    if (blocked) {
      this.showError(this.form.data('rcfm-delete-protected'));
      return;
    }
    this.commit(function() {
      ids.forEach(function(id) {
        var item = this.findItem(id);
        if (item) {
          item.deleted = true;
          this.selected[id] = false;
        }
      }, this);
    }.bind(this), true);
  };

  EnumerationManager.prototype.hideTargetCandidates = function() {
    this.form.find('.rcfm-target-candidates').prop('hidden', true)
      .find('.rcfm-target-candidate-list').empty();
  };

  EnumerationManager.prototype.clearError = function() {
    this.form.find('.rcfm-error').prop('hidden', true).text('');
  };

  EnumerationManager.prototype.showTargetCandidates = function(candidates, selectedIds) {
    var manager = this;
    var panel = this.form.find('.rcfm-target-candidates');
    var list = panel.find('.rcfm-target-candidate-list').empty();
    var activeItems = this.items.filter(function(item) { return !item.deleted; });

    panel.find('.rcfm-target-candidates-message').text(this.form.data('rcfm-target-ambiguous'));
    candidates.forEach(function(item) {
      var clientId = String(item.client_id);
      var label = manager.form.data('rcfm-target-candidate')
        .replace('__POSITION__', activeItems.indexOf(item) + 1)
        .replace('__NAME__', item.name);
      var button = $('<button type="button" class="rcfm-target-candidate">')
        .attr('data-rcfm-target-client-id', clientId)
        .prop('disabled', selectedIds.indexOf(clientId) >= 0)
        .append($('<span>').text(label));
      if (item.id) {
        button.append($('<span class="rcfm-record-id">').text('#' + item.id));
      }
      if (button.prop('disabled')) {
        button.append(
          $('<span class="rcfm-target-candidate-state">')
            .text('(' + manager.form.data('rcfm-target-candidate-selected') + ')')
        );
        button.attr('title', manager.form.data('rcfm-target-error'));
      }
      list.append(button);
    });
    this.clearError();
    panel.prop('hidden', false);
  };

  EnumerationManager.prototype.moveSelected = function(targetClientId) {
    var ids = this.selectedIds();
    var value = this.form.find('.rcfm-target').val().trim();
    var match = value.match(/\(#([^\)]+)\)\s*$/);
    this.hideTargetCandidates();
    this.clearError();
    if (!ids.length) {
      this.showError(this.form.data('rcfm-selection-error'));
      return;
    }
    if (!value) {
      this.showError(this.form.data('rcfm-target-required'));
      return;
    }

    var candidates;
    if (targetClientId) {
      candidates = this.items.filter(function(item) {
        return String(item.client_id) === targetClientId && !item.deleted;
      });
    } else if (match) {
      candidates = this.items.filter(function(item) {
        return (String(item.id) === match[1] || String(item.client_id) === match[1]) && !item.deleted;
      });
    } else {
      var lowered = value.toLocaleLowerCase();
      candidates = this.items.filter(function(item) {
        return !item.deleted && String(item.name).trim().toLocaleLowerCase() === lowered;
      });
      if (!candidates.length) {
        this.showError(this.form.data('rcfm-target-not-found'));
        return;
      }
      if (candidates.length > 1) {
        if (!candidates.some(function(item) {
          return ids.indexOf(String(item.client_id)) < 0;
        })) {
          this.showError(this.form.data('rcfm-target-error'));
          return;
        }
        this.showTargetCandidates(candidates, ids);
        return;
      }
    }
    var target = candidates[0];
    if (!target || ids.indexOf(String(target.client_id)) >= 0) {
      this.showError(this.form.data('rcfm-target-error'));
      return;
    }

    var side = this.form.find('input[name="rcfm_enumeration_move_side"]:checked').val();
    var movingRows = this.body.children('tr').filter(function() {
      return ids.indexOf(String($(this).data('rcfm-client-id'))) >= 0;
    });
    var targetRow = this.body.children('tr[data-rcfm-client-id="' + target.client_id + '"]');
    this.commit(function() {
      var moving = this.items.filter(function(item) {
        return ids.indexOf(String(item.client_id)) >= 0 && !item.deleted;
      });
      var remaining = this.items.filter(function(item) {
        return moving.indexOf(item) < 0;
      });
      var targetIndex = remaining.indexOf(target);
      remaining.splice(targetIndex + (side === 'after' ? 1 : 0), 0, ...moving);
      this.items = remaining;
    }.bind(this), false);
    if (side === 'after') {
      targetRow.after(movingRows);
    } else {
      targetRow.before(movingRows);
    }
    this.refreshTargetList();
  };

  EnumerationManager.prototype.addLines = function() {
    var input = this.form.find('.rcfm-bulk-add-input');
    var names = input.val().split(/\r?\n/).map(function(name) {
      return name.trim();
    }).filter(Boolean);
    if (!names.length) {
      this.showError(this.form.data('rcfm-name-blank'));
      return;
    }
    if (names.some(function(name) { return Array.from(name).length > 60; })) {
      this.showError(this.form.data('rcfm-name-too-long'));
      return;
    }
    this.commit(function() {
      names.forEach(function(name) {
        this.newSequence += 1;
        this.items.push({
          client_id: 'new-' + Date.now() + '-' + this.newSequence,
          id: null,
          name: name,
          active: true,
          deleted: false,
          protected: false
        });
      }, this);
    }.bind(this), true);
    input.val('');
  };

  EnumerationManager.prototype.render = function() {
    var manager = this;
    var fragment = document.createDocumentFragment();
    this.hideTargetCandidates();
    this.body.empty();

    this.items.forEach(function(item) {
      var row = $('<tr>').attr('data-rcfm-client-id', item.client_id);
      row.toggleClass('rcfm-deleted', !!item.deleted);
      row.toggleClass('rcfm-protected', !!item.protected);
      row.toggleClass('rcfm-selected', !!manager.selected[String(item.client_id)]);

      var selection = $('<input type="checkbox" class="rcfm-select">')
        .prop('checked', !!manager.selected[String(item.client_id)])
        .prop('disabled', !!item.deleted)
        .attr('aria-label', manager.form.data('rcfm-select-label').replace('__NAME__', item.name));
      row.append($('<td class="rcfm-selection">').append(selection));

      var nameCell = $('<td class="name">');
      if (manager.editingId === String(item.client_id) && !item.deleted) {
        nameCell.append($('<input type="text" class="rcfm-name-input">').val(item.name).attr('maxlength', 60));
      } else {
        nameCell.append($('<span class="rcfm-enumeration-name">').text(item.name));
      }
      if (item.id) {
        nameCell.append($('<span class="rcfm-record-id">').text('#' + item.id));
      }
      if (item.protected) {
        nameCell.append(
          $('<span class="rcfm-protection-indicator">')
            .text('🔒')
            .attr('title', item.protected_reason)
            .attr('aria-label', manager.form.data('rcfm-protected-indicator') + ': ' + item.protected_reason)
        );
      }
      row.append(nameCell);

      var active = $('<input type="checkbox" class="rcfm-active">')
        .prop('checked', !!item.active)
        .prop('disabled', !!item.deleted)
        .attr('aria-label', manager.form.data('rcfm-active-label').replace('__NAME__', item.name));
      row.append($('<td>').append(active));

      var buttons = $('<td class="buttons">');
      if (item.deleted) {
        buttons.append(
          $('<button type="button" class="rcfm-restore-item">').text(manager.form.data('rcfm-restore-label'))
        );
      } else {
        buttons.append(
          $('<span class="icon-only icon-sort-handle sort-handle rcfm-sort-handle">')
            .attr('title', manager.form.data('rcfm-move-label'))
        );
        buttons.append(
          $('<button type="button" class="icon icon-edit rcfm-edit">').text(manager.form.data('rcfm-edit-label'))
        );
        buttons.append(
          $('<button type="button" class="icon icon-del rcfm-delete">')
            .text(manager.form.data('rcfm-delete-label'))
            .prop('disabled', !!item.protected)
            .attr('title', item.protected ? item.protected_reason : manager.form.data('rcfm-delete-label'))
        );
      }
      row.append(buttons);
      fragment.appendChild(row[0]);
    });

    this.body[0].appendChild(fragment);
    this.body.sortable('refresh');
    this.refreshTargetList();
  };

  EnumerationManager.prototype.changeCounts = function() {
    var baselineById = {};
    this.baseline.forEach(function(item, index) {
      baselineById[String(item.client_id)] = {item: item, index: index};
    });
    var counts = {added: 0, updated: 0, deleted: 0, moved: 0};
    this.items.forEach(function(item, index) {
      var original = baselineById[String(item.client_id)];
      if (!original) {
        if (!item.deleted) {
          counts.added += 1;
        }
        return;
      }
      if (item.deleted && !original.item.deleted) {
        counts.deleted += 1;
      }
      if (!item.deleted && (item.name !== original.item.name || item.active !== original.item.active)) {
        counts.updated += 1;
      }
      if (!item.deleted && index !== original.index) {
        counts.moved += 1;
      }
    });
    return counts;
  };

  EnumerationManager.prototype.isDirty = function() {
    return JSON.stringify(this.items) !== JSON.stringify(this.baseline);
  };

  EnumerationManager.prototype.refresh = function() {
    var counts = this.changeCounts();
    var dirty = this.isDirty();
    var summary = this.form.data('rcfm-no-changes');
    if (dirty) {
      summary = this.form.data('rcfm-changes-summary')
        .replace('__ADDED__', counts.added)
        .replace('__UPDATED__', counts.updated)
        .replace('__DELETED__', counts.deleted)
        .replace('__MOVED__', counts.moved);
    }
    this.form.find('.rcfm-status').text(summary);
    this.refreshSelection();
    this.form.find('.rcfm-items').val(JSON.stringify(this.items));
    this.form.find('.rcfm-save, .rcfm-reset').prop('disabled', !dirty || this.saving);
    this.form.find('.rcfm-undo').prop('disabled', !this.undoStack.length || this.saving);
    this.form.find('.rcfm-redo').prop('disabled', !this.redoStack.length || this.saving);
    if (!this.conflict) {
      this.form.find('.rcfm-force').val('0');
      this.form.find('.rcfm-confirmed-digest').val('');
      this.form.find('.rcfm-resolution').val('normal');
    }
  };

  EnumerationManager.prototype.showError = function(message) {
    this.form.find('.rcfm-error').text(message).prop('hidden', false);
  };

  EnumerationManager.prototype.showConflict = function(payload) {
    this.conflict = payload;
    var panel = this.form.find('.rcfm-conflict');
    panel.find('.rcfm-conflict-message').text(payload.message);
    panel.find('.rcfm-conflict-server-state').text(
      this.form.data('rcfm-server-state').replace('__COUNT__', payload.current_snapshot.length)
    );
    var table = $('<table class="list rcfm-conflict-comparison"><thead><tr></tr></thead><tbody></tbody></table>');
    table.find('thead tr')
      .append($('<th>').text(this.form.data('rcfm-conflict-base')))
      .append($('<th>').text(this.form.data('rcfm-conflict-mine')))
      .append($('<th>').text(this.form.data('rcfm-conflict-server')));
    var proposalById = {};
    if (payload.merge_proposal_snapshot) {
      payload.merge_proposal_snapshot.forEach(function(item) {
        if (item.id) {
          proposalById[String(item.id)] = item;
        }
      });
      table.find('thead tr').append($('<th>').text(this.form.data('rcfm-conflict-merge')));
    }
    payload.diffs.forEach(function(diff) {
      var row = $('<tr>')
          .append($('<td>').text(this.conflictValue(diff.base)))
          .append($('<td>').text(this.conflictValue(diff.mine)))
          .append($('<td>').text(this.conflictValue(diff.current)));
      if (payload.merge_proposal_snapshot) {
        var proposed = proposalById[String(diff.key)];
        if (!proposed && diff.mine) {
          proposed = payload.merge_proposal_snapshot.find(function(item) {
            return !item.id && item.name === diff.mine.name;
          });
        }
        row.append($('<td>').text(this.conflictValue(proposed)));
      }
      table.find('tbody').append(row);
    }, this);
    panel.find('.rcfm-conflict-diffs').empty().append(table);
    panel.find('.rcfm-conflict-merge').prop('hidden', payload.merge_proposal === null);
    panel.prop('hidden', false);
    panel[0].scrollIntoView({behavior: 'smooth', block: 'nearest'});
  };

  EnumerationManager.prototype.conflictValue = function(item) {
    if (!item) {
      return '—';
    }
    var value = item.name || ('#' + item.id);
    if (item.deleted) {
      value += ' [' + this.form.data('rcfm-state-deleted') + ']';
    } else {
      value += item.active === false ? ' [' + this.form.data('rcfm-state-inactive') + ']' : '';
      if (item.position !== undefined && item.position !== null) {
        value += ' (' + this.form.data('rcfm-state-position').replace('__POSITION__', item.position) + ')';
      }
    }
    return value;
  };

  EnumerationManager.prototype.csvMode = function() {
    return this.form.find('input[name="rcfm_csv_mode"]:checked').val();
  };

  EnumerationManager.prototype.csvMissingDefault = function() {
    return this.form.find('input[name="rcfm_csv_missing_default"]:checked').val();
  };

  EnumerationManager.prototype.collectCsvMappings = function() {
    var mappings = {};
    this.form.find('.rcfm-csv-mapping-choice').each(function() {
      if (this.value) {
        mappings[String($(this).data('source-id'))] = this.value;
      }
    });
    return mappings;
  };

  EnumerationManager.prototype.collectCsvMissingActions = function() {
    var actions = {};
    this.form.find('.rcfm-csv-missing-action').each(function() {
      actions[String($(this).data('target-id'))] = this.value;
    });
    return actions;
  };

  EnumerationManager.prototype.csvPayload = function() {
    return {
      csv_data: this.csvData,
      mode: this.csvMode(),
      mappings: this.collectCsvMappings(),
      missing_default: this.csvMissingDefault(),
      missing_actions: this.collectCsvMissingActions()
    };
  };

  EnumerationManager.prototype.invalidateCsvPreview = function(keepChoices) {
    this.csvPreview = null;
    var preview = this.form.find('.rcfm-csv-preview');
    preview.find('.rcfm-csv-apply-button').prop('disabled', true);
    if (keepChoices && !preview.find('.rcfm-csv-stale').length) {
      preview.prepend($('<p class="warning rcfm-csv-stale">').text(this.form.data('rcfm-import-preview-stale')));
    } else if (!keepChoices) {
      preview.empty().prop('hidden', true);
    }
  };

  EnumerationManager.prototype.readCsvFile = function() {
    var manager = this;
    if (this.csvData !== null) {
      return Promise.resolve(this.csvData);
    }
    var file = this.form.find('.rcfm-csv-file')[0].files[0];
    if (!file || file.size > 50 * 1024 * 1024) {
      return Promise.reject(new Error(this.form.data('rcfm-import-read-error')));
    }
    return file.text().then(function(data) {
      manager.csvData = data;
      return data;
    });
  };

  EnumerationManager.prototype.jsonRequest = function(url, payload) {
    var token = document.querySelector('meta[name="csrf-token"]');
    return fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': token ? token.content : ''
      },
      body: JSON.stringify(payload)
    }).then(function(response) {
      return response.json().catch(function() { return {}; }).then(function(body) {
        if (!response.ok) {
          throw {response: response, payload: body};
        }
        return body;
      });
    });
  };

  EnumerationManager.prototype.previewCsvImport = function() {
    var manager = this;
    if (this.isDirty()) {
      this.showError(this.form.data('rcfm-import-unsaved'));
      return;
    }
    if (this.saving) {
      return;
    }
    this.clearError();
    this.readCsvFile().then(function() {
      return manager.jsonRequest(manager.form.data('rcfm-import-preview-url'), manager.csvPayload());
    }).then(function(payload) {
      manager.csvPreview = payload;
      manager.renderCsvPreview(payload);
    }).catch(function(error) {
      manager.showError(
        error.payload && error.payload.message ? error.payload.message : manager.form.data('rcfm-import-read-error')
      );
    });
  };

  EnumerationManager.prototype.renderCsvPreview = function(payload) {
    var manager = this;
    var plan = payload.plan;
    var preview = this.form.find('.rcfm-csv-preview').empty().prop('hidden', false);
    preview.append($('<h3>').text(this.form.data('rcfm-import-preview-heading')));

    if (plan.unresolved.length) {
      preview.append($('<h4>').text(this.form.data('rcfm-import-mapping-heading')));
      preview.append($('<p>').text(this.form.data('rcfm-import-confirm-mapping')));
      plan.unresolved.forEach(function(item) {
        var row = $('<p class="rcfm-csv-mapping-row">');
        row.append($('<span class="rcfm-csv-source">').text(item.name + ' (#' + item.source_id + ') '));
        var select = $('<select class="rcfm-csv-mapping-choice">').attr('data-source-id', item.source_id);
        select.append($('<option value="">').text(manager.form.data('rcfm-import-confirm-mapping')));
        item.candidates.forEach(function(candidate) {
          select.append($('<option>').val(candidate.id).text(candidate.name + ' (#' + candidate.id + ')'));
        });
        select.append($('<option value="new">').text(manager.form.data('rcfm-import-new-item')));
        row.append(select);
        preview.append(row);
      });
    }

    if (plan.missing_items.length) {
      preview.append($('<h4>').text(this.form.data('rcfm-import-missing-heading')));
      plan.missing_items.forEach(function(item) {
        var row = $('<p class="rcfm-csv-missing-row">');
        row.append($('<span>').text(item.name + ' (#' + item.id + ') '));
        var select = $('<select class="rcfm-csv-missing-action">')
          .attr('data-target-id', item.id)
          .prop('disabled', item.used);
        select.append($('<option value="disable">').text(manager.form.data('rcfm-import-disable-label')));
        if (!item.used) {
          select.append($('<option value="delete">').text(manager.form.data('rcfm-import-delete-label')));
        }
        select.val(item.action);
        row.append(select);
        preview.append(row);
      });
    }

    if (plan.diffs.length) {
      var table = $('<table class="list rcfm-csv-diffs"><thead><tr></tr></thead><tbody></tbody></table>');
      table.find('thead tr')
        .append($('<th>').text(this.form.data('rcfm-import-diff-action')))
        .append($('<th>').text(this.form.data('rcfm-import-diff-name')));
      plan.diffs.forEach(function(diff) {
        var action = manager.form.data('rcfm-diff-' + diff.action) || diff.action;
        table.find('tbody').append(
          $('<tr>').append($('<td>').text(action)).append($('<td>').text(diff.name + (diff.id ? ' (#' + diff.id + ')' : '')))
        );
      });
      preview.append(table);
    } else if (plan.resolved) {
      preview.append($('<p>').text(this.form.data('rcfm-import-no-differences')));
    }

    if (plan.resolved) {
      preview.append(
        $('<p>').append($('<button type="button" class="rcfm-csv-apply-button">').text(this.form.data('rcfm-import-apply-label')))
      );
    }
    preview[0].scrollIntoView({behavior: 'smooth', block: 'nearest'});
  };

  EnumerationManager.prototype.applyCsvImport = function() {
    var manager = this;
    if (!this.csvPreview || !this.csvPreview.plan.resolved || this.saving) {
      this.showError(this.form.data('rcfm-import-preview-stale'));
      return;
    }
    if (!window.confirm(this.form.data('rcfm-import-apply-confirm'))) {
      return;
    }
    this.saving = true;
    var payload = this.csvPayload();
    payload.base_digest = this.csvPreview.base_digest;
    payload.plan_digest = this.csvPreview.plan.digest;
    this.jsonRequest(this.form.data('rcfm-import-apply-url'), payload).then(function() {
      window.alert(manager.form.data('rcfm-import-success'));
      window.location.reload();
    }).catch(function(error) {
      manager.saving = false;
      manager.showError(error.payload && error.payload.message ? error.payload.message : manager.form.data('rcfm-save-error'));
    });
  };

  EnumerationManager.prototype.save = function(force, resolution) {
    var manager = this;
    if (!this.isDirty() || this.saving) {
      return;
    }
    if (force && !this.conflict) {
      return;
    }

    this.saving = true;
    this.clearError();
    this.form.find('.rcfm-force').val(force ? '1' : '0');
    this.form.find('.rcfm-confirmed-digest').val(force ? this.conflict.current_digest : '');
    this.form.find('.rcfm-resolution').val(resolution || (force ? 'force' : 'normal'));
    this.refresh();

    fetch(this.form.attr('action'), {
      method: 'PUT',
      body: new FormData(this.form[0]),
      credentials: 'same-origin',
      headers: {'Accept': 'application/json'}
    }).then(function(response) {
      return response.json().catch(function() { return {}; }).then(function(payload) {
        return {response: response, payload: payload};
      });
    }).then(function(result) {
      if (!result.response.ok) {
        throw result;
      }
      window.location.reload();
    }).catch(function(result) {
      manager.saving = false;
      var payload = result && result.payload ? result.payload : {};
      if (payload.error === 'conflict') {
        manager.showConflict(payload);
      } else {
        manager.showError(payload.message || manager.form.data('rcfm-save-error'));
      }
      manager.refresh();
    });
  };

  $(function() {
    $('.rcfm-manager[data-rcfm-manager="enumerations"]').each(function() {
      new EnumerationManager(this);
    });
  });
})(window, document, window.jQuery);
