#!/usr/bin/env python3

import os
import numpy as np
import pandas as pd

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
WEATHER_FILE = os.path.join(
    DATA_DIR,
    "calamba_weather_features.csv"
)
XGB_DIR = os.path.join(DATA_DIR, "xgboost")

os.makedirs(XGB_DIR, exist_ok=True)

# ---------------------------------------------------------
# FEATURES
# ---------------------------------------------------------

WEATHER_FEATURES = [
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

LSTM_FEATURES = [
    "lstm_pred_1h_mm",
    "lstm_pred_3h_mm",
    "lstm_pred_6h_mm",
    "lstm_pred_12h_mm",
    "lstm_pred_24h_mm"
]

TARGET_COLUMNS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

# ---------------------------------------------------------
# LOAD OPEN-METEO DATA
# ---------------------------------------------------------

print("=" * 70)
print("CREATING CLEAN XGBOOST DATASETS")
print("=" * 70)

print()
print("Loading Open-Meteo weather data...")

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

weather = weather.sort_values(
    ["latitude", "longitude", "timestamp"]
).reset_index(drop=True)

print("Weather rows:", len(weather))

# ---------------------------------------------------------
# LOAD LSTM PREDICTIONS
# ---------------------------------------------------------

def load_lstm_predictions(filename):

    path = os.path.join(
        DATA_DIR,
        filename
    )

    data = np.load(
        path,
        allow_pickle=True
    )

    predictions = data["predictions"]

    timestamps = pd.to_datetime(
        data["timestamps"]
    )

    latitude = np.round(
        data["latitude"].astype(float),
        2
    )

    longitude = np.round(
        data["longitude"].astype(float),
        2
    )

    actual = data["actual"]

    rows = pd.DataFrame({
        "timestamp": timestamps,
        "latitude": latitude,
        "longitude": longitude
    })

    # LSTM predictions become XGBoost features.
    for i, column in enumerate(LSTM_FEATURES):
        rows[column] = predictions[:, i]

    # LSTM actual values become XGBoost targets.
    for i, column in enumerate(TARGET_COLUMNS):
        rows[column] = actual[:, i]

    return rows


print()
print("Loading LSTM predictions...")

train_lstm = load_lstm_predictions(
    "lstm_train_predictions.npz"
)

validation_lstm = load_lstm_predictions(
    "lstm_validation_predictions.npz"
)

test_lstm = load_lstm_predictions(
    "lstm_test_predictions.npz"
)

print(
    "Train LSTM predictions:",
    len(train_lstm)
)

print(
    "Validation LSTM predictions:",
    len(validation_lstm)
)

print(
    "Test LSTM predictions:",
    len(test_lstm)
)

# ---------------------------------------------------------
# PREPARE PAST WEATHER
# ---------------------------------------------------------

# Rename weather columns so they cannot collide with
# the target columns during the merge.

weather_past = weather[
    [
        "timestamp",
        "latitude",
        "longitude"
    ] + WEATHER_FEATURES
].copy()

weather_past = weather_past.rename(
    columns={
        column: f"weather_{column}"
        for column in WEATHER_FEATURES
    }
)

# Shift the timestamp forward by one hour.
#
# Example:
#
# Original Open-Meteo:
# 09:00 -> weather information
#
# After shift:
# 09:00 weather -> associated with target time 10:00
#
# Therefore XGBoost only receives information available
# before the target timestamp.

weather_past["timestamp"] = (
    weather_past["timestamp"]
    + pd.Timedelta(hours=1)
)

print()
print(
    "Open-Meteo features shifted by 1 hour."
)

# ---------------------------------------------------------
# MERGE FUNCTION
# ---------------------------------------------------------

def create_split(
    lstm_data,
    split_name
):

    print()
    print("=" * 70)
    print(
        f"CREATING {split_name.upper()} DATASET"
    )
    print("=" * 70)

    merged = pd.merge(
        lstm_data,
        weather_past,
        on=[
            "timestamp",
            "latitude",
            "longitude"
        ],
        how="inner"
    )

    merged = merged.sort_values(
        [
            "timestamp",
            "latitude",
            "longitude"
        ]
    ).reset_index(drop=True)

    print()
    print("Merged rows:", len(merged))

    if len(merged) == 0:
        raise RuntimeError(
            f"No rows merged for {split_name}."
        )

    # -----------------------------------------------------
    # BUILD WEATHER FEATURE NAMES
    # -----------------------------------------------------

    shifted_weather_features = [
        f"weather_{column}"
        for column in WEATHER_FEATURES
    ]

    feature_columns = (
        shifted_weather_features +
        LSTM_FEATURES
    )

    # -----------------------------------------------------
    # CHECK MISSING VALUES
    # -----------------------------------------------------

    missing_features = merged[
        feature_columns
    ].isna().sum()

    missing_targets = merged[
        TARGET_COLUMNS
    ].isna().sum()

    total_missing = (
        missing_features.sum()
        + missing_targets.sum()
    )

    print()
    print(
        "Missing feature values:",
        missing_features.sum()
    )

    print(
        "Missing target values:",
        missing_targets.sum()
    )

    if total_missing != 0:

        print()
        print("Missing feature details:")
        print(
            missing_features[
                missing_features > 0
            ]
        )

        print()
        print("Missing target details:")
        print(
            missing_targets[
                missing_targets > 0
            ]
        )

        raise RuntimeError(
            f"Missing values found in {split_name}."
        )

    # -----------------------------------------------------
    # BUILD ARRAYS
    # -----------------------------------------------------

    X = merged[
        feature_columns
    ].to_numpy(
        dtype=np.float32
    )

    y = merged[
        TARGET_COLUMNS
    ].to_numpy(
        dtype=np.float32
    )

    timestamps = (
        merged["timestamp"]
        .astype(str)
        .to_numpy()
    )

    latitude = merged[
        "latitude"
    ].to_numpy(
        dtype=np.float32
    )

    longitude = merged[
        "longitude"
    ].to_numpy(
        dtype=np.float32
    )

    # -----------------------------------------------------
    # IMPORTANT LEAKAGE CHECK
    # -----------------------------------------------------

    print()
    print("Checking target leakage...")

    for target in TARGET_COLUMNS:

        shifted_column = f"weather_{target}"

        target_values = merged[
            target
        ].to_numpy()

        shifted_values = merged[
            shifted_column
        ].to_numpy()

        identical = np.isclose(
            target_values,
            shifted_values,
            rtol=0,
            atol=0
        ).mean()

        print(
            f"{target}: "
            f"same-value ratio = "
            f"{identical:.6f}"
        )

    print()
    print(
        "The weather features represent t-1, "
        "while targets represent t."
    )

    # -----------------------------------------------------
    # SAVE NPZ
    # -----------------------------------------------------

    npz_file = os.path.join(
        XGB_DIR,
        f"xgboost_{split_name}_clean.npz"
    )

    np.savez_compressed(
        npz_file,
        X=X,
        y=y,
        timestamps=timestamps,
        latitude=latitude,
        longitude=longitude,
        feature_columns=np.array(
            feature_columns
        ),
        target_columns=np.array(
            TARGET_COLUMNS
        )
    )

    # -----------------------------------------------------
    # SAVE CSV
    # -----------------------------------------------------

    csv_file = os.path.join(
        XGB_DIR,
        f"xgboost_{split_name}_clean.csv"
    )

    output_columns = [
        "timestamp",
        "latitude",
        "longitude"
    ] + feature_columns + TARGET_COLUMNS

    merged[
        output_columns
    ].to_csv(
        csv_file,
        index=False
    )

    # -----------------------------------------------------
    # REPORT
    # -----------------------------------------------------

    print()
    print("X shape:", X.shape)
    print("y shape:", y.shape)

    print(
        "Start:",
        merged["timestamp"].min()
    )

    print(
        "End:",
        merged["timestamp"].max()
    )

    print()
    print("Locations:")

    print(
        merged.groupby(
            ["latitude", "longitude"]
        ).size()
    )

    print()
    print("Saved:")
    print(npz_file)
    print(csv_file)

    return merged


# ---------------------------------------------------------
# CREATE SPLITS
# ---------------------------------------------------------

train = create_split(
    train_lstm,
    "train"
)

validation = create_split(
    validation_lstm,
    "validation"
)

test = create_split(
    test_lstm,
    "test"
)

# ---------------------------------------------------------
# FINAL VERIFICATION
# ---------------------------------------------------------

print()
print("=" * 70)
print("FINAL VERIFICATION")
print("=" * 70)

for name, dataframe in [
    ("TRAIN", train),
    ("VALIDATION", validation),
    ("TEST", test)
]:

    print()
    print(name)

    print(
        "Rows:",
        len(dataframe)
    )

    print(
        "Features:",
        len(
            WEATHER_FEATURES +
            LSTM_FEATURES
        )
    )

    print(
        "Targets:",
        len(TARGET_COLUMNS)
    )

    print(
        "Time:",
        dataframe["timestamp"].min(),
        "→",
        dataframe["timestamp"].max()
    )

print()
print("=" * 70)
print("CLEAN XGBOOST DATASET CREATION COMPLETE")
print("=" * 70)
