#!/usr/bin/env python3

import os
import numpy as np
import pandas as pd

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"

WEATHER_FILE = os.path.join(
    DATA_DIR,
    "calamba_weather_features.csv"
)

LSTM_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_predictions_mm.npz"
)

OUTPUT_DIR = os.path.join(
    DATA_DIR,
    "xgboost"
)

os.makedirs(OUTPUT_DIR, exist_ok=True)

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

# ---------------------------------------------------------
# LOAD OPEN-METEO WEATHER DATA
# ---------------------------------------------------------

print("=" * 70)
print("DETECT-CO XGBOOST DATASET PREPARATION")
print("=" * 70)

print()
print("Loading Open-Meteo weather features...")

df = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

# Normalize coordinates to avoid floating-point mismatch.
df["latitude"] = df["latitude"].round(2)
df["longitude"] = df["longitude"].round(2)

print("Weather rows:", len(df))

# ---------------------------------------------------------
# LOAD LSTM PREDICTIONS
# ---------------------------------------------------------

print()
print("Loading LSTM predictions...")

lstm = np.load(
    LSTM_FILE,
    allow_pickle=True
)

lstm_predictions = lstm["predictions_mm"]
lstm_actual = lstm["actual_mm"]

lstm_timestamps = pd.to_datetime(
    lstm["timestamps"]
)

lstm_latitude = np.round(
    lstm["latitude"].astype(float),
    2
)

lstm_longitude = np.round(
    lstm["longitude"].astype(float),
    2
)

print(
    "LSTM prediction shape:",
    lstm_predictions.shape
)

# ---------------------------------------------------------
# BUILD LSTM DATAFRAME
# ---------------------------------------------------------

lstm_df = pd.DataFrame({
    "timestamp": lstm_timestamps,
    "latitude": lstm_latitude,
    "longitude": lstm_longitude
})

for i, column in enumerate(LSTM_COLUMNS):
    lstm_df[column] = lstm_predictions[:, i]

# Retain actual rainfall values for verification.
for i, column in enumerate(TARGET_COLUMNS):
    lstm_df[f"actual_{column}"] = lstm_actual[:, i]

# ---------------------------------------------------------
# MERGE
# ---------------------------------------------------------

print()
print("Merging LSTM predictions with Open-Meteo features...")

merged = df.merge(
    lstm_df,
    on=[
        "timestamp",
        "latitude",
        "longitude"
    ],
    how="inner"
)

print("Merged rows:", len(merged))

if len(merged) == 0:
    raise RuntimeError(
        "No matching timestamps/locations were found."
    )

# ---------------------------------------------------------
# CHECK EXPECTED TEST DATA
# ---------------------------------------------------------

expected_rows = len(lstm_predictions)

if len(merged) != expected_rows:
    raise RuntimeError(
        f"Unexpected merge size: {len(merged)} "
        f"rows. Expected {expected_rows}."
    )

# ---------------------------------------------------------
# SORT
# ---------------------------------------------------------

merged = merged.sort_values(
    [
        "timestamp",
        "latitude",
        "longitude"
    ]
).reset_index(drop=True)

# ---------------------------------------------------------
# REMOVE MISSING VALUES
# ---------------------------------------------------------

required_columns = (
    FEATURE_COLUMNS
    + LSTM_COLUMNS
    + TARGET_COLUMNS
)

before = len(merged)

merged = merged.dropna(
    subset=required_columns
).reset_index(drop=True)

print(
    "Rows removed because of missing values:",
    before - len(merged)
)

# ---------------------------------------------------------
# CREATE X AND Y
# ---------------------------------------------------------

X_COLUMNS = (
    FEATURE_COLUMNS
    + LSTM_COLUMNS
)

X = merged[X_COLUMNS].to_numpy(
    dtype=np.float32
)

y = merged[TARGET_COLUMNS].to_numpy(
    dtype=np.float32
)

timestamps = merged["timestamp"].to_numpy()

latitude = merged["latitude"].to_numpy(
    dtype=np.float32
)

longitude = merged["longitude"].to_numpy(
    dtype=np.float32
)

# ---------------------------------------------------------
# SAVE NPZ
# ---------------------------------------------------------

output_file = os.path.join(
    OUTPUT_DIR,
    "xgboost_test_dataset.npz"
)

np.savez_compressed(
    output_file,
    X=X,
    y=y,
    timestamps=timestamps,
    latitude=latitude,
    longitude=longitude,
    feature_columns=np.array(X_COLUMNS),
    target_columns=np.array(TARGET_COLUMNS)
)

# ---------------------------------------------------------
# SAVE CSV
# ---------------------------------------------------------

csv_columns = (
    [
        "timestamp",
        "latitude",
        "longitude"
    ]
    + X_COLUMNS
    + [
        f"actual_{c}"
        for c in TARGET_COLUMNS
    ]
)

merged[csv_columns].to_csv(
    os.path.join(
        OUTPUT_DIR,
        "xgboost_test_dataset.csv"
    ),
    index=False
)

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------

print()
print("=" * 70)
print("XGBOOST DATASET SUMMARY")
print("=" * 70)

print()
print("X shape:", X.shape)
print("y shape:", y.shape)

print()
print("Input features:")

for i, column in enumerate(X_COLUMNS):
    print(
        f"{i + 1:2d}. {column}"
    )

print()
print("Targets:")

for i, column in enumerate(TARGET_COLUMNS):
    print(
        f"{i + 1}. {column}"
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
print("Timestamp range:")

print(
    merged["timestamp"].min()
)

print(
    merged["timestamp"].max()
)

print()
print("Files saved:")

print(
    os.path.join(
        OUTPUT_DIR,
        "xgboost_test_dataset.npz"
    )
)

print(
    os.path.join(
        OUTPUT_DIR,
        "xgboost_test_dataset.csv"
    )
)

print()
print("Done.")
