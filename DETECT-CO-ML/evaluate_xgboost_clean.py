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

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

# Positions of the rainfall features in the
# original 14-feature LSTM input.
TARGET_INDICES = {
    "rainfall_1h_mm": 2,
    "rainfall_3h_mm": 3,
    "rainfall_6h_mm": 4,
    "rainfall_12h_mm": 5,
    "rainfall_24h_mm": 6
}

# ---------------------------------------------------------
# LOAD XGBOOST PREDICTIONS
# ---------------------------------------------------------

prediction_file = os.path.join(
    XGB_DIR,
    "xgboost_test_predictions_clean.npz"
)

data = np.load(
    prediction_file,
    allow_pickle=True
)

predictions_scaled = data["predictions"]

timestamps = pd.to_datetime(
    data["timestamps"]
)

latitude = np.round(
    data["latitude"].astype(float),
    2
)

longitude = np.round(
    data["longitude"].astype(float),
    2
)

print("=" * 70)
print("XGBOOST CLEAN — REAL-SCALE EVALUATION")
print("=" * 70)

print()
print(
    "Scaled predictions:",
    predictions_scaled.shape
)

# ---------------------------------------------------------
# LOAD ORIGINAL OPEN-METEO DATA
# ---------------------------------------------------------

print()
print("Loading original Open-Meteo data...")

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather[
    "latitude"
].round(2)

weather["longitude"] = weather[
    "longitude"
].round(2)

# Only need actual target values.
weather_targets = weather[
    [
        "timestamp",
        "latitude",
        "longitude"
    ] + TARGET_COLUMNS
].copy()

# ---------------------------------------------------------
# MATCH ACTUAL TARGETS
# ---------------------------------------------------------

results_data = pd.DataFrame({
    "timestamp": timestamps,
    "latitude": latitude,
    "longitude": longitude
})

results_data = results_data.merge(
    weather_targets,
    on=[
        "timestamp",
        "latitude",
        "longitude"
    ],
    how="left"
)

missing_actual = results_data[
    TARGET_COLUMNS
].isna().sum().sum()

print(
    "Missing actual target values:",
    missing_actual
)

if missing_actual != 0:
    raise RuntimeError(
        "Could not recover all actual Open-Meteo "
        "target values."
    )

actual_mm = results_data[
    TARGET_COLUMNS
].to_numpy(
    dtype=np.float32
)

# ---------------------------------------------------------
# INVERSE TRANSFORM XGBOOST PREDICTIONS
# ---------------------------------------------------------

print()
print("Converting XGBoost predictions to millimeters...")

pred_mm = np.zeros_like(
    predictions_scaled,
    dtype=np.float32
)

locations = sorted(
    set(
        zip(
            latitude,
            longitude
        )
    )
)

for lat, lon in locations:

    mask = (
        (latitude == lat) &
        (longitude == lon)
    )

    scaler_file = os.path.join(
        SCALER_DIR,
        f"scaler_{lat:.2f}_{lon:.2f}.joblib"
    )

    scaler = joblib.load(
        scaler_file
    )

    for target_index, target_name in enumerate(
        TARGET_COLUMNS
    ):

        feature_index = TARGET_INDICES[
            target_name
        ]

        # MinMaxScaler transformation:
        #
        # X_scaled = X * scale_ + min_
        #
        # Therefore:
        #
        # X = (X_scaled - min_) / scale_

        pred_mm[
            mask,
            target_index
        ] = (
            predictions_scaled[
                mask,
                target_index
            ]
            - scaler.min_[feature_index]
        ) / scaler.scale_[feature_index]

# Rainfall cannot be negative.
pred_mm = np.maximum(
    pred_mm,
    0
)

# ---------------------------------------------------------
# METRICS
# ---------------------------------------------------------

results = []

print()
print("=" * 70)
print("REAL-SCALE TEST RESULTS")
print("=" * 70)

for i, target in enumerate(
    TARGET_COLUMNS
):

    y_true = actual_mm[:, i]
    y_pred = pred_mm[:, i]

    mae = mean_absolute_error(
        y_true,
        y_pred
    )

    rmse = np.sqrt(
        mean_squared_error(
            y_true,
            y_pred
        )
    )

    r2 = r2_score(
        y_true,
        y_pred
    )

    results.append({
        "target": target,
        "MAE_mm": mae,
        "RMSE_mm": rmse,
        "R2": r2,
        "actual_mean_mm": y_true.mean(),
        "predicted_mean_mm": y_pred.mean(),
        "actual_max_mm": y_true.max(),
        "predicted_max_mm": y_pred.max()
    })

    print()
    print(target)

    print(
        f"  MAE : {mae:.4f} mm"
    )

    print(
        f"  RMSE: {rmse:.4f} mm"
    )

    print(
        f"  R²  : {r2:.4f}"
    )

    print(
        f"  Actual mean: "
        f"{y_true.mean():.4f} mm"
    )

    print(
        f"  Predicted mean: "
        f"{y_pred.mean():.4f} mm"
    )

    print(
        f"  Actual max: "
        f"{y_true.max():.4f} mm"
    )

    print(
        f"  Predicted max: "
        f"{y_pred.max():.4f} mm"
    )

# ---------------------------------------------------------
# OVERALL
# ---------------------------------------------------------

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

print()
print("=" * 70)
print("OVERALL")
print("=" * 70)

print(
    f"Overall MAE : "
    f"{overall_mae:.4f} mm"
)

print(
    f"Overall RMSE: "
    f"{overall_rmse:.4f} mm"
)

# ---------------------------------------------------------
# SAVE REAL-SCALE PREDICTIONS
# ---------------------------------------------------------

output_predictions = os.path.join(
    XGB_DIR,
    "xgboost_test_predictions_clean_mm.npz"
)

np.savez_compressed(
    output_predictions,
    predictions=pred_mm,
    actual=actual_mm,
    timestamps=timestamps.astype(str),
    latitude=latitude,
    longitude=longitude,
    target_columns=np.array(
        TARGET_COLUMNS
    )
)

# ---------------------------------------------------------
# SAVE METRICS
# ---------------------------------------------------------

metrics_file = os.path.join(
    XGB_DIR,
    "xgboost_test_metrics_clean_mm.csv"
)

pd.DataFrame(
    results
).to_csv(
    metrics_file,
    index=False
)

print()
print("=" * 70)
print("FILES SAVED")
print("=" * 70)

print(output_predictions)
print(metrics_file)

print()
print("Done.")
