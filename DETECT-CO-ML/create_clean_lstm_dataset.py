#!/usr/bin/env python3

import os
import json
import joblib
import numpy as np
import pandas as pd
from sklearn.preprocessing import MinMaxScaler

# ============================================================
# CONFIGURATION
# ============================================================

INPUT_FILE = "/home/miguel/DETECT-CO-ML/data/calamba_weather_features.csv"
OLD_SEQUENCE_FILE = "/home/miguel/DETECT-CO-ML/data/lstm_sequences.npz"

OUTPUT_DIR = "/home/miguel/DETECT-CO-ML/data"
SCALER_DIR = os.path.join(OUTPUT_DIR, "lstm_scalers")

TRAIN_OUTPUT = os.path.join(OUTPUT_DIR, "lstm_train_clean.npz")
VALIDATION_OUTPUT = os.path.join(OUTPUT_DIR, "lstm_validation_clean.npz")
TEST_OUTPUT = os.path.join(OUTPUT_DIR, "lstm_test_clean.npz")
METADATA_OUTPUT = os.path.join(OUTPUT_DIR, "lstm_clean_metadata.json")

SEQUENCE_LENGTH = 24

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

TARGET_INDICES = [FEATURE_COLUMNS.index(col) for col in TARGET_COLUMNS]

# ============================================================
# PREPARE DIRECTORIES
# ============================================================

os.makedirs(SCALER_DIR, exist_ok=True)

print("=" * 70)
print("CREATING CLEAN LSTM DATASET")
print("=" * 70)

# ============================================================
# LOAD WEATHER DATA
# ============================================================

print("\nLoading Open-Meteo weather features...")

df = pd.read_csv(INPUT_FILE)

df["timestamp"] = pd.to_datetime(df["timestamp"])

df = df.sort_values(
    ["latitude", "longitude", "timestamp"]
).reset_index(drop=True)

print("Rows:", len(df))
print("Columns:", len(df.columns))

# Check required columns
required_columns = [
    "timestamp",
    "latitude",
    "longitude"
] + FEATURE_COLUMNS

missing_columns = [
    col for col in required_columns
    if col not in df.columns
]

if missing_columns:
    raise ValueError(
        f"Missing required columns: {missing_columns}"
    )

# Remove rows with missing ML features
before = len(df)

df = df.dropna(
    subset=FEATURE_COLUMNS
).reset_index(drop=True)

removed = before - len(df)

print("Rows removed because of missing values:", removed)
print("Rows remaining:", len(df))

# ============================================================
# GET THE SAME CHRONOLOGICAL CUT-OFFS
# ============================================================

print("\nDetermining chronological split...")

# Use timestamps from the previous sequence dataset so that
# the clean dataset keeps the same 70/15/15 time boundaries.

if os.path.exists(OLD_SEQUENCE_FILE):

    old_data = np.load(
        OLD_SEQUENCE_FILE,
        allow_pickle=True
    )

    old_timestamps = pd.to_datetime(
        old_data["timestamps"]
    )

    unique_timestamps = np.sort(
        old_timestamps.unique()
    )

    del old_data

else:

    # Fallback if old sequence file is unavailable
    unique_timestamps = np.sort(
        df["timestamp"].unique()
    )

train_index = int(len(unique_timestamps) * 0.70)
validation_index = int(len(unique_timestamps) * 0.85)

train_cutoff = pd.Timestamp(
    unique_timestamps[train_index]
)

validation_cutoff = pd.Timestamp(
    unique_timestamps[validation_index]
)

print("\nTimestamp cutoffs:")
print("Training ends before :", train_cutoff)
print("Validation ends before:", validation_cutoff)
print("Test starts at       :", validation_cutoff)

# ============================================================
# STORAGE
# ============================================================

train_X_parts = []
train_y_parts = []
train_timestamps_parts = []
train_lat_parts = []
train_lon_parts = []

validation_X_parts = []
validation_y_parts = []
validation_timestamps_parts = []
validation_lat_parts = []
validation_lon_parts = []

test_X_parts = []
test_y_parts = []
test_timestamps_parts = []
test_lat_parts = []
test_lon_parts = []

location_statistics = []

# ============================================================
# PROCESS EACH LOCATION
# ============================================================

locations = (
    df[["latitude", "longitude"]]
    .drop_duplicates()
    .sort_values(["latitude", "longitude"])
)

print("\nLocations found:", len(locations))

for _, location in locations.iterrows():

    latitude = float(location["latitude"])
    longitude = float(location["longitude"])

    print("\n" + "-" * 70)
    print(
        f"Processing location: "
        f"{latitude:.2f}, {longitude:.2f}"
    )
    print("-" * 70)

    location_df = df[
        (df["latitude"] == latitude) &
        (df["longitude"] == longitude)
    ].copy()

    location_df = location_df.sort_values(
        "timestamp"
    ).reset_index(drop=True)

    print("Rows:", len(location_df))
    print(
        "Date range:",
        location_df["timestamp"].min(),
        "to",
        location_df["timestamp"].max()
    )

    # ========================================================
    # FIT SCALER ONLY ON TRAINING PERIOD
    # ========================================================

    training_rows = location_df[
        location_df["timestamp"] < train_cutoff
    ]

    if len(training_rows) == 0:
        raise ValueError(
            f"No training data for "
            f"{latitude}, {longitude}"
        )

    scaler = MinMaxScaler()

    scaler.fit(
        training_rows[FEATURE_COLUMNS].astype(
            np.float32
        )
    )

    print(
        "Scaler fitted using training rows only:",
        len(training_rows)
    )

    # Save actual scaler
    scaler_filename = (
        f"scaler_{latitude:.2f}_{longitude:.2f}.joblib"
    )

    scaler_path = os.path.join(
        SCALER_DIR,
        scaler_filename
    )

    joblib.dump(
        scaler,
        scaler_path
    )

    print("Scaler saved:", scaler_path)

    # ========================================================
    # TRANSFORM ENTIRE LOCATION USING TRAINING SCALER
    # ========================================================

    feature_values = location_df[
        FEATURE_COLUMNS
    ].astype(np.float32).values

    scaled_values = scaler.transform(
        feature_values
    ).astype(np.float32)

    timestamps = (
        location_df["timestamp"]
        .values
    )

    # ========================================================
    # CREATE 24-HOUR WINDOWS
    # ========================================================

    if len(location_df) <= SEQUENCE_LENGTH:
        print("Not enough rows for sequences.")
        continue

    # Each target timestamp starts at index 24.
    target_timestamps = timestamps[
        SEQUENCE_LENGTH:
    ]

    # Check that the previous 24 hours are actually
    # consecutive hourly observations.
    #
    # If t[i] - t[i-24] == 24 hours and timestamps
    # are sorted/unique, then all 25 timestamps are
    # consecutive hourly observations.

    continuity = (
        timestamps[SEQUENCE_LENGTH:]
        - timestamps[:-SEQUENCE_LENGTH]
    )

    valid_sequence = (
        continuity == np.timedelta64(
            SEQUENCE_LENGTH,
            "h"
        )
    )

    # Create sliding windows.
    windows = np.lib.stride_tricks.sliding_window_view(
        scaled_values[:-1],
        window_shape=SEQUENCE_LENGTH,
        axis=0
    )

    # sliding_window_view produces:
    # (number_of_sequences, features, sequence_length)
    #
    # Convert to:
    # (number_of_sequences, sequence_length, features)

    windows = np.transpose(
        windows,
        (0, 2, 1)
    )

    targets = scaled_values[
        SEQUENCE_LENGTH:
    ][:, TARGET_INDICES]

    # Keep only continuous hourly sequences
    windows = windows[valid_sequence]
    targets = targets[valid_sequence]
    target_timestamps = target_timestamps[
        valid_sequence
    ]

    print(
        "Valid continuous 24-hour sequences:",
        len(windows)
    )

    # ========================================================
    # ASSIGN TO CHRONOLOGICAL SPLITS
    # ========================================================

    train_mask = (
        target_timestamps < train_cutoff
    )

    validation_mask = (
        (target_timestamps >= train_cutoff) &
        (target_timestamps < validation_cutoff)
    )

    test_mask = (
        target_timestamps >= validation_cutoff
    )

    # ---------------- TRAIN ----------------

    if np.any(train_mask):

        train_X_parts.append(
            windows[train_mask]
        )

        train_y_parts.append(
            targets[train_mask]
        )

        train_timestamps_parts.append(
            target_timestamps[train_mask]
        )

        train_lat_parts.append(
            np.full(
                np.sum(train_mask),
                latitude,
                dtype=np.float32
            )
        )

        train_lon_parts.append(
            np.full(
                np.sum(train_mask),
                longitude,
                dtype=np.float32
            )
        )

    # ---------------- VALIDATION ----------------

    if np.any(validation_mask):

        validation_X_parts.append(
            windows[validation_mask]
        )

        validation_y_parts.append(
            targets[validation_mask]
        )

        validation_timestamps_parts.append(
            target_timestamps[validation_mask]
        )

        validation_lat_parts.append(
            np.full(
                np.sum(validation_mask),
                latitude,
                dtype=np.float32
            )
        )

        validation_lon_parts.append(
            np.full(
                np.sum(validation_mask),
                longitude,
                dtype=np.float32
            )
        )

    # ---------------- TEST ----------------

    if np.any(test_mask):

        test_X_parts.append(
            windows[test_mask]
        )

        test_y_parts.append(
            targets[test_mask]
        )

        test_timestamps_parts.append(
            target_timestamps[test_mask]
        )

        test_lat_parts.append(
            np.full(
                np.sum(test_mask),
                latitude,
                dtype=np.float32
            )
        )

        test_lon_parts.append(
            np.full(
                np.sum(test_mask),
                longitude,
                dtype=np.float32
            )
        )

    location_statistics.append({
        "latitude": latitude,
        "longitude": longitude,
        "total_rows": int(len(location_df)),
        "training_rows_for_scaler": int(
            len(training_rows)
        ),
        "valid_sequences": int(
            len(windows)
        ),
        "training_sequences": int(
            np.sum(train_mask)
        ),
        "validation_sequences": int(
            np.sum(validation_mask)
        ),
        "test_sequences": int(
            np.sum(test_mask)
        ),
        "scaler": scaler_path
    })

# ============================================================
# COMBINE DATASETS
# ============================================================

print("\n" + "=" * 70)
print("COMBINING DATASETS")
print("=" * 70)

if not train_X_parts:
    raise ValueError("No training sequences were created.")

if not validation_X_parts:
    raise ValueError(
        "No validation sequences were created."
    )

if not test_X_parts:
    raise ValueError(
        "No test sequences were created."
    )

train_X = np.concatenate(
    train_X_parts,
    axis=0
).astype(np.float32)

train_y = np.concatenate(
    train_y_parts,
    axis=0
).astype(np.float32)

train_timestamps = np.concatenate(
    train_timestamps_parts
)

train_latitude = np.concatenate(
    train_lat_parts
).astype(np.float32)

train_longitude = np.concatenate(
    train_lon_parts
).astype(np.float32)

validation_X = np.concatenate(
    validation_X_parts,
    axis=0
).astype(np.float32)

validation_y = np.concatenate(
    validation_y_parts,
    axis=0
).astype(np.float32)

validation_timestamps = np.concatenate(
    validation_timestamps_parts
)

validation_latitude = np.concatenate(
    validation_lat_parts
).astype(np.float32)

validation_longitude = np.concatenate(
    validation_lon_parts
).astype(np.float32)

test_X = np.concatenate(
    test_X_parts,
    axis=0
).astype(np.float32)

test_y = np.concatenate(
    test_y_parts,
    axis=0
).astype(np.float32)

test_timestamps = np.concatenate(
    test_timestamps_parts
)

test_latitude = np.concatenate(
    test_lat_parts
).astype(np.float32)

test_longitude = np.concatenate(
    test_lon_parts
).astype(np.float32)

# ============================================================
# SORT EACH DATASET CHRONOLOGICALLY
# ============================================================

def sort_dataset(
    X,
    y,
    timestamps,
    latitude,
    longitude
):

    order = np.argsort(timestamps)

    return (
        X[order],
        y[order],
        timestamps[order],
        latitude[order],
        longitude[order]
    )


(
    train_X,
    train_y,
    train_timestamps,
    train_latitude,
    train_longitude
) = sort_dataset(
    train_X,
    train_y,
    train_timestamps,
    train_latitude,
    train_longitude
)

(
    validation_X,
    validation_y,
    validation_timestamps,
    validation_latitude,
    validation_longitude
) = sort_dataset(
    validation_X,
    validation_y,
    validation_timestamps,
    validation_latitude,
    validation_longitude
)

(
    test_X,
    test_y,
    test_timestamps,
    test_latitude,
    test_longitude
) = sort_dataset(
    test_X,
    test_y,
    test_timestamps,
    test_latitude,
    test_longitude
)

# ============================================================
# SAVE DATASETS
# ============================================================

print("\nSaving clean datasets...")

np.savez_compressed(
    TRAIN_OUTPUT,
    X=train_X,
    y=train_y,
    timestamps=train_timestamps,
    latitude=train_latitude,
    longitude=train_longitude
)

np.savez_compressed(
    VALIDATION_OUTPUT,
    X=validation_X,
    y=validation_y,
    timestamps=validation_timestamps,
    latitude=validation_latitude,
    longitude=validation_longitude
)

np.savez_compressed(
    TEST_OUTPUT,
    X=test_X,
    y=test_y,
    timestamps=test_timestamps,
    latitude=test_latitude,
    longitude=test_longitude
)

# ============================================================
# SAVE METADATA
# ============================================================

metadata = {
    "source": "Open-Meteo",
    "input_file": INPUT_FILE,
    "sequence_length_hours": SEQUENCE_LENGTH,
    "feature_columns": FEATURE_COLUMNS,
    "target_columns": TARGET_COLUMNS,
    "scaler": "MinMaxScaler",
    "scaler_fitted_on": "training_period_only",
    "train_cutoff": str(train_cutoff),
    "validation_cutoff": str(validation_cutoff),
    "train_sequences": int(len(train_X)),
    "validation_sequences": int(len(validation_X)),
    "test_sequences": int(len(test_X)),
    "location_count": int(len(locations)),
    "locations": location_statistics,
    "continuous_hourly_sequences_only": True
}

with open(
    METADATA_OUTPUT,
    "w"
) as f:
    json.dump(
        metadata,
        f,
        indent=4
    )

# ============================================================
# FINAL REPORT
# ============================================================

print("\n" + "=" * 70)
print("CLEAN LSTM DATASET CREATED")
print("=" * 70)

print("\nTRAINING")
print("X shape:", train_X.shape)
print("y shape:", train_y.shape)
print(
    "Start:",
    train_timestamps.min()
)
print(
    "End:",
    train_timestamps.max()
)

print("\nVALIDATION")
print("X shape:", validation_X.shape)
print("y shape:", validation_y.shape)
print(
    "Start:",
    validation_timestamps.min()
)
print(
    "End:",
    validation_timestamps.max()
)

print("\nTEST")
print("X shape:", test_X.shape)
print("y shape:", test_y.shape)
print(
    "Start:",
    test_timestamps.min()
)
print(
    "End:",
    test_timestamps.max()
)

# ============================================================
# OVERLAP CHECK
# ============================================================

train_set = set(train_timestamps)
validation_set = set(validation_timestamps)
test_set = set(test_timestamps)

print("\n" + "=" * 70)
print("OVERLAP CHECK")
print("=" * 70)

print(
    "Train/Validation overlap:",
    len(train_set & validation_set)
)

print(
    "Validation/Test overlap:",
    len(validation_set & test_set)
)

print(
    "Train/Test overlap:",
    len(train_set & test_set)
)

# ============================================================
# LOCATION COUNTS
# ============================================================

def print_location_counts(
    name,
    latitude,
    longitude
):

    print(f"\n{name}")

    locations_array = np.column_stack(
        [latitude, longitude]
    )

    unique, counts = np.unique(
        locations_array,
        axis=0,
        return_counts=True
    )

    print(
        "Locations:",
        len(unique)
    )

    for loc, count in zip(
        unique,
        counts
    ):
        print(
            f"  {loc[0]:.2f}, "
            f"{loc[1]:.2f}: "
            f"{count}"
        )


print("\n" + "=" * 70)
print("LOCATION COUNTS")
print("=" * 70)

print_location_counts(
    "Training",
    train_latitude,
    train_longitude
)

print_location_counts(
    "Validation",
    validation_latitude,
    validation_longitude
)

print_location_counts(
    "Test",
    test_latitude,
    test_longitude
)

print("\n" + "=" * 70)
print("FILES CREATED")
print("=" * 70)

print(TRAIN_OUTPUT)
print(VALIDATION_OUTPUT)
print(TEST_OUTPUT)
print(METADATA_OUTPUT)
print(SCALER_DIR)

print("\nOld lstm_sequences.npz was NOT modified.")

print("\nDone.")
