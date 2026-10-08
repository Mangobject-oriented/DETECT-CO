"""SQLite persistence for real ML forecasts and later rainfall verification."""

from __future__ import annotations

import json
import math
import os
import sqlite3
import threading
from contextlib import closing
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

_LOCK = threading.Lock()
_TZ = ZoneInfo("Asia/Manila")
_DB_PATH = Path(
    os.environ.get(
        "DETECTCO_ML_MONITORING_DB",
        str(Path(__file__).parent / "data" / "ml_monitoring.sqlite3"),
    )
)
_HORIZONS = (1, 3, 6, 12, 24)


def _connect() -> sqlite3.Connection:
    _DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(_DB_PATH, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def _nonnegative_number(value: object) -> float | None:
    if not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) and number >= 0 else None


def _ensure_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS forecast_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            location_key TEXT NOT NULL,
            generated_at TEXT NOT NULL,
            forecast_start TEXT NOT NULL,
            payload_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS forecast_runs_location_time
            ON forecast_runs(location_key, generated_at DESC);
        CREATE UNIQUE INDEX IF NOT EXISTS forecast_runs_location_hour
            ON forecast_runs(location_key, substr(generated_at, 1, 13));
        CREATE TABLE IF NOT EXISTS forecast_values (
            run_id INTEGER NOT NULL,
            location_key TEXT NOT NULL,
            generated_at TEXT NOT NULL,
            horizon_hours INTEGER NOT NULL,
            predicted_mm REAL NOT NULL,
            forecast_start TEXT NOT NULL,
            actual_mm REAL,
            PRIMARY KEY(run_id, horizon_hours),
            FOREIGN KEY(run_id) REFERENCES forecast_runs(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS forecast_values_location_horizon
            ON forecast_values(location_key, horizon_hours, generated_at DESC);
        CREATE TABLE IF NOT EXISTS observed_hourly_rainfall (
            location_key TEXT NOT NULL,
            hour_key TEXT NOT NULL,
            rainfall_mm REAL NOT NULL,
            PRIMARY KEY(location_key, hour_key)
        );
        """
    )
    connection.commit()


def _parse_hour(value: object) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=_TZ)
    return parsed.astimezone(_TZ).replace(minute=0, second=0, microsecond=0)


def record_forecast(
    location_key: str,
    payload: dict,
    weather_records: list[dict],
    generated_at: datetime,
) -> None:
    """Store a real forecast and hourly rainfall samples; reconcile matured horizons."""
    local_now = generated_at.astimezone(_TZ)
    # The model output targets the hour after its latest observed input row.
    # Compare it to the next complete local hourly window even if inference
    # happened exactly on the clock hour.
    forecast_start = local_now.replace(
        minute=0, second=0, microsecond=0
    ) + timedelta(hours=1)

    rainfall = payload.get("predictions", {})
    generated_text = local_now.isoformat(timespec="seconds")
    start_text = forecast_start.isoformat(timespec="seconds")

    with _LOCK, closing(_connect()) as connection:
        _ensure_schema(connection)
        for record in weather_records:
            hour = _parse_hour(record.get("timestamp"))
            value = _nonnegative_number(record.get("rainfall_mm"))
            if hour is None or value is None:
                continue
            # Keep only completed hourly records. Later calls refresh the last
            # completed hour before it leaves Open-Meteo's past-hours window.
            current_hour = local_now.replace(minute=0, second=0, microsecond=0)
            if hour >= current_hour:
                continue
            connection.execute(
                """INSERT INTO observed_hourly_rainfall(location_key, hour_key, rainfall_mm)
                   VALUES (?, ?, ?)
                   ON CONFLICT(location_key, hour_key)
                   DO UPDATE SET rainfall_mm=excluded.rainfall_mm""",
                (location_key, hour.isoformat(timespec="seconds"), value),
            )

        # Home requests predictions on its existing five-minute cadence.
        # Keep the latest real prediction for each location/hour instead of
        # inflating evaluation samples with near-identical repeated calls.
        generated_hour = generated_text[:13]
        existing = connection.execute(
            "SELECT id FROM forecast_runs WHERE location_key=? "
            "AND substr(generated_at, 1, 13)=?",
            (location_key, generated_hour),
        ).fetchone()
        if existing:
            run_id = int(existing["id"])
            connection.execute(
                "UPDATE forecast_runs SET generated_at=?, forecast_start=?, payload_json=? WHERE id=?",
                (generated_text, start_text, json.dumps(payload), run_id),
            )
            connection.execute("DELETE FROM forecast_values WHERE run_id=?", (run_id,))
        else:
            cursor = connection.execute(
                "INSERT OR IGNORE INTO forecast_runs(location_key, generated_at, forecast_start, payload_json) "
                "VALUES (?, ?, ?, ?)",
                (location_key, generated_text, start_text, json.dumps(payload)),
            )
            if cursor.rowcount:
                run_id = int(cursor.lastrowid)
            else:
                # Another API worker may have inserted this location/hour
                # after the lookup above. Update that same hourly sample.
                existing = connection.execute(
                    "SELECT id FROM forecast_runs WHERE location_key=? "
                    "AND substr(generated_at, 1, 13)=?",
                    (location_key, generated_hour),
                ).fetchone()
                if existing is None:
                    raise sqlite3.IntegrityError("Could not save hourly forecast run")
                run_id = int(existing["id"])
                connection.execute(
                    "UPDATE forecast_runs SET generated_at=?, forecast_start=?, payload_json=? WHERE id=?",
                    (generated_text, start_text, json.dumps(payload), run_id),
                )
                connection.execute("DELETE FROM forecast_values WHERE run_id=?", (run_id,))

        for horizon in _HORIZONS:
            predicted = _nonnegative_number(rainfall.get(f"rainfall_{horizon}h_mm"))
            if predicted is not None:
                connection.execute(
                    """INSERT INTO forecast_values
                       (run_id, location_key, generated_at, horizon_hours, predicted_mm, forecast_start)
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (run_id, location_key, generated_text, horizon, predicted, start_text),
                )

        current_hour = local_now.replace(minute=0, second=0, microsecond=0)
        pending = connection.execute(
            """SELECT run_id, horizon_hours, forecast_start
               FROM forecast_values
               WHERE location_key=? AND actual_mm IS NULL""",
            (location_key,),
        ).fetchall()
        for item in pending:
            start = datetime.fromisoformat(item["forecast_start"])
            end = start + timedelta(hours=int(item["horizon_hours"]))
            if end > current_hour:
                continue
            expected = [start + timedelta(hours=index) for index in range(int(item["horizon_hours"]))]
            keys = [hour.isoformat(timespec="seconds") for hour in expected]
            rows = connection.execute(
                f"""SELECT hour_key, rainfall_mm FROM observed_hourly_rainfall
                    WHERE location_key=? AND hour_key IN ({','.join('?' for _ in keys)})""",
                (location_key, *keys),
            ).fetchall()
            if len(rows) == len(keys):
                actual = sum(float(row["rainfall_mm"]) for row in rows)
                connection.execute(
                    "UPDATE forecast_values SET actual_mm=? WHERE run_id=? AND horizon_hours=?",
                    (actual, item["run_id"], item["horizon_hours"]),
                )

        cutoff = (local_now - timedelta(days=90)).isoformat(timespec="seconds")
        connection.execute("DELETE FROM forecast_runs WHERE generated_at < ?", (cutoff,))
        connection.execute("DELETE FROM observed_hourly_rainfall WHERE hour_key < ?", (cutoff,))
        connection.commit()


def get_monitoring(location_key: str) -> dict:
    with _LOCK, closing(_connect()) as connection:
        _ensure_schema(connection)
        latest = connection.execute(
            """SELECT payload_json FROM forecast_runs
               WHERE location_key=? ORDER BY generated_at DESC LIMIT 1""",
            (location_key,),
        ).fetchone()
        rows = connection.execute(
            """SELECT horizon_hours, predicted_mm, actual_mm, generated_at
               FROM forecast_values WHERE location_key=?
               ORDER BY generated_at DESC LIMIT 500""",
            (location_key,),
        ).fetchall()

    grouped: dict[int, list[dict]] = {hour: [] for hour in _HORIZONS}
    for row in rows:
        horizon = int(row["horizon_hours"])
        if horizon in grouped:
            grouped[horizon].append({
                "predicted_mm": float(row["predicted_mm"]),
                "actual_mm": None if row["actual_mm"] is None else float(row["actual_mm"]),
                "generated_at": row["generated_at"],
            })

    metrics = {}
    for horizon, samples in grouped.items():
        completed = [sample for sample in samples if sample["actual_mm"] is not None]
        if not completed:
            metrics[str(horizon)] = {"count": 0, "mae_mm": None, "rmse_mm": None, "mean_error_percent": None}
            continue
        errors = [sample["predicted_mm"] - sample["actual_mm"] for sample in completed]
        absolute = [abs(error) for error in errors]
        percent = [
            100 * error / sample["actual_mm"]
            for error, sample in zip(errors, completed)
            if sample["actual_mm"] != 0
        ]
        metrics[str(horizon)] = {
            "count": len(completed),
            "mae_mm": sum(absolute) / len(absolute),
            "rmse_mm": (sum(error * error for error in errors) / len(errors)) ** 0.5,
            "mean_error_percent": sum(percent) / len(percent) if percent else None,
        }

    return {
        "latest": json.loads(latest["payload_json"]) if latest else None,
        "history": {str(horizon): samples[:50] for horizon, samples in grouped.items()},
        "metrics": metrics,
        "location_key": location_key,
    }
