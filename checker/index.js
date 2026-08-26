const Parser = require("rss-parser");
const { initializeApp, cert } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const fs = require("fs");

const serviceAccount = require("./serviceAccountKey.json");

initializeApp({
  credential: cert(serviceAccount),
});

const parser = new Parser();

const RSS_URL =
  "https://rss.app/feeds/m1CSSfCzGvUQp26H.xml";

const FCM_TOKEN =
  "dlJfYq8-TiOw0vFzJTDSvI:APA91bFrwx8EC6LD6kkIAArWva68IVUxqlvsMIl6PSqOCw6NA8Rg190bbEBHoX5WpZhCf6hZxh8XouZGT427GuZZaJqRBhSCxLwnLOq80FqGWJqC-9z3Ub4";

const STATE_FILE = "./lastPost.json";

// =====================================================
// LOAD LAST NOTIFIED POST
// =====================================================

function getLastPost() {
  try {
    if (!fs.existsSync(STATE_FILE)) {
      return null;
    }

    const data = fs.readFileSync(STATE_FILE, "utf8");
    return JSON.parse(data);
  } catch (error) {
    console.log("Could not read previous post.");
    return null;
  }
}

// =====================================================
// SAVE LAST NOTIFIED POST
// =====================================================

function saveLastPost(post) {
  fs.writeFileSync(
    STATE_FILE,
    JSON.stringify(post, null, 2)
  );
}

// =====================================================
// CHECK ANNOUNCEMENTS
// =====================================================

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

    const postId =
      newestPost.guid ||
      newestPost.id ||
      newestPost.link ||
      `${title}-${newestPost.pubDate || ""}`;

    console.log("\nNewest post:");
    console.log(title);
    console.log(newestPost.link);

    // =====================================================
    // CHECK IF THIS POST WAS ALREADY NOTIFIED
    // =====================================================

    const lastPost = getLastPost();

    if (lastPost && lastPost.id === postId) {
      console.log("\nThis post was already processed.");
      console.log("No duplicate notification will be sent.");
      return;
    }

    // =====================================================
    // CHECK FOR CLASS SUSPENSION
    // =====================================================

    const isSuspension =
      text.includes("walang pasok") ||
      text.includes("no classes") ||
      text.includes("classes are suspended") ||
      text.includes("suspension of classes");

    if (!isSuspension) {
      console.log("\nNo class suspension detected.");

      // Remember the newest post so we don't repeatedly
      // process the same post later.
      saveLastPost({
        id: postId,
        title: title,
        link: newestPost.link || "",
      });

      return;
    }

    console.log("\nCLASS SUSPENSION DETECTED!");

    // =====================================================
    // SEND FCM NOTIFICATION
    // =====================================================

    const messaging = getMessaging();

    await messaging.send({
      token: FCM_TOKEN,

      notification: {
        title: "⚠️ NO CLASSES",
        body: "Class suspension announcement detected.",
      },

      data: {
        type: "class_suspension",
        link: newestPost.link || "",
      },
    });

    console.log("\nFCM notification sent successfully!");

    // =====================================================
    // REMEMBER THAT WE SENT THIS NOTIFICATION
    // =====================================================

    saveLastPost({
      id: postId,
      title: title,
      link: newestPost.link || "",
    });

    console.log("Post saved as processed.");

  } catch (error) {
    console.error("\nERROR:");
    console.error(error);
    process.exit(1);
  }
}

checkAnnouncements();