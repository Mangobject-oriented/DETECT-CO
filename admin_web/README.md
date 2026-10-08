# DETECT-CO Barangay Emergency Monitor

A small Vite dashboard that listens to Firebase Realtime Database
`emergency_sessions`, displays unexpired active sessions, and writes one-way
announcements to `/announcements`.

## Firebase web configuration

The repository has Android Firebase configuration for the existing project,
but it does not contain a registered Firebase Web App configuration. In the
Firebase Console, register a Web App in the existing DETECT-CO Firebase
project, then copy its client configuration values into `admin_web/.env.local`
using `.env.example` as the template. Include the Realtime Database URL for the
same project.

These `VITE_FIREBASE_*` values are browser client configuration. They are not
service-account credentials and cannot be used to bypass Realtime Database
rules. Never put a service-account JSON file or private key in this directory.

The emergency monitor listens to `emergency_sessions` and filters to records whose
`status` is exactly `active` and whose `expiresAt` is later than the browser's
current time. `startedAt`, `updatedAt`, and `expiresAt` are Unix milliseconds,
matching the Flutter implementation. Location records without `updatedAt`
show that no location update has arrived yet.

The Announcements panel writes title, message, type, priority, and Unix
millisecond timestamp to `/announcements/{announcementId}`. The browser uses
only the Firebase Web SDK and has no FCM credentials. Run the local FCM listener
from the repository root with `node functions/announcement-listener.js`; the
computer running it must remain online to send announcement pushes. See
`functions/README.md` for setup and testing.

## Admin authentication and access

The website signs in with Firebase Authentication Email/Password. Enable that
provider in the Firebase Console and create accounts there. Any valid signed-in
Firebase user can open the dashboard. No role, user record, or custom claim is
required. The dashboard's Realtime Database listeners start only after Firebase
reports an authenticated user, and are stopped on logout.

Authentication does not replace Realtime Database security rules. This
repository has no local Realtime Database rules file, so inspect the deployed
rules before changing them. If rules currently require a privileged account
property for the website's `emergency_sessions` or `announcements` paths, change
only those relevant read/write predicates to require an authenticated user
(`auth != null`) and keep unrelated data rules intact. The Flutter emergency
session writer currently does not use Firebase Authentication; preserve its
existing narrowly scoped write access when adjusting session rules, or that
mobile flow may stop working. Do not make the database public to get the
website working.

## Run locally

From this directory:

```sh
npm install
cp .env.example .env.local
# Fill .env.local with the Firebase Console web app configuration.
npm run dev
```

Vite prints the local URL (normally `http://127.0.0.1:5173`). The browser must
be able to reach Firebase and OpenStreetMap tile servers.
