const fs = require("node:fs");
const path = require("node:path");
const {
  admin,
  initializeAdmin,
} = require("./notification-sender");
const {
  normalizeQuickTunnelUrl,
  publishMlApiUrl,
} = require("./ml-api-config");

const PROJECT_ID = "test1-thesisgrp20";

function readEnvironmentFile(filePath) {
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

async function main() {
  const requestedUrl = process.argv[2];
  if (!requestedUrl) throw new Error("Usage: node functions/publish-ml-api-url.js https://<quick-tunnel-host>");
  const url = normalizeQuickTunnelUrl(requestedUrl);

  const webConfig = readEnvironmentFile(
    path.resolve(__dirname, "../admin_web/.env.local"),
  );
  const databaseURL = process.env.FIREBASE_DATABASE_URL || webConfig.VITE_FIREBASE_DATABASE_URL;
  const projectId = process.env.FIREBASE_PROJECT_ID || webConfig.VITE_FIREBASE_PROJECT_ID;
  if (!databaseURL || projectId !== PROJECT_ID) {
    throw new Error("Firebase project/database configuration is missing or does not match the expected project.");
  }

  initializeAdmin({ databaseURL });
  if (admin.app().options.projectId !== PROJECT_ID) {
    throw new Error("Firebase Admin credentials do not match the expected project.");
  }

  const result = await publishMlApiUrl(url, {
    configRef: admin.database().ref("ml_api/config"),
    sendMessage: (message) => admin.messaging().send(message),
  });

  if (result.notificationSent) {
    console.log(
      `Published verified ML API configuration version ${result.config.version} and sent its FCM update.`,
    );
  } else if (result.notificationPending) {
    console.log(
      `ML API URL version ${result.config.version} is current; another publisher holds the FCM claim, so no second message was sent.`,
    );
  } else {
    console.log(
      `ML API URL version ${result.config.version} is current and its FCM update was already recorded; no message was sent.`,
    );
  }
}

if (require.main === module) {
  main()
    .catch((error) => {
      console.error(`ML API URL publication failed: ${error.message}`);
      process.exitCode = 1;
    })
    .finally(async () => {
      if (admin.apps.length > 0) await admin.app().delete();
    });
}

module.exports = { readEnvironmentFile };
