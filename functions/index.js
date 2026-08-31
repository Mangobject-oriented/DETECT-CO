const Parser = require("rss-parser");
const admin = require("firebase-admin");

const parser = new Parser();

const RSS_URL =
  "https://rss.app/feeds/m1CSSfCzGvUQp26H.xml";

// Firebase service account will come from an environment variable
const serviceAccount = JSON.parse(
  process.env.FIREBASE_SERVICE_ACCOUNT
);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

// FCM topic for all DETECT-CO devices
const FCM_TOPIC = "detect_co_announcements";

async function checkAnnouncements() {
  try {
    console.log("Checking RSS feed...");

    const feed = await parser.parseURL(RSS_URL);

    if (!feed.items || feed.items.length === 0) {
      console.log("No posts found.");
      return;
    }

    const newestPost = feed.items[0];

    const title = newestPost.title || "";
    const content =
      newestPost.contentSnippet ||
      newestPost.content ||
      "";

    const text = `${title} ${content}`.toLowerCase();

    console.log("Newest post:");
    console.log(title);
    console.log(newestPost.link);

    const isSuspension =
      text.includes("walang pasok") ||
      text.includes("no classes") ||
      text.includes("classes are suspended") ||
      text.includes("suspension of classes");

    if (!isSuspension) {
      console.log("No class suspension detected.");
      return;
    }

    console.log("CLASS SUSPENSION DETECTED!");

    await admin.messaging().send({
      topic: FCM_TOPIC,

      notification: {
        title: "⚠️ NO CLASSES",
        body: "Class suspension announcement detected.",
      },

      data: {
        type: "class_suspension",
        link: newestPost.link || "",
      },
    });

    console.log(
      "FCM notification sent successfully to all DETECT-CO devices."
    );

  } catch (error) {
    console.error("ERROR:");
    console.error(error);
    process.exit(1);
  }
}

checkAnnouncements();