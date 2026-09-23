#!/usr/bin/env python3

import os
import numpy as np
import pandas as pd

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")

INPUT_FILE = os.path.join(
    XGB_DIR,
    "ensemble_validation_real_mm.npz"
)

OUTPUT_FILE = os.path.join(
    XGB_DIR,
    "ensemble_weights.json"
)

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

print("=" * 70)
print("ENSEMBLE WEIGHT SEARCH — VALIDATION ONLY")
print("=" * 70)
print()

data = np.load(
    INPUT_FILE,
    allow_pickle=True
)

lstm = data["lstm_predictions_mm"]
xgb = data["xgboost_predictions_mm"]
rf = data["random_forest_predictions_mm"]
actual = data["actual_mm"]

print("LSTM:", lstm.shape)
print("XGBoost:", xgb.shape)
print("Random Forest:", rf.shape)
print("Actual:", actual.shape)
print()

# ------------------------------------------------------------
# GRID SEARCH
# ------------------------------------------------------------

best_rmse = float("inf")
best_weights = None

results = []

STEP = 0.01

for lstm_weight in np.arange(
    0.0,
    1.0 + STEP,
    STEP
):

    for xgb_weight in np.arange(
        0.0,
        1.0 - lstm_weight + STEP,
        STEP
    ):

        rf_weight = (
            1.0
            - lstm_weight
            - xgb_weight
        )

        if rf_weight < -1e-9:
            continue

        ensemble = (
            lstm_weight * lstm
            + xgb_weight * xgb
            + rf_weight * rf
        )

        rmse = np.sqrt(
            np.mean(
                (ensemble - actual) ** 2
            )
        )

        mae = np.mean(
            np.abs(
                ensemble - actual
            )
        )

        results.append({
            "lstm_weight": lstm_weight,
            "xgboost_weight": xgb_weight,
            "random_forest_weight": rf_weight,
            "rmse": rmse,
            "mae": mae
        })

        if rmse < best_rmse:
            best_rmse = rmse

            best_weights = {
                "lstm": float(lstm_weight),
                "xgboost": float(xgb_weight),
                "random_forest": float(rf_weight)
            }

# ------------------------------------------------------------
# RESULTS
# ------------------------------------------------------------

results_df = pd.DataFrame(results)

results_df = results_df.sort_values(
    "rmse"
)

best_row = results_df.iloc[0]

print("=" * 70)
print("BEST VALIDATION WEIGHTS")
print("=" * 70)
print()

print(
    f"LSTM:           "
    f"{best_weights['lstm']:.2f}"
)

print(
    f"XGBoost:        "
    f"{best_weights['xgboost']:.2f}"
)

print(
    f"Random Forest:  "
    f"{best_weights['random_forest']:.2f}"
)

print()

print(
    f"Validation RMSE: "
    f"{best_row['rmse']:.6f} mm"
)

print(
    f"Validation MAE:  "
    f"{best_row['mae']:.6f} mm"
)

print()

# ------------------------------------------------------------
# MODEL-ONLY BASELINES
# ------------------------------------------------------------

print("=" * 70)
print("VALIDATION BASELINES")
print("=" * 70)
print()

for name, prediction in [
    ("LSTM", lstm),
    ("XGBoost", xgb),
    ("Random Forest", rf)
]:

    rmse = np.sqrt(
        np.mean(
            (prediction - actual) ** 2
        )
    )

    mae = np.mean(
        np.abs(
            prediction - actual
        )
    )

    print(
        f"{name:15s} "
        f"RMSE={rmse:.6f} mm  "
        f"MAE={mae:.6f} mm"
    )

print()

# ------------------------------------------------------------
# SAVE WEIGHTS
# ------------------------------------------------------------

import json

output = {
    "method": "grid_search",
    "step": STEP,
    "metric": "overall_validation_rmse",
    "weights": best_weights,
    "validation_rmse_mm": float(best_row["rmse"]),
    "validation_mae_mm": float(best_row["mae"])
}

with open(
    OUTPUT_FILE,
    "w"
) as f:

    json.dump(
        output,
        f,
        indent=4
    )

print("=" * 70)
print("WEIGHTS SAVED")
print("=" * 70)
print()

print(OUTPUT_FILE)
print()

print("These weights are based ONLY on validation data.")
print("They will be frozen before evaluating the test set.")
print()
print("Done.")
