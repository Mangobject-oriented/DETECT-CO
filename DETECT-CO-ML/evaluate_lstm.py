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

PREDICTIONS_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_predictions.npz"
)

SCALER_DIR = os.path.join(
    DATA_DIR,
    "lstm_scalers"
)

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

FEATURE_COLUMNS = [
    "temperature_c",
    "humidity_percent",
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm",
    "rainfall_3h_avg_mm",
    "rainfall_6h_avg_mm",
    "rainfall_12h_avg_mm",
    "rainfall_24h_avg_mm",
    "hour",
    "day_of_week",
    "month"
]

TARGET_INDICES = [
    FEATURE_COLUMNS.index(col)
    for col in TARGET_COLUMNS
]

# ============================================================
# LOAD PREDICTIONS
# ============================================================

print("=" * 70)
print("DETECT-CO LSTM — REAL-SCALE EVALUATION")
print("=" * 70)

data = np.load(
    PREDICTIONS_FILE,
    allow_pickle=True
)

predictions_scaled = data["predictions"]
actual_scaled = data["actual"]

timestamps = pd.to_datetime(
    data["timestamps"]
)

latitude = data["latitude"]
longitude = data["longitude"]

print("\nPredictions shape:")
print(predictions_scaled.shape)

print("\nActual shape:")
print(actual_scaled.shape)

# ============================================================
# PREPARE OUTPUT ARRAYS
# ============================================================

predictions_mm = np.zeros_like(
    predictions_scaled,
    dtype=np.float32
)

actual_mm = np.zeros_like(
    actual_scaled,
    dtype=np.float32
)

# ============================================================
# INVERSE SCALE BY LOCATION
# ============================================================

print("\n" + "=" * 70)
print("CONVERTING BACK TO MILLIMETERS")
print("=" * 70)

locations = np.column_stack(
    [latitude, longitude]
)

unique_locations = np.unique(
    locations,
    axis=0
)

for location in unique_locations:

    lat = float(location[0])
    lon = float(location[1])

    scaler_file = os.path.join(
        SCALER_DIR,
        f"scaler_{lat:.2f}_{lon:.2f}.joblib"
    )

    print(
        f"\nLocation: {lat:.2f}, {lon:.2f}"
    )

    print(
        "Scaler:",
        scaler_file
    )

    scaler = joblib.load(
        scaler_file
    )

    mask = (
        (latitude == lat) &
        (longitude == lon)
    )

    # Convert each target using the corresponding
    # training-only scaler parameters.

    for target_index, feature_index in enumerate(
        TARGET_INDICES
    ):

        data_min = scaler.data_min_[
            feature_index
        ]

        data_max = scaler.data_max_[
            feature_index
        ]

        scale = (
            data_max - data_min
        )

        if scale == 0:
            scale = 1.0

        predictions_mm[
            mask,
            target_index
        ] = (
            predictions_scaled[
                mask,
                target_index
            ] * scale
            + data_min
        )

        actual_mm[
            mask,
            target_index
        ] = (
            actual_scaled[
                mask,
                target_index
            ] * scale
            + data_min
        )

# ============================================================
# CLIP NEGATIVE PREDICTIONS
# ============================================================

# Rainfall cannot physically be negative.

predictions_mm = np.maximum(
    predictions_mm,
    0
)

# ============================================================
# CALCULATE METRICS
# ============================================================

print("\n" + "=" * 70)
print("LSTM TEST RESULTS — ORIGINAL RAINFALL SCALE")
print("=" * 70)

results = []

for i, target in enumerate(
    TARGET_COLUMNS
):

    actual = actual_mm[:, i]
    predicted = predictions_mm[:, i]

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

    results.append({
        "target": target,
        "MAE_mm": mae,
        "RMSE_mm": rmse,
        "R2": r2
    })

    print(
        f"\n{target}"
    )

    print(
        f"  MAE : {mae:.4f} mm"
    )

    print(
        f"  RMSE: {rmse:.4f} mm"
    )

    print(
        f"  R²  : {r2:.4f}"
    )

# ============================================================
# OVERALL METRICS
# ============================================================

overall_mae = mean_absolute_error(
    actual_mm,
    predictions_mm
)

overall_rmse = np.sqrt(
    mean_squared_error(
        actual_mm,
        predictions_mm
    )
)

print("\n" + "=" * 70)
print("OVERALL")
print("=" * 70)

print(
    f"\nOverall MAE : {overall_mae:.4f} mm"
)

print(
    f"Overall RMSE: {overall_rmse:.4f} mm"
)

# ============================================================
# ACTUAL VS PREDICTED SUMMARY
# ============================================================

print("\n" + "=" * 70)
print("RAINFALL RANGE")
print("=" * 70)

for i, target in enumerate(
    TARGET_COLUMNS
):

    print(
        f"\n{target}"
    )

    print(
        f"  Actual minimum : "
        f"{actual_mm[:, i].min():.4f} mm"
    )

    print(
        f"  Actual maximum : "
        f"{actual_mm[:, i].max():.4f} mm"
    )

    print(
        f"  Predicted minimum: "
        f"{predictions_mm[:, i].min():.4f} mm"
    )

    print(
        f"  Predicted maximum: "
        f"{predictions_mm[:, i].max():.4f} mm"
    )

    print(
        f"  Actual mean : "
        f"{actual_mm[:, i].mean():.4f} mm"
    )

    print(
        f"  Predicted mean: "
        f"{predictions_mm[:, i].mean():.4f} mm"
    )

# ============================================================
# SAVE REAL-SCALE PREDICTIONS
# ============================================================

OUTPUT_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_predictions_mm.npz"
)

np.savez_compressed(
    OUTPUT_FILE,

    predictions_mm=predictions_mm,

    actual_mm=actual_mm,

    timestamps=timestamps,

    latitude=latitude,

    longitude=longitude
)

# ============================================================
# SAVE CSV SUMMARY
# ============================================================

results_df = pd.DataFrame(
    results
)

CSV_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_metrics.csv"
)

results_df.to_csv(
    CSV_FILE,
    index=False
)

print("\n" + "=" * 70)
print("FILES SAVED")
print("=" * 70)

print(
    "\nReal-scale predictions:"
)

print(
    OUTPUT_FILE
)

print(
    "\nMetrics:"
)

print(
    CSV_FILE
)

print("\nDone.")
