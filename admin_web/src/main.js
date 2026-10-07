import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';
import { onValue, push, ref, set, update } from 'firebase/database';
import { database, firebaseConfigError } from './firebase.js';
import './styles.css';

L.Icon.Default.mergeOptions({
  iconUrl: markerIcon,
  iconRetinaUrl: markerIcon2x,
  shadowUrl: markerShadow,
});

const map = L.map('map').setView([14.211, 121.165], 12);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19,
  attribution:
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
}).addTo(map);

const markers = new Map();
const connectionState = document.querySelector('#connection-state');
const activeCount = document.querySelector('#active-count');
const summaryCard = document.querySelector('#summary-card');
const dashboardStatus = document.querySelector('#dashboard-status');
const listCaption = document.querySelector('#list-caption');
const emergencyList = document.querySelector('#emergency-list');
const message = document.querySelector('#message');
const details = document.querySelector('#details');
const detailsTitle = document.querySelector('#details-title');
const detailsGrid = document.querySelector('#details-grid');
const announcementForm = document.querySelector('#announcement-form');
const announcementTitle = document.querySelector('#announcement-title');
const announcementBody = document.querySelector('#announcement-body');
const announcementType = document.querySelector('#announcement-type');
const announcementPriority = document.querySelector('#announcement-priority');
const announcementMessage = document.querySelector('#announcement-message');
const announcementList = document.querySelector('#announcement-list');
const announcementCaption = document.querySelector('#announcement-caption');
const announcementConfirmation = document.querySelector('#announcement-confirmation');
const confirmSendAnnouncement = document.querySelector('#confirm-send-announcement');
let pendingAnnouncement = null;

const presets = {
  rain: {
    title: 'Heavy Rainfall Warning',
    message: 'Heavy rainfall is expected. Stay alert, monitor official updates, and avoid flooded areas.',
    type: 'alert',
    priority: 'important',
  },
  flood: {
    title: 'Flood Warning',
    message: 'Flooding is possible in low-lying areas. Move to safer ground and follow local safety advisories.',
    type: 'alert',
    priority: 'emergency',
  },
  evacuation: {
    title: 'Evacuation Notice',
    message: 'Please proceed to your designated evacuation area and follow instructions from local officials.',
    type: 'alert',
    priority: 'emergency',
  },
  advisory: {
    title: 'General Advisory',
    message: 'Please stay informed and follow official barangay announcements.',
    type: 'announcement',
    priority: 'normal',
  },
  classes: {
    title: 'Class Suspension',
    message: 'Classes are suspended until further notice. Please follow official updates from your school and local authorities.',
    type: 'announcement',
    priority: 'important',
  },
};

function showAnnouncementMessage(text, isError = false) {
  announcementMessage.hidden = !text;
  announcementMessage.textContent = text;
  announcementMessage.classList.toggle('announcement-error', isError);
}

function renderAnnouncements(value) {
  const items = value && typeof value === 'object'
    ? Object.entries(value).map(([id, item]) => ({ id, ...item }))
    : [];
  items.sort((a, b) => Number(b.timestamp) - Number(a.timestamp));
  const recent = items.slice(0, 10);
  announcementCaption.textContent = `${recent.length} shown`;
  announcementList.replaceChildren();

  if (recent.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'announcement-empty';
    empty.textContent = 'No notifications sent yet.';
    announcementList.append(empty);
    return;
  }

  for (const item of recent) {
    const card = document.createElement('article');
    card.className = 'announcement-item';
    const title = document.createElement('strong');
    title.textContent = item.title || 'Untitled notification';
    const meta = document.createElement('span');
    meta.className = 'announcement-meta';
    meta.textContent = `${item.type || 'announcement'} · ${item.priority || 'normal'} · ${formatTime(item.timestamp)}`;
    const preview = document.createElement('p');
    const messageText = String(item.message || '');
    preview.textContent = messageText.length > 160 ? `${messageText.slice(0, 157)}…` : messageText;
    card.append(title, meta, preview);
    announcementList.append(card);
  }
}

document.querySelectorAll('[data-preset]').forEach((button) => {
  button.addEventListener('click', () => {
    const preset = presets[button.dataset.preset];
    if (!preset) return;
    announcementTitle.value = preset.title;
    announcementBody.value = preset.message;
    announcementType.value = preset.type;
    announcementPriority.value = preset.priority;
    announcementTitle.focus();
  });
});

announcementForm.addEventListener('submit', (event) => {
  event.preventDefault();
  pendingAnnouncement = {
    title: announcementTitle.value.trim(),
    message: announcementBody.value.trim(),
    type: announcementType.value,
    priority: announcementPriority.value,
  };
  if (!pendingAnnouncement.title || !pendingAnnouncement.message) return;
  announcementConfirmation.showModal();
});

document.querySelector('#cancel-send-announcement').addEventListener('click', () => {
  announcementConfirmation.close();
  pendingAnnouncement = null;
});

confirmSendAnnouncement.addEventListener('click', async () => {
  if (!pendingAnnouncement || !database) return;
  confirmSendAnnouncement.disabled = true;
  try {
    const announcementRef = push(ref(database, 'announcements'));
    await set(announcementRef, {
      ...pendingAnnouncement,
      timestamp: Date.now(),
    });
    announcementConfirmation.close();
    announcementForm.reset();
    pendingAnnouncement = null;
    showAnnouncementMessage('Notification sent successfully.');
  } catch (error) {
    announcementConfirmation.close();
    showAnnouncementMessage(`Could not send notification: ${error.message}`, true);
  } finally {
    confirmSendAnnouncement.disabled = false;
  }
});

let sessions = [];
let selectedId = null;
let lastCenteredSignature = null;

function formatTime(value) {
  const timestamp = Number(value);
  if (!Number.isFinite(timestamp) || timestamp <= 0) return 'Not available';

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'medium',
  }).format(new Date(timestamp));
}

function formatRemaining(value) {
  const seconds = Math.max(0, Math.ceil((Number(value) - Date.now()) / 1000));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return hours > 0
    ? `${hours}h ${String(minutes).padStart(2, '0')}m`
    : `${minutes}m ${String(remainder).padStart(2, '0')}s`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character]);
}

function sessionDetailsHtml(session) {
  const emergencyId = session.sessionId || session.id;
  const lastUpdate = session.updatedAt
    ? formatTime(session.updatedAt)
    : 'No location update received yet';

  return `
    <strong>Emergency ${escapeHtml(emergencyId)}</strong><br>
    Status: ${escapeHtml(session.status)}<br>
    Latitude: ${Number(session.latitude).toFixed(6)}<br>
    Longitude: ${Number(session.longitude).toFixed(6)}<br>
    GPS accuracy: ${escapeHtml(session.accuracy ?? 'Not available')} m<br>
    Started: ${escapeHtml(formatTime(session.startedAt))}<br>
    Last location update: ${escapeHtml(lastUpdate)}<br>
    Expires: ${escapeHtml(formatTime(session.expiresAt))}
  `;
}

function selectSession(id, openMarker = false) {
  const session = sessions.find((item) => item.id === id);
  if (!session) return;

  selectedId = id;
  details.hidden = false;
  detailsTitle.textContent = `Emergency ${session.sessionId || session.id}`;

  const lastUpdate = session.updatedAt
    ? formatTime(session.updatedAt)
    : 'No location update received yet';
  const rows = [
    ['Emergency ID', session.sessionId || session.id],
    ['Status', session.status],
    ['Latitude', Number(session.latitude).toFixed(6)],
    ['Longitude', Number(session.longitude).toFixed(6)],
    ['GPS accuracy', `${session.accuracy ?? 'Not available'} m`],
    ['Started time', formatTime(session.startedAt)],
    ['Last location update', lastUpdate],
    ['Expiration time', formatTime(session.expiresAt)],
  ];

  detailsGrid.replaceChildren(
    ...rows.flatMap(([label, value]) => {
      const term = document.createElement('dt');
      term.textContent = label;
      const description = document.createElement('dd');
      description.textContent = value;
      return [term, description];
    }),
  );

  if (openMarker && markers.has(id)) markers.get(id).openPopup();
  renderList();
}

function renderList() {
  emergencyList.replaceChildren();

  if (sessions.length === 0) {
    listCaption.textContent = 'All clear';
    const empty = document.createElement('p');
    empty.className = 'empty-state';
    const title = document.createElement('strong');
    title.textContent = 'No Active Emergencies';
    const description = document.createElement('span');
    description.textContent =
      'There are currently no users requesting emergency assistance.';
    empty.append(title, description);
    emergencyList.append(empty);
    return;
  }

  listCaption.textContent = `${sessions.length} active session${sessions.length === 1 ? '' : 's'}`;
  const cards = sessions.map((session) => {
    const card = document.createElement('article');
    card.className = `emergency-item${selectedId === session.id ? ' selected' : ''}`;

    const title = document.createElement('strong');
    title.className = 'emergency-title';
    title.textContent = 'Emergency Active';
    const identifier = document.createElement('span');
    identifier.textContent = `Session: ${session.userId || session.sessionId || session.id}`;
    const coordinates = document.createElement('span');
    coordinates.textContent = `Location: ${Number(session.latitude).toFixed(6)}, ${Number(session.longitude).toFixed(6)}`;
    const update = document.createElement('span');
    update.textContent = `Last location update: ${session.updatedAt ? formatTime(session.updatedAt) : 'not received yet'}`;
    const remaining = document.createElement('span');
    remaining.className = 'remaining-time';
    remaining.dataset.expiresAt = String(session.expiresAt);
    remaining.textContent = `Time remaining: ${formatRemaining(session.expiresAt)}`;
    const expiry = document.createElement('span');
    expiry.textContent = `Expires: ${formatTime(session.expiresAt)}`;

    const actions = document.createElement('div');
    actions.className = 'emergency-actions';
    const viewButton = document.createElement('button');
    viewButton.type = 'button';
    viewButton.className = 'view-map-button';
    viewButton.textContent = 'View on Map';
    viewButton.addEventListener('click', () => {
      selectSession(session.id, true);
      map.setView([Number(session.latitude), Number(session.longitude)], 16);
    });
    const endButton = document.createElement('button');
    endButton.type = 'button';
    endButton.className = 'end-emergency-button';
    endButton.textContent = 'End Emergency';
    endButton.addEventListener('click', () => endEmergency(session.id, endButton));

    actions.append(viewButton, endButton);
    card.append(title, identifier, coordinates, update, remaining, expiry, actions);
    return card;
  });

  emergencyList.append(...cards);
}

async function endEmergency(id, button) {
  if (!window.confirm('Are you sure you want to end this emergency session?')) {
    return;
  }

  const session = sessions.find((item) => item.id === id);
  if (!session || Number(session.expiresAt) <= Date.now()) {
    renderSessions();
    return;
  }

  button.disabled = true;
  try {
    await update(ref(database, `emergency_sessions/${id}`), {
      status: 'stopped',
      endedAt: Date.now(),
    });
  } catch (error) {
    message.hidden = false;
    message.textContent = `Could not end this emergency: ${error.message}`;
    button.disabled = false;
  }
}

function updateRemainingLabels() {
  document.querySelectorAll('.remaining-time').forEach((element) => {
    element.textContent = `Time remaining: ${formatRemaining(element.dataset.expiresAt)}`;
  });
}

function renderSessions() {
  const now = Date.now();
  sessions = sessions
    .filter((session) =>
      session.status === 'active' &&
      Number.isFinite(Number(session.expiresAt)) &&
      Number(session.expiresAt) > now,
    )
    .sort((a, b) => Number(b.startedAt) - Number(a.startedAt));

  const activeIds = new Set(sessions.map((session) => session.id));
  for (const [id, marker] of markers) {
    if (!activeIds.has(id)) {
      map.removeLayer(marker);
      markers.delete(id);
    }
  }

  for (const session of sessions) {
    const latitude = Number(session.latitude);
    const longitude = Number(session.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) continue;

    const position = [latitude, longitude];
    let marker = markers.get(session.id);
    if (!marker) {
      marker = L.marker(position).addTo(map);
      marker.on('click', () => selectSession(session.id));
      markers.set(session.id, marker);
    } else {
      marker.setLatLng(position);
    }
    marker.bindPopup(sessionDetailsHtml(session));
  }

  activeCount.textContent = String(sessions.length);
  summaryCard.classList.toggle('active', sessions.length > 0);
  summaryCard.classList.toggle('normal', sessions.length === 0);
  dashboardStatus.classList.toggle('active', sessions.length > 0);
  dashboardStatus.classList.toggle('normal', sessions.length === 0);
  dashboardStatus.textContent = sessions.length > 0
    ? 'Emergency assistance is being requested. Review the live location below.'
    : 'No Active Emergencies · The area is currently all clear.';
  renderList();

  if (sessions.length === 1) {
    const onlySession = sessions[0];
    const latitude = Number(onlySession.latitude);
    const longitude = Number(onlySession.longitude);
    const signature = `${onlySession.id}:${latitude}:${longitude}`;
    if (Number.isFinite(latitude) && Number.isFinite(longitude) && signature !== lastCenteredSignature) {
      map.setView([latitude, longitude], Math.max(map.getZoom(), 15), { animate: false });
      lastCenteredSignature = signature;
    }
  } else {
    lastCenteredSignature = null;
  }

  if (selectedId && !activeIds.has(selectedId)) {
    selectedId = null;
    details.hidden = true;
  } else if (selectedId) {
    selectSession(selectedId);
  }
}

document.querySelector('#close-details').addEventListener('click', () => {
  selectedId = null;
  details.hidden = true;
  renderList();
});

function setConnectionState(state) {
  connectionState.classList.remove('live', 'connecting', 'offline');
  connectionState.classList.add(state);
  connectionState.textContent = state === 'live'
    ? 'Live'
    : (state === 'offline' ? 'Offline' : 'Connecting...');
}

try {
  if (firebaseConfigError) throw new Error(firebaseConfigError);
  onValue(ref(database, '.info/connected'), (snapshot) => {
    setConnectionState(snapshot.val() === true ? 'live' : 'offline');
  }, () => setConnectionState('offline'));

  onValue(
    ref(database, 'emergency_sessions'),
    (snapshot) => {
      const value = snapshot.val();
      sessions = value && typeof value === 'object'
        ? Object.entries(value).map(([id, data]) => ({
            id,
            ...(data && typeof data === 'object' ? data : {}),
          }))
        : [];
      message.hidden = true;
      renderSessions();
    },
    (error) => {
      message.hidden = false;
      message.textContent = `Could not read emergency sessions: ${error.message}. Check Realtime Database rules and web app configuration.`;
    },
  );

  onValue(ref(database, 'announcements'), (snapshot) => {
    renderAnnouncements(snapshot.val());
  }, (error) => {
    announcementCaption.textContent = 'Unavailable';
    showAnnouncementMessage(`Could not load recent notifications: ${error.message}`, true);
  });
} catch (error) {
  setConnectionState('offline');
  message.hidden = false;
  message.textContent = error.message;
}

// Re-evaluate expiration and countdowns without rebuilding active cards each second.
window.setInterval(() => {
  if (sessions.some((session) => Number(session.expiresAt) <= Date.now())) {
    renderSessions();
  } else {
    updateRemainingLabels();
  }
}, 1000);
