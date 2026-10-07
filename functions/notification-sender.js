const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const serviceAccountPath = path.resolve(
  __dirname,
  "../checker/serviceAccountKey.json",
);

function initializeAdmin({ databaseURL } = {}) {
  if (!fs.existsSync(serviceAccountPath)) {
    throw new Error(
      `Firebase credentials are missing: ${serviceAccountPath}. ` +
        "Place the existing serviceAccountKey.json there; it is ignored by Git.",
    );
  }

  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
  if (serviceAccount.project_id !== "test1-thesisgrp20") {
    throw new Error(
      "The service account must belong to the Firebase project test1-thesisgrp20.",
    );
  }

  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: "test1-thesisgrp20",
      ...(databaseURL ? { databaseURL } : {}),
    });
  }
  return admin;
}

async function sendTopicNotification({
  topic = "detect_co_announcements",
  notification,
  android,
  data = {},
}) {
  const fcmData = Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, String(value)]),
  );
  return admin.messaging().send({
    topic,
    notification,
    ...(android ? { android } : {}),
    data: fcmData,
  });
}

module.exports = { admin, initializeAdmin, sendTopicNotification };
