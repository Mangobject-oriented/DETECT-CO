import os
import json
import joblib
import numpy as np
import pandas as pd

from tensorflow.keras.models import load_model
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score


# ============================================================
# PATHS
# ============================================================

BASE = "/home/miguel/DETECT-CO-ML/data"

LSTM_VAL = os.path.join(
    BASE,
    "lstm_validation_clean.npz"
)

XGB_VAL = os.path.join(
    BASE,
    "xgboost",
    "xgboost_validation_clean.npz"
)

WEATHER_FILE = os.path.join(
    BASE,
    "calamba_weather_features.csv"
)

SCALER_DIR = os.path.join(
    BASE,
    "lstm_scalers"
)

REFINED_LSTM_DIR = os.path.join(
    BASE,
    "models",
    "refined_lstm"
)

REFINED_MODEL_DIR = os.path.join(
    BASE,
    "models",
    "refined"
)

OUTPUT_DIR = os.path.join(
    BASE,
    "xgboost"
)

os.makedirs(OUTPUT_DIR, exist_ok=True)


# ============================================================
# TARGETS
# ============================================================

targets = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]


# ============================================================
# LOAD VALIDATION DATA
# ============================================================

print("=" * 70)
print("LOADING VALIDATION DATA")
print("=" * 70)

lstm_val = np.load(LSTM_VAL)
xgb_val = np.load(XGB_VAL)

X_lstm_val = lstm_val["X"].astype(np.float32)

timestamps = lstm_val["timestamps"]
latitude = lstm_val["latitude"]
longitude = lstm_val["longitude"]

print("LSTM validation X:", X_lstm_val.shape)
print("Timestamps:", len(timestamps))


# ============================================================
# LOAD WEATHER DATA
# ============================================================

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

print("Weather rows:", len(weather))


# ============================================================
# LOAD TRAINING-ONLY SCALERS
# ============================================================

scalers = {}

for lat, lon in sorted(
    set(
        zip(
            latitude,
            longitude
        )
    )
):

    lat = round(float(lat), 2)
    lon = round(float(lon), 2)

    scaler_file = os.path.join(
        SCALER_DIR,
        f"scaler_{lat:.2f}_{lon:.2f}.joblib"
    )

    scalers[
        (lat, lon)
    ] = joblib.load(scaler_file)


# ============================================================
# HELPER: CONVERT SCALED TARGETS TO MM
# ============================================================

def inverse_targets(predictions, latitudes, longitudes):

    result = np.zeros_like(
        predictions,
        dtype=np.float32
    )

    for location in scalers:

        lat, lon = location

        mask = (
            (np.round(latitudes, 2) == lat)
            &
            (np.round(longitudes, 2) == lon)
        )

        if not np.any(mask):
            continue

        scaler = scalers[location]

        # Target columns in the scaler:
        # temperature = 0
        # humidity    = 1
        # rainfall    = 2
        # rainfall3h  = 3
        # rainfall6h  = 4
        # rainfall12h = 5
        # rainfall24h = 6

        for j in range(5):

            scaled = predictions[mask, j]

            dummy = np.zeros(
                (len(scaled), 14),
                dtype=np.float32
            )

            dummy[:, 2 + j] = scaled

            inverse = scaler.inverse_transform(
                dummy
            )[:, 2 + j]

            result[mask, j] = inverse

    return result


# ============================================================
# 1. LSTM
# ============================================================

print()
print("=" * 70)
print("GENERATING REFINED LSTM VALIDATION PREDICTIONS")
print("=" * 70)

lstm_model_path = os.path.join(
    REFINED_LSTM_DIR,
    "lstm_refined_3.keras"
)

lstm_model = load_model(
    lstm_model_path
)

lstm_scaled = lstm_model.predict(
    X_lstm_val,
    batch_size=128,
    verbose=1
)

print("LSTM scaled shape:", lstm_scaled.shape)

lstm_real = inverse_targets(
    lstm_scaled,
    latitude,
    longitude
)

print("LSTM real-mm shape:", lstm_real.shape)


# ============================================================
# 2. XGBOOST
# ============================================================

print()
print("=" * 70)
print("GENERATING REFINED XGBOOST VALIDATION PREDICTIONS")
print("=" * 70)

X_xgb_val = xgb_val["X"].astype(np.float32)

xgb_scaled = np.zeros(
    (len(X_xgb_val), 5),
    dtype=np.float32
)

for i, target in enumerate(
    ["1h", "3h", "6h", "12h", "24h"]
):

    model_path = os.path.join(
        REFINED_MODEL_DIR,
        f"xgb_refined_3_{target}.json"
    )

    from xgboost import XGBRegressor

    model = XGBRegressor()

    model.load_model(
        model_path
    )

    print(
        f"Predicting XGBoost {target}"
    )

    xgb_scaled[:, i] = model.predict(
        X_xgb_val
    )

xgb_real = inverse_targets(
    xgb_scaled,
    latitude,
    longitude
)

print(
    "XGBoost real-mm shape:",
    xgb_real.shape
)


# ============================================================
# 3. RANDOM FOREST
# ============================================================

print()
print("=" * 70)
print("GENERATING REFINED RANDOM FOREST VALIDATION PREDICTIONS")
print("=" * 70)

rf_scaled = np.zeros(
    (len(X_xgb_val), 5),
    dtype=np.float32
)

for i, target in enumerate(
    ["1h", "3h", "6h", "12h", "24h"]
):

    model_path = os.path.join(
        REFINED_MODEL_DIR,
        f"rf_refined_1_{target}.joblib"
    )

    print(
        f"Predicting Random Forest {target}"
    )

    model = joblib.load(
        model_path
    )

    rf_scaled[:, i] = model.predict(
        X_xgb_val
    )

rf_real = inverse_targets(
    rf_scaled,
    latitude,
    longitude
)

print(
    "Random Forest real-mm shape:",
    rf_real.shape
)


# ============================================================
# 4. GET ACTUAL VALUES FROM OPEN-METEO DATA
# ============================================================

print()
print("=" * 70)
print("MATCHING ACTUAL OPEN-METEO VALUES")
print("=" * 70)

weather_key = weather[
    [
        "timestamp",
        "latitude",
        "longitude"
    ]
    + targets
].copy()

weather_key["timestamp"] = pd.to_datetime(
    weather_key["timestamp"]
)

weather_lookup = weather_key.set_index(
    [
        "timestamp",
        "latitude",
        "longitude"
    ]
)


actual = np.zeros(
    (len(timestamps), 5),
    dtype=np.float32
)

missing = 0

for i in range(len(timestamps)):

    ts = pd.Timestamp(
        timestamps[i]
    )

    lat = round(
        float(latitude[i]),
        2
    )

    lon = round(
        float(longitude[i]),
        2
    )

    key = (
        ts,
        lat,
        lon
    )

    try:

        row = weather_lookup.loc[key]

        actual[i] = [
            float(row[target])
            for target in targets
        ]

    except KeyError:

        missing += 1


print(
    "Missing actual values:",
    missing
)

if missing > 0:

    raise RuntimeError(
        "Some validation actual values could not be matched."
    )


# ============================================================
# 5. SANITY CHECK
# ============================================================

print()
print("=" * 70)
print("SANITY CHECK")
print("=" * 70)

print(
    "Actual mean:",
    np.mean(actual, axis=0)
)

print(
    "LSTM mean:",
    np.mean(lstm_real, axis=0)
)

print(
    "XGBoost mean:",
    np.mean(xgb_real, axis=0)
)

print(
    "Random Forest mean:",
    np.mean(rf_real, axis=0)
)


# ============================================================
# 6. SAVE
# ============================================================

output_file = os.path.join(
    OUTPUT_DIR,
    "refined_ensemble_validation_real_mm.npz"
)

np.savez_compressed(
    output_file,

    actual=actual,

    lstm=lstm_real,

    xgboost=xgb_real,

    random_forest=rf_real,

    timestamps=timestamps,

    latitude=latitude,

    longitude=longitude,

    target_columns=np.array(
        targets
    )
)

print()
print("=" * 70)
print("SAVED")
print("=" * 70)

print(output_file)


# ============================================================
# 7. INDIVIDUAL VALIDATION METRICS
# ============================================================

print()
print("=" * 70)
print("INDIVIDUAL VALIDATION METRICS")
print("=" * 70)

models = {
    "LSTM refined 3": lstm_real,
    "XGBoost refined 3": xgb_real,
    "Random Forest refined 1": rf_real
}

for name, prediction in models.items():

    print()
    print(name)

    all_mae = []
    all_rmse = []

    for i, target in enumerate(targets):

        mae = mean_absolute_error(
            actual[:, i],
            prediction[:, i]
        )

        rmse = np.sqrt(
            mean_squared_error(
                actual[:, i],
                prediction[:, i]
            )
        )

        r2 = r2_score(
            actual[:, i],
            prediction[:, i]
        )

        all_mae.append(mae)
        all_rmse.append(rmse)

        print(
            f"{target:20s} "
            f"MAE={mae:.4f} "
            f"RMSE={rmse:.4f} "
            f"R2={r2:.4f}"
        )

    print(
        f"AVERAGE              "
        f"MAE={np.mean(all_mae):.4f} "
        f"RMSE={np.mean(all_rmse):.4f}"
    )


print()
print("=" * 70)
print("STEP 4 COMPLETE")
print("=" * 70)
