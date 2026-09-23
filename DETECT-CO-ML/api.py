from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import numpy as np
import pandas as pd
import joblib
import tensorflow as tf
import xgboost as xgb
from pathlib import Path
import requests


# ============================================================
# PATHS
# ============================================================

BASE_DIR = Path("/home/miguel/DETECT-CO-ML")

LSTM_MODEL_PATH = (
    BASE_DIR / "data/models/refined_lstm/lstm_refined_3.keras"
)

XGB_DIR = BASE_DIR / "data/models/xgboost"
RF_DIR = BASE_DIR / "data/models/random_forest"
SCALER_DIR = BASE_DIR / "data/lstm_scalers"


# ============================================================
# MODEL CONFIGURATION
# ============================================================

TARGETS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm",
]


# Exact 14 LSTM training features
LSTM_FEATURES = [
    "temperature_c",
    "humidity_percent",
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm",
    "rainfall_3h_avg_mm",
    "rainfall_6h_avg_mm",
    "rainfall_12h_avg_mm",
    "rainfall_24h_avg_mm",
    "hour",
    "day_of_week",
    "month",
]


# Exact 19 XGBoost / Random Forest training features
XGB_RF_FEATURES = [
    "weather_temperature_c",
    "weather_humidity_percent",
    "weather_rainfall_1h_mm",
    "weather_rainfall_3h_mm",
    "weather_rainfall_6h_mm",
    "weather_rainfall_12h_mm",
    "weather_rainfall_24h_mm",
    "weather_rainfall_3h_avg_mm",
    "weather_rainfall_6h_avg_mm",
    "weather_rainfall_12h_avg_mm",
    "weather_rainfall_24h_avg_mm",
    "weather_hour",
    "weather_day_of_week",
    "weather_month",
    "lstm_pred_1h_mm",
    "lstm_pred_3h_mm",
    "lstm_pred_6h_mm",
    "lstm_pred_12h_mm",
    "lstm_pred_24h_mm",
]


# Final validation-derived ensemble weights
LSTM_WEIGHT = 0.96
XGB_WEIGHT = 0.00
RF_WEIGHT = 0.04


# ============================================================
# TRAINING LOCATIONS / SCALERS
# ============================================================

LOCATIONS = {
    "14.15,121.05": SCALER_DIR / "scaler_14.15_121.05.joblib",
    "14.15,121.15": SCALER_DIR / "scaler_14.15_121.15.joblib",
    "14.25,121.05": SCALER_DIR / "scaler_14.25_121.05.joblib",
    "14.25,121.15": SCALER_DIR / "scaler_14.25_121.15.joblib",
}


# ============================================================
# LOAD MODELS
# ============================================================

print("Loading LSTM model...")
lstm_model = tf.keras.models.load_model(LSTM_MODEL_PATH)

print("Loading XGBoost models...")
xgb_models = {}

for target in TARGETS:
    path = XGB_DIR / f"xgboost_{target}.json"

    model = xgb.XGBRegressor()
    model.load_model(path)

    xgb_models[target] = model


print("Loading Random Forest models...")
rf_models = {}

for target in TARGETS:
    path = RF_DIR / f"random_forest_{target}.joblib"

    rf_models[target] = joblib.load(path)


print("Loading scalers...")
scalers = {}

for location, path in LOCATIONS.items():
    scalers[location] = joblib.load(path)


print("All models loaded successfully.")


# ============================================================
# FASTAPI
# ============================================================

app = FastAPI(
    title="DETECT CO ML Ensemble API",
    description=(
        "DETECT CO LSTM + XGBoost + Random Forest "
        "ensemble using Open-Meteo weather data"
    ),
    version="1.0.0",
)


# ============================================================
# REQUEST MODEL
# ============================================================

class PredictionRequest(BaseModel):
    latitude: float
    longitude: float


# ============================================================
# LOCATION
# ============================================================

def get_location_key(latitude: float, longitude: float):

    key = f"{latitude:.2f},{longitude:.2f}"

    if key not in LOCATIONS:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Unsupported location: {latitude}, {longitude}. "
                f"Supported locations: {list(LOCATIONS.keys())}"
            ),
        )

    return key


# ============================================================
# OPEN-METEO
# ============================================================

def fetch_open_meteo(latitude: float, longitude: float):

    url = "https://api.open-meteo.com/v1/forecast"

    params = {
        "latitude": latitude,
        "longitude": longitude,

        # Exact weather variables used by the trained dataset
        "hourly": (
            "temperature_2m,"
            "relative_humidity_2m,"
            "rain"
        ),

        # Get the recent hourly history needed by the LSTM
        "past_hours": 24,

        # We don't need future weather for this inference
        "forecast_hours": 1,

        # Match the training timezone
        "timezone": "Asia/Manila",
    }

    try:
        response = requests.get(
            url,
            params=params,
            timeout=20,
        )

        response.raise_for_status()

    except requests.RequestException as e:
        raise HTTPException(
            status_code=502,
            detail=f"Open-Meteo request failed: {str(e)}",
        )

    data = response.json()

    if "hourly" not in data:
        raise HTTPException(
            status_code=502,
            detail="Open-Meteo response does not contain hourly data.",
        )

    hourly = data["hourly"]

    times = hourly.get("time", [])
    temperatures = hourly.get("temperature_2m", [])
    humidities = hourly.get("relative_humidity_2m", [])
    rainfall = hourly.get("rain", [])

    if not (
        len(times)
        == len(temperatures)
        == len(humidities)
        == len(rainfall)
    ):
        raise HTTPException(
            status_code=502,
            detail="Open-Meteo returned inconsistent hourly data.",
        )

    weather = []

    for i in range(len(times)):
        if (
            temperatures[i] is None
            or humidities[i] is None
            or rainfall[i] is None
        ):
            continue

        weather.append(
            {
                "timestamp": times[i],
                "temperature_c": float(temperatures[i]),
                "humidity_percent": float(humidities[i]),
                "rainfall_mm": float(rainfall[i]),
            }
        )

    if len(weather) < 24:
        raise HTTPException(
            status_code=502,
            detail=(
                "Open-Meteo did not return at least "
                f"24 valid hourly records. Received {len(weather)}."
            ),
        )

    # Use exactly the latest 24 valid hourly records
    return weather[-24:]


# ============================================================
# WEATHER FEATURE ENGINEERING
# ============================================================

def create_weather_features(weather_records):

    rows = []

    for record in weather_records:
        rows.append(
            {
                "timestamp": pd.to_datetime(record["timestamp"]),
                "temperature_c": record["temperature_c"],
                "humidity_percent": record["humidity_percent"],
                "rainfall_mm": record["rainfall_mm"],
            }
        )

    df = pd.DataFrame(rows)

    df = df.sort_values(
        "timestamp"
    ).reset_index(drop=True)

    # --------------------------------------------------------
    # Time features
    # --------------------------------------------------------

    df["hour"] = df["timestamp"].dt.hour

    df["day_of_week"] = df["timestamp"].dt.dayofweek

    df["month"] = df["timestamp"].dt.month

    # --------------------------------------------------------
    # Rolling rainfall features
    # --------------------------------------------------------

    df["rainfall_1h_mm"] = df["rainfall_mm"]

    df["rainfall_3h_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=3,
            min_periods=3,
        )
        .sum()
    )

    df["rainfall_6h_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=6,
            min_periods=6,
        )
        .sum()
    )

    df["rainfall_12h_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=12,
            min_periods=12,
        )
        .sum()
    )

    df["rainfall_24h_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=24,
            min_periods=24,
        )
        .sum()
    )

    # --------------------------------------------------------
    # Rolling rainfall averages
    # --------------------------------------------------------

    df["rainfall_3h_avg_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=3,
            min_periods=3,
        )
        .mean()
    )

    df["rainfall_6h_avg_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=6,
            min_periods=6,
        )
        .mean()
    )

    df["rainfall_12h_avg_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=12,
            min_periods=12,
        )
        .mean()
    )

    df["rainfall_24h_avg_mm"] = (
        df["rainfall_mm"]
        .rolling(
            window=24,
            min_periods=24,
        )
        .mean()
    )

    return df


# ============================================================
# ENSEMBLE PREDICTION
# ============================================================

def predict_ensemble(
    latitude,
    longitude,
    weather_records,
):

    location_key = get_location_key(
        latitude,
        longitude,
    )

    scaler = scalers[location_key]

    # --------------------------------------------------------
    # Create weather features
    # --------------------------------------------------------

    df = create_weather_features(
        weather_records
    )

    if len(df) != 24:
        raise HTTPException(
            status_code=400,
            detail=(
                f"LSTM requires exactly 24 hourly records. "
                f"Received {len(df)}."
            ),
        )

    # Make sure all required features exist
    missing = [
        feature
        for feature in LSTM_FEATURES
        if feature not in df.columns
    ]

    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Missing LSTM features: {missing}",
        )

    # --------------------------------------------------------
    # LSTM INPUT
    # --------------------------------------------------------

    lstm_input_df = df[
        LSTM_FEATURES
    ].copy()

    lstm_input = lstm_input_df.to_numpy(
        dtype=np.float32
    )

    # Use the training-only scaler
    lstm_scaled = scaler.transform(
        lstm_input
    )

    # (24, 14) -> (1, 24, 14)
    lstm_input_batch = np.expand_dims(
        lstm_scaled,
        axis=0,
    )

    # --------------------------------------------------------
    # LSTM PREDICTION
    # --------------------------------------------------------

    lstm_prediction = lstm_model.predict(
        lstm_input_batch,
        verbose=0,
    )

    lstm_prediction = np.asarray(
        lstm_prediction,
        dtype=np.float32,
    ).reshape(-1)

    if len(lstm_prediction) != 5:
        raise HTTPException(
            status_code=500,
            detail=(
                "LSTM returned an unexpected number "
                f"of outputs: {len(lstm_prediction)}"
            ),
        )

    # --------------------------------------------------------
    # XGBOOST / RANDOM FOREST INPUT
    # --------------------------------------------------------

    latest = df.iloc[-1]

    xgb_rf_values = [
        latest["temperature_c"],
        latest["humidity_percent"],
        latest["rainfall_1h_mm"],
        latest["rainfall_3h_mm"],
        latest["rainfall_6h_mm"],
        latest["rainfall_12h_mm"],
        latest["rainfall_24h_mm"],
        latest["rainfall_3h_avg_mm"],
        latest["rainfall_6h_avg_mm"],
        latest["rainfall_12h_avg_mm"],
        latest["rainfall_24h_avg_mm"],
        latest["hour"],
        latest["day_of_week"],
        latest["month"],
        lstm_prediction[0],
        lstm_prediction[1],
        lstm_prediction[2],
        lstm_prediction[3],
        lstm_prediction[4],
    ]

    xgb_rf_input = pd.DataFrame(
        [xgb_rf_values],
        columns=XGB_RF_FEATURES,
    )

    # --------------------------------------------------------
    # XGBOOST
    # --------------------------------------------------------

    xgb_prediction = []

    for target in TARGETS:

        prediction = xgb_models[target].predict(
            xgb_rf_input
        )[0]

        xgb_prediction.append(
            float(prediction)
        )

    xgb_prediction = np.array(
        xgb_prediction,
        dtype=np.float32,
    )

    # --------------------------------------------------------
    # RANDOM FOREST
    # --------------------------------------------------------

    rf_prediction = []

    for target in TARGETS:

        prediction = rf_models[target].predict(
            xgb_rf_input
        )[0]

        rf_prediction.append(
            float(prediction)
        )

    rf_prediction = np.array(
        rf_prediction,
        dtype=np.float32,
    )

    # --------------------------------------------------------
    # FINAL ENSEMBLE
    # --------------------------------------------------------

    final_prediction = (
        LSTM_WEIGHT * lstm_prediction
        + XGB_WEIGHT * xgb_prediction
        + RF_WEIGHT * rf_prediction
    )

    # Prevent negative rainfall
    final_prediction = np.maximum(
        final_prediction,
        0.0,
    )

    # --------------------------------------------------------
    # RESULT
    # --------------------------------------------------------

    return {
        "location": {
            "latitude": latitude,
            "longitude": longitude,
        },

        "weather_source": "Open-Meteo",

        "weather_records_used": len(
            weather_records
        ),

        "ensemble_weights": {
            "lstm": LSTM_WEIGHT,
            "xgboost": XGB_WEIGHT,
            "random_forest": RF_WEIGHT,
        },

        "predictions": {
            "rainfall_1h_mm": float(
                final_prediction[0]
            ),
            "rainfall_3h_mm": float(
                final_prediction[1]
            ),
            "rainfall_6h_mm": float(
                final_prediction[2]
            ),
            "rainfall_12h_mm": float(
                final_prediction[3]
            ),
            "rainfall_24h_mm": float(
                final_prediction[4]
            ),
        },

        "model_predictions": {

            "lstm": {
                "rainfall_1h_mm": float(
                    lstm_prediction[0]
                ),
                "rainfall_3h_mm": float(
                    lstm_prediction[1]
                ),
                "rainfall_6h_mm": float(
                    lstm_prediction[2]
                ),
                "rainfall_12h_mm": float(
                    lstm_prediction[3]
                ),
                "rainfall_24h_mm": float(
                    lstm_prediction[4]
                ),
            },

            "xgboost": {
                "rainfall_1h_mm": float(
                    xgb_prediction[0]
                ),
                "rainfall_3h_mm": float(
                    xgb_prediction[1]
                ),
                "rainfall_6h_mm": float(
                    xgb_prediction[2]
                ),
                "rainfall_12h_mm": float(
                    xgb_prediction[3]
                ),
                "rainfall_24h_mm": float(
                    xgb_prediction[4]
                ),
            },

            "random_forest": {
                "rainfall_1h_mm": float(
                    rf_prediction[0]
                ),
                "rainfall_3h_mm": float(
                    rf_prediction[1]
                ),
                "rainfall_6h_mm": float(
                    rf_prediction[2]
                ),
                "rainfall_12h_mm": float(
                    rf_prediction[3]
                ),
                "rainfall_24h_mm": float(
                    rf_prediction[4]
                ),
            },
        },
    }


# ============================================================
# API ROUTES
# ============================================================

@app.get("/")
def root():

    return {
        "system": "DETECT CO ML Ensemble API",
        "status": "running",

        "models": [
            "LSTM Refined 3",
            "XGBoost",
            "Random Forest",
        ],

        "weights": {
            "lstm": LSTM_WEIGHT,
            "xgboost": XGB_WEIGHT,
            "random_forest": RF_WEIGHT,
        },

        "weather_source": "Open-Meteo",
    }


@app.get("/health")
def health():

    return {
        "status": "healthy",
        "models_loaded": True,
        "weather_source": "Open-Meteo",
    }


@app.post("/predict")
def predict(
    request: PredictionRequest,
):

    # --------------------------------------------------------
    # Automatically retrieve Open-Meteo data
    # --------------------------------------------------------

    weather = fetch_open_meteo(
        request.latitude,
        request.longitude,
    )

    # --------------------------------------------------------
    # Run complete ensemble
    # --------------------------------------------------------

    return predict_ensemble(
        latitude=request.latitude,
        longitude=request.longitude,
        weather_records=weather,
    )