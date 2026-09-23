import time
import joblib
import pandas as pd
import numpy as np

from xgboost import XGBRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score


# ============================================================
# CONFIGURATION
# ============================================================

DATASET_PATH = "/tmp/Bangladesh-flood-data-set/data/features/2026-08-07c-discharge-regression/all_stations.parquet"

TARGET = "discharge_target_24h"

FEATURES = [
    "rainfall_local_mm",
    "rainfall_upstream_mm",
    "soil_moisture_local",

    "rainfall_local_mm_lag1d",
    "rainfall_local_mm_lag2d",
    "rainfall_local_mm_lag3d",
    "rainfall_local_mm_lag5d",

    "rainfall_upstream_mm_lag1d",
    "rainfall_upstream_mm_lag2d",
    "rainfall_upstream_mm_lag3d",
    "rainfall_upstream_mm_lag5d",

    "soil_moisture_local_lag1d",
    "soil_moisture_local_lag2d",
    "soil_moisture_local_lag3d",
    "soil_moisture_local_lag5d",

    "river_discharge_m3s",
    "river_discharge_m3s_lag1d",
    "river_discharge_m3s_lag2d",
    "river_discharge_m3s_lag3d",
    "river_discharge_m3s_lag5d",

    "rainfall_local_mm_sum7d",
    "rainfall_local_mm_sum14d",

    "rainfall_upstream_mm_sum7d",
    "rainfall_upstream_mm_sum14d",

    "soil_moisture_delta_30d",
    "soil_moisture_swi",

    "elevation_m",
    "hand_m"
]

TRAIN_END_DATE = "2022-01-01"

MODEL_OUTPUT = "xgboost_log_discharge_24h.joblib"


# ============================================================
# LOAD DATA
# ============================================================

print("Loading dataset...")

df = pd.read_parquet(DATASET_PATH)

print("Original shape:", df.shape)


# ============================================================
# SELECT COLUMNS
# ============================================================

selected_columns = ["date"] + FEATURES + [TARGET]

df = df[selected_columns]

print("After selecting columns:", df.shape)


# ============================================================
# REMOVE MISSING VALUES
# ============================================================

print("Rows before removing missing values:", len(df))

df = df.dropna()

print("Rows after removing missing values:", len(df))
print("Rows removed:", 839340 - len(df))


# ============================================================
# SORT BY DATE
# ============================================================

df = df.sort_values("date").reset_index(drop=True)


# ============================================================
# TIME-BASED TRAIN/TEST SPLIT
# ============================================================

train = df[df["date"] < TRAIN_END_DATE]
test = df[df["date"] >= TRAIN_END_DATE]

X_train = train[FEATURES]
X_test = test[FEATURES]

y_train_original = train[TARGET]
y_test_original = test[TARGET]


print()
print("TRAINING DATA")
print("Rows:", len(train))
print("Date:", train["date"].min(), "to", train["date"].max())

print()
print("TEST DATA")
print("Rows:", len(test))
print("Date:", test["date"].min(), "to", test["date"].max())


# ============================================================
# LOG TRANSFORM TARGET
# ============================================================

print()
print("Applying log1p transformation to target...")

y_train = np.log1p(y_train_original)


# ============================================================
# CREATE XGBOOST MODEL
# ============================================================

model = XGBRegressor(
    n_estimators=300,
    max_depth=6,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    objective="reg:squarederror",
    eval_metric="rmse",
    random_state=42,
    n_jobs=-1
)


# ============================================================
# TRAIN
# ============================================================

print()
print("Training XGBoost with log-transformed target...")

start_time = time.time()

model.fit(X_train, y_train)

training_time = time.time() - start_time

print("Training time: %.4f seconds" % training_time)


# ============================================================
# PREDICT
# ============================================================

print()
print("Predicting test data...")

start_time = time.time()

log_predictions = model.predict(X_test)

prediction_time = time.time() - start_time

prediction_time_per_row = (
    prediction_time / len(X_test) * 1000
)


# ============================================================
# CONVERT PREDICTIONS BACK TO ORIGINAL SCALE
# ============================================================

predictions = np.expm1(log_predictions)

# Discharge cannot physically be negative.
predictions = np.maximum(predictions, 0)


# ============================================================
# EVALUATION ON ORIGINAL DISCHARGE SCALE
# ============================================================

mae = mean_absolute_error(
    y_test_original,
    predictions
)

rmse = np.sqrt(
    mean_squared_error(
        y_test_original,
        predictions
    )
)

r2 = r2_score(
    y_test_original,
    predictions
)


# ============================================================
# RESULTS
# ============================================================

print()
print("==============================")
print("XGBOOST LOG-TARGET RESULTS")
print("==============================")

print("MAE:               %.4f" % mae)
print("RMSE:              %.4f" % rmse)
print("R²:                %.4f" % r2)
print("Training time:     %.4f seconds" % training_time)
print("Prediction time:   %.4f seconds" % prediction_time)
print("Prediction time per row: %.6f ms" % prediction_time_per_row)


# ============================================================
# SAMPLE PREDICTIONS
# ============================================================

print()
print("SAMPLE PREDICTIONS:")

sample_results = pd.DataFrame({
    "Actual": y_test_original.iloc[:20].values,
    "Predicted": predictions[:20]
})

print(
    sample_results.to_string(
        index=False,
        formatters={
            "Actual": "{:.2f}".format,
            "Predicted": "{:.5f}".format
        }
    )
)


# ============================================================
# FEATURE IMPORTANCE
# ============================================================

print()
print("FEATURE IMPORTANCE:")

importance = pd.DataFrame({
    "Feature": FEATURES,
    "Importance": model.feature_importances_
})

importance = importance.sort_values(
    "Importance",
    ascending=False
)

print(
    importance.to_string(
        index=False,
        formatters={
            "Importance": "{:.6f}".format
        }
    )
)


# ============================================================
# SAVE MODEL
# ============================================================

joblib.dump(model, MODEL_OUTPUT)

print()
print("Model saved to:")
print(MODEL_OUTPUT)
