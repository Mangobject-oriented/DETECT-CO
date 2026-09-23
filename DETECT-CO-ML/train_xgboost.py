#!/usr/bin/env python3

import os
import time
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import (
    mean_absolute_error,
    mean_squared_error,
    r2_score
)

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
XGB_DIR = os.path.join(DATA_DIR, "xgboost")
MODEL_DIR = os.path.join(DATA_DIR, "models", "xgboost")

os.makedirs(MODEL_DIR, exist_ok=True)

# ---------------------------------------------------------
# TARGETS
# ---------------------------------------------------------

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

# ---------------------------------------------------------
# LOAD DATA
# ---------------------------------------------------------

print("=" * 70)
print("DETECT-CO — XGBOOST TRAINING")
print("=" * 70)

print()
print("Loading datasets...")

train = np.load(
    os.path.join(
        XGB_DIR,
        "xgboost_train.npz"
    ),
    allow_pickle=True
)

validation = np.load(
    os.path.join(
        XGB_DIR,
        "xgboost_validation.npz"
    ),
    allow_pickle=True
)

test = np.load(
    os.path.join(
        XGB_DIR,
        "xgboost_test.npz"
    ),
    allow_pickle=True
)

X_train = train["X"]
y_train = train["y"]

X_validation = validation["X"]
y_validation = validation["y"]

X_test = test["X"]
y_test = test["y"]

print()
print("Train:")
print("X:", X_train.shape)
print("y:", y_train.shape)

print()
print("Validation:")
print("X:", X_validation.shape)
print("y:", y_validation.shape)

print()
print("Test:")
print("X:", X_test.shape)
print("y:", y_test.shape)

# ---------------------------------------------------------
# XGBOOST PARAMETERS
# ---------------------------------------------------------

PARAMETERS = {
    "objective": "reg:squarederror",
    "n_estimators": 1000,
    "learning_rate": 0.03,
    "max_depth": 6,
    "min_child_weight": 3,
    "subsample": 0.8,
    "colsample_bytree": 0.8,
    "reg_alpha": 0.0,
    "reg_lambda": 1.0,
    "tree_method": "hist",
    "n_jobs": 4,
    "random_state": 42
}

print()
print("=" * 70)
print("XGBOOST PARAMETERS")
print("=" * 70)

for key, value in PARAMETERS.items():
    print(f"{key}: {value}")

# ---------------------------------------------------------
# TRAIN FIVE MODELS
# ---------------------------------------------------------

all_predictions = np.zeros_like(
    y_test,
    dtype=np.float32
)

results = []

total_start = time.time()

for target_index, target_name in enumerate(
    TARGET_COLUMNS
):

    print()
    print("=" * 70)
    print(
        f"TRAINING {target_index + 1}/5: "
        f"{target_name}"
    )
    print("=" * 70)

    y_train_target = y_train[
        :, target_index
    ]

    y_validation_target = y_validation[
        :, target_index
    ]

    y_test_target = y_test[
        :, target_index
    ]

    print()
    print(
        "Training target range:",
        f"{y_train_target.min():.4f} - "
        f"{y_train_target.max():.4f} mm"
    )

    print(
        "Validation target range:",
        f"{y_validation_target.min():.4f} - "
        f"{y_validation_target.max():.4f} mm"
    )

    start = time.time()

    model = xgb.XGBRegressor(
        **PARAMETERS,
        early_stopping_rounds=50
    )

    model.fit(
        X_train,
        y_train_target,
        eval_set=[
            (
                X_validation,
                y_validation_target
            )
        ],
        verbose=50
    )

    elapsed = time.time() - start

    # -----------------------------------------------------
    # PREDICTION
    # -----------------------------------------------------

    predictions = model.predict(
        X_test
    )

    predictions = np.maximum(
        predictions,
        0
    )

    all_predictions[
        :, target_index
    ] = predictions

    # -----------------------------------------------------
    # TEST METRICS
    # -----------------------------------------------------

    mae = mean_absolute_error(
        y_test_target,
        predictions
    )

    rmse = np.sqrt(
        mean_squared_error(
            y_test_target,
            predictions
        )
    )

    r2 = r2_score(
        y_test_target,
        predictions
    )

    results.append({
        "target": target_name,
        "MAE_mm": mae,
        "RMSE_mm": rmse,
        "R2": r2,
        "best_iteration": (
            model.best_iteration
            if model.best_iteration is not None
            else -1
        ),
        "training_time_seconds": elapsed
    })

    # -----------------------------------------------------
    # SAVE MODEL
    # -----------------------------------------------------

    model_file = os.path.join(
        MODEL_DIR,
        f"xgboost_{target_name}.json"
    )

    model.save_model(
        model_file
    )

    print()
    print("TEST RESULTS")
    print(
        f"MAE : {mae:.4f} mm"
    )
    print(
        f"RMSE: {rmse:.4f} mm"
    )
    print(
        f"R²  : {r2:.4f}"
    )
    print(
        "Best iteration:",
        model.best_iteration
    )
    print(
        f"Training time: {elapsed / 60:.2f} minutes"
    )

    print()
    print("Model saved:")
    print(model_file)

# ---------------------------------------------------------
# OVERALL RESULTS
# ---------------------------------------------------------

overall_mae = mean_absolute_error(
    y_test,
    all_predictions
)

overall_rmse = np.sqrt(
    mean_squared_error(
        y_test,
        all_predictions
    )
)

print()
print("=" * 70)
print("XGBOOST TEST RESULTS")
print("=" * 70)

for result in results:

    print()
    print(result["target"])

    print(
        f"  MAE : "
        f"{result['MAE_mm']:.4f} mm"
    )

    print(
        f"  RMSE: "
        f"{result['RMSE_mm']:.4f} mm"
    )

    print(
        f"  R²  : "
        f"{result['R2']:.4f}"
    )

    print(
        f"  Best iteration: "
        f"{result['best_iteration']}"
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
# SAVE PREDICTIONS
# ---------------------------------------------------------

prediction_file = os.path.join(
    XGB_DIR,
    "xgboost_test_predictions.npz"
)

np.savez_compressed(
    prediction_file,
    predictions=all_predictions,
    actual=y_test,
    timestamps=test["timestamps"],
    latitude=test["latitude"],
    longitude=test["longitude"],
    target_columns=np.array(TARGET_COLUMNS)
)

# ---------------------------------------------------------
# SAVE METRICS
# ---------------------------------------------------------

metrics_file = os.path.join(
    XGB_DIR,
    "xgboost_test_metrics.csv"
)

pd.DataFrame(
    results
).to_csv(
    metrics_file,
    index=False
)

total_elapsed = time.time() - total_start

print()
print("=" * 70)
print("FILES SAVED")
print("=" * 70)

print()
print(prediction_file)
print(metrics_file)
print(MODEL_DIR)

print()
print(
    f"Total training time: "
    f"{total_elapsed / 60:.2f} minutes"
)

print()
print("Done.")
