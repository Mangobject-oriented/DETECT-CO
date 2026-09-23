#!/usr/bin/env python3

import os
import json
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")

WEIGHTS_FILE = os.path.join(
    XGB_DIR,
    "ensemble_weights.json"
)

LSTM_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_predictions_mm.npz"
)

XGB_FILE = os.path.join(
    XGB_DIR,
    "xgboost_test_predictions_clean_mm.npz"
)

RF_FILE = os.path.join(
    XGB_DIR,
    "random_forest_test_predictions_clean_mm.npz"
)

OUTPUT_PREDICTIONS = os.path.join(
    XGB_DIR,
    "ensemble_test_predictions_final.npz"
)

OUTPUT_METRICS = os.path.join(
    XGB_DIR,
    "ensemble_test_metrics_final.csv"
)

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

print("=" * 70)
print("FINAL ENSEMBLE TEST EVALUATION")
print("=" * 70)
print()

# ------------------------------------------------------------
# LOAD FROZEN WEIGHTS
# ------------------------------------------------------------

with open(WEIGHTS_FILE, "r") as f:
    weight_data = json.load(f)

weights = weight_data["weights"]

w_lstm = weights["lstm"]
w_xgb = weights["xgboost"]
w_rf = weights["random_forest"]

print("FROZEN WEIGHTS")
print("-" * 70)
print(f"LSTM:          {w_lstm:.2f}")
print(f"XGBoost:       {w_xgb:.2f}")
print(f"Random Forest: {w_rf:.2f}")
print()

if not np.isclose(
    w_lstm + w_xgb + w_rf,
    1.0
):
    raise ValueError(
        "Ensemble weights do not sum to 1."
    )

# ------------------------------------------------------------
# LOAD TEST PREDICTIONS
# ------------------------------------------------------------

print("Loading test predictions...")

lstm_data = np.load(
    LSTM_FILE,
    allow_pickle=True
)

xgb_data = np.load(
    XGB_FILE,
    allow_pickle=True
)

rf_data = np.load(
    RF_FILE,
    allow_pickle=True
)

# LSTM uses predictions_mm
lstm = lstm_data["predictions_mm"]

# XGBoost uses predictions
# This file was already converted to real millimeters.
xgb = xgb_data["predictions"]

# Random Forest uses predictions_mm
rf = rf_data["predictions_mm"]

# Use Random Forest actuals as the common test target.
actual = rf_data["actual_mm"]

print()
print("LSTM:", lstm.shape)
print("XGBoost:", xgb.shape)
print("Random Forest:", rf.shape)
print("Actual:", actual.shape)
print()

# ------------------------------------------------------------
# VERIFY SHAPES
# ------------------------------------------------------------

if not (
    lstm.shape == xgb.shape
    == rf.shape
    == actual.shape
):
    raise ValueError(
        "Prediction/actual shapes do not match."
    )

if lstm.shape[1] != len(TARGET_COLUMNS):
    raise ValueError(
        "Unexpected number of target columns."
    )

# ------------------------------------------------------------
# VERIFY TEST TARGET AGREEMENT
# ------------------------------------------------------------

xgb_actual = xgb_data["actual"]

if not np.allclose(
    actual,
    xgb_actual,
    atol=1e-6
):
    raise ValueError(
        "XGBoost actual values do not match "
        "the Random Forest actual values."
    )

print("Actual target verification: PASSED")
print()

# ------------------------------------------------------------
# CREATE FINAL ENSEMBLE
# ------------------------------------------------------------

print("=" * 70)
print("CREATING FINAL ENSEMBLE")
print("=" * 70)
print()

ensemble = (
    w_lstm * lstm
    + w_xgb * xgb
    + w_rf * rf
)

ensemble = np.maximum(
    ensemble,
    0
)

print(
    "Ensemble shape:",
    ensemble.shape
)

# ------------------------------------------------------------
# EVALUATE
# ------------------------------------------------------------

metrics = []

print()
print("=" * 70)
print("FINAL TEST RESULTS")
print("=" * 70)
print()

for i, target in enumerate(TARGET_COLUMNS):

    y_true = actual[:, i]
    y_pred = ensemble[:, i]

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

    metrics.append({
        "target": target,
        "MAE_mm": mae,
        "RMSE_mm": rmse,
        "R2": r2,
        "actual_mean_mm": np.mean(y_true),
        "predicted_mean_mm": np.mean(y_pred),
        "actual_max_mm": np.max(y_true),
        "predicted_max_mm": np.max(y_pred)
    })

    print(target)
    print(f"  MAE:            {mae:.4f} mm")
    print(f"  RMSE:           {rmse:.4f} mm")
    print(f"  R²:             {r2:.4f}")
    print(f"  Actual mean:    {np.mean(y_true):.4f} mm")
    print(f"  Predicted mean: {np.mean(y_pred):.4f} mm")
    print(f"  Actual max:     {np.max(y_true):.4f} mm")
    print(f"  Predicted max:  {np.max(y_pred):.4f} mm")
    print()

# ------------------------------------------------------------
# OVERALL METRICS
# ------------------------------------------------------------

overall_mae = mean_absolute_error(
    actual.flatten(),
    ensemble.flatten()
)

overall_rmse = np.sqrt(
    mean_squared_error(
        actual.flatten(),
        ensemble.flatten()
    )
)

overall_r2 = r2_score(
    actual.flatten(),
    ensemble.flatten()
)

print("=" * 70)
print("OVERALL")
print("=" * 70)

print(
    f"MAE:  {overall_mae:.4f} mm"
)

print(
    f"RMSE: {overall_rmse:.4f} mm"
)

print(
    f"R²:   {overall_r2:.4f}"
)

# ------------------------------------------------------------
# SAVE METRICS
# ------------------------------------------------------------

metrics_df = pd.DataFrame(metrics)

metrics_df.to_csv(
    OUTPUT_METRICS,
    index=False
)

# ------------------------------------------------------------
# SAVE PREDICTIONS
# ------------------------------------------------------------

np.savez_compressed(
    OUTPUT_PREDICTIONS,
    predictions_mm=ensemble,
    actual_mm=actual,
    lstm_predictions_mm=lstm,
    xgboost_predictions_mm=xgb,
    random_forest_predictions_mm=rf,
    timestamps=rf_data["timestamps"],
    latitude=rf_data["latitude"],
    longitude=rf_data["longitude"],
    lstm_weight=w_lstm,
    xgboost_weight=w_xgb,
    random_forest_weight=w_rf
)

print()
print("=" * 70)
print("FINAL ENSEMBLE SAVED")
print("=" * 70)
print()

print("Predictions:")
print(OUTPUT_PREDICTIONS)

print()
print("Metrics:")
print(OUTPUT_METRICS)

print()
print("Test set was evaluated using frozen validation-derived weights.")
print("No test-based weight tuning was performed.")
print()
print("Done.")
