import os
import json
import time
import numpy as np

from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from xgboost import XGBRegressor


BASE = "/home/miguel/DETECT-CO-ML/data/xgboost"

TRAIN_FILE = os.path.join(BASE, "xgboost_train_clean.npz")
VAL_FILE = os.path.join(BASE, "xgboost_validation_clean.npz")

MODEL_DIR = "/home/miguel/DETECT-CO-ML/data/models/refined"
os.makedirs(MODEL_DIR, exist_ok=True)


# ---------------------------------------------------------
# LOAD DATA
# ---------------------------------------------------------

print("=" * 70)
print("LOADING CLEAN DATA")
print("=" * 70)

train = np.load(TRAIN_FILE)
val = np.load(VAL_FILE)

X_train = train["X"]
y_train = train["y"]

X_val = val["X"]
y_val = val["y"]

print("Train X:", X_train.shape)
print("Train y:", y_train.shape)
print("Val X:  ", X_val.shape)
print("Val y:  ", y_val.shape)


# ---------------------------------------------------------
# TARGETS
# ---------------------------------------------------------

targets = [
    "1h",
    "3h",
    "6h",
    "12h",
    "24h"
]


# ---------------------------------------------------------
# METRICS
# ---------------------------------------------------------

def evaluate(y_true, y_pred):

    mae = mean_absolute_error(y_true, y_pred)

    rmse = np.sqrt(
        mean_squared_error(y_true, y_pred)
    )

    r2 = r2_score(y_true, y_pred)

    return mae, rmse, r2


# ---------------------------------------------------------
# XGBOOST CONFIGURATIONS
# ---------------------------------------------------------

xgb_configs = [

    {
        "name": "xgb_refined_1",
        "n_estimators": 500,
        "max_depth": 6,
        "learning_rate": 0.05,
        "subsample": 0.85,
        "colsample_bytree": 0.85,
        "min_child_weight": 3,
        "reg_alpha": 0.0,
        "reg_lambda": 1.0
    },

    {
        "name": "xgb_refined_2",
        "n_estimators": 600,
        "max_depth": 5,
        "learning_rate": 0.04,
        "subsample": 0.9,
        "colsample_bytree": 0.9,
        "min_child_weight": 2,
        "reg_alpha": 0.0,
        "reg_lambda": 1.5
    },

    {
        "name": "xgb_refined_3",
        "n_estimators": 450,
        "max_depth": 7,
        "learning_rate": 0.05,
        "subsample": 0.85,
        "colsample_bytree": 0.9,
        "min_child_weight": 4,
        "reg_alpha": 0.05,
        "reg_lambda": 1.5
    }
]


# ---------------------------------------------------------
# RANDOM FOREST CONFIGURATIONS
# ---------------------------------------------------------

rf_configs = [

    {
        "name": "rf_refined_1",
        "n_estimators": 250,
        "max_depth": 24,
        "min_samples_split": 4,
        "min_samples_leaf": 2,
        "max_features": "sqrt"
    },

    {
        "name": "rf_refined_2",
        "n_estimators": 250,
        "max_depth": 30,
        "min_samples_split": 4,
        "min_samples_leaf": 1,
        "max_features": "sqrt"
    },

    {
        "name": "rf_refined_3",
        "n_estimators": 250,
        "max_depth": 22,
        "min_samples_split": 3,
        "min_samples_leaf": 2,
        "max_features": 0.8
    }
]


results = []


# ---------------------------------------------------------
# XGBOOST
# ---------------------------------------------------------

print()
print("=" * 70)
print("REFINING XGBOOST")
print("=" * 70)

for config in xgb_configs:

    print()
    print("-" * 70)
    print("Configuration:", config["name"])
    print("-" * 70)

    all_predictions = np.zeros_like(y_val, dtype=np.float32)

    start_time = time.time()

    for i, target in enumerate(targets):

        print(f"Training XGBoost target: {target}")

        model = XGBRegressor(
            objective="reg:squarederror",
            n_estimators=config["n_estimators"],
            max_depth=config["max_depth"],
            learning_rate=config["learning_rate"],
            subsample=config["subsample"],
            colsample_bytree=config["colsample_bytree"],
            min_child_weight=config["min_child_weight"],
            reg_alpha=config["reg_alpha"],
            reg_lambda=config["reg_lambda"],
            tree_method="hist",
            n_jobs=-1,
            random_state=42
        )

        model.fit(
            X_train,
            y_train[:, i],
            verbose=False
        )

        all_predictions[:, i] = model.predict(X_val)

        model_path = os.path.join(
            MODEL_DIR,
            f"{config['name']}_{target}.json"
        )

        model.save_model(model_path)

    elapsed = time.time() - start_time

    print(f"\nCompleted in {elapsed / 60:.2f} minutes")

    total_mae = 0
    total_rmse = 0

    for i, target in enumerate(targets):

        mae, rmse, r2 = evaluate(
            y_val[:, i],
            all_predictions[:, i]
        )

        total_mae += mae
        total_rmse += rmse

        print(
            f"{target:>3} | "
            f"MAE={mae:.6f} | "
            f"RMSE={rmse:.6f} | "
            f"R2={r2:.6f}"
        )

    avg_mae = total_mae / len(targets)
    avg_rmse = total_rmse / len(targets)

    results.append({
        "model": config["name"],
        "type": "XGBoost",
        "average_mae": avg_mae,
        "average_rmse": avg_rmse
    })


# ---------------------------------------------------------
# RANDOM FOREST
# ---------------------------------------------------------

print()
print("=" * 70)
print("REFINING RANDOM FOREST")
print("=" * 70)

for config in rf_configs:

    print()
    print("-" * 70)
    print("Configuration:", config["name"])
    print("-" * 70)

    all_predictions = np.zeros_like(y_val, dtype=np.float32)

    start_time = time.time()

    for i, target in enumerate(targets):

        print(f"Training Random Forest target: {target}")

        model = RandomForestRegressor(
            n_estimators=config["n_estimators"],
            max_depth=config["max_depth"],
            min_samples_split=config["min_samples_split"],
            min_samples_leaf=config["min_samples_leaf"],
            max_features=config["max_features"],
            n_jobs=-1,
            random_state=42
        )

        model.fit(
            X_train,
            y_train[:, i]
        )

        all_predictions[:, i] = model.predict(X_val)

        model_path = os.path.join(
            MODEL_DIR,
            f"{config['name']}_{target}.joblib"
        )

        import joblib
        joblib.dump(model, model_path)

    elapsed = time.time() - start_time

    print(f"\nCompleted in {elapsed / 60:.2f} minutes")

    total_mae = 0
    total_rmse = 0

    for i, target in enumerate(targets):

        mae, rmse, r2 = evaluate(
            y_val[:, i],
            all_predictions[:, i]
        )

        total_mae += mae
        total_rmse += rmse

        print(
            f"{target:>3} | "
            f"MAE={mae:.6f} | "
            f"RMSE={rmse:.6f} | "
            f"R2={r2:.6f}"
        )

    avg_mae = total_mae / len(targets)
    avg_rmse = total_rmse / len(targets)

    results.append({
        "model": config["name"],
        "type": "Random Forest",
        "average_mae": avg_mae,
        "average_rmse": avg_rmse
    })


# ---------------------------------------------------------
# SAVE RESULTS
# ---------------------------------------------------------

results.sort(
    key=lambda x: x["average_rmse"]
)

results_path = os.path.join(
    MODEL_DIR,
    "refinement_results.json"
)

with open(results_path, "w") as f:
    json.dump(results, f, indent=4)


# ---------------------------------------------------------
# DISPLAY FINAL RANKING
# ---------------------------------------------------------

print()
print("=" * 70)
print("REFINEMENT RESULTS")
print("=" * 70)

for rank, result in enumerate(results, start=1):

    print(
        f"{rank}. "
        f"{result['model']:20s} | "
        f"MAE={result['average_mae']:.6f} | "
        f"RMSE={result['average_rmse']:.6f}"
    )

print()
print("Results saved to:")
print(results_path)

print()
print("Refined models saved to:")
print(MODEL_DIR)
