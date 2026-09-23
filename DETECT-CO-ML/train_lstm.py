#!/usr/bin/env python3

import os
import json
import time
import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

# ============================================================
# CONFIGURATION
# ============================================================

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"

TRAIN_FILE = os.path.join(
    DATA_DIR,
    "lstm_train_clean.npz"
)

VALIDATION_FILE = os.path.join(
    DATA_DIR,
    "lstm_validation_clean.npz"
)

TEST_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_clean.npz"
)

MODEL_DIR = os.path.join(
    DATA_DIR,
    "models"
)

MODEL_FILE = os.path.join(
    MODEL_DIR,
    "lstm_rainfall_model.keras"
)

HISTORY_FILE = os.path.join(
    MODEL_DIR,
    "lstm_training_history.json"
)

PREDICTIONS_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_predictions.npz"
)

os.makedirs(
    MODEL_DIR,
    exist_ok=True
)

# ============================================================
# TRAINING SETTINGS
# ============================================================

BATCH_SIZE = 128
EPOCHS = 30

LEARNING_RATE = 0.001

# Reproducibility
SEED = 42

np.random.seed(SEED)
tf.random.set_seed(SEED)

# ============================================================
# CPU CONFIGURATION
# ============================================================

# Limit TensorFlow thread usage so the system remains usable
# during training on the 8 GB RAM machine.

try:
    tf.config.threading.set_intra_op_parallelism_threads(4)
    tf.config.threading.set_inter_op_parallelism_threads(2)
except Exception:
    pass

print("=" * 70)
print("DETECT-CO LSTM TRAINING")
print("=" * 70)

print("\nTensorFlow version:")
print(tf.__version__)

print("\nAvailable devices:")
print(
    tf.config.list_physical_devices()
)

print("\nUsing CPU for training.")

# ============================================================
# LOAD DATA
# ============================================================

print("\n" + "=" * 70)
print("LOADING DATA")
print("=" * 70)

print("\nLoading training data...")

train_data = np.load(
    TRAIN_FILE,
    allow_pickle=True
)

X_train = train_data["X"].astype(
    np.float32
)

y_train = train_data["y"].astype(
    np.float32
)

print("Training X:", X_train.shape)
print("Training y:", y_train.shape)

print("\nLoading validation data...")

validation_data = np.load(
    VALIDATION_FILE,
    allow_pickle=True
)

X_validation = validation_data["X"].astype(
    np.float32
)

y_validation = validation_data["y"].astype(
    np.float32
)

print(
    "Validation X:",
    X_validation.shape
)

print(
    "Validation y:",
    y_validation.shape
)

print("\nLoading test data...")

test_data = np.load(
    TEST_FILE,
    allow_pickle=True
)

X_test = test_data["X"].astype(
    np.float32
)

y_test = test_data["y"].astype(
    np.float32
)

test_timestamps = test_data[
    "timestamps"
]

test_latitude = test_data[
    "latitude"
]

test_longitude = test_data[
    "longitude"
]

print(
    "Test X:",
    X_test.shape
)

print(
    "Test y:",
    y_test.shape
)

# ============================================================
# BASIC VALIDATION
# ============================================================

print("\n" + "=" * 70)
print("DATA VALIDATION")
print("=" * 70)

print(
    "\nTraining NaN:",
    np.isnan(X_train).sum() +
    np.isnan(y_train).sum()
)

print(
    "Validation NaN:",
    np.isnan(X_validation).sum() +
    np.isnan(y_validation).sum()
)

print(
    "Test NaN:",
    np.isnan(X_test).sum() +
    np.isnan(y_test).sum()
)

print(
    "\nTraining value range:",
    float(X_train.min()),
    "to",
    float(X_train.max())
)

print(
    "Validation value range:",
    float(X_validation.min()),
    "to",
    float(X_validation.max())
)

print(
    "Test value range:",
    float(X_test.min()),
    "to",
    float(X_test.max())
)

# ============================================================
# BUILD LSTM MODEL
# ============================================================

print("\n" + "=" * 70)
print("BUILDING LSTM MODEL")
print("=" * 70)

input_shape = (
    X_train.shape[1],
    X_train.shape[2]
)

print(
    "\nInput shape:",
    input_shape
)

print(
    "Output targets:",
    y_train.shape[1]
)

model = keras.Sequential(
    [

        layers.Input(
            shape=input_shape
        ),

        layers.LSTM(
            64,
            return_sequences=True
        ),

        layers.Dropout(
            0.20
        ),

        layers.LSTM(
            32,
            return_sequences=False
        ),

        layers.Dropout(
            0.20
        ),

        layers.Dense(
            32,
            activation="relu"
        ),

        layers.Dense(
            5,
            activation="linear"
        )
    ]
)

optimizer = keras.optimizers.Adam(
    learning_rate=LEARNING_RATE
)

model.compile(
    optimizer=optimizer,
    loss=keras.losses.Huber(),
    metrics=[
        keras.metrics.MeanAbsoluteError(
            name="mae"
        ),
        keras.metrics.RootMeanSquaredError(
            name="rmse"
        )
    ]
)

print("\nModel summary:\n")

model.summary()

# ============================================================
# CALLBACKS
# ============================================================

checkpoint = keras.callbacks.ModelCheckpoint(
    MODEL_FILE,
    monitor="val_loss",
    save_best_only=True,
    mode="min",
    verbose=1
)

early_stopping = keras.callbacks.EarlyStopping(
    monitor="val_loss",
    patience=5,
    mode="min",
    restore_best_weights=True,
    verbose=1
)

reduce_lr = keras.callbacks.ReduceLROnPlateau(
    monitor="val_loss",
    factor=0.5,
    patience=2,
    min_lr=1e-6,
    verbose=1
)

# ============================================================
# TRAIN
# ============================================================

print("\n" + "=" * 70)
print("STARTING TRAINING")
print("=" * 70)

print(
    f"\nBatch size: {BATCH_SIZE}"
)

print(
    f"Maximum epochs: {EPOCHS}"
)

print(
    "\nTraining may take some time because "
    "TensorFlow is using the CPU."
)

start_time = time.time()

history = model.fit(
    X_train,
    y_train,

    validation_data=(
        X_validation,
        y_validation
    ),

    epochs=EPOCHS,

    batch_size=BATCH_SIZE,

    callbacks=[
        checkpoint,
        early_stopping,
        reduce_lr
    ],

    verbose=1,

    shuffle=False
)

training_time = (
    time.time() - start_time
)

# ============================================================
# SAVE TRAINING HISTORY
# ============================================================

history_dict = {
    key: [
        float(value)
        for value in values
    ]
    for key, values in history.history.items()
}

history_dict["training_time_seconds"] = float(
    training_time
)

history_dict["epochs_completed"] = int(
    len(history.history["loss"])
)

with open(
    HISTORY_FILE,
    "w"
) as f:

    json.dump(
        history_dict,
        f,
        indent=4
    )

# ============================================================
# LOAD BEST MODEL
# ============================================================

print("\n" + "=" * 70)
print("LOADING BEST MODEL")
print("=" * 70)

best_model = keras.models.load_model(
    MODEL_FILE
)

print(
    "\nBest model loaded from:"
)

print(
    MODEL_FILE
)

# ============================================================
# TEST EVALUATION
# ============================================================

print("\n" + "=" * 70)
print("TEST EVALUATION")
print("=" * 70)

test_results = best_model.evaluate(
    X_test,
    y_test,
    batch_size=BATCH_SIZE,
    verbose=1
)

print("\nTest results:")

for name, value in zip(
    best_model.metrics_names,
    test_results
):

    print(
        f"{name}: {value:.6f}"
    )

# ============================================================
# GENERATE TEST PREDICTIONS
# ============================================================

print("\n" + "=" * 70)
print("GENERATING TEST PREDICTIONS")
print("=" * 70)

prediction_start = time.time()

test_predictions = best_model.predict(
    X_test,
    batch_size=BATCH_SIZE,
    verbose=1
)

prediction_time = (
    time.time() - prediction_start
)

print(
    "\nPrediction shape:",
    test_predictions.shape
)

# ============================================================
# SAVE PREDICTIONS
# ============================================================

np.savez_compressed(
    PREDICTIONS_FILE,

    predictions=test_predictions,

    actual=y_test,

    timestamps=test_timestamps,

    latitude=test_latitude,

    longitude=test_longitude
)

print(
    "\nPredictions saved:"
)

print(
    PREDICTIONS_FILE
)

# ============================================================
# FINAL REPORT
# ============================================================

print("\n" + "=" * 70)
print("LSTM TRAINING COMPLETE")
print("=" * 70)

print(
    f"\nTraining time: "
    f"{training_time / 60:.2f} minutes"
)

print(
    f"Prediction time: "
    f"{prediction_time:.2f} seconds"
)

print(
    "\nEpochs completed:",
    len(history.history["loss"])
)

print(
    "\nFinal training loss:",
    f"{history.history['loss'][-1]:.6f}"
)

print(
    "Final validation loss:",
    f"{history.history['val_loss'][-1]:.6f}"
)

print(
    "\nBest model:"
)

print(
    MODEL_FILE
)

print(
    "\nTraining history:"
)

print(
    HISTORY_FILE
)

print(
    "\nTest predictions:"
)

print(
    PREDICTIONS_FILE
)

print("\n" + "=" * 70)
print("NEXT STAGE")
print("=" * 70)

print(
    "\nAfter this model is verified, "
    "we will prepare its outputs for XGBoost."
)

print(
    "\nImportant: the current LSTM predicts "
    "rainfall values. It is not yet a validated "
    "flood-event classifier."
)

print("\nDone.")
