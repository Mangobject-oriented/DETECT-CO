import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';
import mapPlaces from '../../assets/data/map_places.json';
import { onValue, push, ref, remove, set, update } from 'firebase/database';
import { onAuthStateChanged, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import { auth, database, firebaseConfigError } from './firebase.js';
import './styles.css';

L.Icon.Default.mergeOptions({
  iconUrl: markerIcon,
  iconRetinaUrl: markerIcon2x,
  shadowUrl: markerShadow,
});

// Start near the middle of the existing Calamba coverage area.
// Emergency markers can still recenter the map anywhere afterward.
const map = L.map('map', { trackResize: true }).setView([14.188421, 121.108354], 12);
const osmTiles = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19,
  attribution:
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
}).addTo(map);

const markers = new Map();
const centerMarkers = new Map();
const routeToggle = document.querySelector('#route-toggle');
const centersToggle = document.querySelector('#centers-toggle');
const routeStatus = document.querySelector('#route-status');
const rescueLocationButton = document.querySelector('#rescue-location-button');
const rescueMarker = L.marker([14.211, 121.165], { icon: makeMapMarkerIcon('rescue', 'Rescue location') });
let rescueLocation = null;
let routeLayer = null;
let routeDistance = null;
let lastRouteTarget = null;
let lastRoutedSessionId = null;
let routeRequestAt = 0;
let routeGeneration = 0;
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
const emergencyPage = document.querySelector('#emergency-page');
const notificationsPage = document.querySelector('#notifications-page');
const mlMonitoringPage = document.querySelector('#ml-monitoring-page');
const pageTitle = document.querySelector('#page-title');
const pageNavigationButtons = document.querySelectorAll('[data-page]');
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
const clearHistoryButton = document.querySelector('#clear-history-button');
const clearHistoryConfirmation = document.querySelector('#clear-history-confirmation');
const confirmClearHistoryButton = document.querySelector('#confirm-clear-history');
let pendingAnnouncement = null;
osmTiles.on('tileerror', (event) => {
  // Leaflet keeps rendering other tiles; this only surfaces the failed URL
  // for browser diagnostics and does not remove or replace the base layer.
  console.warn('OpenStreetMap tile failed to load:', event.tile?.src || 'unknown tile');
});
const loginScreen = document.querySelector('#login-screen');
const loginForm = document.querySelector('#login-form');
const loginEmail = document.querySelector('#login-email');
const loginPassword = document.querySelector('#login-password');
const loginError = document.querySelector('#login-error');
const loginSubmit = document.querySelector('#login-submit');
const togglePassword = document.querySelector('#toggle-password');
const logoutButton = document.querySelector('#logout-button');
const adminIdentity = document.querySelector('#admin-identity');
let databaseUnsubscribers = [];
let authenticatedUiReady = false;
let expirationInterval = null;
let mlRefreshInterval = null;
let mlRiskMap = null;
let mlRiskMarker = null;
let mlFloodDistanceCm = null;
let latestMlPrediction = null;
let mlRefreshInFlight = false;

const mlLocation = { latitude: 14.15, longitude: 121.05, label: 'Calamba model location' };
const mlApiBase = (import.meta.env.VITE_ML_API_URL || 'http://192.168.18.14:8000').replace(/\/+$/, '');
const mlHorizons = [1, 3, 6, 12, 24];

togglePassword.addEventListener('click', () => {
  const showing = loginPassword.type === 'password';
  loginPassword.type = showing ? 'text' : 'password';
  togglePassword.textContent = showing ? 'Hide' : 'Show';
  togglePassword.setAttribute('aria-label', showing ? 'Hide password' : 'Show password');
  togglePassword.setAttribute('aria-pressed', String(showing));
});

loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!auth) return;
  loginSubmit.disabled = true;
  loginSubmit.textContent = 'Signing in…';
  loginError.hidden = true;
  try {
    await signInWithEmailAndPassword(auth, loginEmail.value.trim(), loginPassword.value);
    loginPassword.value = '';
  } catch (_) {
    loginError.textContent = 'Could not sign in. Check your email and password, then try again.';
    loginError.hidden = false;
  } finally {
    loginSubmit.disabled = false;
    loginSubmit.textContent = 'Log In';
  }
});

logoutButton.addEventListener('click', async () => {
  logoutButton.disabled = true;
  try {
    await signOut(auth);
  } catch (_) {
    message.hidden = false;
    message.textContent = 'Could not sign out. Please try again.';
  } finally {
    logoutButton.disabled = false;
  }
});

function showAuthenticatedUser(user) {
  document.querySelector('#app').hidden = !user;
  loginScreen.hidden = Boolean(user);
  adminIdentity.textContent = user ? (user.email || 'Admin') : '';
  if (!user) {
    stopAuthenticatedListeners();
  } else {
    if (!authenticatedUiReady) {
      authenticatedUiReady = true;
      startAuthenticatedListeners();
      expirationInterval = window.setInterval(() => {
        if (sessions.some((session) => Number(session.expiresAt) <= Date.now())) renderSessions();
        else updateRemainingLabels();
      }, 1000);
      mlRefreshInterval = window.setInterval(() => {
        if (!mlMonitoringPage.hidden) refreshMlMonitoring();
      }, 5 * 60 * 1000);
    }
    // The map is created while #app is hidden on the login screen.
    // Wait for the dashboard layout to become measurable before asking
    // Leaflet to lay out the base tiles and existing map layers again.
    invalidateMapAfterReveal();
  }
}

function invalidateMapAfterReveal() {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      map.invalidateSize({ pan: false });
    });
  });
}

function updatePriorityAppearance() {
  announcementPriority.dataset.priority = announcementPriority.value;
}

announcementPriority.addEventListener('change', updatePriorityAppearance);
updatePriorityAppearance();

function showPage(page) {
  const showEmergency = page === 'emergency';
  const showMl = page === 'ml-monitoring';
  emergencyPage.hidden = !showEmergency;
  notificationsPage.hidden = showEmergency || showMl;
  mlMonitoringPage.hidden = !showMl;
  pageTitle.textContent = showEmergency ? 'Emergency Map' : (showMl ? 'ML Monitoring' : 'Notifications');

  pageNavigationButtons.forEach((button) => {
    const selected = button.dataset.page === page;
    button.classList.toggle('selected', selected);
    if (selected) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });

  if (showEmergency) {
    invalidateMapAfterReveal();
  }
  if (showMl) {
    ensureMlRiskMap();
    requestAnimationFrame(() => mlRiskMap?.invalidateSize({ pan: false }));
    refreshMlMonitoring({ refreshPrediction: true });
  }
}

pageNavigationButtons.forEach((button) => {
  button.addEventListener('click', () => showPage(button.dataset.page));
});

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
    message: 'Please proceed to your designated evacuation area and follow local safety advisories.',
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
    updatePriorityAppearance();
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
    updatePriorityAppearance();
    pendingAnnouncement = null;
    showAnnouncementMessage('Notification sent successfully.');
  } catch (error) {
    announcementConfirmation.close();
    showAnnouncementMessage(`Could not send notification: ${error.message}`, true);
  } finally {
    confirmSendAnnouncement.disabled = false;
  }
});

clearHistoryButton.addEventListener('click', () => {
  if (!database) {
    showAnnouncementMessage('Cannot clear history while Firebase is unavailable.', true);
    return;
  }
  clearHistoryConfirmation.showModal();
});

document.querySelector('#cancel-clear-history').addEventListener('click', () => {
  clearHistoryConfirmation.close();
});

confirmClearHistoryButton.addEventListener('click', async () => {
  if (!database) return;
  confirmClearHistoryButton.disabled = true;
  try {
    await remove(ref(database, 'announcements'));
    renderAnnouncements(null);
    clearHistoryConfirmation.close();
    showAnnouncementMessage('Announcement history cleared.');
  } catch (error) {
    clearHistoryConfirmation.close();
    showAnnouncementMessage(`Could not clear history: ${error.message}`, true);
  } finally {
    confirmClearHistoryButton.disabled = false;
  }
});

let sessions = [];
let selectedId = null;
let lastCenteredSignature = null;

function makeMapMarkerIcon(kind, label) {
  return L.divIcon({ className: `map-marker ${kind}-marker`, html: `<span aria-label="${label}" title="${label}"></span>`, iconSize: [34, 42], iconAnchor: [17, 38], popupAnchor: [0, -34] });
}

function renderCenters() {
  for (const place of mapPlaces.filter((item) => item.type === 'evacuation')) {
    const key = place.name;
    if (!centerMarkers.has(key)) {
      const marker = L.marker([place.latitude, place.longitude], { icon: makeMapMarkerIcon('center', 'Evacuation center') })
        .bindPopup(`<strong>${escapeHtml(place.name)}</strong><br>${escapeHtml(place.description || '')}`);
      centerMarkers.set(key, marker);
    }
    const marker = centerMarkers.get(key);
    if (centersToggle.checked && !map.hasLayer(marker)) marker.addTo(map);
    if (!centersToggle.checked && map.hasLayer(marker)) map.removeLayer(marker);
  }
  sessionStorage.setItem('detectco-centers-visible', String(centersToggle.checked));
}

function clearRescueRoute(text = 'Rescue route is off.') {
  routeGeneration++;
  if (routeLayer) map.removeLayer(routeLayer);
  routeLayer = null;
  routeDistance = null;
  lastRoutedSessionId = null;
  routeStatus.textContent = text;
}

function getRescueLocation() {
  if (rescueLocation) return Promise.resolve(rescueLocation);
  if (!navigator.geolocation) return Promise.reject(new Error('Browser location is unavailable.'));
  routeStatus.textContent = 'Getting rescue location…';
  return new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition((position) => {
    rescueLocation = [position.coords.latitude, position.coords.longitude];
    rescueMarker.setLatLng(rescueLocation).addTo(map);
    rescueLocationButton.textContent = 'Update Rescue Location';
    resolve(rescueLocation);
  }, () => reject(new Error('Rescue location unavailable. Allow browser location access and try again.')), { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 }));
}

async function updateRescueRoute(force = false) {
  const session = sessions.find((item) => item.id === selectedId);
  if (!routeToggle.checked || !session) return;
  const destination = [Number(session.latitude), Number(session.longitude)];
  if (!destination.every(Number.isFinite)) { routeStatus.textContent = 'Selected user has no valid location.'; return; }
  if (!force && lastRoutedSessionId === session.id && lastRouteTarget && L.latLng(lastRouteTarget).distanceTo(destination) < 60) return;
  const wait = Math.max(0, 4000 - (Date.now() - routeRequestAt));
  if (wait) await new Promise((resolve) => window.setTimeout(resolve, wait));
  if (!routeToggle.checked || selectedId !== session.id) return;
  routeRequestAt = Date.now();
  const generation = ++routeGeneration;
  try {
    const start = await getRescueLocation();
    const url = `https://router.project-osrm.org/route/v1/driving/${start[1]},${start[0]};${destination[1]},${destination[0]}?overview=full&geometries=geojson`;
    const response = await fetch(url, { signal: AbortSignal.timeout(12000) });
    if (!response.ok) throw new Error('Routing service is unavailable.');
    const data = await response.json();
    const route = data.routes?.[0];
    if (!route) throw new Error('No route is available for these locations.');
    if (generation !== routeGeneration || !routeToggle.checked) return;
    if (routeLayer) map.removeLayer(routeLayer);
    routeLayer = L.geoJSON(route.geometry, { style: { color: '#42a5f5', weight: 6, opacity: 0.9, dashArray: '10 7' } }).addTo(map);
    lastRouteTarget = destination;
    lastRoutedSessionId = session.id;
    const km = route.distance / 1000;
    const minutes = Math.round(route.duration / 60);
    routeDistance = `Distance: ${km < 10 ? km.toFixed(1) : Math.round(km)} km · ETA: ${minutes} min`;
    routeStatus.textContent = routeDistance;
    map.fitBounds(routeLayer.getBounds(), { padding: [35, 35], maxZoom: 16 });
  } catch (error) {
    if (generation === routeGeneration) routeStatus.textContent = error.message || 'Could not calculate the rescue route.';
  }
}

centersToggle.checked = sessionStorage.getItem('detectco-centers-visible') !== 'false';
centersToggle.addEventListener('change', renderCenters);
routeToggle.addEventListener('change', () => {
  if (routeToggle.checked) {
    if (!selectedId) { routeToggle.checked = false; routeStatus.textContent = 'Select an emergency user first.'; return; }
    updateRescueRoute();
  } else clearRescueRoute();
});
rescueLocationButton.addEventListener('click', () => {
  rescueLocation = null;
  getRescueLocation().then(() => updateRescueRoute(true)).catch((error) => { routeStatus.textContent = error.message; });
});
renderCenters();

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
  routeToggle.disabled = false;
  routeStatus.textContent = routeToggle.checked ? 'Updating rescue route…' : 'Selected user is the route destination.';
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
  if (routeToggle.checked) {
    updateRescueRoute();
  }
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
      marker = L.marker(position, { icon: makeMapMarkerIcon('emergency', 'Emergency user location') }).addTo(map);
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
    routeToggle.disabled = true;
    routeToggle.checked = false;
    clearRescueRoute('Selected emergency session ended.');
  } else if (selectedId) {
    const selected = sessions.find((item) => item.id === selectedId);
    const nextTarget = selected ? [Number(selected.latitude), Number(selected.longitude)] : null;
    const changed = nextTarget && (!lastRouteTarget || L.latLng(lastRouteTarget).distanceTo(nextTarget) >= 60);
    selectSession(selectedId);
    if (routeToggle.checked && changed) updateRescueRoute();
  } else {
    routeToggle.disabled = true;
  }
}

document.querySelector('#close-details').addEventListener('click', () => {
  selectedId = null;
  details.hidden = true;
  routeToggle.disabled = true;
  routeToggle.checked = false;
  clearRescueRoute('Select an emergency to route.');
  renderList();
});

function setConnectionState(state) {
  connectionState.classList.remove('live', 'connecting', 'offline');
  connectionState.classList.add(state);
  connectionState.textContent = state === 'live'
    ? 'Live'
    : (state === 'offline' ? 'Offline' : 'Connecting...');
}

function readMlNumber(value) {
  if (value == null || value === '') return null;
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
}

function mlPredictions(result) {
  const data = result?.predictions || {};
  return Object.fromEntries(mlHorizons.map((hour) => [
    hour,
    readMlNumber(data[`rainfall_${hour}h_mm`]),
  ]));
}

function formatMl(value, suffix = 'mm') {
  return value == null ? 'Unavailable' : `${value.toFixed(1)} ${suffix}`;
}

function ensureMlRiskMap() {
  if (mlRiskMap) return;
  const element = document.querySelector('#ml-risk-map');
  if (!element) return;
  mlRiskMap = L.map(element, { zoomControl: false, scrollWheelZoom: false }).setView(
    [mlLocation.latitude, mlLocation.longitude],
    12,
  );
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 18,
    attribution: '&copy; OpenStreetMap contributors',
  }).addTo(mlRiskMap);
  mlRiskMarker = L.circleMarker([mlLocation.latitude, mlLocation.longitude], {
    radius: 10,
    color: '#5cdb6e',
    fillColor: '#5cdb6e',
    fillOpacity: 0.85,
    weight: 2,
  }).addTo(mlRiskMap);
  mlRiskMarker.bindPopup(mlLocation.label);
}

function renderMlRisk() {
  const rise = mlFloodDistanceCm == null
    ? null
    : Math.max(0, 150 - mlFloodDistanceCm);
  let level = 'Unavailable';
  let levelClass = 'risk-unavailable';
  let color = '#a5abb3';
  if (rise != null) {
    if (rise <= 4) {
      level = 'LOW · NORMAL'; levelClass = 'risk-low'; color = '#5cdb6e';
    } else if (rise <= 40) {
      level = 'MODERATE · WARNING'; levelClass = 'risk-moderate'; color = '#ff9a3c';
    } else {
      level = 'HIGH · CRITICAL'; levelClass = 'risk-high'; color = '#ff4b4b';
    }
  }
  const value = document.querySelector('#ml-risk-value');
  value.textContent = level;
  value.className = levelClass;
  document.querySelector('#ml-risk-detail').textContent = rise == null
    ? 'Sensor reading unavailable'
    : 'Based on measured sensor water rise';
  document.querySelector('#ml-water-rise').textContent = formatMl(rise, 'cm');
  document.querySelector('#ml-current-rain').textContent = formatMl(
    readMlNumber(latestMlPrediction?.current_rainfall_mm),
  );
  if (mlRiskMarker) {
    mlRiskMarker.setStyle({ color, fillColor: color });
    const popup = document.createElement('div');
    const title = document.createElement('strong');
    title.textContent = mlLocation.label;
    const status = document.createElement('p');
    status.textContent = `Sensor-backed flood status: ${level}`;
    const riseText = document.createElement('p');
    riseText.textContent = `Current water rise: ${formatMl(rise, 'cm')}`;
    const rainText = document.createElement('p');
    rainText.textContent = `Current rainfall: ${formatMl(readMlNumber(latestMlPrediction?.current_rainfall_mm))}`;
    popup.append(title, status, riseText, rainText);
    mlRiskMarker.bindPopup(popup);
  }
}

function renderMlChart(predictions) {
  const host = document.querySelector('#ml-forecast-chart');
  const valid = mlHorizons
    .map((hour) => ({ hour, value: predictions[hour] }))
    .filter((point) => point.value != null);
  host.replaceChildren();
  if (!valid.length) {
    const empty = document.createElement('p');
    empty.className = 'ml-muted';
    empty.textContent = 'Chart unavailable until real predictions arrive.';
    host.append(empty);
    return;
  }

  const width = 520; const height = 190;
  const left = 38; const right = 14; const top = 18; const bottom = 35;
  const maxValue = Math.max(1, ...valid.map((point) => point.value));
  const plotHeight = height - top - bottom;
  const plotWidth = width - left - right;
  const points = valid.map((point, index) => ({
    ...point,
    x: left + (valid.length === 1 ? plotWidth / 2 : index * plotWidth / (valid.length - 1)),
    y: top + plotHeight - point.value / maxValue * plotHeight,
  }));
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
  svg.setAttribute('role', 'img');
  svg.setAttribute('aria-label', 'Predicted rainfall accumulation by forecast period');
  for (let index = 0; index < 4; index++) {
    const y = top + index * plotHeight / 3;
    const grid = document.createElementNS(svg.namespaceURI, 'line');
    grid.setAttribute('x1', String(left)); grid.setAttribute('x2', String(width - right));
    grid.setAttribute('y1', String(y)); grid.setAttribute('y2', String(y));
    grid.setAttribute('class', 'ml-chart-grid'); svg.append(grid);
    const tick = document.createElementNS(svg.namespaceURI, 'text');
    tick.setAttribute('x', String(left - 6)); tick.setAttribute('y', String(y + 4));
    tick.setAttribute('text-anchor', 'end'); tick.setAttribute('class', 'ml-chart-label');
    tick.textContent = `${(maxValue * (3 - index) / 3).toFixed(1)}`;
    svg.append(tick);
  }
  const line = document.createElementNS(svg.namespaceURI, 'polyline');
  line.setAttribute('points', points.map((point) => `${point.x},${point.y}`).join(' '));
  line.setAttribute('class', 'ml-chart-line'); svg.append(line);
  for (const point of points) {
    const dot = document.createElementNS(svg.namespaceURI, 'circle');
    dot.setAttribute('cx', String(point.x)); dot.setAttribute('cy', String(point.y)); dot.setAttribute('r', '5');
    dot.setAttribute('class', 'ml-chart-dot');
    dot.append(document.createElementNS(svg.namespaceURI, 'title'));
    dot.firstChild.textContent = `${point.hour}h: ${point.value.toFixed(1)} mm`;
    svg.append(dot);
    const label = document.createElementNS(svg.namespaceURI, 'text');
    label.setAttribute('x', String(point.x)); label.setAttribute('y', String(height - 10));
    label.setAttribute('text-anchor', 'middle'); label.setAttribute('class', 'ml-chart-label');
    label.textContent = `${point.hour}h`; svg.append(label);
  }
  host.append(svg);
}

function renderMlForecast(result) {
  const predictions = mlPredictions(result);
  const values = document.querySelector('#ml-forecast-values');
  values.replaceChildren();
  for (const hour of mlHorizons) {
    const card = document.createElement('div');
    card.className = 'ml-forecast-value';
    const label = document.createElement('span'); label.textContent = `${hour}h`;
    const number = document.createElement('strong'); number.textContent = formatMl(predictions[hour]);
    card.append(label, number); values.append(card);
  }
  renderMlChart(predictions);
  latestMlPrediction = result;
  const timestamp = result?.generated_at ? new Date(result.generated_at) : null;
  document.querySelector('#ml-last-prediction').textContent = timestamp && !Number.isNaN(timestamp.getTime())
    ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(timestamp)
    : 'Unavailable';
  document.querySelector('#ml-location-label').textContent = `${mlLocation.label} · 14.15, 121.05`;
  const states = result?.model_status || {};
  const weights = result?.ensemble_weights || {};
  const statusHost = document.querySelector('#ml-model-status');
  statusHost.replaceChildren();
  for (const model of ['lstm', 'xgboost', 'random_forest']) {
    const row = document.createElement('div'); row.className = 'ml-model-row';
    const name = document.createElement('strong'); name.textContent = model === 'random_forest' ? 'Random Forest' : model.toUpperCase();
    const state = document.createElement('span');
    const online = states[model] === 'online';
    const weight = readMlNumber(weights[model]);
    state.textContent = `${online ? 'ONLINE' : 'UNAVAILABLE'} · ensemble weight ${weight == null ? '—' : `${(weight * 100).toFixed(0)}%`}`;
    if (!online) state.classList.add('risk-unavailable');
    row.append(name, state); statusHost.append(row);
  }
  document.querySelector('#ml-connection-state').textContent = result?.history_recorded === false
    ? 'Forecast live · history unavailable'
    : 'Forecast live';
  document.querySelector('#ml-connection-state').className = 'ml-state live';
  document.querySelector('#ml-message').hidden = true;
  renderMlRisk();
}

function renderMlEvaluation(data) {
  const tbody = document.querySelector('#ml-evaluation-rows');
  tbody.replaceChildren();
  const latest = data?.latest;
  const predictions = mlPredictions(latest);
  const metrics = data?.metrics || {};
  for (const hour of mlHorizons) {
    const history = data?.history?.[String(hour)] || [];
    const completed = history.find((sample) => readMlNumber(sample.actual_mm) != null);
    const actual = completed ? readMlNumber(completed.actual_mm) : null;
    const predicted = completed ? readMlNumber(completed.predicted_mm) : predictions[hour];
    const error = actual != null && predicted != null ? Math.abs(predicted - actual) : null;
    const metric = metrics[String(hour)] || {};
    const values = [
      `${hour}h`, formatMl(predicted), formatMl(actual), formatMl(error),
      formatMl(readMlNumber(metric.mae_mm)), formatMl(readMlNumber(metric.rmse_mm)),
      metric.mean_error_percent == null ? '—' : `${Number(metric.mean_error_percent).toFixed(1)}%`,
      String(metric.count || 0),
    ];
    const row = document.createElement('tr');
    for (const value of values) { const cell = document.createElement('td'); cell.textContent = value; row.append(cell); }
    tbody.append(row);
  }
}

async function refreshMlMonitoring({ refreshPrediction = false } = {}) {
  if (!auth?.currentUser || mlRefreshInFlight) return;
  mlRefreshInFlight = true;
  const button = document.querySelector('#ml-refresh-button');
  button.disabled = true;
  document.querySelector('#ml-connection-state').textContent = 'Refreshing…';
  try {
    const requestPrediction = async () => {
      const response = await fetch(`${mlApiBase}/predict`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ latitude: mlLocation.latitude, longitude: mlLocation.longitude }),
        signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) throw new Error(`ML API returned ${response.status}.`);
      return response.json();
    };
    let prediction = refreshPrediction ? await requestPrediction() : null;
    let monitoring = { latest: null, history: {}, metrics: {} };
    let historyUnavailable = false;
    const readMonitoring = async () => {
      const response = await fetch(
        `${mlApiBase}/monitoring?latitude=${mlLocation.latitude}&longitude=${mlLocation.longitude}`,
        { signal: AbortSignal.timeout(15000) },
      );
      if (!response.ok) throw new Error(`Monitoring history returned ${response.status}.`);
      return response.json();
    };
    try {
      monitoring = await readMonitoring();
    } catch (error) {
      if (!prediction) throw error;
      historyUnavailable = true;
    }
    if (!prediction) prediction = monitoring.latest;
    if (!prediction) {
      prediction = await requestPrediction();
      try {
        monitoring = await readMonitoring();
      } catch (_) {
        historyUnavailable = true;
      }
    }
    if (prediction) renderMlForecast(prediction);
    if (!monitoring.latest && prediction) monitoring.latest = prediction;
    renderMlEvaluation(monitoring);
    if (historyUnavailable) {
      document.querySelector('#ml-connection-state').textContent = 'Forecast live · history unavailable';
      document.querySelector('#ml-connection-state').className = 'ml-state unavailable';
      document.querySelector('#ml-message').textContent = 'Live predictions are available, but prediction history could not be read. Check SQLite storage and the monitoring endpoint.';
      document.querySelector('#ml-message').hidden = false;
    }
  } catch (error) {
    document.querySelector('#ml-connection-state').textContent = 'ML service unavailable';
    document.querySelector('#ml-connection-state').className = 'ml-state unavailable';
    const notice = document.querySelector('#ml-message');
    notice.textContent = error.name === 'TimeoutError'
      ? 'The ML service did not respond in time. Check the configured API URL and server status.'
      : 'Could not retrieve ML monitoring data. Check the configured API URL, CORS origins, and server status.';
    notice.hidden = false;
    renderMlRisk();
  } finally {
    mlRefreshInFlight = false;
    button.disabled = false;
  }
}

document.querySelector('#ml-refresh-button').addEventListener('click', () =>
  refreshMlMonitoring({ refreshPrediction: true }),
);

function updateMlFloodReading(value) {
  let raw = value;
  let sensorOnline = true;
  if (value && typeof value === 'object') {
    raw = value.distance;
    let timestamp = Number(value.timestamp);
    if (!Number.isFinite(timestamp)) {
      sensorOnline = false;
    } else {
      if (timestamp < 100000000000) timestamp *= 1000;
      const age = Date.now() - timestamp;
      sensorOnline = age >= 0 && age <= 30000;
    }
  }
  const distance = readMlNumber(raw);
  // ESP32 publishes centimeters, as confirmed by its distance formula and UI.
  mlFloodDistanceCm = sensorOnline && distance != null && distance < 200
    ? distance
    : null;
  renderMlRisk();
}

function startAuthenticatedListeners() {
  if (!database) {
    message.hidden = false;
    message.textContent = 'Firebase is not configured for this admin website.';
    return;
  }
  databaseUnsubscribers.push(onValue(ref(database, '.info/connected'), (snapshot) => {
    setConnectionState(snapshot.val() === true ? 'live' : 'offline');
  }, () => setConnectionState('offline')));

  databaseUnsubscribers.push(onValue(
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
  ));

  databaseUnsubscribers.push(onValue(ref(database, 'announcements'), (snapshot) => {
    renderAnnouncements(snapshot.val());
  }, (error) => {
    announcementCaption.textContent = 'Unavailable';
    showAnnouncementMessage(`Could not load recent notifications: ${error.message}`, true);
  }));

  databaseUnsubscribers.push(onValue(ref(database, 'flood'), (snapshot) => {
    updateMlFloodReading(snapshot.val());
  }, () => {
    mlFloodDistanceCm = null;
    renderMlRisk();
  }));
}

function stopAuthenticatedListeners() {
  databaseUnsubscribers.forEach((unsubscribe) => unsubscribe());
  databaseUnsubscribers = [];
  authenticatedUiReady = false;
  if (expirationInterval != null) window.clearInterval(expirationInterval);
  expirationInterval = null;
  if (mlRefreshInterval != null) window.clearInterval(mlRefreshInterval);
  mlRefreshInterval = null;
  mlFloodDistanceCm = null;
  latestMlPrediction = null;
  document.querySelector('#ml-evaluation-rows').replaceChildren();
  document.querySelector('#ml-forecast-values').replaceChildren();
  document.querySelector('#ml-forecast-chart').replaceChildren();
  for (const marker of markers.values()) map.removeLayer(marker);
  markers.clear();
  sessions = [];
  selectedId = null;
  details.hidden = true;
  renderSessions();
  clearRescueRoute('Select an emergency to route.');
  if (map.hasLayer(rescueMarker)) map.removeLayer(rescueMarker);
  rescueLocation = null;
  setConnectionState('connecting');
}

if (!auth || firebaseConfigError) {
  loginError.textContent = 'Admin sign-in is unavailable because Firebase is not configured.';
  loginError.hidden = false;
} else {
  onAuthStateChanged(auth, showAuthenticatedUser, () => {
    loginError.textContent = 'Could not check your sign-in session. Refresh and try again.';
    loginError.hidden = false;
  });
}
