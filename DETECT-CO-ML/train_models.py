import pandas as pd
import time
import joblib

from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder
from sklearn.pipeline import Pipeline
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    confusion_matrix
)
from xgboost import XGBClassifier


# ==========================================
# 1. LOAD DATASET
# ==========================================

DATASET = "flood_risk_dataset_india.csv"

df = pd.read_csv(DATASET)

print("=" * 60)
print("DATASET")
print("=" * 60)
print("Rows:", len(df))
print("Columns:", len(df.columns))
print()


# ==========================================
# 2. SEPARATE FEATURES AND TARGET
# ==========================================

X = df.drop(columns=["Flood Occurred"])
y = df["Flood Occurred"]


# ==========================================
# 3. IDENTIFY COLUMN TYPES
# ==========================================

categorical_features = [
    "Land Cover",
    "Soil Type"
]

numeric_features = [
    col for col in X.columns
    if col not in categorical_features
]


# ==========================================
# 4. PREPROCESSING
# ==========================================

preprocessor = ColumnTransformer(
    transformers=[
        (
            "categorical",
            OneHotEncoder(handle_unknown="ignore"),
            categorical_features
        ),
        (
            "numeric",
            "passthrough",
            numeric_features
        )
    ]
)


# ==========================================
# 5. TRAIN / TEST SPLIT
# ==========================================

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.20,
    random_state=42,
    stratify=y
)

print("=" * 60)
print("DATA SPLIT")
print("=" * 60)
print("Training rows:", len(X_train))
print("Testing rows :", len(X_test))
print()


# ==========================================
# 6. RANDOM FOREST
# ==========================================

print("=" * 60)
print("TRAINING RANDOM FOREST")
print("=" * 60)

rf_model = Pipeline(
    steps=[
        ("preprocessor", preprocessor),
        (
            "model",
            RandomForestClassifier(
                n_estimators=200,
                random_state=42,
                n_jobs=-1
            )
        )
    ]
)

rf_start = time.perf_counter()

rf_model.fit(X_train, y_train)

rf_train_time = time.perf_counter() - rf_start

rf_start = time.perf_counter()

rf_predictions = rf_model.predict(X_test)

rf_prediction_time = time.perf_counter() - rf_start


# ==========================================
# 7. XGBOOST
# ==========================================

print("=" * 60)
print("TRAINING XGBOOST")
print("=" * 60)

xgb_model = Pipeline(
    steps=[
        ("preprocessor", preprocessor),
        (
            "model",
            XGBClassifier(
                n_estimators=200,
                max_depth=6,
                learning_rate=0.1,
                subsample=0.8,
                colsample_bytree=0.8,
                objective="binary:logistic",
                eval_metric="logloss",
                random_state=42,
                n_jobs=-1
            )
        )
    ]
)

xgb_start = time.perf_counter()

xgb_model.fit(X_train, y_train)

xgb_train_time = time.perf_counter() - xgb_start

xgb_start = time.perf_counter()

xgb_predictions = xgb_model.predict(X_test)

xgb_prediction_time = time.perf_counter() - xgb_start


# ==========================================
# 8. EVALUATION FUNCTION
# ==========================================

def evaluate_model(name, y_true, predictions, train_time, prediction_time):

    accuracy = accuracy_score(y_true, predictions)
    precision = precision_score(y_true, predictions)
    recall = recall_score(y_true, predictions)
    f1 = f1_score(y_true, predictions)

    print()
    print("=" * 60)
    print(name)
    print("=" * 60)

    print(f"Accuracy        : {accuracy:.4f} ({accuracy * 100:.2f}%)")
    print(f"Precision       : {precision:.4f} ({precision * 100:.2f}%)")
    print(f"Recall          : {recall:.4f} ({recall * 100:.2f}%)")
    print(f"F1 Score        : {f1:.4f} ({f1 * 100:.2f}%)")
    print(f"Training time   : {train_time:.4f} seconds")
    print(f"Prediction time : {prediction_time:.6f} seconds")
    print(f"Prediction/row  : {(prediction_time / len(y_true)) * 1000:.6f} ms")

    print()
    print("Confusion Matrix:")
    print(confusion_matrix(y_true, predictions))


# ==========================================
# 9. DISPLAY RESULTS
# ==========================================

evaluate_model(
    "RANDOM FOREST",
    y_test,
    rf_predictions,
    rf_train_time,
    rf_prediction_time
)

evaluate_model(
    "XGBOOST",
    y_test,
    xgb_predictions,
    xgb_train_time,
    xgb_prediction_time
)


# ==========================================
# 10. SAVE MODELS
# ==========================================

joblib.dump(rf_model, "random_forest_model.joblib")
joblib.dump(xgb_model, "xgboost_model.joblib")

print()
print("=" * 60)
print("MODELS SAVED")
print("=" * 60)
print("random_forest_model.joblib")
print("xgboost_model.joblib")
print()
