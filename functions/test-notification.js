const admin = require("firebase-admin");

const serviceAccount = require(
  "../checker/serviceAccountKey.json"
);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

async function sendTestNotification() {
  try {
    await admin.messaging().send({
      topic: "detect_co_announcements",

      notification: {
        title: "DETECT-CO ANNOUNCEMENT",
        body: "kurt papwet",
      },

      android: {
        notification: {
          channelId: "test_alerts",
          sound: "test_alert",
        },
      },

      data: {
        type: "alert",
        message: "Manual notification test",
      },
    });

    console.log(
      "Test notification sent successfully!"
    );
  } catch (error) {
    console.error("ERROR:");
    console.error(error);
  }
}

sendTestNotification();