#!/usr/bin/env python3

import os
import pandas as pd

INPUT_FILE = "/home/miguel/DETECT-CO-ML/data/calamba_historical_weather.csv"
OUTPUT_FILE = "/home/miguel/DETECT-CO-ML/data/calamba_weather_features.csv"

print("Loading historical weather data...")
df = pd.read_csv(INPUT_FILE)

# Convert timestamp
df["timestamp"] = pd.to_datetime(df["timestamp"])

# Sort correctly by location and time
df = df.sort_values(
    ["latitude", "longitude", "timestamp"]
).reset_index(drop=True)

print("Original rows:", len(df))

# ---------------------------------------------------------
# REMOVE ROWS WITH MISSING WEATHER VALUES
# ---------------------------------------------------------

required_columns = [
    "temperature_c",
    "humidity_percent",
    "rainfall_mm"
]

before = len(df)

df = df.dropna(
    subset=required_columns
).copy()

removed = before - len(df)

print("Rows removed because of missing values:", removed)
print("Rows remaining:", len(df))

# ---------------------------------------------------------
# RAINFALL FEATURES
# ---------------------------------------------------------
# IMPORTANT:
# These are calculated separately for each coordinate so
# rainfall from one grid point does not leak into another.

grouped = df.groupby(
    ["latitude", "longitude"],
    group_keys=False
)

df["rainfall_1h_mm"] = df["rainfall_mm"]

df["rainfall_3h_mm"] = grouped["rainfall_mm"].transform(
    lambda x: x.rolling(3, min_periods=1).sum()
)

df["rainfall_6h_mm"] = grouped["rainfall_mm"].transform(
    lambda x: x.rolling(6, min_periods=1).sum()
)

df["rainfall_12h_mm"] = grouped["rainfall_mm"].transform(
    lambda x: x.rolling(12, min_periods=1).sum()
)

df["rainfall_24h_mm"] = grouped["rainfall_mm"].transform(
    lambda x: x.rolling(24, min_periods=1).sum()
)

# ---------------------------------------------------------
# RAINFALL INTENSITY FEATURES
# ---------------------------------------------------------

df["rainfall_3h_avg_mm"] = (
    df["rainfall_3h_mm"] / 3.0
)

df["rainfall_6h_avg_mm"] = (
    df["rainfall_6h_mm"] / 6.0
)

df["rainfall_12h_avg_mm"] = (
    df["rainfall_12h_mm"] / 12.0
)

df["rainfall_24h_avg_mm"] = (
    df["rainfall_24h_mm"] / 24.0
)

# ---------------------------------------------------------
# TIME FEATURES
# ---------------------------------------------------------

df["hour"] = df["timestamp"].dt.hour
df["day_of_week"] = df["timestamp"].dt.dayofweek
df["month"] = df["timestamp"].dt.month

# ---------------------------------------------------------
# SAVE
# ---------------------------------------------------------

os.makedirs(
    os.path.dirname(OUTPUT_FILE),
    exist_ok=True
)

df.to_csv(
    OUTPUT_FILE,
    index=False
)

print()
print("========================================")
print("WEATHER DATA PREPARATION COMPLETE")
print("========================================")
print("Output:", OUTPUT_FILE)
print("Rows:", len(df))
print("Columns:", len(df.columns))
print()
print("Columns:")
for column in df.columns:
    print(" -", column)

print()
print("Missing values:")
print(df.isna().sum())

print()
print("Sample:")
print(df.head(10).to_string(index=False))

print()
print("========================================")
print("RAINFALL FEATURE SUMMARY")
print("========================================")
print(
    df[
        [
            "rainfall_1h_mm",
            "rainfall_3h_mm",
            "rainfall_6h_mm",
            "rainfall_12h_mm",
            "rainfall_24h_mm"
        ]
    ].describe()
)
