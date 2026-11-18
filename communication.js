/* STEADYFIX CMMS — Company Communication Centre */
let COMM_STATE = {
  tab: 'chats',
  activeId: null,
  showNew: false,
  conversations: [],
  members: [],
  staff: [],
  messages: [],
  realtime: null
};

function openCommunicationCentre() {
  const panel = document.getElementById('notifPanel');
  if (panel) panel.hidden = true;
  COMM_STATE.tab = 'chats';
  cur = 'comms';
  draw();
}

function setCommunicationTab(tab) {
  COMM_STATE.tab = tab;
  COMM_STATE.showNew = false;
  if (tab !== 'chats') COMM_STATE.activeId = null;
  draw();
}

function communicationTime(value) {
  if (!value) return '';
  try {
    return new Date(value).toLocaleString('en-ZA', { day:'numeric', month:'short', hour:'2-digit', minute:'2-digit' });
  } catch (e) { return ''; }
}

async function loadCommunicationData() {
  const { data: conversations, error } = await sb.from('company_conversations')
    .select('id,kind,title,created_by,created_at,last_message_at')
    .eq('company_id', me.company_id)
    .order('last_message_at', { ascending:false })
    .limit(100);
  if (error) throw error;
  COMM_STATE.conversations = conversations || [];

  const ids = COMM_STATE.conversations.map(c => c.id);
  if (!ids.length) {
    COMM_STATE.members = [];
    COMM_STATE.staff = [];
    COMM_STATE.messages = [];
    return;
  }

  const [membersResult, staffResult, latestResult] = await Promise.all([
    sb.from('conversation_members').select('conversation_id,user_id,last_read_at').in('conversation_id', ids),
    sb.from('profiles').select('id,full_name,role,active').eq('company_id', me.company_id).eq('active', true),
    sb.from('messages').select('conversation_id,sender_id,body,created_at').in('conversation_id', ids).order('created_at', { ascending:false }).limit(300)
  ]);
  if (membersResult.error) throw membersResult.error;
  if (staffResult.error) throw staffResult.error;
  if (latestResult.error) throw latestResult.error;
  COMM_STATE.members = membersResult.data || [];
  COMM_STATE.staff = staffResult.data || [];

  const latestByConversation = {};
  (latestResult.data || []).forEach(message => {
    if (!latestByConversation[message.conversation_id]) latestByConversation[message.conversation_id] = message;
  });
  COMM_STATE.conversations = COMM_STATE.conversations.map(conversation => ({
    ...conversation,
    latest: latestByConversation[conversation.id] || null,
    myMembership: COMM_STATE.members.find(m => m.conversation_id === conversation.id && m.user_id === me.id) || null
  }));
}

function communicationLabel(conversation) {
  if (conversation.kind === 'announcement') return conversation.title || 'Company announcement';
  if (conversation.kind === 'group') return conversation.title || 'Team group';
  const others = COMM_STATE.members
    .filter(m => m.conversation_id === conversation.id && m.user_id !== me.id)
    .map(m => COMM_STATE.staff.find(p => p.id === m.user_id))
    .filter(Boolean);
  return others.map(p => p.full_name).join(', ') || 'Private chat';
}

function communicationPreview(conversation) {
  const latest = conversation.latest;
  if (!latest) return 'No messages yet';
  const prefix = latest.sender_id === me.id ? 'You: ' : '';
  return prefix + String(latest.body || '').slice(0, 72);
}

function communicationListMarkup() {
  let rows = COMM_STATE.conversations;
  if (COMM_STATE.tab === 'announcements') rows = rows.filter(c => c.kind === 'announcement');
  else rows = rows.filter(c => c.kind !== 'announcement');

  if (!rows.length) {
    return '<div class="comm-empty">Nothing here yet. Start a conversation with your team.</div>';
  }

  return rows.map(c => {
    const unread = c.latest && c.latest.sender_id !== me.id &&
      c.myMembership && (!c.myMembership.last_read_at || new Date(c.latest.created_at) > new Date(c.myMembership.last_read_at));
    const type = c.kind === 'direct' ? 'Private' : c.kind === 'group' ? 'Group' : 'Announcement';
    return '<button type="button" class="comm-conversation ' +
      (COMM_STATE.activeId === c.id ? 'active ' : '') + (unread ? 'unread' : '') +
      '" onclick="selectCommunication(\'' + esc(c.id) + '\')">' +
      '<span class="comm-avatar">' + (c.kind === 'announcement' ? '!' : c.kind === 'group' ? 'G' : '•') + '</span>' +
      '<span class="comm-conversation-copy"><b>' + esc(communicationLabel(c)) + '</b>' +
      '<small>' + esc(communicationPreview(c)) + '</small></span>' +
      '<span class="comm-conversation-meta"><small>' + esc(type) + '</small>' +
      (unread ? '<i aria-label="Unread"></i>' : '') + '</span></button>';
  }).join('');
}

async function loadCommunicationMessages(conversationId) {
  const { data, error } = await sb.from('messages')
    .select('id,conversation_id,sender_id,body,created_at')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending:false })
    .limit(100);
  if (error) throw error;
  COMM_STATE.messages = (data || []).reverse();
}

function communicationThreadMarkup(conversation) {
  if (!conversation) {
    return '<div class="comm-thread-empty"><div class="comm-empty-icon">✉</div><b>Your company conversations</b><p>Select a chat or announcement to read messages, or start a new conversation.</p></div>';
  }
  const senderName = id => {
    if (id === me.id) return 'You';
    const profile = COMM_STATE.staff.find(p => p.id === id);
    return profile ? profile.full_name : 'Former staff member';
  };
  const items = COMM_STATE.messages.map(message => {
    const mine = message.sender_id === me.id;
    return '<div class="comm-message-row ' + (mine ? 'mine' : '') + '">' +
      '<div class="comm-message"><small>' + esc(senderName(message.sender_id)) + ' · ' + esc(communicationTime(message.created_at)) + '</small>' +
      '<div>' + esc(message.body) + '</div></div></div>';
  }).join('');
  const last = COMM_STATE.messages.length ? COMM_STATE.messages[COMM_STATE.messages.length - 1] : null;
  const otherMembers = COMM_STATE.members.filter(m => m.conversation_id === conversation.id && m.user_id !== me.id);
  let readStatus = '';
  if (last && last.sender_id === me.id && otherMembers.length) {
    const readCount = otherMembers.filter(m => m.last_read_at && new Date(m.last_read_at) >= new Date(last.created_at)).length;
    readStatus = '<div class="comm-read-status">' + (readCount === otherMembers.length ? 'Seen by everyone' : readCount ? 'Seen by ' + readCount + ' of ' + otherMembers.length : 'Sent') + '</div>';
  }
  const canPost = conversation.kind !== 'announcement' || ['owner','manager'].includes(me.role);
  return '<div class="comm-thread-head"><button class="comm-back" type="button" onclick="selectCommunication(null)">← Back</button>' +
    '<div><b>' + esc(communicationLabel(conversation)) + '</b><small>' +
    (conversation.kind === 'announcement' ? 'Company announcement' : conversation.kind === 'group' ? 'Team group conversation' : 'Private one-to-one chat') +
    '</small></div></div>' +
    '<div class="comm-message-list" id="commMessageList">' + (items || '<div class="comm-empty">This conversation is ready. Send the first message.</div>') + readStatus + '</div>' +
    (canPost ? '<form class="comm-compose" onsubmit="sendCommunicationMessage(event)"><textarea id="commMessageInput" maxlength="5000" rows="2" placeholder="Write a message…" required></textarea><button class="b" type="submit">Send</button></form>' :
      '<div class="comm-readonly-note">Only company owners and managers can post in announcements.</div>');
}

function communicationNewMarkup() {
  const options = COMM_STATE.staff.filter(p => p.id !== me.id)
    .map(p => '<option value="' + esc(p.id) + '">' + esc(p.full_name) + ' · ' + esc(p.role) + '</option>').join('');
  return '<div class="comm-new p"><div class="ct">Start a conversation</div>' +
    '<label class="el">Conversation type<select id="commNewKind"><option value="direct">Private one-to-one</option><option value="group">Group chat</option></select></label>' +
    '<label class="el">Select staff members<select id="commNewPeople" multiple size="5">' + options + '</select></label>' +
    '<label class="el">Group name (optional)<input id="commNewTitle" maxlength="80" placeholder="e.g. Maintenance team"></label>' +
    '<div class="comm-new-actions"><button class="b" type="button" onclick="createCommunicationConversation()">Create chat</button>' +
    '<button type="button" onclick="COMM_STATE.showNew=false;draw()">Cancel</button></div>' +
    '<small>Only active staff in your company can be added. Private chats are limited to two people.</small></div>';
}

async function communicationCentre() {
  await loadCommunicationData();
  if (COMM_STATE.activeId && !COMM_STATE.conversations.some(c => c.id === COMM_STATE.activeId)) COMM_STATE.activeId = null;
  const active = COMM_STATE.conversations.find(c => c.id === COMM_STATE.activeId) || null;
  if (active && COMM_STATE.tab !== 'activity') {
    await loadCommunicationMessages(active.id);
    const membership = COMM_STATE.members.find(m => m.conversation_id === active.id && m.user_id === me.id);
    if (!membership || !membership.last_read_at || new Date(active.last_message_at) > new Date(membership.last_read_at)) {
      const readAt = new Date().toISOString();
      const { error } = await sb.from('conversation_members').update({ last_read_at:readAt })
        .eq('conversation_id', active.id).eq('user_id', me.id);
      if (error) console.warn('Could not update conversation read status:', error.message);
      if (membership) membership.last_read_at = readAt;
    }
  }

  const activity = COMM_STATE.tab === 'activity';
  if (activity) await loadNotifications();

  const tabs = '<div class="comm-tabs">' +
    '<button class="' + (COMM_STATE.tab === 'chats' ? 'on' : '') + '" onclick="setCommunicationTab(\'chats\')">Chats</button>' +
    '<button class="' + (COMM_STATE.tab === 'announcements' ? 'on' : '') + '" onclick="setCommunicationTab(\'announcements\')">Announcements</button>' +
    '<button class="' + (activity ? 'on' : '') + '" onclick="setCommunicationTab(\'activity\')">Activity & alerts</button></div>';

  if (activity) {
    const rows = (NOTIFICATIONS || []).map(n =>
      '<button class="comm-activity-item ' + (!n.read_at ? 'unread' : '') + '" onclick="openNotification(\'' + esc(n.id) + '\',\'' + esc(n.work_order_id || '') + '\')">' +
      '<b>' + esc(n.title || 'STEADYFIX notification') + '</b><span>' + esc(n.message || '') + '</span><small>' + esc(communicationTime(n.created_at)) + '</small></button>'
    ).join('');
    return '<div class="comm-page"><div class="comm-page-heading"><div><h2>Company Communication Centre</h2><p>Messages, announcements and live CMMS alerts for your team.</p></div></div>' +
      tabs + '<div class="comm-activity-toolbar"><b>Recent alerts</b><button type="button" onclick="markAllNotificationsRead()">Mark all read</button></div>' + '<div class="comm-activity-list">' + (rows || '<div class="comm-empty">You are all caught up. No activity yet.</div>') + '</div></div>';
  }

  const list = communicationListMarkup();
  const actions = '<div class="comm-list-actions">' +
    (COMM_STATE.tab === 'chats' ? '<button class="b" type="button" onclick="COMM_STATE.showNew=!COMM_STATE.showNew;draw()">＋ New chat</button>' : '') +
    (COMM_STATE.tab === 'announcements' && ['owner','manager'].includes(me.role) ? '<button class="b" type="button" onclick="createCompanyAnnouncement()">＋ New announcement</button>' : '') +
    '</div>';
  return '<div class="comm-page"><div class="comm-page-heading"><div><h2>Company Communication Centre</h2><p>Messages, announcements and live CMMS alerts for your team.</p></div></div>' +
    tabs + (COMM_STATE.showNew ? communicationNewMarkup() : '') +
    '<div class="comm-layout ' + (active ? 'has-active' : '') + '">' +
    '<aside class="comm-list-panel"><div class="comm-list-heading"><b>' + (COMM_STATE.tab === 'announcements' ? 'Company announcements' : 'Your conversations') + '</b>' + actions + '</div>' +
    '<div class="comm-conversation-list">' + list + '</div></aside>' +
    '<section class="comm-thread-panel">' + communicationThreadMarkup(active) + '</section></div></div>';
}

async function selectCommunication(id) {
  COMM_STATE.activeId = id || null;
  COMM_STATE.showNew = false;
  if (!id) COMM_STATE.messages = [];
  draw();
}

async function createCommunicationConversation() {
  const kind = document.getElementById('commNewKind').value;
  const selected = Array.from(document.getElementById('commNewPeople').selectedOptions).map(o => o.value);
  const title = document.getElementById('commNewTitle').value.trim();
  if (kind === 'direct' && selected.length !== 1) return alert('Choose exactly one colleague for a private chat.');
  if (kind === 'group' && selected.length < 1) return alert('Choose at least one colleague for the group.');
  const { data, error } = await sb.rpc('create_company_conversation', {
    p_kind:kind, p_title:title || null, p_member_ids:selected
  });
  if (error) return alert('Could not create the conversation: ' + error.message);
  COMM_STATE.activeId = data;
  COMM_STATE.tab = 'chats';
  COMM_STATE.showNew = false;
  draw();
}

async function createCompanyAnnouncement() {
  const title = prompt('Announcement title');
  if (title === null) return;
  if (!title.trim()) return alert('Please enter an announcement title.');
  const { data, error } = await sb.rpc('create_company_conversation', {
    p_kind:'announcement', p_title:title.trim(), p_member_ids:[]
  });
  if (error) return alert('Could not create the announcement: ' + error.message);
  COMM_STATE.activeId = data;
  COMM_STATE.tab = 'announcements';
  draw();
}

async function sendCommunicationMessage(event) {
  event.preventDefault();
  const input = document.getElementById('commMessageInput');
  const body = input ? input.value.trim() : '';
  if (!body || !COMM_STATE.activeId) return;
  const { error } = await sb.from('messages').insert({
    conversation_id:COMM_STATE.activeId,
    company_id:me.company_id,
    sender_id:me.id,
    body
  });
  if (error) return alert('Message could not be sent: ' + error.message);
  COMM_STATE.messages = [];
  await draw();
}

function startCommsRealtime() {
  if (!me) return;
  if (COMM_STATE.realtime) sb.removeChannel(COMM_STATE.realtime);
  COMM_STATE.realtime = sb.channel('cmms-company-messages-' + me.id)
    .on('postgres_changes', {
      event:'INSERT', schema:'public', table:'messages',
      filter:'company_id=eq.' + me.company_id
    }, payload => {
      if (!payload.new || payload.new.company_id !== me.company_id) return;
      if (cur === 'comms') draw();
    })
    .subscribe((status, error) => {
      if (status !== 'SUBSCRIBED') console.warn('CMMS messaging realtime:', status, error || '');
    });
}
