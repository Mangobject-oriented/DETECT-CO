#!/usr/bin/env python3

import os
import json
import time
import numpy as np
import tensorflow as tf
from tensorflow import keras

# ============================================================
# CONFIGURATION
# ============================================================

DATA_DIR = "/home/miguel/DETECT-CO-ML/data"
MODEL_DIR = os.path.join(DATA_DIR, "models")

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

MODEL_FILE = os.path.join(
    MODEL_DIR,
    "lstm_rainfall_model.keras"
)

RESUME_MODEL_FILE = os.path.join(
    MODEL_DIR,
    "lstm_rainfall_resume.keras"
)

HISTORY_FILE = os.path.join(
    MODEL_DIR,
    "lstm_resume_history.json"
)

PREDICTIONS_FILE = os.path.join(
    DATA_DIR,
    "lstm_test_predictions.npz"
)

BATCH_SIZE = 128
ADDITIONAL_EPOCHS = 15

SEED = 42

np.random.seed(SEED)
tf.random.set_seed(SEED)

# ============================================================
# CPU SETTINGS
# ============================================================

try:
    tf.config.threading.set_intra_op_parallelism_threads(4)
    tf.config.threading.set_inter_op_parallelism_threads(2)
except Exception:
    pass

print("=" * 70)
print("DETECT-CO LSTM — RESUME TRAINING")
print("=" * 70)

print("\nTensorFlow:", tf.__version__)

print(
    "Devices:",
    tf.config.list_physical_devices()
)

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

print("Training:", X_train.shape, y_train.shape)

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
    "Validation:",
    X_validation.shape,
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
    "Test:",
    X_test.shape,
    y_test.shape
)

# ============================================================
# LOAD EXISTING CHECKPOINT
# ============================================================

if not os.path.exists(MODEL_FILE):

    raise FileNotFoundError(
        f"Checkpoint not found:\n{MODEL_FILE}"
    )

print("\n" + "=" * 70)
print("LOADING EXISTING CHECKPOINT")
print("=" * 70)

print(
    "\nLoading:",
    MODEL_FILE
)

model = keras.models.load_model(
    MODEL_FILE
)

print("\nCheckpoint loaded successfully.")

print("\nCurrent model:")

model.summary()

# ============================================================
# RECOMPILE
# ============================================================

print("\nRecompiling model...")

model.compile(
    optimizer=keras.optimizers.Adam(
        learning_rate=0.0005
    ),

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

# ============================================================
# CALLBACKS
# ============================================================

checkpoint = keras.callbacks.ModelCheckpoint(
    RESUME_MODEL_FILE,
    monitor="val_loss",
    save_best_only=True,
    mode="min",
    verbose=1
)

early_stopping = keras.callbacks.EarlyStopping(
    monitor="val_loss",
    patience=4,
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
# TRAINING
# ============================================================

print("\n" + "=" * 70)
print("RESUMING TRAINING")
print("=" * 70)

print(
    f"\nAdditional epochs allowed: "
    f"{ADDITIONAL_EPOCHS}"
)

print(
    f"Batch size: {BATCH_SIZE}"
)

print(
    "\nThe model is starting from the saved "
    "best checkpoint."
)

start_time = time.time()

history = model.fit(

    X_train,
    y_train,

    validation_data=(
        X_validation,
        y_validation
    ),

    epochs=ADDITIONAL_EPOCHS,

    batch_size=BATCH_SIZE,

    callbacks=[
        checkpoint,
        early_stopping,
        reduce_lr
    ],

    shuffle=False,

    verbose=1
)

training_time = (
    time.time() - start_time
)

# ============================================================
# SAVE HISTORY
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
# LOAD BEST RESUMED MODEL
# ============================================================

if os.path.exists(
    RESUME_MODEL_FILE
):

    print(
        "\nLoading best resumed model..."
    )

    model = keras.models.load_model(
        RESUME_MODEL_FILE
    )

else:

    print(
        "\nNo improved resume checkpoint was "
        "created. Using current model."
    )

# ============================================================
# TEST EVALUATION
# ============================================================

print("\n" + "=" * 70)
print("TEST EVALUATION")
print("=" * 70)

test_results = model.evaluate(
    X_test,
    y_test,
    batch_size=BATCH_SIZE,
    verbose=1
)

for name, value in zip(
    model.metrics_names,
    test_results
):

    print(
        f"{name}: {value:.6f}"
    )

# ============================================================
# TEST PREDICTIONS
# ============================================================

print("\n" + "=" * 70)
print("GENERATING TEST PREDICTIONS")
print("=" * 70)

prediction_start = time.time()

predictions = model.predict(
    X_test,
    batch_size=BATCH_SIZE,
    verbose=1
)

prediction_time = (
    time.time() - prediction_start
)

print(
    "\nPrediction shape:",
    predictions.shape
)

# ============================================================
# SAVE PREDICTIONS
# ============================================================

np.savez_compressed(
    PREDICTIONS_FILE,

    predictions=predictions,

    actual=y_test,

    timestamps=test_timestamps,

    latitude=test_latitude,

    longitude=test_longitude
)

# ============================================================
# REPLACE MAIN MODEL ONLY IF RESUME MODEL EXISTS
# ============================================================

if os.path.exists(
    RESUME_MODEL_FILE
):

    import shutil

    shutil.copy2(
        RESUME_MODEL_FILE,
        MODEL_FILE
    )

    print(
        "\nUpdated main LSTM model:"
    )

    print(
        MODEL_FILE
    )

# ============================================================
# FINAL REPORT
# ============================================================

print("\n" + "=" * 70)
print("RESUMED LSTM TRAINING COMPLETE")
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
    "\nAdditional epochs completed:",
    len(history.history["loss"])
)

print(
    "\nStarting loss:",
    f"{history.history['loss'][0]:.6f}"
)

print(
    "Ending loss:",
    f"{history.history['loss'][-1]:.6f}"
)

print(
    "\nStarting validation loss:",
    f"{history.history['val_loss'][0]:.6f}"
)

print(
    "Ending validation loss:",
    f"{history.history['val_loss'][-1]:.6f}"
)

print(
    "\nModel:",
    MODEL_FILE
)

print(
    "Predictions:",
    PREDICTIONS_FILE
)

print("\nDone.")
