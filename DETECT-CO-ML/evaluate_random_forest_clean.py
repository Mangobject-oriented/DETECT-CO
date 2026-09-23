#!/usr/bin/env python3

import os
import numpy as np
import pandas as pd
import joblib
from sklearn.metrics import (
    mean_absolute_error,
    mean_squared_error,
    r2_score
)

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")
SCALER_DIR = os.path.join(DATA_DIR, "lstm_scalers")

WEATHER_FILE = os.path.join(
    DATA_DIR,
    "calamba_weather_features.csv"
)

PREDICTION_FILE = os.path.join(
    XGB_DIR,
    "random_forest_test_predictions_clean.npz"
)

TEST_FILE = os.path.join(
    XGB_DIR,
    "xgboost_test_clean.npz"
)

OUTPUT_PREDICTION_FILE = os.path.join(
    XGB_DIR,
    "random_forest_test_predictions_clean_mm.npz"
)

OUTPUT_METRICS_FILE = os.path.join(
    XGB_DIR,
    "random_forest_test_metrics_clean_mm.csv"
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

print("=" * 70)
print("RANDOM FOREST CLEAN — REAL-SCALE EVALUATION")
print("=" * 70)
print()

# ------------------------------------------------------------
# LOAD RANDOM FOREST PREDICTIONS
# ------------------------------------------------------------

data = np.load(
    PREDICTION_FILE,
    allow_pickle=True
)

pred_scaled = data["predictions"]

print("Scaled predictions:", pred_scaled.shape)
print()

# ------------------------------------------------------------
# LOAD ORIGINAL OPEN-METEO DATA
# ------------------------------------------------------------

print("Loading original Open-Meteo data...")

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

# ------------------------------------------------------------
# LOAD TEST INDEX
# ------------------------------------------------------------

test_data = np.load(
    TEST_FILE,
    allow_pickle=True
)

test_timestamps = pd.to_datetime(
    test_data["timestamps"]
)

test_latitude = np.asarray(
    test_data["latitude"],
    dtype=float
)

test_longitude = np.asarray(
    test_data["longitude"],
    dtype=float
)

test_index = pd.DataFrame({
    "timestamp": test_timestamps,
    "latitude": np.round(test_latitude, 2),
    "longitude": np.round(test_longitude, 2)
})

# ------------------------------------------------------------
# GET ACTUAL TARGET VALUES
# ------------------------------------------------------------

actual_data = weather.merge(
    test_index,
    on=[
        "timestamp",
        "latitude",
        "longitude"
    ],
    how="right"
)

missing = actual_data[TARGET_COLUMNS].isna().any(axis=1).sum()

print("Missing actual target values:", missing)

if missing > 0:
    raise ValueError(
        f"Found {missing} rows with missing actual target values."
    )

actual_mm = actual_data[
    TARGET_COLUMNS
].to_numpy(
    dtype=np.float64
)

# ------------------------------------------------------------
# CONVERT PREDICTIONS TO MILLIMETERS
# ------------------------------------------------------------

print()
print("Converting Random Forest predictions to millimeters...")
print()

pred_mm = np.zeros_like(
    pred_scaled,
    dtype=np.float64
)

# Load scalers
scalers = {}

locations = sorted(
    set(
        zip(
            test_index["latitude"],
            test_index["longitude"]
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

# Convert each prediction using the correct
# location-specific training-only scaler
for i in range(len(test_index)):

    lat = test_index.iloc[i]["latitude"]
    lon = test_index.iloc[i]["longitude"]

    scaler = scalers[(lat, lon)]

    for j, target_name in enumerate(TARGET_COLUMNS):

        feature_index = RAINFALL_FEATURE_INDICES[
            target_name
        ]

        pred_mm[i, j] = (
            pred_scaled[i, j]
            - scaler.min_[feature_index]
        ) / scaler.scale_[feature_index]

# Rainfall cannot be negative
pred_mm = np.maximum(
    pred_mm,
    0
)

# ------------------------------------------------------------
# EVALUATION
# ------------------------------------------------------------

print("=" * 70)
print("REAL-SCALE TEST RESULTS")
print("=" * 70)
print()

metrics = []

for j, target_name in enumerate(TARGET_COLUMNS):

    actual = actual_mm[:, j]
    predicted = pred_mm[:, j]

    mae = mean_absolute_error(
        actual,
        predicted
    )

    rmse = np.sqrt(
        mean_squared_error(
            actual,
            predicted
        )
    )

    r2 = r2_score(
        actual,
        predicted
    )

    print(target_name)
    print(f"  MAE : {mae:.4f} mm")
    print(f"  RMSE: {rmse:.4f} mm")
    print(f"  R²  : {r2:.4f}")
    print(f"  Actual mean: {actual.mean():.4f} mm")
    print(f"  Predicted mean: {predicted.mean():.4f} mm")
    print(f"  Actual max: {actual.max():.4f} mm")
    print(f"  Predicted max: {predicted.max():.4f} mm")
    print()

    metrics.append({
        "target": target_name,
        "mae_mm": mae,
        "rmse_mm": rmse,
        "r2": r2,
        "actual_mean_mm": actual.mean(),
        "predicted_mean_mm": predicted.mean(),
        "actual_max_mm": actual.max(),
        "predicted_max_mm": predicted.max()
    })

# ------------------------------------------------------------
# OVERALL
# ------------------------------------------------------------

overall_mae = mean_absolute_error(
    actual_mm,
    pred_mm
)

overall_rmse = np.sqrt(
    mean_squared_error(
        actual_mm,
        pred_mm
    )
)

print("=" * 70)
print("OVERALL")
print("=" * 70)

print(f"Overall MAE : {overall_mae:.4f} mm")
print(f"Overall RMSE: {overall_rmse:.4f} mm")

# ------------------------------------------------------------
# SAVE
# ------------------------------------------------------------

np.savez_compressed(
    OUTPUT_PREDICTION_FILE,
    predictions_mm=pred_mm,
    actual_mm=actual_mm,
    timestamps=test_timestamps.to_numpy(),
    latitude=test_latitude,
    longitude=test_longitude
)

pd.DataFrame(metrics).to_csv(
    OUTPUT_METRICS_FILE,
    index=False
)

print()
print("=" * 70)
print("FILES SAVED")
print("=" * 70)

print(OUTPUT_PREDICTION_FILE)
print(OUTPUT_METRICS_FILE)

print()
print("Done.")
