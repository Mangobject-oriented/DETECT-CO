#!/usr/bin/env python3

import os
import requests
import pandas as pd
import time

# ============================================================
# SETTINGS
# ============================================================

START_DATE = "2020-01-01"
END_DATE = "2026-09-20"

OUTPUT_DIR = os.path.expanduser(
    "~/DETECT-CO-ML/data"
)

OUTPUT_FILE = os.path.join(
    OUTPUT_DIR,
    "calamba_historical_weather.csv"
)

# Calamba / surrounding area
TARGETS = [
    (14.15, 121.05),
    (14.15, 121.15),
    (14.25, 121.05),
    (14.25, 121.15),
]

API_URL = "https://archive-api.open-meteo.com/v1/archive"

# ============================================================
# PREPARE
# ============================================================

os.makedirs(OUTPUT_DIR, exist_ok=True)

print()
print("==============================================")
print(" DETECT-CO Historical Weather Downloader")
print("==============================================")
print()

print("Period:")
print(START_DATE)
print("to")
print(END_DATE)

print()
print("Locations:")

for lat, lon in TARGETS:
    print(f"  {lat}, {lon}")

print()

all_data = []

# ============================================================
# DOWNLOAD EACH LOCATION
# ============================================================

for location_number, (lat, lon) in enumerate(TARGETS, start=1):

    print(
        f"[{location_number}/{len(TARGETS)}] "
        f"Downloading {lat}, {lon}..."
    )

    params = {
        "latitude": lat,
        "longitude": lon,

        "start_date": START_DATE,
        "end_date": END_DATE,

        "hourly": ",".join([
            "temperature_2m",
            "relative_humidity_2m",
            "precipitation",
            "rain"
        ]),

        "timezone": "Asia/Manila",

        "cell_selection": "land",

        "models": "era5"
    }

    try:

        response = requests.get(
            API_URL,
            params=params,
            timeout=120
        )

        response.raise_for_status()

        data = response.json()

        hourly = data["hourly"]

        df = pd.DataFrame(hourly)

        df["latitude"] = lat
        df["longitude"] = lon

        all_data.append(df)

        print(
            f"    Received {len(df):,} hourly records"
        )

    except Exception as e:

        print(
            f"    ERROR: {e}"
        )

    time.sleep(1)

# ============================================================
# CHECK DATA
# ============================================================

if not all_data:

    print()
    print("ERROR: No data was downloaded.")
    print("Check your internet connection and try again.")
    exit(1)

# ============================================================
# COMBINE
# ============================================================

df = pd.concat(
    all_data,
    ignore_index=True
)

# ============================================================
# RENAME COLUMNS
# ============================================================

df = df.rename(
    columns={
        "time": "timestamp",
        "temperature_2m": "temperature_c",
        "relative_humidity_2m": "humidity_percent",
        "precipitation": "rainfall_mm",
        "rain": "rain_mm"
    }
)

# ============================================================
# SORT
# ============================================================

df["timestamp"] = pd.to_datetime(
    df["timestamp"]
)

df = df.sort_values(
    [
        "latitude",
        "longitude",
        "timestamp"
    ]
)

# ============================================================
# SAVE
# ============================================================

df.to_csv(
    OUTPUT_FILE,
    index=False
)

# ============================================================
# SUMMARY
# ============================================================

print()
print("==============================================")
print(" DOWNLOAD COMPLETE")
print("==============================================")
print()

print("Output:")
print(OUTPUT_FILE)

print()

print(f"Total rows: {len(df):,}")

print()

print("Columns:")
for column in df.columns:
    print(f"  {column}")

print()

print("First records:")
print(df.head(5).to_string(index=False))

print()
print("Last records:")
print(df.tail(5).to_string(index=False))

print()
print("==============================================")
