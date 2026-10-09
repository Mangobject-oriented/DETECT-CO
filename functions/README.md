# Local DETECT-CO announcement listener

The admin website writes announcements to Realtime Database. This local Node.js
process watches `/announcements` and sends new entries to the existing
`detect_co_announcements` FCM topic with the Firebase Admin SDK. It uses no
Cloud Functions and does not require Blaze billing. The computer running the
listener must stay online for announcement pushes to be sent.

## Setup

1. Install the packages from this directory once:

   ```sh
   cd functions
   npm install
   cd ..
   ```

2. Put the service account JSON for project `test1-thesisgrp20` at
   `checker/serviceAccountKey.json`. This is the same ignored local credential
   used by the existing manual notification script. Do not commit it.
3. Ensure `admin_web/.env.local` contains the existing web config values
   `VITE_FIREBASE_PROJECT_ID=test1-thesisgrp20` and
   `VITE_FIREBASE_DATABASE_URL=...` for that project's Realtime Database.

The listener reads only the database URL from that browser config file; it
reads credentials only from the local service account JSON. It validates the
service account project without printing credential contents. The announcement
delivery state is stored in the Git-ignored
`functions/.announcement-listener-state.json` file.

## Run and test

From the repository root, start the listener:

```sh
node functions/announcement-listener.js
```

Or from `functions/`, use `npm run announcement-listener`. Start the admin site
in a separate terminal with `cd admin_web && npm run dev`, create an
announcement, and confirm the listener logs its ID and successful FCM send.
The Flutter app must have notification permission and be subscribed to
`detect_co_announcements`. The existing Flutter FCM handlers store the received
announcement through `NotificationStorage` and update the unread count.

To run the existing manual push test from the repository root:

```sh
node functions/test-notification.js
```

Or from `functions/`, use `npm run test-notification`. This sends the existing
manual test notification to the same topic.

The listener skips records whose timestamp predates its start time and records
successfully sent IDs locally. Restarting it does not replay old announcements.
Do not delete the ignored state file during normal restarts; remove it only if
you intentionally want to reset the listener's local delivery history.

## Automatic ML Quick Tunnel URL updates

The laptop's `~/DETECT-CO-ML/start-tunnel.sh` captures the Quick Tunnel host,
waits for its public `/health` response to report loaded models, and then runs
`node functions/publish-ml-api-url.js <verified-url>`. The publisher uses the
same local Firebase Admin service account as the announcement listener. That
credential is the publishing authorization; there is no public URL-update
endpoint or token in the app.

The publisher transactionally stores the current record at Realtime Database
`/ml_api/config` (`url`, `version`, `updatedAt`) and sends a data-only
`ml_api_update` message to the dedicated `detect_co_ml_config` topic. It uses
the existing FCM infrastructure while keeping config messages out of the
announcement topic, where legacy app versions would treat them as visible
announcements. It suppresses duplicate URL messages and retries a missed FCM
send for the same version. Existing announcement records and notifications are
unchanged.

Flutter reads this fixed Firebase path on startup and app resume, and it also
handles the FCM update in foreground and background. It accepts only HTTPS
Quick Tunnel hosts, checks `/health`, and persists a replacement only after
that check passes. If a push is missed, startup/resume synchronization is the
fallback. On the Menu > Display Settings > ML Server Address dialog, Clear URL
also retries the shared configuration.

The repository does not contain the Firebase Realtime Database security-rule
source. In the Firebase console, verify `/ml_api/config` can be read by app
clients but cannot be written by client SDKs; Admin SDK writes bypass those
client rules. Do not loosen existing announcement or sensor rules to make this
path work. The app verifies the value's format and health before using it.
