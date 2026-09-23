import os
import json
import time
import numpy as np
import tensorflow as tf

from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau


# ============================================================
# PATHS
# ============================================================

BASE = "/home/miguel/DETECT-CO-ML/data"

TRAIN_FILE = os.path.join(
    BASE,
    "lstm_train_clean.npz"
)

VAL_FILE = os.path.join(
    BASE,
    "lstm_validation_clean.npz"
)

MODEL_DIR = os.path.join(
    BASE,
    "models",
    "refined_lstm"
)

os.makedirs(MODEL_DIR, exist_ok=True)


# ============================================================
# REPRODUCIBILITY
# ============================================================

np.random.seed(42)
tf.random.set_seed(42)


# ============================================================
# LOAD DATA
# ============================================================

print("=" * 70)
print("LOADING CLEAN LSTM DATA")
print("=" * 70)

train = np.load(TRAIN_FILE)
val = np.load(VAL_FILE)

X_train = train["X"].astype(np.float32)
y_train = train["y"].astype(np.float32)

X_val = val["X"].astype(np.float32)
y_val = val["y"].astype(np.float32)

print("Train X:", X_train.shape)
print("Train y:", y_train.shape)
print("Val X:  ", X_val.shape)
print("Val y:  ", y_val.shape)


# ============================================================
# MODEL CONFIGURATIONS
# ============================================================

configs = [

    {
        "name": "lstm_refined_1",
        "lstm1": 64,
        "lstm2": 32,
        "dropout": 0.15,
        "dense": 32,
        "learning_rate": 0.0005
    },

    {
        "name": "lstm_refined_2",
        "lstm1": 96,
        "lstm2": 48,
        "dropout": 0.20,
        "dense": 32,
        "learning_rate": 0.0005
    },

    {
        "name": "lstm_refined_3",
        "lstm1": 64,
        "lstm2": 32,
        "dropout": 0.10,
        "dense": 64,
        "learning_rate": 0.0005
    }
]


# ============================================================
# BUILD MODEL
# ============================================================

def build_model(config):

    model = Sequential([

        LSTM(
            config["lstm1"],
            return_sequences=True,
            input_shape=(
                X_train.shape[1],
                X_train.shape[2]
            )
        ),

        Dropout(
            config["dropout"]
        ),

        LSTM(
            config["lstm2"]
        ),

        Dropout(
            config["dropout"]
        ),

        Dense(
            config["dense"],
            activation="relu"
        ),

        Dense(
            5,
            activation="linear"
        )
    ])

    model.compile(
        optimizer=Adam(
            learning_rate=config["learning_rate"]
        ),
        loss=tf.keras.losses.Huber(),
        metrics=[
            tf.keras.metrics.MeanAbsoluteError(
                name="mae"
            ),
            tf.keras.metrics.RootMeanSquaredError(
                name="rmse"
            )
        ]
    )

    return model


# ============================================================
# TRAIN
# ============================================================

results = []

for config in configs:

    print()
    print("=" * 70)
    print("TRAINING:", config["name"])
    print("=" * 70)

    model = build_model(config)

    model.summary()

    checkpoint_path = os.path.join(
        MODEL_DIR,
        f"{config['name']}.keras"
    )

    history_path = os.path.join(
        MODEL_DIR,
        f"{config['name']}_history.json"
    )

    callbacks = [

        EarlyStopping(
            monitor="val_loss",
            patience=4,
            restore_best_weights=True,
            verbose=1
        ),

        ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=2,
            min_lr=1e-6,
            verbose=1
        ),

        tf.keras.callbacks.ModelCheckpoint(
            checkpoint_path,
            monitor="val_loss",
            save_best_only=True,
            verbose=1
        )
    ]

    start_time = time.time()

    history = model.fit(
        X_train,
        y_train,

        validation_data=(
            X_val,
            y_val
        ),

        epochs=20,
        batch_size=128,

        shuffle=False,

        callbacks=callbacks,

        verbose=1
    )

    elapsed = time.time() - start_time

    # --------------------------------------------------------
    # SAVE HISTORY
    # --------------------------------------------------------

    history_clean = {
        key: [
            float(value)
            for value in values
        ]
        for key, values in history.history.items()
    }

    with open(history_path, "w") as f:
        json.dump(
            history_clean,
            f,
            indent=4
        )

    # --------------------------------------------------------
    # VALIDATION EVALUATION
    # --------------------------------------------------------

    evaluation = model.evaluate(
        X_val,
        y_val,
        batch_size=128,
        verbose=0
    )

    val_loss = float(evaluation[0])
    val_mae = float(evaluation[1])
    val_rmse = float(evaluation[2])

    best_epoch = int(
        np.argmin(
            history.history["val_loss"]
        ) + 1
    )

    print()
    print(
        f"{config['name']} finished "
        f"in {elapsed / 60:.2f} minutes"
    )

    print(
        f"Best epoch: {best_epoch}"
    )

    print(
        f"Validation Loss: {val_loss:.8f}"
    )

    print(
        f"Validation MAE: {val_mae:.8f}"
    )

    print(
        f"Validation RMSE: {val_rmse:.8f}"
    )

    results.append({
        "model": config["name"],
        "val_loss": val_loss,
        "val_mae": val_mae,
        "val_rmse": val_rmse,
        "best_epoch": best_epoch,
        "training_minutes": elapsed / 60
    })


# ============================================================
# RANK RESULTS
# ============================================================

results.sort(
    key=lambda x: x["val_loss"]
)

results_path = os.path.join(
    MODEL_DIR,
    "lstm_refinement_results.json"
)

with open(results_path, "w") as f:
    json.dump(
        results,
        f,
        indent=4
    )


print()
print("=" * 70)
print("LSTM REFINEMENT RESULTS")
print("=" * 70)

for rank, result in enumerate(
    results,
    start=1
):

    print(
        f"{rank}. "
        f"{result['model']:18s} | "
        f"Loss={result['val_loss']:.8f} | "
        f"MAE={result['val_mae']:.8f} | "
        f"RMSE={result['val_rmse']:.8f} | "
        f"Epoch={result['best_epoch']}"
    )

print()
print("Results saved:")
print(results_path)

print()
print("Models saved:")
print(MODEL_DIR)
