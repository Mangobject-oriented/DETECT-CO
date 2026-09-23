#!/usr/bin/env python3

import os
import numpy as np
import pandas as pd
import joblib

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")
SCALER_DIR = os.path.join(DATA_DIR, "lstm_scalers")

WEATHER_FILE = os.path.join(
    DATA_DIR,
    "calamba_weather_features.csv"
)

LSTM_FILE = os.path.join(
    DATA_DIR,
    "lstm_validation_predictions.npz"
)

XGB_FILE = os.path.join(
    XGB_DIR,
    "xgboost_validation_predictions_clean.npz"
)

RF_FILE = os.path.join(
    XGB_DIR,
    "random_forest_validation_predictions_clean.npz"
)

OUTPUT_FILE = os.path.join(
    XGB_DIR,
    "ensemble_validation_real_mm.npz"
)

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

RAINFALL_FEATURE_INDICES = {
    "rainfall_1h_mm": 2,
    "rainfall_3h_mm": 3,
    "rainfall_6h_mm": 4,
    "rainfall_12h_mm": 5,
    "rainfall_24h_mm": 6
}


def convert_predictions_to_mm(
    predictions,
    latitude,
    longitude
):

    predictions_mm = np.zeros_like(
        predictions,
        dtype=np.float64
    )

    scalers = {}

    locations = sorted(
        set(
            zip(
                np.round(latitude, 2),
                np.round(longitude, 2)
            )
        )
    )

    for lat, lon in locations:

        scaler_file = os.path.join(
            SCALER_DIR,
            f"scaler_{lat:.2f}_{lon:.2f}.joblib"
        )

        if not os.path.exists(scaler_file):
            raise FileNotFoundError(
                f"Scaler not found: {scaler_file}"
            )

        scalers[(lat, lon)] = joblib.load(
            scaler_file
        )

    for i in range(len(predictions)):

        lat = round(float(latitude[i]), 2)
        lon = round(float(longitude[i]), 2)

        scaler = scalers[(lat, lon)]

        for j, target_name in enumerate(
            TARGET_COLUMNS
        ):

            feature_index = (
                RAINFALL_FEATURE_INDICES[target_name]
            )

            predictions_mm[i, j] = (
                predictions[i, j]
                - scaler.min_[feature_index]
            ) / scaler.scale_[feature_index]

    predictions_mm = np.maximum(
        predictions_mm,
        0
    )

    return predictions_mm


print("=" * 70)
print("ENSEMBLE VALIDATION DATA PREPARATION")
print("=" * 70)
print()

# ------------------------------------------------------------
# LOAD LSTM
# ------------------------------------------------------------

print("Loading LSTM validation predictions...")

lstm_data = np.load(
    LSTM_FILE,
    allow_pickle=True
)

lstm_predictions = lstm_data["predictions"]

print(
    "LSTM shape:",
    lstm_predictions.shape
)

# ------------------------------------------------------------
# LOAD XGBOOST
# ------------------------------------------------------------

print("Loading XGBoost validation predictions...")

xgb_data = np.load(
    XGB_FILE,
    allow_pickle=True
)

xgb_predictions = xgb_data["predictions"]

print(
    "XGBoost shape:",
    xgb_predictions.shape
)

# ------------------------------------------------------------
# LOAD RANDOM FOREST
# ------------------------------------------------------------

print("Loading Random Forest validation predictions...")

rf_data = np.load(
    RF_FILE,
    allow_pickle=True
)

rf_predictions = rf_data["predictions"]

print(
    "Random Forest shape:",
    rf_predictions.shape
)

# ------------------------------------------------------------
# METADATA
# ------------------------------------------------------------

timestamps = pd.to_datetime(
    rf_data["timestamps"]
)

latitude = np.asarray(
    rf_data["latitude"],
    dtype=float
)

longitude = np.asarray(
    rf_data["longitude"],
    dtype=float
)

print()
print("Validation rows:", len(timestamps))
print()

# ------------------------------------------------------------
# CONVERT ALL PREDICTIONS TO MM
# ------------------------------------------------------------

print("=" * 70)
print("CONVERTING PREDICTIONS TO MILLIMETERS")
print("=" * 70)
print()

print("Converting LSTM...")
lstm_mm = convert_predictions_to_mm(
    lstm_predictions,
    latitude,
    longitude
)

print("Converting XGBoost...")
xgb_mm = convert_predictions_to_mm(
    xgb_predictions,
    latitude,
    longitude
)

print("Converting Random Forest...")
rf_mm = convert_predictions_to_mm(
    rf_predictions,
    latitude,
    longitude
)

# ------------------------------------------------------------
# LOAD ACTUAL OPEN-METEO TARGETS
# ------------------------------------------------------------

print()
print("Loading actual validation rainfall from Open-Meteo...")

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

validation_index = pd.DataFrame({
    "timestamp": timestamps,
    "latitude": np.round(latitude, 2),
    "longitude": np.round(longitude, 2)
})

actual_data = weather.merge(
    validation_index,
    on=[
        "timestamp",
        "latitude",
        "longitude"
    ],
    how="right"
)

missing = actual_data[
    TARGET_COLUMNS
].isna().any(axis=1).sum()

print(
    "Missing actual target values:",
    missing
)

if missing > 0:
    raise ValueError(
        f"Found {missing} missing actual values."
    )

actual_mm = actual_data[
    TARGET_COLUMNS
].to_numpy(
    dtype=np.float64
)

# ------------------------------------------------------------
# VALIDATION CHECK
# ------------------------------------------------------------

print()
print("=" * 70)
print("VALIDATION DATA CHECK — REAL MILLIMETERS")
print("=" * 70)
print()

print("LSTM:", lstm_mm.shape)
print("XGBoost:", xgb_mm.shape)
print("Random Forest:", rf_mm.shape)
print("Actual:", actual_mm.shape)
print()

for i, target in enumerate(TARGET_COLUMNS):

    print(target)

    print(
        f"  Actual mean: "
        f"{actual_mm[:, i].mean():.4f} mm"
    )

    print(
        f"  LSTM mean:   "
        f"{lstm_mm[:, i].mean():.4f} mm"
    )

    print(
        f"  XGBoost mean:"
        f" {xgb_mm[:, i].mean():.4f} mm"
    )

    print(
        f"  RF mean:     "
        f"{rf_mm[:, i].mean():.4f} mm"
    )

    print()

# ------------------------------------------------------------
# SAVE
# ------------------------------------------------------------

np.savez_compressed(
    OUTPUT_FILE,
    lstm_predictions_mm=lstm_mm,
    xgboost_predictions_mm=xgb_mm,
    random_forest_predictions_mm=rf_mm,
    actual_mm=actual_mm,
    timestamps=timestamps.to_numpy(),
    latitude=latitude,
    longitude=longitude
)

print("=" * 70)
print("STEP 2B COMPLETE")
print("=" * 70)
print()

print("Saved:")
print(OUTPUT_FILE)

print()
print("All three validation predictions are now in real millimeters.")
print()
print("Done.")
