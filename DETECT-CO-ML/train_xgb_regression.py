import pandas as pd
import numpy as np
import joblib
import time

from xgboost import XGBRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score


# ============================================================
# 1. LOAD DATA
# ============================================================

FILE = "/tmp/Bangladesh-flood-data-set/data/features/2026-08-07c-discharge-regression/all_stations.parquet"

print("Loading dataset...")
df = pd.read_parquet(FILE)

print("Original shape:", df.shape)


# ============================================================
# 2. FEATURES
# ============================================================

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
    "hand_m",
]

TARGET = "discharge_target_24h"


# ============================================================
# 3. KEEP REQUIRED COLUMNS
# ============================================================

df = df[["date", "station_id"] + FEATURES + [TARGET]]

print("After selecting columns:", df.shape)


# ============================================================
# 4. REMOVE MISSING VALUES
# ============================================================

before = len(df)

df = df.dropna(subset=FEATURES + [TARGET]).copy()

after = len(df)

print("Rows before removing missing values:", before)
print("Rows after removing missing values:", after)
print("Rows removed:", before - after)


# ============================================================
# 5. SORT CHRONOLOGICALLY
# ============================================================

df = df.sort_values("date").reset_index(drop=True)


# ============================================================
# 6. TIME-BASED TRAIN / TEST SPLIT
# ============================================================

train = df[df["date"] < "2022-01-01"].copy()
test = df[df["date"] >= "2022-01-01"].copy()

print("\nTRAINING DATA")
print("Rows:", len(train))
print("Date:", train["date"].min(), "to", train["date"].max())

print("\nTEST DATA")
print("Rows:", len(test))
print("Date:", test["date"].min(), "to", test["date"].max())


# ============================================================
# 7. PREPARE X AND Y
# ============================================================

X_train = train[FEATURES]
y_train = train[TARGET]

X_test = test[FEATURES]
y_test = test[TARGET]


# ============================================================
# 8. TRAIN XGBOOST
# ============================================================

print("\nTraining XGBoost...")

start = time.perf_counter()

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

model.fit(
    X_train,
    y_train
)

train_time = time.perf_counter() - start

print(f"Training time: {train_time:.4f} seconds")


# ============================================================
# 9. PREDICTION
# ============================================================

print("\nPredicting test data...")

start = time.perf_counter()

predictions = model.predict(X_test)

prediction_time = time.perf_counter() - start


# ============================================================
# 10. EVALUATION
# ============================================================

mae = mean_absolute_error(
    y_test,
    predictions
)

rmse = np.sqrt(
    mean_squared_error(
        y_test,
        predictions
    )
)

r2 = r2_score(
    y_test,
    predictions
)


# ============================================================
# 11. RESULTS
# ============================================================

print("\n==============================")
print("XGBOOST RESULTS")
print("==============================")

print(f"MAE:               {mae:.4f}")
print(f"RMSE:              {rmse:.4f}")
print(f"R²:                {r2:.4f}")

print(f"Training time:     {train_time:.4f} seconds")
print(f"Prediction time:   {prediction_time:.4f} seconds")

print(
    f"Prediction time per row: "
    f"{prediction_time / len(X_test) * 1000:.6f} ms"
)


# ============================================================
# 12. SAMPLE PREDICTIONS
# ============================================================

results = pd.DataFrame({
    "Actual": y_test.values,
    "Predicted": predictions
})

print("\nSAMPLE PREDICTIONS:")
print(
    results.head(20).to_string(index=False)
)


# ============================================================
# 13. FEATURE IMPORTANCE
# ============================================================

importance = pd.DataFrame({
    "Feature": FEATURES,
    "Importance": model.feature_importances_
})

importance = importance.sort_values(
    "Importance",
    ascending=False
)

print("\nFEATURE IMPORTANCE:")
print(
    importance.to_string(index=False)
)


# ============================================================
# 14. SAVE MODEL
# ============================================================

MODEL_FILE = "xgboost_discharge_24h.joblib"

joblib.dump(
    model,
    MODEL_FILE
)

print("\nModel saved to:")
print(MODEL_FILE)
