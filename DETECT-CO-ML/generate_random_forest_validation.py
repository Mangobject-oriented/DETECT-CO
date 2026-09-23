#!/usr/bin/env python3

import os
import numpy as np
import joblib

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")
MODEL_DIR = os.path.join(
    DATA_DIR,
    "models",
    "random_forest"
)

VALIDATION_FILE = os.path.join(
    XGB_DIR,
    "xgboost_validation_clean.npz"
)

OUTPUT_FILE = os.path.join(
    XGB_DIR,
    "random_forest_validation_predictions_clean.npz"
)

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

print("=" * 70)
print("RANDOM FOREST — VALIDATION PREDICTIONS")
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
        f"random_forest_{target_name}.joblib"
    )

    print(f"Loading model: {target_name}")

    if not os.path.exists(model_file):
        raise FileNotFoundError(
            f"Model not found: {model_file}"
        )

    model = joblib.load(model_file)

    print("Generating predictions...")

    predictions[:, i] = model.predict(
        X_validation
    )

    print(
        f"Prediction range: "
        f"{predictions[:, i].min():.6f} - "
        f"{predictions[:, i].max():.6f}"
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
print("VALIDATION PREDICTIONS GENERATED")
print("=" * 70)
print()

print("Prediction shape:", predictions.shape)

print()
print("Saved:")
print(OUTPUT_FILE)

print()
print("Done.")
