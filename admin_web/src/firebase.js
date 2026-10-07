import { initializeApp } from 'firebase/app';
import { getDatabase } from 'firebase/database';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  databaseURL: import.meta.env.VITE_FIREBASE_DATABASE_URL,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};

const requiredConfig = [
  'apiKey',
  'authDomain',
  'databaseURL',
  'projectId',
  'appId',
];

const missingConfig = requiredConfig.filter((key) => !firebaseConfig[key]);
export const firebaseConfigError = missingConfig.length > 0
  ? `Missing Firebase web configuration: ${missingConfig.join(', ')}. ` +
    'Copy the web app values into admin_web/.env.local.'
  : null;

export const database = firebaseConfigError
  ? null
  : getDatabase(initializeApp(firebaseConfig));
