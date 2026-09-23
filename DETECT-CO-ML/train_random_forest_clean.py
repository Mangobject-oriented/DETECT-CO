#!/usr/bin/env python3

import os
import time
import numpy as np
import pandas as pd

from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import (
    mean_absolute_error,
    mean_squared_error,
    r2_score
)

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")
MODEL_DIR = os.path.join(DATA_DIR, "models", "random_forest")

os.makedirs(MODEL_DIR, exist_ok=True)

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

TRAIN_FILE = os.path.join(
    XGB_DIR, "xgboost_train_clean.npz"
)

VALIDATION_FILE = os.path.join(
    XGB_DIR, "xgboost_validation_clean.npz"
)

TEST_FILE = os.path.join(
    XGB_DIR, "xgboost_test_clean.npz"
)

PREDICTION_FILE = os.path.join(
    XGB_DIR, "random_forest_test_predictions_clean.npz"
)

METRICS_FILE = os.path.join(
    XGB_DIR, "random_forest_test_metrics_clean.csv"
)


def load_dataset(path):
    data = np.load(path)

    X = data["X"]
    y = data["y"]

    print(f"Loaded: {path}")
    print(f"X shape: {X.shape}")
    print(f"y shape: {y.shape}")
    print()

    return X, y


print("=" * 70)
print("RANDOM FOREST — CLEAN TRAINING")
print("=" * 70)
print()

X_train, y_train = load_dataset(TRAIN_FILE)
X_val, y_val = load_dataset(VALIDATION_FILE)
X_test, y_test = load_dataset(TEST_FILE)

print("=" * 70)
print("DATA SUMMARY")
print("=" * 70)

print("Training:", X_train.shape, y_train.shape)
print("Validation:", X_val.shape, y_val.shape)
print("Test:", X_test.shape, y_test.shape)

print()
print("Number of features:", X_train.shape[1])
print("Number of targets:", y_train.shape[1])

print()
print("=" * 70)
print("TRAINING RANDOM FOREST MODELS")
print("=" * 70)
print()

predictions = np.zeros_like(y_test, dtype=np.float32)

metrics = []

for target_index, target_name in enumerate(TARGET_COLUMNS):

    print("-" * 70)
    print(f"TARGET: {target_name}")
    print("-" * 70)

    start_time = time.time()

    model = RandomForestRegressor(
        n_estimators=150,
        max_depth=20,
        min_samples_split=5,
        min_samples_leaf=2,
        max_features="sqrt",
        n_jobs=-1,
        random_state=42
    )

    model.fit(
        X_train,
        y_train[:, target_index]
    )

    training_time = time.time() - start_time

    prediction = model.predict(X_test)

    predictions[:, target_index] = prediction

    mae = mean_absolute_error(
        y_test[:, target_index],
        prediction
    )

    rmse = np.sqrt(
        mean_squared_error(
            y_test[:, target_index],
            prediction
        )
    )

    r2 = r2_score(
        y_test[:, target_index],
        prediction
    )

    print(f"MAE : {mae:.6f}")
    print(f"RMSE: {rmse:.6f}")
    print(f"R²  : {r2:.6f}")
    print(f"Training time: {training_time / 60:.2f} minutes")
    print()

    model_path = os.path.join(
        MODEL_DIR,
        f"random_forest_{target_name}.joblib"
    )

    import joblib
    joblib.dump(model, model_path)

    print("Model saved:")
    print(model_path)
    print()

    metrics.append({
        "target": target_name,
        "mae_scaled": mae,
        "rmse_scaled": rmse,
        "r2_scaled": r2,
        "training_time_minutes": training_time / 60
    })


overall_mae = mean_absolute_error(
    y_test,
    predictions
)

overall_rmse = np.sqrt(
    mean_squared_error(
        y_test,
        predictions
    )
)

print("=" * 70)
print("OVERALL RANDOM FOREST RESULTS — SCALED")
print("=" * 70)

print(f"Overall MAE : {overall_mae:.6f}")
print(f"Overall RMSE: {overall_rmse:.6f}")

print()
print("Saving predictions...")

np.savez_compressed(
    PREDICTION_FILE,
    predictions=predictions,
    actual=y_test
)

pd.DataFrame(metrics).to_csv(
    METRICS_FILE,
    index=False
)

print()
print("=" * 70)
print("FILES SAVED")
print("=" * 70)

print(PREDICTION_FILE)
print(METRICS_FILE)
print(MODEL_DIR)

print()
print("Done.")
