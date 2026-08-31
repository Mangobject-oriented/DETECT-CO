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
        title: "Mj kay peter ",
        body: "I don't love you",
      },

      android: {
        notification: {
          channelId: "test_alerts",
          sound: "test_alert",
        },
      },

      data: {
        type: "test",
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