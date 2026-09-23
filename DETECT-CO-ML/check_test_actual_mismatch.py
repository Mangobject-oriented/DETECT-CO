import numpy as np
import pandas as pd

BASE = "/home/miguel/DETECT-CO-ML/data"

TEST_XGB_FILE = f"{BASE}/xgboost/xgboost_test_predictions_clean_mm.npz"
WEATHER_FILE = f"{BASE}/calamba_weather_features.csv"

TARGETS = [
    "rainfall_1h_mm",
    "rainfall_3h_mm",
    "rainfall_6h_mm",
    "rainfall_12h_mm",
    "rainfall_24h_mm"
]

xgb_data = np.load(
    TEST_XGB_FILE,
    allow_pickle=True
)

stored_actual = xgb_data["actual"]

timestamps = pd.to_datetime(
    xgb_data["timestamps"]
)

latitude = np.round(
    xgb_data["latitude"].astype(float),
    2
)

longitude = np.round(
    xgb_data["longitude"].astype(float),
    2
)

weather = pd.read_csv(
    WEATHER_FILE,
    parse_dates=["timestamp"]
)

weather["latitude"] = weather["latitude"].round(2)
weather["longitude"] = weather["longitude"].round(2)

lookup = weather[
    [
        "timestamp",
        "latitude",
        "longitude"
    ] + TARGETS
].copy()

keys = pd.DataFrame({
    "timestamp": timestamps,
    "latitude": latitude,
    "longitude": longitude
})

merged = keys.merge(
    lookup,
    on=[
        "timestamp",
        "latitude",
        "longitude"
    ],
    how="left"
)

reconstructed = merged[
    TARGETS
].to_numpy(
    dtype=float
)

print("=" * 75)
print("TEST ACTUAL MISMATCH DIAGNOSTIC")
print("=" * 75)

print()
print("Stored actual shape:", stored_actual.shape)
print("Reconstructed shape:", reconstructed.shape)

print()
print("Stored actual means:")
print(np.mean(stored_actual, axis=0))

print()
print("Reconstructed Open-Meteo means:")
print(np.mean(reconstructed, axis=0))

print()
print("Stored actual maxima:")
print(np.max(stored_actual, axis=0))

print()
print("Reconstructed maxima:")
print(np.max(reconstructed, axis=0))

print()
print("Missing reconstructed values:")
print(np.isnan(reconstructed).sum())

diff = stored_actual - reconstructed

print()
print("Maximum absolute difference per target:")
print(np.nanmax(np.abs(diff), axis=0))

print()
print("Mean absolute difference per target:")
print(np.nanmean(np.abs(diff), axis=0))

print()
print("Number of different values per target:")
print(np.sum(~np.isclose(
    stored_actual,
    reconstructed,
    atol=1e-6,
    rtol=1e-6
), axis=0))

# ---------------------------------------------------------
# SHOW FIRST MISMATCH
# ---------------------------------------------------------

different = ~np.isclose(
    stored_actual,
    reconstructed,
    atol=1e-6,
    rtol=1e-6
)

rows = np.where(
    np.any(different, axis=1)
)[0]

print()

if len(rows) == 0:

    print("NO MEANINGFUL DIFFERENCES FOUND.")

else:

    print("First mismatch rows:")
    print()

    for row in rows[:10]:

        print("Row:", row)
        print("Timestamp:", timestamps[row])
        print("Latitude:", latitude[row])
        print("Longitude:", longitude[row])

        print("Stored:")
        print(stored_actual[row])

        print("Open-Meteo:")
        print(reconstructed[row])

        print("Difference:")
        print(diff[row])

        print()

print("=" * 75)
print("DIAGNOSTIC COMPLETE")
print("=" * 75)
