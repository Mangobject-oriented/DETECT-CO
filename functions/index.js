const admin = require("firebase-admin");
const { onValueCreated } = require("firebase-functions/v2/database");
const logger = require("firebase-functions/logger");

admin.initializeApp();

const FCM_TOPIC = "detect_co_announcements";

exports.sendAnnouncementNotification = onValueCreated(
  "/announcements/{announcementId}",
  async (event) => {
    const announcement = event.data.val();
    if (!announcement || typeof announcement !== "object") return;

    const title = String(announcement.title || "").trim();
    const body = String(announcement.message || "").trim();
    const type = announcement.type === "alert" ? "alert" : "announcement";
    if (!title || !body) {
      logger.warn("Skipping incomplete announcement", {
        announcementId: event.params.announcementId,
      });
      return;
    }

    await admin.messaging().send({
      topic: FCM_TOPIC,
      notification: { title, body },
      data: {
        announcementId: event.params.announcementId,
        title,
        body,
        type,
        priority: String(announcement.priority || "normal"),
      },
    });
    logger.info("Announcement notification sent", {
      announcementId: event.params.announcementId,
    });
  },
);
