#!/usr/bin/env python3

import os
import numpy as np
import pandas as pd
from sklearn.preprocessing import MinMaxScaler

INPUT_FILE = "/home/miguel/DETECT-CO-ML/data/calamba_weather_features.csv"
OUTPUT_FILE = "/home/miguel/DETECT-CO-ML/data/lstm_sequences.npz"
SCALER_FILE = "/home/miguel/DETECT-CO-ML/data/lstm_scaler.npz"

SEQUENCE_LENGTH = 24

# ---------------------------------------------------------
# LOAD DATA
# ---------------------------------------------------------

print("Loading Open-Meteo weather features...")

df = pd.read_csv(INPUT_FILE)
df["timestamp"] = pd.to_datetime(df["timestamp"])

df = df.sort_values(
    ["latitude", "longitude", "timestamp"]
).reset_index(drop=True)

print("Rows:", len(df))

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

print()
print("Features:")
for feature in FEATURE_COLUMNS:
    print(" -", feature)

# ---------------------------------------------------------
# CREATE SEQUENCES
# ---------------------------------------------------------

X_sequences = []
y_values = []
timestamps = []
locations = []

print()
print("Creating 24-hour sequences...")

for (latitude, longitude), group in df.groupby(
    ["latitude", "longitude"]
):

    group = group.sort_values("timestamp").reset_index(drop=True)

    # Make sure values are numeric
    values = group[FEATURE_COLUMNS].astype(float).values

    # Scale each location independently
    scaler = MinMaxScaler()

    scaled = scaler.fit_transform(values)

    for i in range(SEQUENCE_LENGTH, len(group)):

        X_sequences.append(
            scaled[i - SEQUENCE_LENGTH:i]
        )

        # Target = next/current hour rainfall features
        y_values.append(
            scaled[i][
                [
                    FEATURE_COLUMNS.index("rainfall_1h_mm"),
                    FEATURE_COLUMNS.index("rainfall_3h_mm"),
                    FEATURE_COLUMNS.index("rainfall_6h_mm"),
                    FEATURE_COLUMNS.index("rainfall_12h_mm"),
                    FEATURE_COLUMNS.index("rainfall_24h_mm")
                ]
            ]
        )

        timestamps.append(
            group.loc[i, "timestamp"]
        )

        locations.append(
            [latitude, longitude]
        )

# ---------------------------------------------------------
# CONVERT TO NUMPY
# ---------------------------------------------------------

X = np.asarray(X_sequences, dtype=np.float32)
y = np.asarray(y_values, dtype=np.float32)

timestamps = np.asarray(timestamps, dtype="datetime64[ns]")
locations = np.asarray(locations, dtype=np.float32)

print()
print("=" * 60)
print("LSTM SEQUENCE DATASET")
print("=" * 60)

print("X shape:", X.shape)
print("y shape:", y.shape)
print("Timestamp shape:", timestamps.shape)
print("Location shape:", locations.shape)

# ---------------------------------------------------------
# SAVE
# ---------------------------------------------------------

os.makedirs(
    os.path.dirname(OUTPUT_FILE),
    exist_ok=True
)

np.savez_compressed(
    OUTPUT_FILE,
    X=X,
    y=y,
    timestamps=timestamps,
    locations=locations
)

print()
print("Saved:")
print(OUTPUT_FILE)

# ---------------------------------------------------------
# SAVE FEATURE INFORMATION
# ---------------------------------------------------------

np.savez(
    SCALER_FILE,
    feature_columns=np.asarray(FEATURE_COLUMNS),
    sequence_length=np.asarray([SEQUENCE_LENGTH])
)

print("Feature information:")
print(SCALER_FILE)

print()
print("=" * 60)
print("COMPLETE")
print("=" * 60)
