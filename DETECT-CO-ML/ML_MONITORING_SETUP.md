# DETECT-CO ML monitoring

The existing `POST /predict` endpoint remains the source of live model output.
It returns the five accumulated-rainfall targets, per-model predictions,
ensemble weights, current-hour Open-Meteo rainfall, and a Manila-time generation
timestamp. `GET /monitoring` returns the latest stored response, per-horizon
comparisons, and metrics.

## Admin website

There is no hardcoded API host. Configure the Vite build with
`VITE_ML_API_URL` set to the FastAPI base URL (for example
`https://ml.example.org`). For the Flutter app, set the full prediction URL
using `--dart-define=ML_API_URL=https://ml.example.org/predict`. The API's
`DETECTCO_ADMIN_ORIGINS` variable must include the exact admin website origin.
Its development default allows only `http://127.0.0.1:5173` and
`http://localhost:5173`; set the production admin origin explicitly.

## Flutter

The mobile app keeps its existing endpoint by default. To override it at build
time, pass the full predict URL with:

```sh
flutter build apk --dart-define=ML_API_URL=https://ml.example.org/predict
```

## Forecast verification storage

The FastAPI host stores only real forecast responses and completed hourly
Open-Meteo rainfall in a local SQLite file at
`DETECT-CO-ML/data/ml_monitoring.sqlite3`. Set
`DETECTCO_ML_MONITORING_DB` to move it to a persistent volume. Data is retained
for 90 days. The 1h/3h/6h/12h/24h values are evaluated only after their whole
corresponding hourly window is available. No historical predictions are
backfilled or fabricated. MAE and RMSE use completed windows; mean signed
percentage error excludes zero-rainfall actuals because percentage error is
undefined there.

This implementation does not add Firebase paths. The project has no validated
rainfall-to-flood-risk cutoffs or supported barangay risk-coordinate data, so
the shared LOW/MODERATE/HIGH severity remains based on the existing measured
water-rise boundaries (0–4 cm, 5–40 cm, and over 40 cm). Rainfall forecasts are
shown as context and are not assigned invented risk thresholds.
