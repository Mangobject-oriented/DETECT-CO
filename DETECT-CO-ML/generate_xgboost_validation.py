#!/usr/bin/env python3

import os
import numpy as np
import xgboost as xgb

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")
MODEL_DIR = os.path.join(
    DATA_DIR,
    "models",
    "xgboost"
)

VALIDATION_FILE = os.path.join(
    XGB_DIR,
    "xgboost_validation_clean.npz"
)

OUTPUT_FILE = os.path.join(
    XGB_DIR,
    "xgboost_validation_predictions_clean.npz"
)

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

print("=" * 70)
print("XGBOOST — VALIDATION PREDICTIONS")
print("=" * 70)
print()

# ------------------------------------------------------------
# LOAD VALIDATION DATA
# ------------------------------------------------------------

data = np.load(
    VALIDATION_FILE,
    allow_pickle=True
)

X_validation = data["X"]
y_validation = data["y"]

print("Validation X:", X_validation.shape)
print("Validation y:", y_validation.shape)
print()

# ------------------------------------------------------------
# GENERATE PREDICTIONS
# ------------------------------------------------------------

predictions = np.zeros_like(
    y_validation,
    dtype=np.float32
)

for i, target_name in enumerate(TARGET_COLUMNS):

    model_file = os.path.join(
        MODEL_DIR,
        f"xgboost_{target_name}.json"
    )

    print("-" * 70)
    print(f"TARGET: {target_name}")
    print("Loading:", model_file)

    if not os.path.exists(model_file):
        raise FileNotFoundError(
            f"Model not found: {model_file}"
        )

    model = xgb.XGBRegressor()
    model.load_model(model_file)

    predictions[:, i] = model.predict(
        X_validation
    )

    print(
        f"Prediction range: "
        f"{predictions[:, i].min():.6f} - "
        f"{predictions[:, i].max():.6f}"
    )

    print(
        f"Actual range:     "
        f"{y_validation[:, i].min():.6f} - "
        f"{y_validation[:, i].max():.6f}"
    )

    print()

# ------------------------------------------------------------
# SAVE
# ------------------------------------------------------------

np.savez_compressed(
    OUTPUT_FILE,
    predictions=predictions,
    actual=y_validation,
    timestamps=data["timestamps"],
    latitude=data["latitude"],
    longitude=data["longitude"]
)

print("=" * 70)
print("XGBOOST VALIDATION PREDICTIONS GENERATED")
print("=" * 70)
print()

print("Prediction shape:", predictions.shape)
print()
print("Saved:")
print(OUTPUT_FILE)
print()
print("Done.")
