const {
  initializeAdmin,
  sendTopicNotification,
} = require("./notification-sender");

async function sendTestNotification() {
  try {
    initializeAdmin();
    await sendTopicNotification({
      notification: {
        title: "DETECT_CO ALERT NOTIFICATION",
        body: "FLOOD IS HIGHLY LIKELY",
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
    console.log("Test notification sent successfully!");
  } catch (error) {
    console.error("Could not send test notification:", error.message);
    process.exitCode = 1;
  }
}

sendTestNotification();
