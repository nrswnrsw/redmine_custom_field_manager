(function(window, document, $) {
  'use strict';

  function arraysEqual(left, right) {
    return left.length === right.length && left.every(function(value, index) {
      return value === right[index];
    });
  }

  function CustomFieldManager(form) {
    if (window.performance && window.performance.mark) {
      window.performance.mark('rcfm-custom-fields-init-start');
    }
    this.form = $(form);
    this.body = this.form.find('tbody');
    this.baseline = this.currentOrder();
    this.undoStack = [];
    this.redoStack = [];
    this.dragStartOrder = null;
    this.draggedRows = [];
    this.saving = false;
    this.conflict = null;
    this.bind();
    this.refresh();
    if (window.performance && window.performance.mark && window.performance.measure) {
      window.performance.mark('rcfm-custom-fields-init-end');
      window.performance.measure(
        'rcfm-custom-fields-init',
        'rcfm-custom-fields-init-start',
        'rcfm-custom-fields-init-end'
      );
    }
  }

  CustomFieldManager.prototype.currentOrder = function() {
    return this.body.children('tr[data-rcfm-id]').map(function() {
      return String($(this).data('rcfm-id'));
    }).get();
  };

  CustomFieldManager.prototype.restore = function(order) {
    var rows = {};
    this.body.children('tr[data-rcfm-id]').each(function() {
      rows[String($(this).data('rcfm-id'))] = this;
    });
    order.forEach(function(id) {
      if (rows[id]) {
        this.body.append(rows[id]);
      }
    }, this);
    this.refreshTargetList();
    this.refresh();
  };

  CustomFieldManager.prototype.recordChange = function(previousOrder) {
    var current = this.currentOrder();
    if (arraysEqual(previousOrder, current)) {
      return;
    }
    this.undoStack.push(previousOrder);
    this.redoStack = [];
    this.conflict = null;
    this.clearError();
    this.form.find('.rcfm-conflict').prop('hidden', true);
    this.refreshTargetList();
    this.refresh();
  };

  CustomFieldManager.prototype.bind = function() {
    var manager = this;

    this.body.sortable({
      axis: 'y',
      handle: '.rcfm-sort-handle',
      scroll: true,
      scrollSensitivity: 80,
      scrollSpeed: 18,
      placeholder: 'rcfm-sort-placeholder',
      start: function(_event, ui) {
        manager.dragStartOrder = manager.currentOrder();
        var selected = manager.body.find('.rcfm-select:checked').closest('tr').toArray();
        manager.draggedRows = selected.indexOf(ui.item[0]) >= 0 ? selected : [ui.item[0]];
        manager.draggedRows.forEach(function(row) {
          if (row !== ui.item[0]) {
            $(row).detach();
          }
        });
      },
      stop: function(_event, ui) {
        if (manager.draggedRows.length > 1) {
          var marker = $('<tr class="rcfm-group-marker"><td></td></tr>');
          marker.insertBefore(ui.item);
          manager.draggedRows.forEach(function(row) {
            marker.before(row);
          });
          marker.remove();
        }
        manager.recordChange(manager.dragStartOrder || manager.baseline);
        manager.dragStartOrder = null;
        manager.draggedRows = [];
      }
    });

    this.form.on('change', '.rcfm-select', function() {
      $(this).closest('tr').toggleClass('rcfm-selected', this.checked);
      manager.hideTargetCandidates();
      manager.clearError();
      manager.refreshSelection();
    });

    this.form.on('input', '.rcfm-target', function() {
      manager.hideTargetCandidates();
      manager.clearError();
    });

    this.form.on('click', '.rcfm-select-all', function() {
      manager.form.find('.rcfm-select').prop('checked', true).trigger('change');
    });

    this.form.on('click', '.rcfm-clear-selection', function() {
      manager.form.find('.rcfm-select').prop('checked', false).trigger('change');
    });

    this.form.on('click', '.rcfm-move-selected', function() {
      manager.moveSelected();
    });

    this.form.on('click', '.rcfm-target-candidate', function() {
      manager.moveSelected($(this).attr('data-rcfm-target-id'));
    });

    this.form.on('click', '.rcfm-undo', function() {
      if (!manager.undoStack.length) {
        return;
      }
      manager.redoStack.push(manager.currentOrder());
      manager.conflict = null;
      manager.clearError();
      manager.restore(manager.undoStack.pop());
    });

    this.form.on('click', '.rcfm-redo', function() {
      if (!manager.redoStack.length) {
        return;
      }
      manager.undoStack.push(manager.currentOrder());
      manager.conflict = null;
      manager.clearError();
      manager.restore(manager.redoStack.pop());
    });

    this.form.on('click', '.rcfm-reset', function() {
      if (!manager.isDirty()) {
        return;
      }
      manager.undoStack.push(manager.currentOrder());
      manager.redoStack = [];
      manager.conflict = null;
      manager.clearError();
      manager.restore(manager.baseline);
    });

    this.form.on('submit', function(event) {
      event.preventDefault();
      manager.save('normal');
    });

    this.form.on('click', '.rcfm-conflict-continue', function() {
      manager.form.find('.rcfm-conflict').prop('hidden', true);
    });

    this.form.on('click', '.rcfm-conflict-reload', function() {
      if (window.confirm(manager.form.data('rcfm-confirm-discard'))) {
        window.location.reload();
      }
    });

    this.form.on('click', '.rcfm-conflict-merge', function() {
      if (!manager.conflict || !manager.conflict.merge_proposal) {
        return;
      }
      manager.restore(manager.conflict.merge_proposal.map(String));
      manager.save('merge');
    });

    this.form.on('click', '.rcfm-conflict-force', function() {
      if (window.confirm(manager.form.data('rcfm-confirm-force'))) {
        manager.save('force');
      }
    });

    $(window).on('beforeunload.rcfm-' + this.form.attr('id'), function(event) {
      if (!manager.saving && manager.isDirty()) {
        event.preventDefault();
        event.returnValue = '';
      }
    });
  };

  CustomFieldManager.prototype.hideTargetCandidates = function() {
    this.form.find('.rcfm-target-candidates').prop('hidden', true)
      .find('.rcfm-target-candidate-list').empty();
  };

  CustomFieldManager.prototype.clearError = function() {
    this.form.find('.rcfm-error').prop('hidden', true).text('');
  };

  CustomFieldManager.prototype.showTargetCandidates = function(targets, selected) {
    var manager = this;
    var panel = this.form.find('.rcfm-target-candidates');
    var list = panel.find('.rcfm-target-candidate-list').empty();
    var rows = this.body.children('tr[data-rcfm-id]');

    panel.find('.rcfm-target-candidates-message').text(this.form.data('rcfm-target-ambiguous'));
    targets.each(function() {
      var row = $(this);
      var id = String(row.data('rcfm-id'));
      var name = String(row.attr('data-rcfm-name'));
      var label = manager.form.data('rcfm-target-candidate')
        .replace('__POSITION__', rows.index(row) + 1)
        .replace('__NAME__', name);
      var button = $('<button type="button" class="rcfm-target-candidate">')
        .attr('data-rcfm-target-id', id)
        .prop('disabled', selected.filter(row).length > 0)
        .append($('<span>').text(label))
        .append($('<span class="rcfm-record-id">').text('#' + id));
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

  CustomFieldManager.prototype.moveSelected = function(targetId) {
    var selected = this.body.find('.rcfm-select:checked').closest('tr');
    var value = this.form.find('.rcfm-target').val().trim();
    var match = value.match(/\(#(\d+)\)\s*$/);
    var error = this.form.find('.rcfm-error');

    this.hideTargetCandidates();
    this.clearError();
    if (!selected.length) {
      error.text(this.form.data('rcfm-selection-error')).prop('hidden', false);
      return;
    }
    if (!value) {
      error.text(this.form.data('rcfm-target-required')).prop('hidden', false);
      return;
    }

    var target;
    if (targetId) {
      target = this.body.find('tr[data-rcfm-id="' + targetId + '"]');
    } else if (match) {
      target = this.body.find('tr[data-rcfm-id="' + match[1] + '"]');
    } else {
      var lowered = value.toLocaleLowerCase();
      target = this.body.children('tr[data-rcfm-id]').filter(function() {
        return String($(this).attr('data-rcfm-name')).trim().toLocaleLowerCase() === lowered;
      });
      if (!target.length) {
        error.text(this.form.data('rcfm-target-not-found')).prop('hidden', false);
        return;
      }
      if (target.length > 1) {
        if (!target.filter(function() { return selected.filter(this).length === 0; }).length) {
          error.text(this.form.data('rcfm-target-error')).prop('hidden', false);
          return;
        }
        this.showTargetCandidates(target, selected);
        return;
      }
    }
    if (!target.length || selected.filter(target).length) {
      error.text(this.form.data('rcfm-target-error')).prop('hidden', false);
      return;
    }

    var previous = this.currentOrder();
    var side = this.form.find('input[type="radio"]:checked').val();
    var rows = selected.detach();
    if (side === 'after') {
      target.after(rows);
    } else {
      target.before(rows);
    }
    this.recordChange(previous);
  };

  CustomFieldManager.prototype.isDirty = function() {
    return !arraysEqual(this.baseline, this.currentOrder());
  };

  CustomFieldManager.prototype.refreshSelection = function() {
    var count = this.body.find('.rcfm-select:checked').length;
    this.form.toggleClass('rcfm-has-selection', count > 0);
    this.form.find('.rcfm-selection-count').text(
      this.form.data('rcfm-selected-count').replace('__COUNT__', count)
    );
  };

  CustomFieldManager.prototype.refreshTargetList = function() {
    var manager = this;
    var targetList = this.form.find('.rcfm-target-list').empty();
    this.body.children('tr[data-rcfm-id]').each(function(index) {
      var row = $(this);
      var id = String(row.data('rcfm-id'));
      var label = manager.form.data('rcfm-target-candidate')
        .replace('__POSITION__', index + 1)
        .replace('__NAME__', String(row.attr('data-rcfm-name')));
      targetList.append($('<option>').val(label + ' (#' + id + ')'));
    });
  };

  CustomFieldManager.prototype.refresh = function() {
    var current = this.currentOrder();
    var changedCount = current.reduce(function(count, id, index) {
      return count + (this.baseline[index] === id ? 0 : 1);
    }.bind(this), 0);
    var dirty = changedCount > 0;

    this.form.toggleClass('rcfm-dirty', dirty);
    this.form.find('.rcfm-ordered-ids').val(JSON.stringify(current));
    this.form.find('.rcfm-save, .rcfm-reset').prop('disabled', !dirty || this.saving);
    this.form.find('.rcfm-undo').prop('disabled', !this.undoStack.length || this.saving);
    this.form.find('.rcfm-redo').prop('disabled', !this.redoStack.length || this.saving);
    var status = dirty ? this.form.data('rcfm-changed-count').replace('__COUNT__', changedCount) : this.form.data('rcfm-no-changes');
    this.form.find('.rcfm-status').text(status);
    this.refreshSelection();
    if (!this.conflict) {
      this.form.find('.rcfm-force').val('0');
      this.form.find('.rcfm-confirmed-digest').val('');
      this.form.find('.rcfm-resolution').val('normal');
    }
  };

  CustomFieldManager.prototype.conflictValue = function(item) {
    if (!item) {
      return '—';
    }
    var value = item.name || ('#' + item.id);
    if (item.position !== undefined && item.position !== null) {
      value += ' (' + this.form.data('rcfm-state-position').replace('__POSITION__', item.position) + ')';
    }
    return value;
  };

  CustomFieldManager.prototype.showConflict = function(payload) {
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
        proposalById[String(item.id)] = item;
      });
      table.find('thead tr').append($('<th>').text(this.form.data('rcfm-conflict-merge')));
    }
    payload.diffs.forEach(function(diff) {
      var row = $('<tr>')
          .append($('<td>').text(this.conflictValue(diff.base)))
          .append($('<td>').text(this.conflictValue(diff.mine)))
          .append($('<td>').text(this.conflictValue(diff.current)));
      if (payload.merge_proposal_snapshot) {
        row.append($('<td>').text(this.conflictValue(proposalById[String(diff.key)])));
      }
      table.find('tbody').append(row);
    }, this);
    panel.find('.rcfm-conflict-diffs').empty().append(table);
    panel.find('.rcfm-conflict-merge').prop('hidden', payload.merge_proposal === null);
    panel.prop('hidden', false);
    panel[0].scrollIntoView({behavior: 'smooth', block: 'nearest'});
  };

  CustomFieldManager.prototype.save = function(resolution) {
    var manager = this;
    if (!this.isDirty() || this.saving) {
      return;
    }
    resolution = resolution || 'normal';
    var resolving = resolution !== 'normal';
    if (resolving && !this.conflict) {
      return;
    }

    this.saving = true;
    this.form.find('.rcfm-error').prop('hidden', true).text('');
    this.form.find('.rcfm-force').val(resolving ? '1' : '0');
    this.form.find('.rcfm-confirmed-digest').val(resolving ? this.conflict.current_digest : '');
    this.form.find('.rcfm-resolution').val(resolution);
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
        var message = payload.message || manager.form.data('rcfm-save-error');
        manager.form.find('.rcfm-error').text(message).prop('hidden', false);
      }
      manager.refresh();
    });
  };

  $(function() {
    $('.rcfm-manager[data-rcfm-manager="custom-fields"]').each(function() {
      new CustomFieldManager(this);
    });
  });
})(window, document, window.jQuery);
