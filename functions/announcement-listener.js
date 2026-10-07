const fs = require("fs");
const path = require("path");
const {
  admin,
  initializeAdmin,
  sendTopicNotification,
} = require("./notification-sender");

const PROJECT_ID = "test1-thesisgrp20";
const TOPIC = "detect_co_announcements";
const STATE_PATH = path.join(__dirname, ".announcement-listener-state.json");
const STARTED_AT = Date.now();

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  return Object.fromEntries(
    fs.readFileSync(filePath, "utf8")
      .split(/\r?\n/)
      .map((line) => line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/))
      .filter(Boolean)
      .map((match) => {
        let value = match[2];
        if (
          (value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))
        ) {
          value = value.slice(1, -1);
        }
        return [match[1], value];
      }),
  );
}

function getDatabaseUrl() {
  const env = parseEnvFile(path.resolve(__dirname, "../admin_web/.env.local"));
  const databaseURL = process.env.FIREBASE_DATABASE_URL || env.VITE_FIREBASE_DATABASE_URL;
  const webProject = process.env.FIREBASE_PROJECT_ID || env.VITE_FIREBASE_PROJECT_ID;
  if (!databaseURL) {
    throw new Error(
      "Realtime Database URL is missing. Set FIREBASE_DATABASE_URL or add " +
        "VITE_FIREBASE_DATABASE_URL to admin_web/.env.local.",
    );
  }
  if (webProject && webProject !== PROJECT_ID) {
    throw new Error(`Admin web configuration must point to ${PROJECT_ID}.`);
  }
  return databaseURL;
}

function readSentIds() {
  if (!fs.existsSync(STATE_PATH)) return new Set();
  try {
    const value = JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
    return new Set(Array.isArray(value.sentIds) ? value.sentIds : []);
  } catch {
    throw new Error(
      `Listener state file is invalid: ${STATE_PATH}. Rename or remove it to start with an empty delivery history.`,
    );
  }
}

const sentIds = readSentIds();

function saveSentIds() {
  const recentIds = [...sentIds].slice(-5000);
  const temporaryPath = `${STATE_PATH}.tmp`;
  fs.writeFileSync(temporaryPath, JSON.stringify({ sentIds: recentIds }, null, 2));
  fs.renameSync(temporaryPath, STATE_PATH);
}

async function handleAnnouncement(snapshot) {
  const announcementId = snapshot.key;
  if (!announcementId || sentIds.has(announcementId)) return;

  const announcement = snapshot.val();
  if (!announcement || typeof announcement !== "object") return;

  // child_added emits existing records on startup. The browser writes Unix
  // milliseconds, so only records created after this process started qualify.
  const timestamp = Number(announcement.timestamp);
  if (!Number.isFinite(timestamp) || timestamp < STARTED_AT) return;

  const title = String(announcement.title || "").trim();
  const body = String(announcement.message || "").trim();
  if (!title || !body) {
    console.warn(`Skipping incomplete announcement: ${announcementId}`);
    return;
  }

  console.log(`New announcement detected: ${announcementId}`);
  console.log("Sending FCM notification...");
  try {
    await sendTopicNotification({
      topic: TOPIC,
      notification: { title, body },
      data: {
        announcementId,
        title,
        body,
        type: announcement.type === "alert" ? "alert" : "announcement",
        priority: String(announcement.priority || "normal"),
      },
    });
    sentIds.add(announcementId);
    saveSentIds();
    console.log("Notification sent successfully");
  } catch (error) {
    console.error(`Could not send announcement ${announcementId}: ${error.message}`);
  }
}

async function start() {
  const databaseURL = getDatabaseUrl();
  initializeAdmin({ databaseURL });

  if (admin.app().options.projectId !== PROJECT_ID) {
    throw new Error(`Firebase credentials must belong to ${PROJECT_ID}.`);
  }

  console.log("Announcement listener started");
  console.log("Watching /announcements...");

  const announcementsRef = admin.database().ref("announcements");
  announcementsRef.on(
    "child_added",
    (snapshot) => {
      void handleAnnouncement(snapshot);
    },
    (error) => {
      console.error(`Realtime Database listener error: ${error.message}`);
    },
  );

  const stop = async () => {
    announcementsRef.off();
    await admin.app().delete();
    process.exit(0);
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
}

start().catch((error) => {
  console.error(`Announcement listener could not start: ${error.message}`);
  process.exitCode = 1;
});
