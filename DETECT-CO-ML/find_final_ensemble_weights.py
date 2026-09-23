import json
import numpy as np
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

BASE = "/home/miguel/DETECT-CO-ML/data"

INPUT = f"{BASE}/xgboost/final_ensemble_validation_real_mm.npz"
OUTPUT = f"{BASE}/xgboost/final_ensemble_weights.json"

data = np.load(INPUT, allow_pickle=True)

actual = data["actual"]
lstm = data["lstm"]
xgb = data["xgboost"]
rf = data["random_forest"]

TARGETS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

# ---------------------------------------------------------
# METRIC FUNCTION
# ---------------------------------------------------------

def metrics(pred):

    mae = mean_absolute_error(
        actual,
        pred
    )

    rmse = np.sqrt(
        mean_squared_error(
            actual,
            pred
        )
    )

    r2 = r2_score(
        actual,
        pred,
        multioutput="uniform_average"
    )

    return mae, rmse, r2


# ---------------------------------------------------------
# BASELINE MODELS
# ---------------------------------------------------------

print("=" * 75)
print("FINAL ENSEMBLE WEIGHT SEARCH")
print("=" * 75)

models = {
    "LSTM Refined 3": lstm,
    "Original XGBoost": xgb,
    "Original Random Forest": rf
}

for name, prediction in models.items():

    mae, rmse, r2 = metrics(prediction)

    print()
    print(name)
    print(f"MAE :  {mae:.6f} mm")
    print(f"RMSE:  {rmse:.6f} mm")
    print(f"R²  :  {r2:.6f}")


# ---------------------------------------------------------
# GRID SEARCH
# ---------------------------------------------------------

best_rmse = float("inf")
best_mae = None
best_r2 = None
best_weights = None
best_prediction = None

# 1% increments
for lstm_weight in np.arange(
    0.0,
    1.001,
    0.01
):

    for xgb_weight in np.arange(
        0.0,
        1.001 - lstm_weight,
        0.01
    ):

        rf_weight = (
            1.0
            - lstm_weight
            - xgb_weight
        )

        if rf_weight < -1e-9:
            continue

        prediction = (
            lstm_weight * lstm
            + xgb_weight * xgb
            + rf_weight * rf
        )

        mae, rmse, r2 = metrics(
            prediction
        )

        if rmse < best_rmse:

            best_rmse = rmse
            best_mae = mae
            best_r2 = r2
            best_weights = {
                "lstm": float(lstm_weight),
                "xgboost": float(xgb_weight),
                "random_forest": float(rf_weight)
            }
            best_prediction = prediction.copy()


# ---------------------------------------------------------
# RESULTS
# ---------------------------------------------------------

print()
print("=" * 75)
print("BEST VALIDATION WEIGHTS")
print("=" * 75)

print(
    f"LSTM Refined 3      : "
    f"{best_weights['lstm']:.2f}"
)

print(
    f"Original XGBoost    : "
    f"{best_weights['xgboost']:.2f}"
)

print(
    f"Original Random Forest: "
    f"{best_weights['random_forest']:.2f}"
)

print()
print(f"Weight sum: {sum(best_weights.values()):.2f}")

print()
print("Overall validation metrics:")
print(f"MAE :  {best_mae:.6f} mm")
print(f"RMSE:  {best_rmse:.6f} mm")
print(f"R²  :  {best_r2:.6f}")


# ---------------------------------------------------------
# PER-TARGET METRICS
# ---------------------------------------------------------

print()
print("=" * 75)
print("PER-TARGET ENSEMBLE RESULTS")
print("=" * 75)

for i, target in enumerate(TARGETS):

    mae = mean_absolute_error(
        actual[:, i],
        best_prediction[:, i]
    )

    rmse = np.sqrt(
        mean_squared_error(
            actual[:, i],
            best_prediction[:, i]
        )
    )

    r2 = r2_score(
        actual[:, i],
        best_prediction[:, i]
    )

    print()
    print(target)
    print(f"MAE :  {mae:.6f} mm")
    print(f"RMSE:  {rmse:.6f} mm")
    print(f"R²  :  {r2:.6f}")


# ---------------------------------------------------------
# SAVE WEIGHTS
# ---------------------------------------------------------

results = {
    "selection_dataset": "validation",
    "optimization_metric": "overall_rmse",
    "weight_step": 0.01,
    "weights": best_weights,
    "validation_metrics": {
        "mae_mm": float(best_mae),
        "rmse_mm": float(best_rmse),
        "r2": float(best_r2)
    },
    "models": {
        "lstm": "refined_lstm/lstm_refined_3.keras",
        "xgboost": "xgboost/xgboost_rainfall_*_mm.json",
        "random_forest": "random_forest/random_forest_rainfall_*_mm.joblib"
    }
}

with open(
    OUTPUT,
    "w"
) as f:

    json.dump(
        results,
        f,
        indent=4
    )

print()
print("=" * 75)
print("SAVED")
print("=" * 75)
print(OUTPUT)
print()
print("These weights will be frozen before test evaluation.")
