# DETECT-CO

DETECT-CO is a Flutter flood preparedness app with Firebase sensor and notification features and a laptop-hosted ML rainfall forecast service. The ML pipeline remains on the Pop!_OS laptop and runs the existing LSTM, XGBoost, and Random Forest models.

## Cross-network ML access

See [ML_API_SETUP.txt](ML_API_SETUP.txt) for the laptop setup, Cloudflare Tunnel commands, automatic URL publication, stable hostname instructions, and troubleshooting. The laptop script publishes a verified temporary URL to the existing Firebase configuration path and sends an update over the existing FCM topic. The app also syncs that configuration on startup and resume, so users do not paste tunnel URLs:

```sh
flutter run
```

Temporary tunnel URLs change when restarted. They are stored as current backend configuration only after the public API health check succeeds. The laptop must publish each new tunnel URL. For a long-running deployment, use a stable HTTPS hostname on a Cloudflare-managed domain.

The laptop is still the server. It must stay powered on, awake, connected to the internet, and keep both FastAPI and `cloudflared` running. This is a best-effort service and must not be the sole emergency-warning channel.

## Other app features

Firebase sensor readings, notifications, Home, Map, and the existing local AI and preparedness features remain part of the Flutter app. ML API failure is reported as unavailable; it is not interpreted as a flood-risk reading.

## Development

```sh
flutter pub get
flutter run
```

`ML_API_URL` remains an optional build-time fallback. The optional admin web app takes its API base from `VITE_ML_API_URL` in its local environment. Never put service-account credentials or tunnel credentials in Flutter assets, source control, or public environment files.
