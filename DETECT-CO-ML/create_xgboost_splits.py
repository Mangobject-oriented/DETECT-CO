#!/usr/bin/env python3

import os
import numpy as np
import pandas as pd

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
OUTPUT_DIR = os.path.join(DATA_DIR, "xgboost")

os.makedirs(OUTPUT_DIR, exist_ok=True)

WEATHER_FILE = os.path.join(
    DATA_DIR,
    "calamba_weather_features.csv"
)

# ---------------------------------------------------------
# FEATURES
# ---------------------------------------------------------

FEATURE_COLUMNS = [
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
    "month"
]

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

LSTM_COLUMNS = [
    "lstm_pred_1h_mm",
    "lstm_pred_3h_mm",
    "lstm_pred_6h_mm",
    "lstm_pred_12h_mm",
    "lstm_pred_24h_mm"
]

X_COLUMNS = FEATURE_COLUMNS + LSTM_COLUMNS

# ---------------------------------------------------------
# DATASETS
# ---------------------------------------------------------

SPLITS = {
    "train": "lstm_train_predictions.npz",
    "validation": "lstm_validation_predictions.npz",
    "test": "lstm_test_predictions.npz"
}

print("=" * 70)
print("DETECT-CO XGBOOST — CREATE TRAIN/VALIDATION/TEST DATA")
print("=" * 70)

# ---------------------------------------------------------
# LOAD OPEN-METEO DATA
# ---------------------------------------------------------

print()
print("Loading Open-Meteo weather features...")

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

print(
    "Weather rows:",
    len(weather)
)

# ---------------------------------------------------------
# PROCESS EACH SPLIT
# ---------------------------------------------------------

for split, prediction_file in SPLITS.items():

    print()
    print("=" * 70)
    print(f"{split.upper()} DATASET")
    print("=" * 70)

    prediction_path = os.path.join(
        DATA_DIR,
        prediction_file
    )

    print()
    print("Loading LSTM predictions:")
    print(prediction_path)

    lstm = np.load(
        prediction_path,
        allow_pickle=True
    )

    predictions = lstm["predictions"]
    actual = lstm["actual"]

    timestamps = pd.to_datetime(
        lstm["timestamps"]
    )

    latitude = np.round(
        lstm["latitude"].astype(float),
        2
    )

    longitude = np.round(
        lstm["longitude"].astype(float),
        2
    )

    print(
        "Prediction shape:",
        predictions.shape
    )

    # -----------------------------------------------------
    # BUILD LSTM DATAFRAME
    # -----------------------------------------------------

    lstm_df = pd.DataFrame({
        "timestamp": timestamps,
        "latitude": latitude,
        "longitude": longitude
    })

    for i, column in enumerate(LSTM_COLUMNS):
        lstm_df[column] = predictions[:, i]

    # Actual target values
    for i, column in enumerate(TARGET_COLUMNS):
        lstm_df[f"actual_{column}"] = actual[:, i]

    # -----------------------------------------------------
    # MERGE
    # -----------------------------------------------------

    merged = weather.merge(
        lstm_df,
        on=[
            "timestamp",
            "latitude",
            "longitude"
        ],
        how="inner"
    )

    print(
        "Merged rows:",
        len(merged)
    )

    if len(merged) != len(predictions):
        raise RuntimeError(
            f"{split}: merge mismatch. "
            f"Expected {len(predictions)}, "
            f"got {len(merged)}."
        )

    # -----------------------------------------------------
    # SORT
    # -----------------------------------------------------

    merged = merged.sort_values(
        [
            "timestamp",
            "latitude",
            "longitude"
        ]
    ).reset_index(drop=True)

    # -----------------------------------------------------
    # CHECK MISSING VALUES
    # -----------------------------------------------------

    required = (
        FEATURE_COLUMNS
        + LSTM_COLUMNS
        + TARGET_COLUMNS
    )

    missing = merged[required].isna().sum().sum()

    print(
        "Missing feature/target values:",
        missing
    )

    if missing != 0:
        raise RuntimeError(
            f"{split}: missing values detected."
        )

    # -----------------------------------------------------
    # CREATE ARRAYS
    # -----------------------------------------------------

    X = merged[X_COLUMNS].to_numpy(
        dtype=np.float32
    )

    y = merged[TARGET_COLUMNS].to_numpy(
        dtype=np.float32
    )

    timestamps_out = merged[
        "timestamp"
    ].to_numpy()

    latitude_out = merged[
        "latitude"
    ].to_numpy(
        dtype=np.float32
    )

    longitude_out = merged[
        "longitude"
    ].to_numpy(
        dtype=np.float32
    )

    # -----------------------------------------------------
    # SAVE
    # -----------------------------------------------------

    output_file = os.path.join(
        OUTPUT_DIR,
        f"xgboost_{split}.npz"
    )

    np.savez_compressed(
        output_file,
        X=X,
        y=y,
        timestamps=timestamps_out,
        latitude=latitude_out,
        longitude=longitude_out,
        feature_columns=np.array(X_COLUMNS),
        target_columns=np.array(TARGET_COLUMNS)
    )

    # CSV for inspection
    csv_columns = (
        [
            "timestamp",
            "latitude",
            "longitude"
        ]
        + X_COLUMNS
        + [
            f"actual_{column}"
            for column in TARGET_COLUMNS
        ]
    )

    csv_file = os.path.join(
        OUTPUT_DIR,
        f"xgboost_{split}.csv"
    )

    merged[csv_columns].to_csv(
        csv_file,
        index=False
    )

    # -----------------------------------------------------
    # SUMMARY
    # -----------------------------------------------------

    print()
    print("X shape:", X.shape)
    print("y shape:", y.shape)

    print()
    print("Timestamp range:")
    print(
        merged["timestamp"].min()
    )
    print(
        merged["timestamp"].max()
    )

    print()
    print("Locations:")

    locations = merged[
        ["latitude", "longitude"]
    ].drop_duplicates()

    for _, row in locations.iterrows():

        lat = row["latitude"]
        lon = row["longitude"]

        count = (
            (merged["latitude"] == lat)
            &
            (merged["longitude"] == lon)
        ).sum()

        print(
            f"{lat:.2f}, {lon:.2f}: "
            f"{count:,} rows"
        )

    print()
    print("Saved:")
    print(output_file)
    print(csv_file)

# ---------------------------------------------------------
# FINAL SUMMARY
# ---------------------------------------------------------

print()
print("=" * 70)
print("XGBOOST SPLITS CREATED SUCCESSFULLY")
print("=" * 70)

print()
print("Expected files:")

for split in SPLITS:
    print(
        os.path.join(
            OUTPUT_DIR,
            f"xgboost_{split}.npz"
        )
    )

print()
print("Done.")
