import os
import joblib
import numpy as np
import pandas as pd
import xgboost as xgb
import tensorflow as tf

BASE = "/home/miguel/DETECT-CO-ML/data"

# ---------------------------------------------------------
# FILES
# ---------------------------------------------------------

WEATHER_FILE = f"{BASE}/calamba_weather_features.csv"

LSTM_VAL_FILE = f"{BASE}/lstm_validation_clean.npz"
XGB_VAL_FILE = f"{BASE}/xgboost/xgboost_validation_clean.npz"

SCALER_DIR = f"{BASE}/lstm_scalers"

LSTM_MODEL = f"{BASE}/models/refined_lstm/lstm_refined_3.keras"

XGB_DIR = f"{BASE}/models/xgboost"

RF_DIR = f"{BASE}/models/random_forest"

OUTPUT = f"{BASE}/xgboost/final_ensemble_validation_real_mm.npz"

TARGETS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

XGB_FILES = [
    "xgboost_rainfall_1h_mm.json",
    "xgboost_rainfall_3h_mm.json",
    "xgboost_rainfall_6h_mm.json",
    "xgboost_rainfall_12h_mm.json",
    "xgboost_rainfall_24h_mm.json"
]

RF_FILES = [
    "random_forest_rainfall_1h_mm.joblib",
    "random_forest_rainfall_3h_mm.joblib",
    "random_forest_rainfall_6h_mm.joblib",
    "random_forest_rainfall_12h_mm.joblib",
    "random_forest_rainfall_24h_mm.joblib"
]

TARGET_INDICES = {
    "rainfall_1h_mm": 2,
    "rainfall_3h_mm": 3,
    "rainfall_6h_mm": 4,
    "rainfall_12h_mm": 5,
    "rainfall_24h_mm": 6
}

# ---------------------------------------------------------
# LOAD DATA
# ---------------------------------------------------------

print("=" * 70)
print("FINAL ENSEMBLE VALIDATION PREPARATION")
print("=" * 70)

lstm_data = np.load(
    LSTM_VAL_FILE,
    allow_pickle=True
)

xgb_data = np.load(
    XGB_VAL_FILE,
    allow_pickle=True
)

X_lstm = lstm_data["X"]
X_xgb = xgb_data["X"]

timestamps = pd.to_datetime(
    lstm_data["timestamps"]
)

latitude = np.round(
    lstm_data["latitude"].astype(float),
    2
)

longitude = np.round(
    lstm_data["longitude"].astype(float),
    2
)

print("LSTM X:", X_lstm.shape)
print("XGB/RF X:", X_xgb.shape)

# ---------------------------------------------------------
# LOAD TRAINING-ONLY SCALERS
# ---------------------------------------------------------

scalers = {}

for lat, lon in sorted(
    set(zip(latitude, longitude))
):

    path = (
        f"{SCALER_DIR}/"
        f"scaler_{lat:.2f}_{lon:.2f}.joblib"
    )

    scalers[(lat, lon)] = joblib.load(path)

print("Loaded scalers:", len(scalers))

# ---------------------------------------------------------
# LOAD ACTUAL OPEN-METEO VALUES
# ---------------------------------------------------------

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

actual_lookup = weather[
    [
        "timestamp",
        "latitude",
        "longitude"
    ] + TARGETS
].copy()

actual_df = pd.DataFrame({
    "timestamp": timestamps,
    "latitude": latitude,
    "longitude": longitude
})

actual_df = actual_df.merge(
    actual_lookup,
    on=[
        "timestamp",
        "latitude",
        "longitude"
    ],
    how="left"
)

actual = actual_df[
    TARGETS
].to_numpy(
    dtype=np.float64
)

missing = np.isnan(actual).sum()

print("Actual shape:", actual.shape)
print("Missing actual values:", missing)

if missing:
    raise RuntimeError(
        "Missing Open-Meteo actual values."
    )

# ---------------------------------------------------------
# INVERSE SCALING
# ---------------------------------------------------------

def inverse_scale(pred_scaled):

    pred_scaled = np.asarray(
        pred_scaled,
        dtype=np.float64
    )

    pred_mm = np.zeros_like(
        pred_scaled
    )

    for lat, lon in sorted(
        set(zip(latitude, longitude))
    ):

        mask = (
            (latitude == lat) &
            (longitude == lon)
        )

        scaler = scalers[(lat, lon)]

        for j, target in enumerate(TARGETS):

            idx = TARGET_INDICES[target]

            pred_mm[mask, j] = (
                pred_scaled[mask, j]
                - scaler.min_[idx]
            ) / scaler.scale_[idx]

    return np.maximum(
        pred_mm,
        0
    )

# ---------------------------------------------------------
# LSTM — REFINED 3
# ---------------------------------------------------------

print()
print("=" * 70)
print("REFINED LSTM 3")
print("=" * 70)

lstm_model = tf.keras.models.load_model(
    LSTM_MODEL,
    compile=False
)

lstm_scaled = lstm_model.predict(
    X_lstm,
    batch_size=128,
    verbose=1
)

lstm_mm = inverse_scale(
    lstm_scaled
)

print("LSTM prediction shape:", lstm_mm.shape)

# ---------------------------------------------------------
# XGBOOST — ORIGINAL
# ---------------------------------------------------------

print()
print("=" * 70)
print("ORIGINAL XGBOOST")
print("=" * 70)

xgb_predictions = []

for filename in XGB_FILES:

    path = f"{XGB_DIR}/{filename}"

    model = xgb.XGBRegressor()
    model.load_model(path)

    prediction = model.predict(
        X_xgb
    )

    xgb_predictions.append(
        np.maximum(prediction, 0)
    )

xgb_scaled = np.column_stack(
    xgb_predictions
)

xgb_mm = inverse_scale(
    xgb_scaled
)

print("XGBoost prediction shape:", xgb_mm.shape)

# ---------------------------------------------------------
# RANDOM FOREST — ORIGINAL
# ---------------------------------------------------------

print()
print("=" * 70)
print("ORIGINAL RANDOM FOREST")
print("=" * 70)

rf_predictions = []

for filename in RF_FILES:

    path = f"{RF_DIR}/{filename}"

    model = joblib.load(path)

    prediction = model.predict(
        X_xgb
    )

    rf_predictions.append(
        np.maximum(prediction, 0)
    )

rf_scaled = np.column_stack(
    rf_predictions
)

rf_mm = inverse_scale(
    rf_scaled
)

print("Random Forest prediction shape:", rf_mm.shape)

# ---------------------------------------------------------
# BASIC CHECKS
# ---------------------------------------------------------

print()
print("=" * 70)
print("PREDICTION SUMMARY")
print("=" * 70)

print()
print("Actual means:")
print(np.mean(actual, axis=0))

print()
print("LSTM means:")
print(np.mean(lstm_mm, axis=0))

print()
print("XGBoost means:")
print(np.mean(xgb_mm, axis=0))

print()
print("Random Forest means:")
print(np.mean(rf_mm, axis=0))

# ---------------------------------------------------------
# SAVE
# ---------------------------------------------------------

np.savez_compressed(
    OUTPUT,
    actual=actual,
    lstm=lstm_mm,
    xgboost=xgb_mm,
    random_forest=rf_mm,
    timestamps=np.asarray(
        timestamps.astype(str)
    ),
    latitude=latitude,
    longitude=longitude,
    target_columns=np.array(TARGETS)
)

print()
print("=" * 70)
print("SAVED")
print("=" * 70)
print(OUTPUT)
print()
print("Done.")
