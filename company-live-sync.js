/* STEADYFIX CMMS — tenant-scoped live operational sync.
 * The database remains the source of truth. Each committed change emits a
 * minimal private company event; clients reload through their normal RLS reads.
 */
(() => {
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

    const topic = 'company:' + me.company_id + ':cmms-live';
    channel = sb.channel(topic, { config: { private: true } })
      .on('broadcast', { event: 'cmms_change' }, message => {
        const event = message?.payload || message;
        if (event?.company_id && event.company_id !== me.company_id) return;
        scheduleRefresh();
      })
      .subscribe((status, error) => {
        if (status === 'SUBSCRIBED') {
          console.info('CMMS private company live sync connected');
          if (refreshPending) scheduleRefresh();
        } else {
          console.warn('CMMS private company live sync:', status, error || '');
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
