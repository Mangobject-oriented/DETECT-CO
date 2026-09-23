#!/usr/bin/env python3

import numpy as np

INPUT_FILE = "/home/miguel/DETECT-CO-ML/data/lstm_sequences.npz"
OUTPUT_DIR = "/home/miguel/DETECT-CO-ML/data"

print("Loading LSTM sequence dataset...")

data = np.load(INPUT_FILE)

X = data["X"]
y = data["y"]
timestamps = data["timestamps"]
locations = data["locations"]

print("Total sequences:", len(X))
print("X shape:", X.shape)
print("y shape:", y.shape)

# ---------------------------------------------------------
# SORT BY TIMESTAMP
# ---------------------------------------------------------

print()
print("Sorting sequences chronologically...")

order = np.argsort(timestamps)

X = X[order]
y = y[order]
timestamps = timestamps[order]
locations = locations[order]

# ---------------------------------------------------------
# UNIQUE TIMESTAMPS
# ---------------------------------------------------------

unique_timestamps = np.unique(timestamps)

print("Unique timestamps:", len(unique_timestamps))

# ---------------------------------------------------------
# 70 / 15 / 15 CHRONOLOGICAL SPLIT
# ---------------------------------------------------------

train_index = int(len(unique_timestamps) * 0.70)
validation_index = int(len(unique_timestamps) * 0.85)

train_cutoff = unique_timestamps[train_index]
validation_cutoff = unique_timestamps[validation_index]

print()
print("Timestamp cutoffs:")
print("Training cutoff:", train_cutoff)
print("Validation cutoff:", validation_cutoff)

# ---------------------------------------------------------
# MASKS
# ---------------------------------------------------------

train_mask = timestamps < train_cutoff

validation_mask = (
    (timestamps >= train_cutoff)
    & (timestamps < validation_cutoff)
)

test_mask = timestamps >= validation_cutoff

# ---------------------------------------------------------
# DATASETS
# ---------------------------------------------------------

X_train = X[train_mask]
y_train = y[train_mask]
ts_train = timestamps[train_mask]
loc_train = locations[train_mask]

X_val = X[validation_mask]
y_val = y[validation_mask]
ts_val = timestamps[validation_mask]
loc_val = locations[validation_mask]

X_test = X[test_mask]
y_test = y[test_mask]
ts_test = timestamps[test_mask]
loc_test = locations[test_mask]

# ---------------------------------------------------------
# SAVE
# ---------------------------------------------------------

np.savez_compressed(
    f"{OUTPUT_DIR}/lstm_train.npz",
    X=X_train,
    y=y_train,
    timestamps=ts_train,
    locations=loc_train
)

np.savez_compressed(
    f"{OUTPUT_DIR}/lstm_validation.npz",
    X=X_val,
    y=y_val,
    timestamps=ts_val,
    locations=loc_val
)

np.savez_compressed(
    f"{OUTPUT_DIR}/lstm_test.npz",
    X=X_test,
    y=y_test,
    timestamps=ts_test,
    locations=loc_test
)

# ---------------------------------------------------------
# REPORT
# ---------------------------------------------------------

print()
print("=" * 60)
print("CORRECT CHRONOLOGICAL SPLIT")
print("=" * 60)

print()
print("TRAINING")
print("Sequences:", len(X_train))
print("X:", X_train.shape)
print("y:", y_train.shape)
print("Start:", ts_train.min())
print("End:", ts_train.max())

print()
print("VALIDATION")
print("Sequences:", len(X_val))
print("X:", X_val.shape)
print("y:", y_val.shape)
print("Start:", ts_val.min())
print("End:", ts_val.max())

print()
print("TEST")
print("Sequences:", len(X_test))
print("X:", X_test.shape)
print("y:", y_test.shape)
print("Start:", ts_test.min())
print("End:", ts_test.max())

# ---------------------------------------------------------
# OVERLAP CHECK
# ---------------------------------------------------------

train_times = set(ts_train)
validation_times = set(ts_val)
test_times = set(ts_test)

print()
print("=" * 60)
print("OVERLAP CHECK")
print("=" * 60)

print(
    "Train/Validation overlap:",
    len(train_times & validation_times)
)

print(
    "Validation/Test overlap:",
    len(validation_times & test_times)
)

print(
    "Train/Test overlap:",
    len(train_times & test_times)
)

# ---------------------------------------------------------
# LOCATION CHECK
# ---------------------------------------------------------

print()
print("=" * 60)
print("LOCATION COUNTS")
print("=" * 60)

for name, loc in [
    ("Training", loc_train),
    ("Validation", loc_val),
    ("Test", loc_test)
]:
    unique_locations = np.unique(loc, axis=0)

    print()
    print(name)
    print("Locations:", len(unique_locations))

    for latitude, longitude in unique_locations:
        count = np.sum(
            (loc[:, 0] == latitude)
            & (loc[:, 1] == longitude)
        )

        print(
            f"  {latitude}, {longitude}: {count}"
        )

print()
print("=" * 60)
print("FILES CREATED")
print("=" * 60)

print(f"{OUTPUT_DIR}/lstm_train.npz")
print(f"{OUTPUT_DIR}/lstm_validation.npz")
print(f"{OUTPUT_DIR}/lstm_test.npz")

print()
print("Chronological ordering preserved.")
print("No random shuffling.")
