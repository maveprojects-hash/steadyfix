/* STEADYFIX CMMS — tenant-scoped live operational sync.
 * The database remains the source of truth. Realtime events invalidate the
 * active view so every signed-in client reloads the same committed records.
 */
(() => {
  const TABLES = [
    'work_orders','pm_schedules','stock_items','purchase_orders','shutdowns',
    'sensors','assets','shifts','budgets','expenses','customers','suppliers',
    'damage_reports','ohs_inspections','ohs_hazards','ohs_incidents','ohs_ppe',
    'ohs_training','ohs_regs','fire_equipment','fire_inspections','vehicles',
    'workshop_jobs','work_order_time_entries','work_order_material_issues',
    'work_order_customer_signoffs','logistics_shipments','logistics_tracking_events',
    'logistics_pod_signoffs','documents'
  ];
  let channel = null;
  let refreshTimer = null;
  let refreshPending = false;
  let lastRefreshAt = 0;

  function isEditing() {
    const el = document.activeElement;
    return !!el && (
      el.isContentEditable ||
      /^(INPUT|SELECT|TEXTAREA)$/.test(el.tagName) ||
      !!el.closest?.('[contenteditable="true"]')
    );
  }

  function refreshActiveView() {
    if (typeof me === 'undefined' || !me || typeof draw !== 'function') return;
    if (document.hidden || isEditing()) {
      refreshPending = true;
      return;
    }
    refreshPending = false;
    const now = Date.now();
    if (now - lastRefreshAt < 700) return;
    lastRefreshAt = now;
    Promise.resolve(draw()).catch(error =>
      console.warn('CMMS live view refresh failed:', error?.message || error)
    );
  }

  function scheduleRefresh() {
    refreshPending = true;
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(refreshActiveView, 350);
  }

  window.startCompanyLiveSync = function startCompanyLiveSync() {
    if (typeof me === 'undefined' || !me?.id || !me?.company_id || !sb) return;
    if (channel) sb.removeChannel(channel);

    channel = sb.channel('cmms-live-company-' + me.company_id);
    TABLES.forEach(table => {
      channel = channel.on('postgres_changes', {
        event: '*',
        schema: 'public',
        table,
        filter: 'company_id=eq.' + me.company_id
      }, payload => {
        if (!payload?.new && !payload?.old) return;
        const row = payload.new || payload.old;
        if (row.company_id !== me.company_id) return;
        scheduleRefresh();
      });
    });

    channel.subscribe((status, error) => {
      if (status === 'SUBSCRIBED') {
        console.info('CMMS live operational sync connected for company', me.company_id);
        if (refreshPending) scheduleRefresh();
      } else {
        console.warn('CMMS live operational sync:', status, error || '');
      }
    });

    if (!window.__sfLiveSyncListeners) {
      window.__sfLiveSyncListeners = true;
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden && refreshPending) scheduleRefresh();
      });
      document.addEventListener('focusout', () => {
        if (refreshPending) setTimeout(() => {
          if (!isEditing()) refreshActiveView();
        }, 250);
      });
    }
  };

  window.stopCompanyLiveSync = function stopCompanyLiveSync() {
    if (channel && sb) sb.removeChannel(channel);
    channel = null;
    clearTimeout(refreshTimer);
  };
})();
