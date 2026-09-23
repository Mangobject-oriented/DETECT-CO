#!/usr/bin/env python3

import os
import numpy as np
import tensorflow as tf

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"

MODEL_FILE = os.path.join(
    DATA_DIR,
    "models",
    "lstm_rainfall_model.keras"
)

DATASETS = {
    "train": "lstm_train_clean.npz",
    "validation": "lstm_validation_clean.npz",
    "test": "lstm_test_clean.npz"
}

print("=" * 70)
print("DETECT-CO — GENERATE LSTM PREDICTIONS")
print("=" * 70)

print()
print("Loading model:")
print(MODEL_FILE)

model = tf.keras.models.load_model(
    MODEL_FILE
)

print()
print("Model loaded successfully.")

for split, filename in DATASETS.items():

    print()
    print("=" * 70)
    print(f"{split.upper()} PREDICTIONS")
    print("=" * 70)

    input_file = os.path.join(
        DATA_DIR,
        filename
    )

    print("Loading:")
    print(input_file)

    data = np.load(
        input_file,
        allow_pickle=True
    )

    X = data["X"]
    y = data["y"]

    timestamps = data["timestamps"]
    latitude = data["latitude"]
    longitude = data["longitude"]

    print("X shape:", X.shape)
    print("y shape:", y.shape)

    print()
    print("Generating predictions...")

    predictions = model.predict(
        X,
        batch_size=256,
        verbose=1
    )

    output_file = os.path.join(
        DATA_DIR,
        f"lstm_{split}_predictions.npz"
    )

    np.savez_compressed(
        output_file,
        predictions=predictions,
        actual=y,
        timestamps=timestamps,
        latitude=latitude,
        longitude=longitude
    )

    print()
    print("Predictions shape:", predictions.shape)
    print("Saved:")
    print(output_file)

print()
print("=" * 70)
print("ALL LSTM PREDICTIONS GENERATED")
print("=" * 70)

print()
print("Files:")

for split in DATASETS:
    print(
        os.path.join(
            DATA_DIR,
            f"lstm_{split}_predictions.npz"
        )
    )

print()
print("Done.")
