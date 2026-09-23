
import joblib
import numpy as np
import pandas as pd
import xgboost as xgb
import tensorflow as tf
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

BASE = "/home/miguel/DETECT-CO-ML/data"

weather_file = f"{BASE}/calamba_weather_features.csv"
xgb_val_file = f"{BASE}/xgboost/xgboost_validation_clean.npz"
lstm_val_file = f"{BASE}/lstm_validation_clean.npz"
scaler_dir = f"{BASE}/lstm_scalers"

targets = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

# ---------------------------------------------------------
# LOAD VALIDATION DATA
# ---------------------------------------------------------
print("=" * 70)
print("LOADING VALIDATION DATA")
print("=" * 70)

lstm_data = np.load(lstm_val_file, allow_pickle=True)
xgb_data = np.load(xgb_val_file, allow_pickle=True)

X_lstm = lstm_data["X"]
X_xgb = xgb_data["X"]

timestamps = pd.to_datetime(lstm_data["timestamps"])
latitude = np.asarray(lstm_data["latitude"], dtype=float)
longitude = np.asarray(lstm_data["longitude"], dtype=float)

print("LSTM X:", X_lstm.shape)
print("XGB/RF X:", X_xgb.shape)

# ---------------------------------------------------------
# LOAD TRAINING-ONLY SCALERS
# ---------------------------------------------------------
locations = [
    (14.15, 121.05),
    (14.15, 121.15),
    (14.25, 121.05),
    (14.25, 121.15)
]

scalers = {}

for lat, lon in locations:
    key = f"{lat:.2f}_{lon:.2f}"
    path = f"{scaler_dir}/scaler_{key}.joblib"
    scalers[key] = joblib.load(path)

print("Loaded", len(scalers), "training-only scalers.")

# ---------------------------------------------------------
# LOAD ACTUAL OPEN-METEO TARGETS
# ---------------------------------------------------------
weather = pd.read_csv(weather_file)
weather["timestamp"] = pd.to_datetime(weather["timestamp"])
weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

lookup = {}

for _, row in weather.iterrows():
    key = (
        str(row["timestamp"])
        + "_"
        + f"{row['latitude']:.2f}"
        + "_"
        + f"{row['longitude']:.2f}"
    )

    lookup[key] = np.array(
        [row[t] for t in targets],
        dtype=float
    )

actual = []

for ts, lat, lon in zip(timestamps, latitude, longitude):
    key = (
        str(ts)
        + "_"
        + f"{lat:.2f}"
        + "_"
        + f"{lon:.2f}"
    )

    if key not in lookup:
        raise ValueError(f"Missing actual target: {key}")

    actual.append(lookup[key])

actual = np.asarray(actual)

print("Actual shape:", actual.shape)
print("Missing actuals:", np.isnan(actual).sum())

# ---------------------------------------------------------
# INVERSE TARGET SCALING
# ---------------------------------------------------------
def inverse_targets(pred_scaled):
    pred_scaled = np.asarray(pred_scaled)
    result = np.zeros_like(pred_scaled, dtype=float)

    for i, (lat, lon) in enumerate(zip(latitude, longitude)):
        key = f"{lat:.2f}_{lon:.2f}"
        scaler = scalers[key]

        for j in range(5):
            result[i, j] = (
                pred_scaled[i, j]
                * (scaler.data_max_[j + 2] - scaler.data_min_[j + 2])
                + scaler.data_min_[j + 2]
            )

    return result

# ---------------------------------------------------------
# EVALUATION
# ---------------------------------------------------------
def evaluate(name, predictions):
    print()
    print("=" * 70)
    print(name)
    print("=" * 70)

    all_true = actual.reshape(-1)
    all_pred = predictions.reshape(-1)

    for j, target in enumerate(targets):
        y_true = actual[:, j]
        y_pred = predictions[:, j]

        mae = mean_absolute_error(y_true, y_pred)
        rmse = np.sqrt(mean_squared_error(y_true, y_pred))
        r2 = r2_score(y_true, y_pred)

        print(
            f"{target:20s}"
            f" MAE={mae:.4f}"
            f" RMSE={rmse:.4f}"
            f" R2={r2:.4f}"
        )

    overall_mae = mean_absolute_error(all_true, all_pred)
    overall_rmse = np.sqrt(mean_squared_error(all_true, all_pred))

    print()
    print(f"Overall MAE : {overall_mae:.4f}")
    print(f"Overall RMSE: {overall_rmse:.4f}")

    print()
    print("Prediction means:")
    print(np.mean(predictions, axis=0))

    print("Actual means:")
    print(np.mean(actual, axis=0))

    print()
    print("Prediction maxima:")
    print(np.max(predictions, axis=0))

    print("Actual maxima:")
    print(np.max(actual, axis=0))

# ---------------------------------------------------------
# LSTM
# ---------------------------------------------------------
def run_lstm(path, name):
    print()
    print("=" * 70)
    print("LOADING", name)
    print("=" * 70)

    model = tf.keras.models.load_model(path, compile=False)

    pred_scaled = model.predict(
        X_lstm,
        batch_size=128,
        verbose=1
    )

    pred = inverse_targets(pred_scaled)

    evaluate(name, pred)

    return pred

original_lstm = run_lstm(
    f"{BASE}/models/lstm_rainfall_model.keras",
    "ORIGINAL LSTM"
)

refined_lstm = run_lstm(
    f"{BASE}/models/refined_lstm/lstm_refined_3.keras",
    "REFINED LSTM 3"
)

# ---------------------------------------------------------
# XGBOOST
# ---------------------------------------------------------
def run_xgb(directory, filenames, name):
    predictions = []

    print()
    print("=" * 70)
    print("LOADING", name)
    print("=" * 70)

    for filename in filenames:
        path = f"{directory}/{filename}"

        model = xgb.XGBRegressor()
        model.load_model(path)

        predictions.append(model.predict(X_xgb))

    pred_scaled = np.column_stack(predictions)
    pred = inverse_targets(pred_scaled)

    evaluate(name, pred)

    return pred

xgb_original_files = [
    "xgboost_rainfall_1h_mm.json",
    "xgboost_rainfall_3h_mm.json",
    "xgboost_rainfall_6h_mm.json",
    "xgboost_rainfall_12h_mm.json",
    "xgboost_rainfall_24h_mm.json"
]

xgb_refined_files = [
    "xgb_refined_3_1h.json",
    "xgb_refined_3_3h.json",
    "xgb_refined_3_6h.json",
    "xgb_refined_3_12h.json",
    "xgb_refined_3_24h.json"
]

original_xgb = run_xgb(
    f"{BASE}/models/xgboost",
    xgb_original_files,
    "ORIGINAL XGBOOST"
)

refined_xgb = run_xgb(
    f"{BASE}/models/refined",
    xgb_refined_files,
    "REFINED XGBOOST 3"
)

# ---------------------------------------------------------
# RANDOM FOREST
# ---------------------------------------------------------
def run_rf(directory, filenames, name):
    predictions = []

    print()
    print("=" * 70)
    print("LOADING", name)
    print("=" * 70)

    for filename in filenames:
        path = f"{directory}/{filename}"
        model = joblib.load(path)
        predictions.append(model.predict(X_xgb))

    pred_scaled = np.column_stack(predictions)
    pred = inverse_targets(pred_scaled)

    evaluate(name, pred)

    return pred

rf_original_files = [
    "random_forest_rainfall_1h_mm.joblib",
    "random_forest_rainfall_3h_mm.joblib",
    "random_forest_rainfall_6h_mm.joblib",
    "random_forest_rainfall_12h_mm.joblib",
    "random_forest_rainfall_24h_mm.joblib"
]

rf_refined_files = [
    "rf_refined_1_1h.joblib",
    "rf_refined_1_3h.joblib",
    "rf_refined_1_6h.joblib",
    "rf_refined_1_12h.joblib",
    "rf_refined_1_24h.joblib"
]

original_rf = run_rf(
    f"{BASE}/models/random_forest",
    rf_original_files,
    "ORIGINAL RANDOM FOREST"
)

refined_rf = run_rf(
    f"{BASE}/models/refined",
    rf_refined_files,
    "REFINED RANDOM FOREST 1"
)

# ---------------------------------------------------------
# SAVE
# ---------------------------------------------------------
output = f"{BASE}/xgboost/original_vs_refined_validation.npz"

np.savez(
    output,
    actual=actual,
    original_lstm=original_lstm,
    refined_lstm=refined_lstm,
    original_xgb=original_xgb,
    refined_xgb=refined_xgb,
    original_rf=original_rf,
    refined_rf=refined_rf,
    timestamps=np.asarray(timestamps.astype(str)),
    latitude=latitude,
    longitude=longitude
)

print()
print("=" * 70)
print("COMPARISON COMPLETE")
print("=" * 70)
print("Saved:", output)
