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
