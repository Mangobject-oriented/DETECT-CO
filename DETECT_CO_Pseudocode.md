# DETECT-CO System Pseudocode

## Introduction

This document expresses the runtime behavior visible in the DETECT-CO repository as language-independent pseudocode. It covers the ESP32 firmware sketch, Firebase Realtime Database exchange, Flutter dashboard, weather retrieval, and the local FastAPI rainfall-inference service. Model training scripts are not part of runtime prediction. The deployed API loads trained artifacts and performs inference.

The term *flood risk* in the application refers to thresholds applied to measured ultrasonic water rise. The LSTM–XGBoost–Random Forest service forecasts rainfall in millimeters; its rainfall output is presented as forecast context and is not converted into a separate rainfall-based flood threshold.

## Algorithm 1: Overall DETECT-CO System Operation

INPUT: Ultrasonic, water, and DHT11 sensor signals; requested weather coordinates; Firebase and network availability.

OUTPUT:Local hardware readings and indicators; Firebase sensor record; Flutter dashboard and rainfall forecast; applicable application alerts.


ALGORITHM 1: Overall DETECT-CO System Operation
BEGIN
    ESP32 initializes sensors, OLED, buzzer, RGB LED, and Wi-Fi
    Flutter subscribes to Firebase path /flood and starts its refresh tasks

    WHILE ESP32 is running DO
        Read ultrasonic distance, digital water input, and (when due) DHT11 values
        Update ESP32 OLED, buzzer, and RGB LED from local sensor values
        IF Wi-Fi is connected and one second has elapsed THEN
            Replace Firebase /flood data with the current sensor record
        END IF
    END WHILE

    Flutter receives Firebase value changes and checks sensor-record freshness
    IF a recent timestamp is available THEN
        Parse valid distance and calculate water rise and sensor-based risk
        Display sensor readings, water gauge, and risk information
    ELSE
        Mark physical sensor status unavailable and use weather fallback where available
    END IF

    Every five minutes, Flutter requests rainfall inference from the ML API
    ML API retrieves hourly weather, preprocesses it, runs the loaded models,
    combines their outputs, and returns rainfall forecasts
    Flutter displays valid forecasts and may issue a sensor-risk warning
END


## Algorithm 2: ESP32 Sensor Data Acquisition and Processing

INPUT: JSN-SR04T echo pulse; digital water-sensor level; DHT11 measurements.

OUTPUT: Distance in centimeters or out-of-range marker; water state; retained temperature and humidity; OLED, LED, and buzzer states; sensor values sent to Firebase.


ALGORITHM 2: ESP32 Sensor Data Acquisition and Processing
BEGIN
    Configure trigger pin 2, echo pin 5, water input pin 4,
        DHT11 pin 18, buzzer pin 14, RGB pins 25/27/26, and OLED over I2C
    Connect to configured Wi-Fi, waiting until connected

    WHILE running DO
        Set ultrasonic trigger LOW for 2 microseconds
        Set trigger HIGH for 10 microseconds, then LOW
        Measure HIGH echo duration with a 50,000-microsecond timeout
        IF duration equals zero THEN
            distance ← -1
        ELSE
            distance ← duration × 0.0343 / 2
        END IF

        waterDetected ← (digital water input is HIGH)

        IF at least 2 seconds have elapsed since the last DHT read THEN
            Read temperature and humidity
            Replace each retained value only if that measurement is not NaN
        END IF

        IF (distance > 0 AND distance ≤ 21) OR waterDetected THEN
            Turn buzzer ON; turn red LED ON and green LED OFF
        ELSE
            Turn buzzer OFF; turn red LED OFF and green LED ON
        END IF
        Turn blue LED OFF

        Display distance (--- when out of range), water YES/NO,
            retained temperature, and retained humidity on OLED

        IF Wi-Fi is connected AND at least 1 second elapsed since last update THEN
            Send distance, water as 1/0, temperature, and humidity to Firebase
        END IF
        Wait 10 milliseconds
    END WHILE
END


## Algorithm 3: Firebase Data Transmission and Retrieval

INPUT: ESP32 readings and Firebase Realtime Database events.

OUTPUT: Replaced `/flood` record and Flutter sensor/dashboard state.


ALGORITHM 3: Firebase Data Transmission and Retrieval
BEGIN
    ESP32 prepares a JSON record containing distance, water, temperature, humidity
    IF Wi-Fi is connected and the one-second interval has elapsed THEN
        Send HTTP PUT to the configured Firebase /flood.json endpoint
        Log the HTTP response code and close the HTTP request
    ELSE IF Wi-Fi is disconnected THEN
        Log Wi-Fi Disconnected
    END IF

    Flutter listens to Firebase Realtime Database path /flood using onValue
    IF the stream reports an error THEN
        Show an error loading data
    ELSE IF the snapshot contains a map THEN
        Read distance, temperature, humidity, and timestamp fields
        Treat timestamp as seconds when below 100,000,000,000; otherwise milliseconds
        Treat data as online when its timestamp is no more than 30 seconds old
            (a future timestamp also passes this age check)
        IF online THEN
            Parse distance only when finite and 0 ≤ distance < 200 cm
            Display available ESP32 values
        ELSE
            Ignore stale physical distance and request weather fallback
        END IF
    ELSE
        Keep sensor values unavailable/idle
    END IF
    Every 2 seconds, recheck the last known timestamp so a stopped ESP32
        can become offline even when Firebase emits no new event
END


The firmware sketch sends no timestamp and does not inspect the HTTP response to retry a failed PUT. Consequently, as written, its record cannot satisfy the Flutter dashboard's timestamp-based online check. The Flutter listener also does not use the transmitted `water` field for its flood-risk decision; risk is derived from valid ultrasonic distance. No database rules or server-side authentication behavior is inferred here.

## Algorithm 4: LSTM Rainfall Prediction

**INPUT:** Exactly 24 valid hourly Open-Meteo records for a supported location; that location's saved scaler; loaded refined LSTM model.

**OUTPUT:** Five predicted rainfall values for 1, 3, 6, 12, and 24 hours, in the model's output units (millimeters as named by the API).

```text
ALGORITHM 4: LSTM Rainfall Prediction
BEGIN
    Sort the 24 weather records by timestamp
    For every record, calculate hour, day of week, and month
    Derive rainfall features from hourly rain:
        1-hour value; rolling sums over 3, 6, 12, and 24 records;
        rolling means over 3, 6, 12, and 24 records
    Assemble 14 features per time step in the configured LSTM feature order:
        temperature, humidity, rainfall features, time features
    Select the saved scaler for the rounded supported coordinate key
    Transform the 24-by-14 feature matrix with that scaler
    Add a batch dimension to form one sequence of shape 1-by-24-by-14
    Run the already-loaded LSTM model; do not train the model at runtime
    Flatten the output
    IF output count is not five THEN
        Return an inference error
    END IF
    Return outputs aligned to rainfall horizons 1, 3, 6, 12, and 24 hours
END


## Algorithm 5: XGBoost Rainfall Prediction

INPUT: Latest engineered weather row and the five LSTM estimates; five loaded target-specific XGBoost models.
OUTPUT: Five XGBoost rainfall estimates, one per forecast horizon.


ALGORITHM 5: XGBoost Rainfall Prediction
BEGIN
    Take the latest weather row and assemble 19 features in configured order:
        temperature, humidity, 1/3/6/12/24-hour rainfall sums,
        3/6/12/24-hour rainfall means, hour, day of week, month,
        and the five LSTM predictions
    For each target horizon in 1, 3, 6, 12, and 24 hours DO
        Apply that horizon's already-loaded XGBoost model to the feature row
        Store its scalar prediction at the matching horizon
    END FOR
    Return the five XGBoost predictions
END


## Algorithm 6: LSTM–XGBoost Ensemble Prediction

INPUT: Five LSTM, XGBoost, and Random Forest predictions aligned to the same horizons.

OUTPUT: Five nonnegative ensemble rainfall predictions plus each component model's outputs.


ALGORITHM 6: LSTM–XGBoost Ensemble Prediction
BEGIN
    For each matching horizon h in 1, 3, 6, 12, and 24 hours DO
        combined[h] ← 0.96 × LSTM[h]
                     + 0.00 × XGBoost[h]
                     + 0.04 × RandomForest[h]
        combined[h] ← maximum(combined[h], 0)
    END FOR
    Return combined predictions, component predictions, and weights
END




 Algorithm 7: Flood-Risk Assessment and Alert Handling

INPUT:Fresh valid ultrasonic distance, current rainfall and forecast values when available, and stored warning history.

OUTPUT: Sensor-derived LOW/MODERATE/HIGH dashboard status and, when conditions qualify, a local notification and saved alert.

ALGORITHM 7: Flood-Risk Assessment and Alert Handling
BEGIN
    IF ESP32 is offline OR distance is missing, nonfinite, negative, or ≥ 200 cm THEN
        Mark physical sensor inactive and show IDLE
    ELSE
        rise ← maximum(150 cm - distance, 0)
        IF rise ≤ 4 cm THEN risk ← LOW
        ELSE IF rise ≤ 40 cm THEN risk ← MODERATE
        ELSE risk ← HIGH
        END IF
        Display the sensor-derived risk and measured rise
    END IF

    Keep rainfall forecast as separate forecast information;
        do not use rainfall amount to change the risk level

    IF a valid ML prediction arrives AND physical sensor is active
       AND risk is MODERATE or HIGH THEN
        Read previous warning level and warning time
        IF no warning cooldown is active OR risk rank increased THEN
            Send local notification with measured rise, current rainfall,
                and 3-hour forecast (or unavailable labels)
            Save an alert in local notification storage
            Save current risk level and time
        END IF
    END IF
END


.

## Algorithm 8: Flutter Application Data Display and Periodic Updates

INPUT: Firebase `/flood` stream, ML API response, Open-Meteo weather responses, and optional device location.

OUTPUT: Dashboard sensor/weather values, water gauge and risk status, rainfall forecasts, and refresh/error state.


ALGORITHM 8: Flutter Application Data Display and Periodic Updates
BEGIN
    At Home initialization, request device location once for the app session
    IF permission, service, or lookup fails THEN use fixed coordinates (14.15, 121.05)
    Subscribe to Firebase /flood and start the 2-second ESP32 freshness check
    Fetch an ML prediction immediately and then every 5 minutes
    Fetch weather-condition data immediately and then every 10 minutes

    ON Firebase value event DO
        Parse fresh ESP32 values; calculate water rise and sensor risk
        When ESP32 is offline, use weather fallback for temperature/humidity
        Keep physical water-level display IDLE without fresh sensor distance
        Update dashboard immediately by default, or apply configured display throttle
    END ON

    ON ML prediction timer or retry DO
        Resolve a healthy ML endpoint and POST latitude/longitude
        IF valid prediction map is returned THEN
            Store and display valid nonnegative horizon values and current rainfall
            Evaluate sensor-derived warning eligibility
        ELSE
            Mark forecast unavailable and request Open-Meteo rainfall fallback
        END IF
    END ON

    On connectivity restoration, invalidate endpoint health cache and retry prediction
    On page disposal, cancel periodic timers and subscriptions
END


The Home page currently posts fixed coordinates `(14.15, 121.05)` to the ML service even though it separately performs a one-time location lookup for weather requests. The ML API accepts only four supported two-decimal coordinate keys. If Open-Meteo lacks hourly data, returns inconsistent arrays, or has fewer than 24 complete records, the API returns an error; the Flutter page marks ML unavailable and requests its separate weather fallback. Open-Meteo rainfall display values and model rainfall estimates remain distinct data sources.

## Algorithm 9: Emergency Location Sharing

INPUT: User-initiated sharing request, location permission and GPS readings, Firebase availability.

OUTPUT: An active `emergency_sessions/{id}` record updated with location for up to 30 minutes, or a user-visible failure/stop result.


ALGORITHM 9: Emergency Location Sharing
BEGIN
    Check for an existing active session; refuse to create a second session
    Verify location service and permission; obtain an initial high-accuracy fix
    Create a Firebase emergency_sessions child with ID, coordinates, accuracy,
        start time, expiry time, and active status
    Persist session ID and times locally; start expiry timer and location stream
    On each location update at least 10 meters away, update coordinates,
        accuracy, and updatedAt in Firebase
    Listen to the session record for an external status change
    IF user stops sharing OR session expires THEN
        Stop location and status streams; update status to stopped or expired
        Clear local session and active notification when the update succeeds
    END IF
    On temporary position/database update errors, keep the session active
        and allow later location updates or retry of a manual stop
END


Sessions expire after 30 minutes. The service restores a saved session after app recreation only when its Firebase status is active; while offline, saved expiry time remains authoritative. Location sharing is user-initiated and distinct from the dashboard's one-time weather-location lookup.

## Algorithm 10: SOS Flashlight

INPUT: User start/stop action and device flashlight availability.

OUTPUT:*Active SOS flashlight signal or an availability/error message.


ALGORITHM 10: SOS Flashlight
BEGIN
    IF user selects Start SOS THEN
        Check whether flashlight is available
        IF unavailable THEN show availability message
        ELSE start SOS flashlight pattern and mark SOS active
        END IF
    ELSE IF user selects Stop SOS THEN
        Stop SOS flashlight pattern and mark SOS inactive
    END IF
    If the plugin operation fails, show an error message
END


## How the Algorithms Interact

- **Hardware flow:** JSN-SR04T, water input, and DHT11 → ESP32 processing and local indicators → Firebase `/flood` updates.
- **Mobile flow:** Firebase sensor stream plus separate Open-Meteo weather retrieval → Flutter dashboard, water-rise status, and weather display. The current firmware sketch's missing timestamp prevents its record from passing the dashboard's freshness test unless another writer supplies that field.
- **ML flow:** Open-Meteo hourly history → feature engineering and per-location scaling → LSTM → XGBoost and Random Forest using the latest weather row plus LSTM outputs → weighted, nonnegative rainfall forecast → Flutter forecast display. The actual weights are 0.96 LSTM, 0.00 XGBoost, and 0.04 Random Forest.
- **Alert flow:** ESP32 water/distance rule → local buzzer and red LED; separately, fresh ultrasonic distance → app risk bands → conditional local application warning. Rainfall forecasts provide notification context but do not determine those risk bands.
- **Emergency flow:** User action → temporary GPS session in Firebase and SOS flashlight behavior. These tools are separate from automatic flood detection and rainfall inference.

## Implementation Verification Note

The algorithms above were traced against repository source, not validated by operating physical hardware or a live Firebase/API deployment. The available source includes `arduino.txt`, which is the firmware sketch inspected; a separate compiled firmware project was not present in the repository listing. In particular, the sketch does not transmit the timestamp required by the Flutter online check. The API's runtime model/configuration declares exact feature orders, uses saved per-location scalers and model artifacts, and specifies the ensemble weights; model internals and the numerical behavior of serialized artifacts were not independently inspected. Training scripts were inspected only to distinguish offline training from runtime inference. The separate Firebase security rules, deployed database contents, and deployed ML server state were not available for verification.

The API feature code does not fill the leading missing values created by rolling rainfall windows before scaling and LSTM inference. This pseudocode therefore records the observed preprocessing exactly; actual inference quality and successful handling of those missing values were not established from source inspection alone.


