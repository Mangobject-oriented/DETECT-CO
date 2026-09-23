import json
import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

BASE = "/home/miguel/DETECT-CO-ML/data"

WEIGHTS_FILE = f"{BASE}/xgboost/final_ensemble_weights.json"

TEST_LSTM_FILE = f"{BASE}/lstm_test_predictions.npz"
TEST_XGB_FILE = f"{BASE}/xgboost/xgboost_test_predictions_clean_mm.npz"
TEST_RF_FILE = f"{BASE}/xgboost/random_forest_test_predictions_clean_mm.npz"

SCALER_DIR = f"{BASE}/lstm_scalers"
WEATHER_FILE = f"{BASE}/calamba_weather_features.csv"

OUTPUT_NPZ = f"{BASE}/xgboost/final_ensemble_test_predictions.npz"
OUTPUT_CSV = f"{BASE}/xgboost/final_ensemble_test_metrics.csv"

TARGETS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

TARGET_INDICES = {
    "rainfall_1h_mm": 2,
    "rainfall_3h_mm": 3,
    "rainfall_6h_mm": 4,
    "rainfall_12h_mm": 5,
    "rainfall_24h_mm": 6
}

# ---------------------------------------------------------
# LOAD FROZEN VALIDATION WEIGHTS
# ---------------------------------------------------------

with open(WEIGHTS_FILE, "r") as f:
    weight_data = json.load(f)

weights = weight_data["weights"]

lstm_weight = weights["lstm"]
xgb_weight = weights["xgboost"]
rf_weight = weights["random_forest"]

print("=" * 75)
print("FINAL TEST ENSEMBLE")
print("=" * 75)

print()
print("FROZEN VALIDATION WEIGHTS:")
print(f"LSTM Refined 3        : {lstm_weight:.2f}")
print(f"Original XGBoost      : {xgb_weight:.2f}")
print(f"Original Random Forest: {rf_weight:.2f}")
print(f"Weight sum            : {sum(weights.values()):.2f}")

# ---------------------------------------------------------
# LOAD TEST DATA
# ---------------------------------------------------------

lstm_data = np.load(
    TEST_LSTM_FILE,
    allow_pickle=True
)

xgb_data = np.load(
    TEST_XGB_FILE,
    allow_pickle=True
)

rf_data = np.load(
    TEST_RF_FILE,
    allow_pickle=True
)

# ---------------------------------------------------------
# LOAD LSTM TEST PREDICTIONS
# ---------------------------------------------------------

lstm_scaled = lstm_data["predictions"]

timestamps = pd.to_datetime(
    lstm_data["timestamps"]
)

latitude = np.round(
    lstm_data["latitude"].astype(float),
    2
)

longitude = np.round(
    lstm_data["longitude"].astype(float),
    2
)

print()
print("Raw LSTM prediction shape:", lstm_scaled.shape)

# ---------------------------------------------------------
# LOAD TRAINING-ONLY SCALERS
# ---------------------------------------------------------

scalers = {}

locations = sorted(
    set(zip(latitude, longitude))
)

for lat, lon in locations:

    path = (
        f"{SCALER_DIR}/"
        f"scaler_{lat:.2f}_{lon:.2f}.joblib"
    )

    scalers[(lat, lon)] = joblib.load(path)

print("Loaded training-only scalers:", len(scalers))

# ---------------------------------------------------------
# INVERSE TRANSFORM LSTM
# ---------------------------------------------------------

lstm = np.zeros_like(
    lstm_scaled,
    dtype=np.float64
)

for lat, lon in locations:

    mask = (
        (latitude == lat) &
        (longitude == lon)
    )

    scaler = scalers[(lat, lon)]

    for j, target in enumerate(TARGETS):

        idx = TARGET_INDICES[target]

        lstm[mask, j] = (
            lstm_scaled[mask, j]
            - scaler.min_[idx]
        ) / scaler.scale_[idx]

lstm = np.maximum(
    lstm,
    0
)

print()
print("LSTM predictions converted to real mm.")

# ---------------------------------------------------------
# LOAD XGBOOST / RANDOM FOREST
# ---------------------------------------------------------

xgb = xgb_data["predictions"]

rf = rf_data["predictions_mm"]

stored_actual = xgb_data["actual"]

print()
print("TEST SHAPES:")
print("LSTM:", lstm.shape)
print("XGBoost:", xgb.shape)
print("Random Forest:", rf.shape)
print("Stored Actual:", stored_actual.shape)

# ---------------------------------------------------------
# VERIFY SHAPES
# ---------------------------------------------------------

if not (
    lstm.shape == xgb.shape == rf.shape == stored_actual.shape
):
    raise RuntimeError(
        "Prediction/actual shapes do not match."
    )

# ---------------------------------------------------------
# VERIFY OPEN-METEO ACTUALS
# ---------------------------------------------------------

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

actual_lookup = weather[
    [
        "timestamp",
        "latitude",
        "longitude"
    ] + TARGETS
].copy()

test_keys = pd.DataFrame({
    "timestamp": timestamps,
    "latitude": np.round(latitude, 2),
    "longitude": np.round(longitude, 2)
})

test_keys["_test_order"] = np.arange(len(test_keys))

verified = test_keys.merge(
    actual_lookup,
    on=[
        "timestamp",
        "latitude",
        "longitude"
    ],
    how="left",
    sort=False
)

verified = verified.sort_values("_test_order")

verified_actual = verified[
    TARGETS
].to_numpy(
    dtype=np.float64
)

if np.isnan(verified_actual).any():
    raise RuntimeError(
        "Missing Open-Meteo test actual values."
    )

actual = verified_actual

if np.isnan(actual).any():
    raise RuntimeError(
        "Open-Meteo test actual values contain missing data."
    )

print()
print("Open-Meteo test actual verification: PASSED")
print("Missing actual values: 0")

# ---------------------------------------------------------
# CHECK MODEL MEANS BEFORE ENSEMBLE
# ---------------------------------------------------------

print()
print("=" * 75)
print("MODEL TEST PREDICTION MEANS")
print("=" * 75)

print()
print("Actual:")
print(np.mean(actual, axis=0))

print()
print("LSTM Refined 3:")
print(np.mean(lstm, axis=0))

print()
print("Original XGBoost:")
print(np.mean(xgb, axis=0))

print()
print("Original Random Forest:")
print(np.mean(rf, axis=0))

# ---------------------------------------------------------
# FINAL ENSEMBLE
# ---------------------------------------------------------

ensemble = (
    lstm_weight * lstm
    + xgb_weight * xgb
    + rf_weight * rf
)

ensemble = np.maximum(
    ensemble,
    0
)

# ---------------------------------------------------------
# FINAL RESULTS
# ---------------------------------------------------------

rows = []

print()
print("=" * 75)
print("FINAL TEST RESULTS")
print("=" * 75)

for i, target in enumerate(TARGETS):

    actual_i = actual[:, i]
    pred_i = ensemble[:, i]

    mae = mean_absolute_error(
        actual_i,
        pred_i
    )

    rmse = np.sqrt(
        mean_squared_error(
            actual_i,
            pred_i
        )
    )

    r2 = r2_score(
        actual_i,
        pred_i
    )

    actual_mean = np.mean(actual_i)
    pred_mean = np.mean(pred_i)

    actual_max = np.max(actual_i)
    pred_max = np.max(pred_i)

    rows.append({
        "target": target,
        "MAE_mm": mae,
        "RMSE_mm": rmse,
        "R2": r2,
        "actual_mean_mm": actual_mean,
        "predicted_mean_mm": pred_mean,
        "actual_max_mm": actual_max,
        "predicted_max_mm": pred_max
    })

    print()
    print(target)
    print(f"MAE : {mae:.6f} mm")
    print(f"RMSE: {rmse:.6f} mm")
    print(f"R²  : {r2:.6f}")
    print(f"Actual mean: {actual_mean:.6f} mm")
    print(f"Pred mean  : {pred_mean:.6f} mm")
    print(f"Actual max : {actual_max:.6f} mm")
    print(f"Pred max   : {pred_max:.6f} mm")

# ---------------------------------------------------------
# OVERALL METRICS
# ---------------------------------------------------------

overall_mae = mean_absolute_error(
    actual,
    ensemble
)

overall_rmse = np.sqrt(
    mean_squared_error(
        actual,
        ensemble
    )
)

overall_r2 = r2_score(
    actual,
    ensemble,
    multioutput="uniform_average"
)

print()
print("=" * 75)
print("OVERALL TEST PERFORMANCE")
print("=" * 75)

print(f"MAE : {overall_mae:.6f} mm")
print(f"RMSE: {overall_rmse:.6f} mm")
print(f"R²  : {overall_r2:.6f}")

# ---------------------------------------------------------
# SAVE CSV
# ---------------------------------------------------------

metrics_df = pd.DataFrame(rows)

metrics_df.loc[len(metrics_df)] = {
    "target": "OVERALL",
    "MAE_mm": overall_mae,
    "RMSE_mm": overall_rmse,
    "R2": overall_r2,
    "actual_mean_mm": np.mean(actual),
    "predicted_mean_mm": np.mean(ensemble),
    "actual_max_mm": np.max(actual),
    "predicted_max_mm": np.max(ensemble)
}

metrics_df.to_csv(
    OUTPUT_CSV,
    index=False
)

# ---------------------------------------------------------
# SAVE PREDICTIONS
# ---------------------------------------------------------

np.savez_compressed(
    OUTPUT_NPZ,
    predictions=ensemble,
    actual=actual,
    lstm=lstm,
    xgboost=xgb,
    random_forest=rf,
    timestamps=np.asarray(
        timestamps.astype(str)
    ),
    latitude=latitude,
    longitude=longitude,
    target_columns=np.array(TARGETS),
    lstm_weight=lstm_weight,
    xgboost_weight=xgb_weight,
    random_forest_weight=rf_weight
)

print()
print("=" * 75)
print("FILES SAVED")
print("=" * 75)

print(OUTPUT_NPZ)
print(OUTPUT_CSV)

print()
print("FINAL ENSEMBLE TEST EVALUATION COMPLETE.")
