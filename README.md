# DETECT-CO

DETECT-CO is a Flutter flood preparedness app with Firebase sensor and notification features and a laptop-hosted ML rainfall forecast service. The ML pipeline remains on the Pop!_OS laptop and runs the existing LSTM, XGBoost, and Random Forest models.

## Cross-network ML access

See [ML_API_SETUP.txt](ML_API_SETUP.txt) for the laptop setup, Cloudflare Tunnel commands, URL configuration, stable hostname instructions, and troubleshooting. For the first test, run the temporary `trycloudflare.com` tunnel and build/run Flutter with the printed HTTPS URL:

```sh
flutter run --dart-define=ML_API_URL=https://printed-name.trycloudflare.com/predict
```

Temporary tunnel URLs change when restarted. Do not save one in production builds. Set a stable HTTPS hostname using a Cloudflare-managed domain for a long-running deployment.

The laptop is still the server. It must stay powered on, awake, connected to the internet, and keep both FastAPI and `cloudflared` running. This is a best-effort service and must not be the sole emergency-warning channel.

## Other app features

Firebase sensor readings, notifications, Home, Map, and the existing local AI and preparedness features remain part of the Flutter app. ML API failure is reported as unavailable; it is not interpreted as a flood-risk reading.

## Development

```sh
flutter pub get
flutter run --dart-define=ML_API_URL=https://your-public-ml-host/predict
```

The optional admin web app takes its API base from `VITE_ML_API_URL` in its local environment. Never put service-account credentials or tunnel credentials in Flutter assets, source control, or public environment files.
