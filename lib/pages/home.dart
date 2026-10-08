import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:detectco/pages/menu.dart'; // change to your actual menu file name
import 'package:detectco/services/weather_condition.dart';
import 'package:detectco/services/flood_risk.dart';
import 'package:detectco/services/ml_flood_risk.dart';
import 'package:detectco/pages/notification.dart';

// =====================================================
// ONE-TIME DEVICE LOCATION (FOR OPEN-METEO)
// =====================================================
//
// The device location is looked up ONLY ONCE per app session.
//
//   * First call  -> checks / requests the normal foreground
//                    location permission, then gets the current
//                    position ONE TIME and stores it in memory.
//   * Later calls -> reuse the stored latitude / longitude. The
//                    device location is never requested again.
//
// There is NO location stream, NO tracking, NO background or
// foreground service. If permission is denied, location services
// are off, GPS fails, or the request times out, the existing fixed
// Calamba coordinates are used instead (and no retry is made).
//
// These variables live at file level (not inside the State), so
// they survive the Home page being rebuilt / re-opened. They are
// only reset when the app process is completely restarted.

// Existing fixed Calamba coordinates (fallback).
const double _fallbackLatitude = 14.15;
const double _fallbackLongitude = 121.05;

// Coordinates stored in memory for the current app session.
double? _sessionLatitude;
double? _sessionLongitude;

// True once the one-time lookup has finished (success or not).
bool _sessionLocationDone = false;

// Shared in-flight lookup, so several weather fetches that start at
// the same time all wait for the SAME single lookup.
Future<void>? _sessionLocationFuture;

// Latitude used by every Open-Meteo request.
double get _weatherLatitude => _sessionLatitude ?? _fallbackLatitude;

// Longitude used by every Open-Meteo request.
double get _weatherLongitude => _sessionLongitude ?? _fallbackLongitude;

// Makes sure the one-time lookup has happened. Safe to call as many
// times as you like: the real lookup only ever runs once.
Future<void> _ensureSessionLocation() {
  if (_sessionLocationDone) {
    return Future<void>.value();
  }

  return _sessionLocationFuture ??= _lookupSessionLocationOnce();
}

Future<void> _lookupSessionLocationOnce() async {
  try {
    // Normal Android location permission dialog (only shown
    // when permission has not been decided yet).
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final bool permissionGranted =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    if (permissionGranted) {
      final bool servicesEnabled = await Geolocator.isLocationServiceEnabled();

      if (servicesEnabled) {
        // ONE single position request (not a stream).
        final Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 15),
          ),
        ).timeout(const Duration(seconds: 20));

        if (position.latitude.isFinite && position.longitude.isFinite) {
          _sessionLatitude = position.latitude;
          _sessionLongitude = position.longitude;
        }
      }
    }
  } catch (e) {
    // Any location error -> keep the Calamba fallback.
    // No retry is made.
  } finally {
    _sessionLocationDone = true;
  }
}

// =====================================================
// OPEN-METEO HOURLY ROW MATCHING (CURRENT LOCAL HOUR)
// =====================================================
//
// The Open-Meteo request uses timezone=auto, so every timestamp in
// the response (current.time and hourly.time[]) is expressed in the
// LOCAL time of the requested coordinates. The request asks for
// forecast_days=2, so hourly.* starts at 00:00 of the local day.
//
// Instead of assuming "index 0 = now", the hourly row is found by
// matching current.time (floored to the hour) against hourly.time[].
// The rain probability, hourly rainfall and the rainfall forecast
// sums are all read from that same row, so they describe the same
// period as the current temperature / humidity.

double? _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '');
}

// Converts an Open-Meteo local timestamp such as "2026-10-07T15:30"
// into a timezone-free value floored to the hour, so two timestamps
// can be compared by their local wall-clock hour only.
DateTime? _localHour(dynamic raw) {
  if (raw == null) return null;

  final DateTime? parsed = DateTime.tryParse(raw.toString());

  if (parsed == null) return null;

  return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour);
}

// Index of the hourly row that matches the current local hour.
int _currentHourlyIndex(
  Map<String, dynamic> result,
  Map<String, dynamic>? current,
  List<dynamic> hourlyTimes,
) {
  if (hourlyTimes.isEmpty) return 0;

  DateTime? nowLocalHour = _localHour(current?['time']);

  // Fallback: build the local hour from the UTC offset that
  // Open-Meteo returns for the requested coordinates.
  if (nowLocalHour == null) {
    final int offsetSeconds = (_toDouble(result['utc_offset_seconds']) ?? 0)
        .round();

    final DateTime shifted = DateTime.now().toUtc().add(
      Duration(seconds: offsetSeconds),
    );

    nowLocalHour = DateTime.utc(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
    );
  }

  // The matching row is the last hourly timestamp that is not
  // later than the current local hour.
  int match = -1;

  for (int i = 0; i < hourlyTimes.length; i++) {
    final DateTime? t = _localHour(hourlyTimes[i]);

    if (t == null) continue;

    if (t.isAfter(nowLocalHour)) break;

    match = i;
  }

  return match < 0 ? 0 : match;
}

class _HourlyRainReading {
  // Rainfall (mm) summed from the current hourly row onward.
  final double rainfall1h;
  final double rainfall3h;
  final double rainfall6h;
  final double rainfall12h;
  final double rainfall24h;

  // Hourly precipitation (mm) of the current hourly row.
  final double? rainNow;

  // Precipitation probability (%) of the current hourly row.
  final double? probabilityNow;

  const _HourlyRainReading({
    required this.rainfall1h,
    required this.rainfall3h,
    required this.rainfall6h,
    required this.rainfall12h,
    required this.rainfall24h,
    required this.rainNow,
    required this.probabilityNow,
  });
}

_HourlyRainReading _readHourlyRain({
  required Map<String, dynamic> result,
  required Map<String, dynamic>? current,
  required Map<String, dynamic>? hourly,
}) {
  if (hourly == null) {
    return const _HourlyRainReading(
      rainfall1h: 0,
      rainfall3h: 0,
      rainfall6h: 0,
      rainfall12h: 0,
      rainfall24h: 0,
      rainNow: null,
      probabilityNow: null,
    );
  }

  final List<dynamic> times = hourly['time'] is List
      ? hourly['time'] as List
      : [];

  final List<dynamic> precipitationValues = hourly['precipitation'] is List
      ? hourly['precipitation'] as List
      : [];

  final List<dynamic> probabilityValues =
      hourly['precipitation_probability'] is List
      ? hourly['precipitation_probability'] as List
      : [];

  final int start = _currentHourlyIndex(result, current, times);

  double sumRainfall(int count) {
    final int end = math.min(start + count, precipitationValues.length);

    double total = 0;

    for (int i = start; i < end; i++) {
      total += _toDouble(precipitationValues[i]) ?? 0;
    }

    return total;
  }

  double? probabilityNow;

  if (start < probabilityValues.length) {
    probabilityNow = _toDouble(probabilityValues[start]);
  }

  double? rainNow;

  if (start < precipitationValues.length) {
    rainNow = _toDouble(precipitationValues[start]);
  }

  return _HourlyRainReading(
    rainfall1h: sumRainfall(1),
    rainfall3h: sumRainfall(3),
    rainfall6h: sumRainfall(6),
    rainfall12h: sumRainfall(12),
    rainfall24h: sumRainfall(24),
    rainNow: rainNow,
    probabilityNow: probabilityNow,
  );
}

// =====================================================
// DASHBOARD REFRESH RATE
// =====================================================
//
// Controls how often the dashboard info (temperature, humidity,
// water level and flood risk status) is allowed to change on
// screen. This is separate from the original data refresh rate:
// Firebase / ESP32 / API data keeps updating in the background
// exactly as before, the screen just shows the latest value only
// once per interval.
//
// Duration.zero = original behavior (real-time, no limit).
//
// From menu.dart, call:
//   setHomeRefreshRate(const Duration(minutes: 1));
//   setHomeRefreshRate(Duration.zero); // back to real-time

final ValueNotifier<Duration> homeRefreshInterval = ValueNotifier<Duration>(
  Duration.zero,
);

void setHomeRefreshRate(Duration interval) {
  homeRefreshInterval.value = interval < Duration.zero
      ? Duration.zero
      : interval;
}

// =====================================================
// WATER LITE MODE (NO WAVES, NO RUBBER DUCK)
// =====================================================
//
// When true, the water level in the tube is drawn with a
// straight, flat surface (no waving) and the rubber duck is
// never shown. The wave animation is also stopped completely,
// which removes the constant repaints and makes the dashboard
// much lighter on weak devices.
//
// false = original behavior (waving water + floating duck).
//
// From menu.dart, call:
//   setHomeWaterLiteMode(true);   // straight water, no duck
//   setHomeWaterLiteMode(false);  // waves + duck (original)
//
// or bind a switch directly to the notifier:
//   homeWaterLite.value = newValue;

final ValueNotifier<bool> homeWaterLite = ValueNotifier<bool>(false);

void setHomeWaterLiteMode(bool enabled) {
  homeWaterLite.value = enabled;
}

// =====================================================
// LOW-END PERFORMANCE MODE
// =====================================================
//
// One switch that turns on every extra performance
// optimization for weak devices. When it is OFF (default) the
// home page behaves exactly like the original.
//
// When it is ON:
//   * Glass cards use a plain translucent fill instead of the
//     expensive BackdropFilter blur, and each card is wrapped
//     in its own RepaintBoundary.
//   * The weather background always uses the lightweight
//     ("lite") version, no matter what homeBgQuality says.
//   * Water gauge: RepaintBoundary around the gauge, the human
//     image is built once (not every animation frame), and the
//     wave path is calculated with fewer points.
//   * The 2-second ESP32 check only rebuilds the screen when the
//     online/offline status really changes.
//   * Network fetches no longer rebuild the screen just to show or
//     hide a loading spinner (the spinners are hidden), and the
//     weather-condition fetch only rebuilds when a value changed.
//   * Images are decoded at the size they are displayed
//     (cacheWidth / cacheHeight) instead of at full size.
//
// From menu.dart, call:
//   setHomePerformanceMode(true);   // low-end device mode
//   setHomePerformanceMode(false);  // original behavior
//
// or bind a switch directly to the notifier:
//   homePerformanceMode.value = newValue;
//
// TIP: for the lightest result also turn on water lite mode:
//   setHomeWaterLiteMode(true);

final ValueNotifier<bool> homePerformanceMode = ValueNotifier<bool>(false);

void setHomePerformanceMode(bool enabled) {
  homePerformanceMode.value = enabled;
}

// =====================================================
// GLASSMORPHISM CARD HELPER
// =====================================================
//
// Reusable frosted-glass container used across the new
// dashboard UI. Semi-transparent background, subtle light
// border, soft drop shadow, and an optional colored glow
// border (used for the flood-risk card).
//
// In low-end performance mode the blur (BackdropFilter) is
// skipped and the card is wrapped in a RepaintBoundary.

Widget _glassCard({
  required Widget child,
  Color? glowColor,
  EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  BorderRadius? borderRadius,
}) {
  final BorderRadius radius = borderRadius ?? BorderRadius.circular(18);

  // ---------------------------------------------------
  // LOW-END VERSION (no blur)
  // ---------------------------------------------------
  if (homePerformanceMode.value) {
    return RepaintBoundary(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: radius,
          // More opaque than the blurred version so the card
          // stays readable without the blur behind it.
          color: Colors.black.withOpacity(0.32),
          border: Border.all(
            color: glowColor != null
                ? glowColor.withOpacity(0.5)
                : Colors.white.withOpacity(0.12),
            width: glowColor != null ? 1.4 : 1,
          ),
          boxShadow: [
            if (glowColor != null)
              BoxShadow(color: glowColor.withOpacity(0.22), blurRadius: 8),
          ],
        ),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------
  // NORMAL VERSION (frosted glass)
  // ---------------------------------------------------
  return ClipRRect(
    borderRadius: radius,
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Colors.white.withOpacity(0.025),
          border: Border.all(
            color: glowColor != null
                ? glowColor.withOpacity(0.5)
                : Colors.white.withOpacity(0.12),
            width: glowColor != null ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
            if (glowColor != null)
              BoxShadow(
                color: glowColor.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 1,
              ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  String _selectedBarangay = 'Uwisan';

  // Shortcut for the low-end performance switch.
  bool get _perf => homePerformanceMode.value;

  // =====================================================
  // BARANGAY PICKER (opens directly below the pill)
  // =====================================================

  static const List<String> _barangays = ['Uwisan', 'Palingon', 'Lingga'];

  Future<void> _showBarangayMenu(BuildContext fieldContext) async {
    final RenderBox button = fieldContext.findRenderObject() as RenderBox;

    final RenderBox overlay =
        Overlay.of(fieldContext).context.findRenderObject() as RenderBox;

    final Offset position = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    final String? selected = await showMenu<String>(
      context: fieldContext,
      color: const Color(0xFF303030),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: BoxConstraints(
        minWidth: math.max(button.size.width, 200),
        maxWidth: 260,
      ),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + button.size.height + 4,
        overlay.size.width - position.dx - button.size.width,
        0,
      ),
      items: _barangays.map((name) {
        return PopupMenuItem<String>(
          value: name,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Barangay $name',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (name == _selectedBarangay)
                const Icon(Icons.check_rounded, color: Colors.white, size: 20),
            ],
          ),
        );
      }).toList(),
    );

    if (selected == null || !mounted) return;

    setState(() {
      _selectedBarangay = selected;
    });
  }

  // =====================================================
  // WATER SETTINGS
  // =====================================================

  // The gauge displays the maximum possible rise from the 150 cm baseline.
  static const double maxWaterLevel = FloodRiskReading.baselineDistanceCm;

  static const double idleWaterLevel = 40.0;

  late final AnimationController _waterAnimationController;

  double _previousWaterLevel = idleWaterLevel;

  // =====================================================
  // ESP32 SENSOR CONNECTION
  // =====================================================

  // The ESP32 sends a Firebase server timestamp every second.
  // If no recent timestamp is received, the ESP32 is considered
  // offline and Open-Meteo is used as the weather fallback.
  static const int esp32TimeoutSeconds = 30;

  bool _esp32Online = false;

  // Stores the latest Firebase timestamp received from ESP32.
  // IMPORTANT:
  // This allows the local timer to detect when Firebase stops
  // receiving updates even though Firebase itself sends no new event.
  int? _latestEsp32Timestamp;

  // Lets us know that Firebase has provided at least one reading.
  bool _hasReceivedFirebaseData = false;

  // Checks the timestamp independently of Firebase onValue events.
  Timer? _esp32StatusTimer;

  // =====================================================
  // DASHBOARD REFRESH RATE (DISPLAY THROTTLE)
  // =====================================================
  //
  // Holds the values currently shown on the dashboard and the
  // time they were last updated. When a refresh interval is set
  // (see setHomeRefreshRate above), the dashboard keeps showing
  // this snapshot until the interval has passed.

  _DashboardSnapshot? _displayedSnapshot;
  DateTime? _lastDashboardUpdate;

  // =====================================================
  // OPEN-METEO FALLBACK WEATHER
  // =====================================================

  double? _fallbackTemperature;
  double? _fallbackHumidity;

  bool _fallbackWeatherLoading = false;
  String? _fallbackWeatherError;

  // Prevent repeated Open-Meteo requests while Firebase
  // continues rebuilding the StreamBuilder.
  bool _fallbackWeatherRequestScheduled = false;

  // =====================================================
  // ML FLOOD PREDICTION API
  // =====================================================

  static const String mlApiUrl = String.fromEnvironment(
    'ML_API_URL',
    defaultValue: 'http://192.168.18.14:8000/predict',
  );

  double? _mlRainfall1h;
  double? _mlRainfall3h;
  double? _mlRainfall6h;
  double? _mlRainfall12h;
  double? _mlRainfall24h;
  DateTime? _mlLastPredictionAt;
  double? _mlCurrentRainfallMm;
  double _latestWaterRiseCm = 0;
  bool _latestWaterSensorActive = false;

  bool _mlLoading = false;
  String? _mlError;

  // True when the ML forecast is idle, unavailable,
  // missing, or the ML server cannot be reached.
  bool _mlForecastIdle = false;

  Timer? _mlPredictionTimer;

  // =====================================================
  // OPEN-METEO RAINFALL FALLBACK
  // =====================================================

  double? _openMeteoCurrentRainfall;
  double? _openMeteoRainfall1h;
  double? _openMeteoRainfall3h;
  double? _openMeteoRainfall6h;
  double? _openMeteoRainfall12h;
  double? _openMeteoRainfall24h;
  double? _openMeteoRainProbability;

  bool _openMeteoRainLoading = false;
  String? _openMeteoRainError;

  // =====================================================
  // WEATHER CONDITION (FOR BACKGROUND ANIMATION)
  // =====================================================
  //
  // This is separate from the flood/rainfall logic above.
  // It only tells the background what the sky currently looks
  // like (sunny / cloudy / rainy / stormy), using Open-Meteo's
  // weather_code and cloud_cover, combined with the rainfall
  // data that is already fetched elsewhere in this file.

  int? _weatherCode;
  double? _cloudCover;
  double? _weatherCurrentPrecipitation;
  bool _weatherConditionLoading = false;
  Timer? _weatherConditionTimer;
  StreamSubscription<List<ConnectivityResult>>? _weatherConnectivitySub;

  // =====================================================
  // INIT STATE
  // =====================================================

  @override
  void initState() {
    super.initState();

    // Continuous water-wave animation.
    // In water lite mode the animation is not started at all.
    _waterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    if (!homeWaterLite.value) {
      _waterAnimationController.repeat();
    }

    // =====================================================
    // WATER LITE MODE LISTENER
    // =====================================================
    //
    // When the switch in menu.dart changes, the wave animation
    // is stopped / restarted and the dashboard is rebuilt.

    homeWaterLite.addListener(_onWaterLiteChanged);

    // =====================================================
    // DASHBOARD REFRESH RATE LISTENER
    // =====================================================
    //
    // When the refresh rate is changed (from menu.dart), the
    // dashboard immediately takes a fresh snapshot and then
    // follows the new interval.

    homeRefreshInterval.addListener(_onRefreshRateChanged);

    // =====================================================
    // LOW-END PERFORMANCE MODE LISTENER
    // =====================================================
    //
    // When the low-end switch in menu.dart changes, the whole
    // dashboard is rebuilt with the matching (light / normal)
    // widgets.

    homePerformanceMode.addListener(_onPerformanceModeChanged);

    // =====================================================
    // ONE-TIME DEVICE LOCATION
    // =====================================================
    //
    // Starts the one-time location lookup (only if it has not
    // already happened during this app session). The weather
    // fetches below also wait for the same single lookup, so
    // the device location is never requested more than once.

    _ensureSessionLocation();

    // =====================================================
    // START ML PREDICTION
    // =====================================================

    _fetchMLPrediction();

    _mlPredictionTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _fetchMLPrediction(),
    );

    // =====================================================
    // START ESP32 CONNECTION CHECK
    // =====================================================
    //
    // Firebase only emits onValue when data changes.
    // When ESP32 is turned off, Firebase keeps the old data
    // and does NOT automatically emit another event.
    //
    // Therefore this timer checks the age of the last ESP32
    // timestamp independently every 2 seconds.
    //

    _esp32StatusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkEsp32Connection(),
    );

    // =====================================================
    // START WEATHER CONDITION (BACKGROUND ANIMATION)
    // =====================================================

    _fetchWeatherCondition();

    _weatherConnectivitySub = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        _fetchWeatherCondition();
      }
    }, onError: (_) {});

    _weatherConditionTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _fetchWeatherCondition(),
    );
  }

  @override
  void dispose() {
    homeWaterLite.removeListener(_onWaterLiteChanged);
    homeRefreshInterval.removeListener(_onRefreshRateChanged);
    homePerformanceMode.removeListener(_onPerformanceModeChanged);
    _mlPredictionTimer?.cancel();
    _esp32StatusTimer?.cancel();
    _weatherConditionTimer?.cancel();
    _weatherConnectivitySub?.cancel();
    _waterAnimationController.dispose();
    super.dispose();
  }

  // =====================================================
  // WATER LITE MODE CHANGED
  // =====================================================

  // Called whenever the water lite switch is changed.
  // ON  -> stop the wave animation (straight water, no duck).
  // OFF -> restart the wave animation (waves + duck again).
  void _onWaterLiteChanged() {
    if (homeWaterLite.value) {
      _waterAnimationController.stop();
    } else {
      if (!_waterAnimationController.isAnimating) {
        _waterAnimationController.repeat();
      }
    }

    if (!mounted) return;

    setState(() {});
  }

  // =====================================================
  // LOW-END PERFORMANCE MODE CHANGED
  // =====================================================

  // Called whenever the low-end performance switch is changed.
  void _onPerformanceModeChanged() {
    if (!mounted) return;

    setState(() {});
  }

  // =====================================================
  // LOADING-FLAG UPDATE (NETWORK FETCHES)
  // =====================================================
  //
  // Normal mode: updates the flag with setState (the loading
  // spinner appears / disappears, same as the original).
  //
  // Low-end mode: only changes the flag, WITHOUT rebuilding the
  // screen. The flag still protects against overlapping requests,
  // and the spinners are hidden in this mode, so nothing needs to
  // be redrawn. This saves two rebuilds per network request.
  void _loadingUpdate(VoidCallback change) {
    if (!mounted) return;

    if (_perf) {
      change();
    } else {
      setState(change);
    }
  }

  // =====================================================
  // DASHBOARD REFRESH RATE
  // =====================================================

  // Called whenever the refresh rate is changed.
  // Clears the held snapshot so the dashboard updates right away,
  // then continues at the new interval.
  void _onRefreshRateChanged() {
    _displayedSnapshot = null;
    _lastDashboardUpdate = null;

    if (!mounted) return;

    setState(() {});
  }

  // Returns the values the dashboard should display.
  //
  // - Interval is zero          -> live values (original behavior).
  // - No data received yet      -> live values (so startup is not delayed).
  // - Interval has passed       -> take a new snapshot of live values.
  // - Interval has NOT passed   -> keep showing the previous snapshot.
  _DashboardSnapshot _applyRefreshRate(_DashboardSnapshot live) {
    final Duration interval = homeRefreshInterval.value;

    if (interval <= Duration.zero || !_hasReceivedFirebaseData) {
      _displayedSnapshot = live;
      _lastDashboardUpdate = DateTime.now();
      return live;
    }

    final DateTime now = DateTime.now();
    final _DashboardSnapshot? cached = _displayedSnapshot;
    final DateTime? last = _lastDashboardUpdate;

    if (cached == null || last == null || now.difference(last) >= interval) {
      _displayedSnapshot = live;
      _lastDashboardUpdate = now;
      return live;
    }

    return cached;
  }

  // =====================================================
  // CHECK ESP32 CONNECTION
  // =====================================================

  void _checkEsp32Connection() {
    if (!mounted) return;

    bool newOnlineStatus = false;

    if (_latestEsp32Timestamp != null) {
      final int now = DateTime.now().millisecondsSinceEpoch;

      final int age = now - _latestEsp32Timestamp!;

      newOnlineStatus =
          age >= 0 &&
          age <= const Duration(seconds: esp32TimeoutSeconds).inMilliseconds;
    }

    // If Firebase has not provided any ESP32 data yet,
    // keep the current startup state for now.
    if (!_hasReceivedFirebaseData) {
      return;
    }

    if (_esp32Online != newOnlineStatus) {
      setState(() {
        _esp32Online = newOnlineStatus;
      });

      // =================================================
      // ESP32 JUST WENT OFFLINE
      // =================================================

      if (!newOnlineStatus) {
        _scheduleFallbackWeather();
      }
    } else if (!_perf) {
      // IMPORTANT:
      // Force the StreamBuilder UI to rebuild even when
      // Firebase itself is no longer sending events.
      //
      // This is what allows the old/stale ESP32 reading
      // to stop being displayed after 30 seconds.
      //
      // LOW-END MODE: this extra forced rebuild is skipped.
      // The rebuild above already happens the moment the
      // status changes (online -> offline), which is the only
      // time the screen really needs to be refreshed.
      setState(() {});
    }
  }

  // =====================================================
  // PARSE DOUBLE
  // =====================================================

  double? _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  // =====================================================
  // ML PREDICTION
  // =====================================================

  Future<void> _fetchMLPrediction() async {
    if (_mlLoading) return;

    _loadingUpdate(() {
      _mlLoading = true;
      _mlError = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(mlApiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'latitude': 14.15, 'longitude': 121.05}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('ML API returned HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> result = jsonDecode(response.body);

      // =================================================
      // CHECK IF ML IS IDLE
      // =================================================

      final String mlStatus = result['status']?.toString().toLowerCase() ?? '';

      if (mlStatus == 'idle') {
        MlFloodRiskStore.instance.markUnavailable('ML prediction is idle.');
        if (!mounted) return;

        setState(() {
          _mlForecastIdle = true;
          _mlError = null;
          _mlRainfall1h = null;
          _mlRainfall3h = null;
          _mlRainfall6h = null;
          _mlRainfall12h = null;
          _mlRainfall24h = null;
        });

        _fetchOpenMeteoRainfall();
        return;
      }

      // =================================================
      // GET ML PREDICTIONS
      // =================================================

      final dynamic rawPredictions = result['predictions'];

      if (rawPredictions is! Map) {
        MlFloodRiskStore.instance.markUnavailable(
          'ML predictions are unavailable.',
        );
        if (!mounted) return;

        setState(() {
          _mlForecastIdle = true;
          _mlError = null;
          _mlRainfall1h = null;
          _mlRainfall3h = null;
          _mlRainfall6h = null;
          _mlRainfall12h = null;
          _mlRainfall24h = null;
        });

        _fetchOpenMeteoRainfall();
        return;
      }

      final Map<String, dynamic> predictions = Map<String, dynamic>.from(
        rawPredictions,
      );

      final double? rainfall1h = _parseDouble(predictions['rainfall_1h_mm']);

      final double? rainfall3h = _parseDouble(predictions['rainfall_3h_mm']);

      final double? rainfall6h = _parseDouble(predictions['rainfall_6h_mm']);

      final double? rainfall12h = _parseDouble(predictions['rainfall_12h_mm']);

      final double? rainfall24h = _parseDouble(predictions['rainfall_24h_mm']);

      // =================================================
      // CHECK FOR COMPLETELY MISSING ML FORECAST
      // =================================================
      //
      // IMPORTANT:
      // Zero is a valid rainfall prediction.
      // Therefore 0.00 is NOT treated as idle.
      //

      if (rainfall1h == null &&
          rainfall3h == null &&
          rainfall6h == null &&
          rainfall12h == null &&
          rainfall24h == null) {
        MlFloodRiskStore.instance.markUnavailable(
          'ML predictions are unavailable.',
        );
        if (!mounted) return;

        setState(() {
          _mlForecastIdle = true;
          _mlError = null;
          _mlRainfall1h = null;
          _mlRainfall3h = null;
          _mlRainfall6h = null;
          _mlRainfall12h = null;
          _mlRainfall24h = null;
        });

        _fetchOpenMeteoRainfall();
        return;
      }

      // =================================================
      // VALID ML FORECAST
      // =================================================

      if (!mounted) return;

      final mlSnapshot = MlForecastSnapshot.fromApi(result);
      MlFloodRiskStore.instance.update(result);

      setState(() {
        _mlRainfall1h = rainfall1h;
        _mlRainfall3h = rainfall3h;
        _mlRainfall6h = rainfall6h;
        _mlRainfall12h = rainfall12h;
        _mlRainfall24h = rainfall24h;

        _mlError = null;
        _mlForecastIdle = false;
        _mlLastPredictionAt = mlSnapshot.generatedAt;
        _mlCurrentRainfallMm = mlSnapshot.currentRainfallMm;
      });

      if (_latestWaterSensorActive) {
        final assessment = MlFloodRiskAssessment.calculate(
          waterRiseCm: _latestWaterRiseCm,
          forecast: mlSnapshot,
        );
        await NotificationStorage.maybeSendMlFloodWarning(
          riskLevel: assessment.label,
          waterRiseCm: assessment.waterRiseCm,
          currentRainfallMm: assessment.currentRainfallMm,
          predicted3hMm: mlSnapshot.rainfall3hMm,
        );
      }
    } catch (e) {
      if (!mounted) return;

      MlFloodRiskStore.instance.markUnavailable(
        'ML prediction is unavailable while offline.',
      );

      setState(() {
        _mlError = 'Unable to connect to ML server';

        _mlForecastIdle = true;

        _mlRainfall1h = null;
        _mlRainfall3h = null;
        _mlRainfall6h = null;
        _mlRainfall12h = null;
        _mlRainfall24h = null;
      });

      // =================================================
      // ML ERROR -> OPEN-METEO FALLBACK
      // =================================================

      _fetchOpenMeteoRainfall();
    } finally {
      _loadingUpdate(() {
        _mlLoading = false;
      });
    }
  }

  // =====================================================
  // OPEN-METEO FALLBACK WEATHER
  // =====================================================

  Future<void> _fetchFallbackWeather() async {
    if (_fallbackWeatherLoading) return;

    _loadingUpdate(() {
      _fallbackWeatherLoading = true;
      _fallbackWeatherError = null;
    });

    try {
      // Wait for the one-time location lookup (already done
      // after the first time). Never requests location again.
      await _ensureSessionLocation();

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_weatherLatitude'
        '&longitude=$_weatherLongitude'
        '&current=temperature_2m,relative_humidity_2m,rain,precipitation'
        '&hourly=precipitation,rain,precipitation_probability'
        '&forecast_days=2'
        '&timezone=auto',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Open-Meteo returned HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> result = jsonDecode(response.body);

      final Map<String, dynamic>? current = result['current'] is Map
          ? Map<String, dynamic>.from(result['current'] as Map)
          : null;

      if (current == null) {
        throw Exception('Open-Meteo current weather data missing');
      }

      final dynamic temperatureRaw = current['temperature_2m'];

      final dynamic humidityRaw = current['relative_humidity_2m'];

      final double? temperature = _parseDouble(temperatureRaw);

      final double? humidity = _parseDouble(humidityRaw);

      if (temperature == null || humidity == null) {
        throw Exception('Invalid Open-Meteo weather values');
      }

      // =================================================
      // ALSO READ RAINFALL DATA
      // =================================================

      final double? currentRain = _parseDouble(current['rain']);

      final double? currentPrecipitation = _parseDouble(
        current['precipitation'],
      );

      final Map<String, dynamic>? hourly = result['hourly'] is Map
          ? Map<String, dynamic>.from(result['hourly'] as Map)
          : null;

      // Read rainfall + probability from the hourly row that
      // matches the CURRENT LOCAL HOUR (see _readHourlyRain).
      final _HourlyRainReading hourlyReading = _readHourlyRain(
        result: result,
        current: current,
        hourly: hourly,
      );

      final double rainfall1h = hourlyReading.rainfall1h;
      final double rainfall3h = hourlyReading.rainfall3h;
      final double rainfall6h = hourlyReading.rainfall6h;
      final double rainfall12h = hourlyReading.rainfall12h;
      final double rainfall24h = hourlyReading.rainfall24h;

      if (!mounted) return;

      setState(() {
        _fallbackTemperature = temperature;
        _fallbackHumidity = humidity;

        _fallbackWeatherError = null;

        // =================================================
        // OPEN-METEO RAINFALL DATA
        // =================================================

        _openMeteoCurrentRainfall =
            currentRain ?? currentPrecipitation ?? hourlyReading.rainNow;

        _openMeteoRainfall1h = rainfall1h;

        _openMeteoRainfall3h = rainfall3h;

        _openMeteoRainfall6h = rainfall6h;

        _openMeteoRainfall12h = rainfall12h;

        _openMeteoRainfall24h = rainfall24h;

        _openMeteoRainProbability = hourlyReading.probabilityNow;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _fallbackWeatherError = 'Unable to load Open-Meteo weather';
      });
    } finally {
      _loadingUpdate(() {
        _fallbackWeatherLoading = false;
      });
    }
  }

  // =====================================================
  // OPEN-METEO RAINFALL FALLBACK
  // =====================================================

  Future<void> _fetchOpenMeteoRainfall() async {
    if (_openMeteoRainLoading) return;

    _loadingUpdate(() {
      _openMeteoRainLoading = true;
      _openMeteoRainError = null;
    });

    try {
      // Wait for the one-time location lookup (already done
      // after the first time). Never requests location again.
      await _ensureSessionLocation();

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_weatherLatitude'
        '&longitude=$_weatherLongitude'
        '&current=rain,precipitation'
        '&hourly=precipitation,rain,precipitation_probability'
        '&forecast_days=2'
        '&timezone=auto',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Open-Meteo returned HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> result = jsonDecode(response.body);

      final Map<String, dynamic>? current = result['current'] is Map
          ? Map<String, dynamic>.from(result['current'] as Map)
          : null;

      if (current == null) {
        throw Exception('Open-Meteo current rainfall data missing');
      }

      final double? currentRain = _parseDouble(current['rain']);

      final double? currentPrecipitation = _parseDouble(
        current['precipitation'],
      );

      final Map<String, dynamic>? hourly = result['hourly'] is Map
          ? Map<String, dynamic>.from(result['hourly'] as Map)
          : null;

      // Read rainfall + probability from the hourly row that
      // matches the CURRENT LOCAL HOUR (see _readHourlyRain).
      final _HourlyRainReading hourlyReading = _readHourlyRain(
        result: result,
        current: current,
        hourly: hourly,
      );

      final double rainfall1h = hourlyReading.rainfall1h;
      final double rainfall3h = hourlyReading.rainfall3h;
      final double rainfall6h = hourlyReading.rainfall6h;
      final double rainfall12h = hourlyReading.rainfall12h;
      final double rainfall24h = hourlyReading.rainfall24h;

      if (!mounted) return;

      setState(() {
        _openMeteoCurrentRainfall =
            currentRain ?? currentPrecipitation ?? hourlyReading.rainNow;

        _openMeteoRainfall1h = rainfall1h;

        _openMeteoRainfall3h = rainfall3h;

        _openMeteoRainfall6h = rainfall6h;

        _openMeteoRainfall12h = rainfall12h;

        _openMeteoRainfall24h = rainfall24h;

        _openMeteoRainProbability = hourlyReading.probabilityNow;

        _openMeteoRainError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _openMeteoRainError = 'Unable to load Open-Meteo rainfall';
      });
    } finally {
      _loadingUpdate(() {
        _openMeteoRainLoading = false;
      });
    }
  }

  // =====================================================
  // SCHEDULE OPEN-METEO FALLBACK
  // =====================================================

  void _scheduleFallbackWeather() {
    if (_fallbackWeatherRequestScheduled) return;

    _fallbackWeatherRequestScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fallbackWeatherRequestScheduled = false;

      if (!mounted) return;

      if (!_esp32Online) {
        _fetchFallbackWeather();
      }
    });
  }

  // =====================================================
  // FETCH WEATHER CONDITION (SUNNY / CLOUDY / RAIN CODE)
  // =====================================================
  //
  // This small Open-Meteo call supplies current weather code,
  // cloud cover, and observed precipitation for the background
  // effect. Forecast probability never selects an animation.

  Future<void> _fetchWeatherCondition() async {
    if (_weatherConditionLoading) return;
    _weatherConditionLoading = true;
    try {
      final List<ConnectivityResult> connectivity = await Connectivity()
          .checkConnectivity();
      if (connectivity.isEmpty ||
          connectivity.every((result) => result == ConnectivityResult.none)) {
        return;
      }
      // Wait for the one-time location lookup (already done
      // after the first time). Never requests location again.
      await _ensureSessionLocation();

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_weatherLatitude'
        '&longitude=$_weatherLongitude'
        '&current=weather_code,cloud_cover,precipitation,rain'
        '&timezone=auto',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return;
      }

      final Map<String, dynamic> result = jsonDecode(response.body);

      final Map<String, dynamic>? current = result['current'] is Map
          ? Map<String, dynamic>.from(result['current'] as Map)
          : null;

      if (current == null) {
        return;
      }

      final double? weatherCodeValue = _parseDouble(current['weather_code']);

      final double? cloudCoverValue = _parseDouble(current['cloud_cover']);
      final double? precipitationValue = _parseDouble(current['precipitation']);
      final double? rainValue = _parseDouble(current['rain']);
      final double? currentPrecipitation = precipitationValue == null
          ? rainValue
          : rainValue == null
          ? precipitationValue
          : math.max(precipitationValue, rainValue).toDouble();

      if (!mounted) return;

      // LOW-END MODE: skip the rebuild completely when
      // nothing changed since the last fetch.
      if (_perf) {
        final bool codeSame =
            weatherCodeValue == null ||
            weatherCodeValue.round() == _weatherCode;

        final bool cloudSame =
            cloudCoverValue == null || cloudCoverValue == _cloudCover;

        final bool precipitationSame =
            currentPrecipitation == null ||
            currentPrecipitation == _weatherCurrentPrecipitation;

        if (codeSame && cloudSame && precipitationSame) {
          return;
        }
      }

      setState(() {
        if (weatherCodeValue != null) {
          _weatherCode = weatherCodeValue.round();
        }

        if (cloudCoverValue != null) {
          _cloudCover = cloudCoverValue;
        }

        if (currentPrecipitation != null) {
          _weatherCurrentPrecipitation = currentPrecipitation;
        }
      });
    } catch (e) {
      // Silently ignored: the background simply falls back
      // to whatever rainfall data is already available.
    } finally {
      _weatherConditionLoading = false;
    }
  }

  // =====================================================
  // COMPUTE BACKGROUND WEATHER MODE
  // =====================================================
  //
  // Uses the shared current-condition resolver. ML forecasts
  // and hourly precipitation probability do not select effects.

  _WeatherBackgroundMode _computeWeatherMode() {
    final int? code = _weatherCode;
    final WeatherCondition condition = resolveWeatherCondition(
      weatherCode: code,
      currentPrecipitationMm: _weatherCurrentPrecipitation,
    );
    switch (homeBgChoice.value) {
      case HomeBgChoice.storm:
        return condition == WeatherCondition.thunderstorm
            ? _WeatherBackgroundMode.storm
            : _modeForWeatherCondition(condition);
      case HomeBgChoice.rain:
        return condition == WeatherCondition.rain ||
                condition == WeatherCondition.drizzle
            ? _WeatherBackgroundMode.rain
            : _modeForWeatherCondition(condition);
      case HomeBgChoice.cloudy:
        return _WeatherBackgroundMode.cloudy;
      case HomeBgChoice.sunny:
        return _WeatherBackgroundMode.sunny;
      case HomeBgChoice.auto:
        break; // fall through to the API-based logic below
    }

    return _modeForWeatherCondition(condition);
  }

  _WeatherBackgroundMode _modeForWeatherCondition(WeatherCondition condition) {
    switch (condition) {
      case WeatherCondition.thunderstorm:
        return _WeatherBackgroundMode.storm;
      case WeatherCondition.rain:
      case WeatherCondition.drizzle:
        return _WeatherBackgroundMode.rain;
      case WeatherCondition.cloudy:
      case WeatherCondition.partlyCloudy:
        return _WeatherBackgroundMode.cloudy;
      case WeatherCondition.fog:
        return _WeatherBackgroundMode.fog;
      case WeatherCondition.snow:
        return _WeatherBackgroundMode.snow;
      case WeatherCondition.clear:
        if (condition == WeatherCondition.clear && (_cloudCover ?? 0) > 50) {
          return _WeatherBackgroundMode.cloudy;
        }
        return _WeatherBackgroundMode.sunny;
    }
  }

  // =====================================================
  // CHECK ESP32 TIMESTAMP
  // =====================================================

  bool _isEsp32TimestampRecent(dynamic timestampRaw) {
    if (timestampRaw == null) {
      return false;
    }

    double? timestamp;

    if (timestampRaw is num) {
      timestamp = timestampRaw.toDouble();
    } else {
      timestamp = double.tryParse(timestampRaw.toString());
    }

    if (timestamp == null || !timestamp.isFinite) {
      return false;
    }

    // Firebase server timestamps are milliseconds.
    // This also safely handles seconds if they are ever used.
    if (timestamp < 100000000000) {
      timestamp *= 1000;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;

    final int timestampMilliseconds = timestamp.round();

    final int age = now - timestampMilliseconds;

    // Future timestamps are also treated as valid within
    // the timeout range to tolerate a small clock difference.
    return age <= const Duration(seconds: esp32TimeoutSeconds).inMilliseconds;
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final dbRef = FirebaseDatabase.instance.ref();

    // Dark mode is now the permanent, fixed UI for this app.
    const bool isDarkMode = true;

    // Low-end performance switch (see homePerformanceMode).
    final bool perf = _perf;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF212121),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Color(0xFF212121),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        color: isDarkMode ? const Color(0xFF212121) : Colors.white,
        child: Scaffold(
          backgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,
          // =====================================================
          // RAIN BACKGROUND (BEHIND EVERYTHING) + PAGE CONTENT
          // =====================================================
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Weather-based background.
              // IgnorePointer keeps all taps and double-taps working.
              //
              // ValueListenableBuilder makes the background react
              // instantly when the Menu's Home Background dropdown
              // changes (Default / Storm / Rain / Cloudy / Sunny),
              // and when the Menu's quality setting changes
              // (High / Low). The quality setting lives in menu.dart.
              //
              // LOW-END MODE: always uses the lite background.
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<HomeBgChoice>(
                      valueListenable: homeBgChoice,
                      builder: (context, choice, _) {
                        return ValueListenableBuilder<HomeBgQuality>(
                          valueListenable: homeBgQuality,
                          builder: (context, quality, _) {
                            return _RainBackground(
                              mode: _computeWeatherMode(),
                              lite:
                                  quality == HomeBgQuality.low ||
                                  homePerformanceMode.value,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),

              StreamBuilder<DatabaseEvent>(
                stream: dbRef.child('flood').onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Error loading data',
                        style: TextStyle(fontSize: 16, color: Colors.red),
                      ),
                    );
                  }

                  // =====================================================
                  // SENSOR DATA
                  // =====================================================

                  Map<String, dynamic> data = {};

                  double waterLevel = idleWaterLevel;

                  bool sensorActive = false;

                  bool esp32Online = _esp32Online;

                  if (snapshot.hasData &&
                      snapshot.data!.snapshot.value != null) {
                    final rawValue = snapshot.data!.snapshot.value;

                    if (rawValue is Map) {
                      final rawData = rawValue as Map<dynamic, dynamic>;

                      data = rawData.map(
                        (key, value) => MapEntry(key.toString(), value),
                      );

                      // =================================================
                      // ESP32 TIMESTAMP
                      // =================================================

                      final dynamic timestampRaw = data['timestamp'];

                      // Store the latest Firebase timestamp.
                      //
                      // This value will continue to be checked by
                      // _esp32StatusTimer even after the ESP32 stops
                      // sending Firebase updates.
                      double? parsedTimestamp;

                      if (timestampRaw is num) {
                        parsedTimestamp = timestampRaw.toDouble();
                      } else {
                        parsedTimestamp = double.tryParse(
                          timestampRaw?.toString() ?? '',
                        );
                      }

                      if (parsedTimestamp != null && parsedTimestamp.isFinite) {
                        if (parsedTimestamp < 100000000000) {
                          parsedTimestamp *= 1000;
                        }

                        _latestEsp32Timestamp = parsedTimestamp.round();

                        _hasReceivedFirebaseData = true;
                      }

                      // Use the timestamp immediately for the current
                      // Firebase rebuild.
                      esp32Online = _isEsp32TimestampRecent(timestampRaw);

                      _esp32Online = esp32Online;
                    }
                  }

                  // =====================================================
                  // OPEN-METEO FALLBACK
                  // =====================================================

                  if (!esp32Online) {
                    _scheduleFallbackWeather();
                  }

                  // =================================================
                  // DISTANCE FROM ULTRASONIC SENSOR
                  // =================================================

                  if (esp32Online) {
                    final dynamic distanceRaw = data['distance'];

                    final double? parsedDistance =
                        FloodRiskReading.parseSensorDistanceCm(distanceRaw);

                    if (parsedDistance == null) {
                      // Keep invalid or out-of-range ultrasonic readings idle.
                      sensorActive = false;
                      waterLevel = idleWaterLevel;
                    } else {
                      sensorActive = true;
                      waterLevel = FloodRiskReading.waterRiseCm(parsedDistance);
                    }
                  } else {
                    // =================================================
                    // ESP32 OFFLINE
                    // =================================================
                    //
                    // Do NOT use stale distance data.
                    // Do NOT display 0 as the water level.
                    //
                    // Open-Meteo does not provide the physical
                    // ultrasonic water level, so the water section
                    // remains IDLE until the ESP32 reconnects.

                    sensorActive = false;
                    waterLevel = idleWaterLevel;
                  }

                  // =====================================================
                  // TEMPERATURE
                  // =====================================================

                  final dynamic temperatureRaw = data['temperature'];

                  final double? sensorTemperature = temperatureRaw is num
                      ? temperatureRaw.toDouble()
                      : double.tryParse(temperatureRaw?.toString() ?? '');

                  double? displayedTemperature = esp32Online
                      ? sensorTemperature
                      : _fallbackTemperature;

                  // =====================================================
                  // HUMIDITY
                  // =====================================================

                  final dynamic humidityRaw = data['humidity'];

                  final double? sensorHumidity = humidityRaw is num
                      ? humidityRaw.toDouble()
                      : double.tryParse(humidityRaw?.toString() ?? '');

                  double humidity =
                      (esp32Online ? sensorHumidity : _fallbackHumidity) ?? 0;

                  // =====================================================
                  // DASHBOARD REFRESH RATE
                  // =====================================================
                  //
                  // The values above are always the live values. Here they
                  // are passed through the refresh-rate function so the
                  // dashboard (temperature, humidity, water level and flood
                  // risk status) only changes once per chosen interval.
                  // With the default interval (Duration.zero) the live
                  // values are used as-is, exactly like before.

                  final _DashboardSnapshot shown = _applyRefreshRate(
                    _DashboardSnapshot(
                      waterLevel: waterLevel,
                      sensorActive: sensorActive,
                      esp32Online: esp32Online,
                      temperature: displayedTemperature,
                      humidity: humidity,
                      humidityAvailable:
                          esp32Online || _fallbackHumidity != null,
                    ),
                  );

                  waterLevel = shown.waterLevel;
                  sensorActive = shown.sensorActive;
                  esp32Online = shown.esp32Online;
                  _latestWaterRiseCm = waterLevel;
                  _latestWaterSensorActive = sensorActive;
                  displayedTemperature = shown.temperature;
                  humidity = shown.humidity;
                  final bool humidityAvailable = shown.humidityAvailable;

                  // =====================================================
                  // SCREEN / HEADER
                  // =====================================================
                  //
                  // LAYOUT FIX:
                  // The header used to take 32% of the screen height, which
                  // left a lot of unused space above the cards. It is now
                  // just tall enough for its content (status bar + logo +
                  // greeting + location row), and every remaining pixel goes
                  // to the cards below (mostly to the Water Level card).

                  final double topHeight =
                      MediaQuery.of(context).padding.top + 150;

                  // =====================================================
                  // WATER ANIMATION
                  // =====================================================

                  final double animationStart = _previousWaterLevel;

                  final double animationEnd = waterLevel;

                  _previousWaterLevel = waterLevel;

                  // =====================================================
                  // FLOOD RISK STATUS from the baseline-adjusted water rise.
                  // =====================================================

                  final FloodRiskStatus floodRisk =
                      FloodRiskReading.statusForWaterRise(waterLevel);
                  final MlFloodRiskAssessment mlRiskAssessment =
                      MlFloodRiskAssessment.calculate(
                        waterRiseCm: waterLevel,
                        forecast: MlFloodRiskStore.instance.forecast,
                      );
                  final Color floodColor = !sensorActive
                      ? Colors.grey.shade500
                      : floodRisk == FloodRiskStatus.critical
                      ? Colors.red.shade400
                      : floodRisk == FloodRiskStatus.warning
                      ? Colors.orange.shade400
                      : Colors.green.shade400;

                  final String floodStatusText = !sensorActive
                      ? 'IDLE'
                      : mlRiskAssessment.label;

                  final String floodMessage = !sensorActive
                      ? 'Waiting for sensor data'
                      : floodRisk == FloodRiskStatus.critical
                      ? 'Critical water rise detected'
                      : floodRisk == FloodRiskStatus.warning
                      ? 'Flooding detected — monitor conditions closely'
                      : 'Conditions are normal';

                  final mlForecastValues = [
                    _mlRainfall1h,
                    _mlRainfall3h,
                    _mlRainfall6h,
                    _mlRainfall12h,
                    _mlRainfall24h,
                  ];
                  final bool hasMlForecast =
                      !_mlForecastIdle &&
                      _mlError == null &&
                      mlForecastValues.any((value) => value != null);
                  final fallbackForecastValues = [
                    _openMeteoRainfall1h,
                    _openMeteoRainfall3h,
                    _openMeteoRainfall6h,
                    _openMeteoRainfall12h,
                    _openMeteoRainfall24h,
                  ];
                  final forecastDisplayValues = hasMlForecast
                      ? mlForecastValues
                      : fallbackForecastValues;

                  // =====================================================
                  // FIXED PAGE - NO SCROLLING
                  // =====================================================

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // =================================================
                      // HEADER
                      // =================================================

                      Container(
                        height: topHeight,
                        width: double.infinity,
                        alignment: Alignment.topCenter,
                        // Transparent so the rainy background shows
                        // through. The background gradient starts with the
                        // same blue (light) / dark grey (dark) as before.
                        color: Colors.transparent,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // =====================================
                                // HEADER TOP ROW
                                // =====================================

                                Row(
                                  children: [
                                    SizedBox(
                                      width: 50,
                                      height: 50,
                                      child: Image.asset(
                                        "assets/icon/detect-co_logo.png",
                                        // LOW-END MODE: decode the logo at
                                        // its displayed size only.
                                        cacheWidth: perf
                                            ? (50 *
                                                      MediaQuery.of(
                                                        context,
                                                      ).devicePixelRatio)
                                                  .round()
                                            : null,
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    const Text(
                                      'DETECT-CO',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),

                                    const Spacer(),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // =====================================
                                // GREETING
                                // =====================================
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Hello!',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),

                                    Text(
                                      'Last Synced',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.85),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 4),

                                // =====================================
                                // LOCATION
                                // =====================================
                                //
                                // The Manila clock was removed from this
                                // row (it rebuilt the whole screen every
                                // second).
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Colors.white70,
                                      size: 16,
                                    ),

                                    const SizedBox(width: 4),

                                    // =================================
                                    // BARANGAY PICKER
                                    // =================================
                                    //
                                    // Custom popup (showMenu) so the menu
                                    // always opens directly below the pill.
                                    Builder(
                                      builder: (fieldContext) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.025,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(
                                                0.12,
                                              ),
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.22,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 5),
                                              ),
                                            ],
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              onTap: () => _showBarangayMenu(
                                                fieldContext,
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4,
                                                    ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Barangay $_selectedBarangay',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    const Icon(
                                                      Icons
                                                          .keyboard_arrow_down_rounded,
                                                      color: Colors.white70,
                                                      size: 20,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // =================================================
                      // SENSOR CARD (glassmorphism dashboard)
                      // =================================================
                      //
                      // LAYOUT FIX:
                      // The old Transform.translate(0, -28) only moved the
                      // painting up while the layout box stayed the same,
                      // which wasted 28px at the bottom. The header is now
                      // 28px shorter instead, so the cards start at the same
                      // visual position and use the full remaining height.
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // =========================================
                              // FLOOD RISK STATUS
                              // =========================================
                              //
                              // LAYOUT FIX: slightly smaller (less vertical
                              // padding, smaller badge, slightly smaller title).
                              //
                              // (Placed ABOVE the temperature + humidity row.)

                              _glassCard(
                                glowColor: floodColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: floodColor.withOpacity(
                                                0.18,
                                              ),
                                              border: Border.all(
                                                color: floodColor.withOpacity(
                                                  0.6,
                                                ),
                                                width: 1.4,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.shield_outlined,
                                            color: floodColor,
                                            size: 25,
                                          ),
                                          Positioned(
                                            bottom: 7,
                                            right: 7,
                                            child: Icon(
                                              Icons.check_circle,
                                              color: floodColor,
                                              size: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'FLOOD RISK STATUS',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.0,
                                              color: Colors.white60,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            floodStatusText,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: floodColor,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            floodMessage,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white60,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Colors.white38,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 10),

                              // =========================================
                              // TOP ROW: TEMPERATURE + HUMIDITY
                              // =========================================
                              //
                              // (Placed BELOW the flood risk status card.)
                              Row(
                                children: [
                                  Expanded(
                                    child: _glassCard(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.thermostat_rounded,
                                            color: Colors.orangeAccent,
                                            size: 26,
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'TEMPERATURE',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.8,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  displayedTemperature != null
                                                      ? '${displayedTemperature.toStringAsFixed(1)}°C'
                                                      : '--°C',
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _glassCard(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.water_drop_rounded,
                                            color: Colors.lightBlueAccent,
                                            size: 26,
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'HUMIDITY',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.8,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  humidityAvailable
                                                      ? '${humidity.toStringAsFixed(0)}%'
                                                      : '--%',
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),

                              // =========================================
                              // WATER LEVEL
                              // =========================================
                              //
                              // LAYOUT FIX: this is the only flexible
                              // (Expanded) card, so it receives all the space
                              // left over after the other cards. Because the
                              // header, flood card and rainfall card are now
                              // smaller / fixed, it is much taller than before.
                              Expanded(
                                child: _glassCard(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Water Rise',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final double tubeCanvasWidth = math
                                                .min(
                                                  180,
                                                  constraints.maxWidth * 0.62,
                                                );

                                            // OVERFLOW FIX:
                                            // The gauge has 11 labels that used to
                                            // need ~132px of height no matter how
                                            // small the card was, which caused the
                                            // 40+px overflow. The font now scales
                                            // down only if the space is too small,
                                            // so the labels can never overflow.
                                            final double gaugeFontSize =
                                                ((constraints.maxHeight - 40) /
                                                        11 /
                                                        1.3)
                                                    .clamp(6.0, 10.0)
                                                    .toDouble();

                                            // The water gauge widget.
                                            // LOW-END MODE: wrapped in its own
                                            // RepaintBoundary so its animation
                                            // never repaints the rest of the card.
                                            final Widget
                                            waterGauge = _WaterWithDuck(
                                              width: tubeCanvasWidth,
                                              height:
                                                  constraints.maxHeight - 40,
                                              animation:
                                                  _waterAnimationController,
                                              animationStart: animationStart,
                                              animationEnd: animationEnd,
                                              maxWaterLevel: maxWaterLevel,
                                              isDark: isDarkMode,
                                              lite: homeWaterLite.value,
                                              performance: perf,
                                            );

                                            return Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // WATER CONTAINER
                                                SizedBox(
                                                  width: tubeCanvasWidth + 8,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      // FLOATING PILL WITH VALUE
                                                      TweenAnimationBuilder<
                                                        double
                                                      >(
                                                        tween: Tween<double>(
                                                          begin: animationStart,
                                                          end: animationEnd,
                                                        ),
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 800,
                                                            ),
                                                        curve: Curves.easeInOut,
                                                        builder:
                                                            (
                                                              context,
                                                              animatedLevel,
                                                              child,
                                                            ) {
                                                              return Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          4,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .white
                                                                      .withOpacity(
                                                                        0.10,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: Colors
                                                                        .lightBlueAccent
                                                                        .withOpacity(
                                                                          0.45,
                                                                        ),
                                                                    width: 1,
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  sensorActive
                                                                      ? '${animatedLevel.toStringAsFixed(1)} cm rise'
                                                                      : 'IDLE',
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                      ),

                                                      const SizedBox(height: 4),

                                                      Expanded(
                                                        child: Center(
                                                          child: perf
                                                              ? RepaintBoundary(
                                                                  child:
                                                                      waterGauge,
                                                                )
                                                              : waterGauge,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // GAUGE SCALE
                                                Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 40,
                                                          left: 0,
                                                        ),
                                                    child: SizedBox(
                                                      height:
                                                          constraints
                                                              .maxHeight -
                                                          40,
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            '150 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '135 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '120 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '105 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '90 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '75 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '60 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '45 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '30 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .orange
                                                                  .shade300,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '15 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .orange
                                                                  .shade300,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                          Text(
                                                            '0 cm',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .green
                                                                  .shade600,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  gaugeFontSize,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // =========================================
                              // RAINFALL FORECAST (always visible)
                              // =========================================
                              //
                              // LAYOUT FIX: fixed height (SizedBox) so the card
                              // never changes size when the forecast content
                              // changes (ML vs Open-Meteo, extra lines, etc.).
                              // The content sits in a FittedBox(scaleDown) so it
                              // can never overflow the fixed height.
                              //
                              // LOW-END MODE: the loading spinners are hidden
                              // (loading flags no longer trigger a rebuild).
                              SizedBox(
                                height: 154,
                                child: _glassCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.cloud_queue_rounded,
                                            color: Colors.white70,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              hasMlForecast
                                                  ? 'ML RAINFALL FORECAST'
                                                  : 'OPEN-METEO RAINFALL · ML UNAVAILABLE',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.7,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                          if (!perf && _mlLoading)
                                            const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        height: 37,
                                        child: Row(
                                          children: List.generate(5, (index) {
                                            const periods = [
                                              '1h',
                                              '3h',
                                              '6h',
                                              '12h',
                                              '24h',
                                            ];
                                            final value =
                                                forecastDisplayValues[index];
                                            return Expanded(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    periods[index],
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey[400],
                                                    ),
                                                  ),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      value == null
                                                          ? '-- mm'
                                                          : '${value.toStringAsFixed(1)} mm',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                      Expanded(
                                        child: hasMlForecast
                                            ? CustomPaint(
                                                painter:
                                                    _MlRainfallChartPainter(
                                                      values: mlForecastValues,
                                                      color: Colors
                                                          .lightBlueAccent,
                                                    ),
                                                child: const SizedBox.expand(),
                                              )
                                            : Center(
                                                child: Text(
                                                  _mlLoading
                                                      ? 'Loading ML predictions…'
                                                      : (_mlError ??
                                                            'ML prediction unavailable'),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[400],
                                                  ),
                                                ),
                                              ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          hasMlForecast &&
                                                  _mlLastPredictionAt != null
                                              ? 'Last prediction ${TimeOfDay.fromDateTime(_mlLastPredictionAt!).format(context)}'
                                              : (_mlCurrentRainfallMm != null
                                                    ? 'Current rainfall ${_mlCurrentRainfallMm!.toStringAsFixed(1)} mm'
                                                    : (_openMeteoCurrentRainfall !=
                                                              null
                                                          ? 'Open-Meteo current rain ${_openMeteoCurrentRainfall!.toStringAsFixed(1)} mm'
                                                          : 'Forecast unavailable offline')),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MlRainfallChartPainter extends CustomPainter {
  const _MlRainfallChartPainter({required this.values, required this.color});

  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final valid = values
        .asMap()
        .entries
        .where((entry) => entry.value != null && entry.value!.isFinite)
        .toList();
    if (valid.isEmpty || size.width <= 0 || size.height <= 0) return;

    final maxValue = valid.fold<double>(
      0,
      (maximum, entry) => math.max(maximum, entry.value!),
    );
    final usableHeight = math.max(1.0, size.height - 8);
    final points = valid.map((entry) {
      final x = values.length <= 1
          ? size.width / 2
          : size.width * entry.key / (values.length - 1);
      final y =
          size.height -
          4 -
          (maxValue == 0
              ? usableHeight / 2
              : entry.value! / maxValue * usableHeight);
      return Offset(x, y);
    }).toList();

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      path.lineTo(points[index].dx, points[index].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.9)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final pointPaint = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MlRainfallChartPainter oldDelegate) =>
      !listEquals(oldDelegate.values, values) || oldDelegate.color != color;
}

// =====================================================
// DASHBOARD SNAPSHOT
// =====================================================
//
// The set of values shown on the dashboard at one moment.
// Used by the refresh-rate function to hold the displayed
// values between updates.

class _DashboardSnapshot {
  final double waterLevel;
  final bool sensorActive;
  final bool esp32Online;
  final double? temperature;
  final double humidity;
  final bool humidityAvailable;

  const _DashboardSnapshot({
    required this.waterLevel,
    required this.sensorActive,
    required this.esp32Online,
    required this.temperature,
    required this.humidity,
    required this.humidityAvailable,
  });
}

// =====================================================
// BACKGROUND WEATHER MODE
// =====================================================

enum _WeatherBackgroundMode { sunny, cloudy, fog, snow, rain, storm }

// =====================================================
// RAIN BACKGROUND
// =====================================================
//
// Soft, slow, low-opacity rain that is concentrated along the
// left / right edges of the screen and fades toward the center,
// so the sensor card stays fully readable.
//
// The background now switches automatically between four looks
// based on current weather: sunny, cloudy, rain (unchanged from
// before), and storm (the same rain animation, made heavier and
// faster, with occasional lightning).
//
// LOW-END MODE ("lite"):
// When `lite` is true, a second set of four lightweight
// backgrounds is used instead (sunny / cloudy / rain / storm).
// They use far fewer particles, no blur filters, and draw their
// gradients once as static layers instead of every frame, so
// they run smoothly on weak devices.

class _RainDrop {
  final double x; // 0..1 across the screen width
  final double phase; // 0..1 starting offset
  final double length; // pixels
  final int speed; // whole number so the loop is seamless
  final double opacity; // 0..1 per-drop variation

  const _RainDrop({
    required this.x,
    required this.phase,
    required this.length,
    required this.speed,
    required this.opacity,
  });
}

class _RainBackground extends StatefulWidget {
  final _WeatherBackgroundMode mode;

  // True = use the low-end (lightweight) backgrounds.
  final bool lite;

  const _RainBackground({required this.mode, this.lite = false});

  @override
  State<_RainBackground> createState() => _RainBackgroundState();
}

class _RainBackgroundState extends State<_RainBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_RainDrop> _drops;

  // Much smaller particle set used by the low-end backgrounds.
  late final List<_RainDrop> _liteDrops;

  @override
  void initState() {
    super.initState();

    // SLOW animation:
    // one full cycle takes 10 seconds.
    // Drops with speed 1 take 10s to cross the screen,
    // drops with speed 2 take 5s.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    final math.Random rnd = math.Random(42);

    _drops = List.generate(80, (i) {
      double x;

      // ~85% of the drops are placed near the left/right edges.
      // The rest are spread across the screen (very faint in the middle).
      if (rnd.nextDouble() < 0.85) {
        final double t = rnd.nextDouble();
        final double s = t * t * 0.30;
        x = rnd.nextBool() ? s : 1 - s;
      } else {
        x = rnd.nextDouble();
      }

      return _RainDrop(
        x: x,
        phase: rnd.nextDouble(),
        length: 10 + rnd.nextDouble() * 14,
        speed: rnd.nextBool() ? 1 : 2,
        opacity: 0.5 + rnd.nextDouble() * 0.5,
      );
    });

    // LOW-END DROPS:
    // Only 22 drops (instead of 80), all placed near the edges.
    final math.Random liteRnd = math.Random(7);

    _liteDrops = List.generate(22, (i) {
      final double t = liteRnd.nextDouble();
      final double s = t * t * 0.28;
      final double x = liteRnd.nextBool() ? s : 1 - s;

      return _RainDrop(
        x: x,
        phase: liteRnd.nextDouble(),
        length: 10 + liteRnd.nextDouble() * 10,
        speed: liteRnd.nextBool() ? 1 : 2,
        opacity: 0.6 + liteRnd.nextDouble() * 0.4,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // =====================================================
  // LOW-END BACKGROUNDS
  // =====================================================

  Widget _buildLite() {
    final _WeatherBackgroundMode mode = widget.mode;

    switch (mode) {
      // ---------------------------------------------
      // SUNNY (LITE)
      // ---------------------------------------------
      case _WeatherBackgroundMode.sunny:
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1E5CA6),
                    Color(0xFF3C82C4),
                    Color(0xFF6FA6D4),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // Sun + rainbow are painted once and never repainted.
            RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _LiteSunPainter(),
              ),
            ),

            // A few soft clouds drifting slowly.
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _LiteCloudsPainter(
                    progress: _controller.value,
                    color: Colors.white.withOpacity(0.30),
                    clouds: _liteSunnyClouds,
                    drift: 8,
                    scroll: 0,
                  ),
                );
              },
            ),
          ],
        );

      // ---------------------------------------------
      // CLOUDY (LITE)
      // ---------------------------------------------
      case _WeatherBackgroundMode.cloudy:
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF161B22),
                    Color(0xFF20262E),
                    Color(0xFF212121),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _LiteCloudsPainter(
                    progress: _controller.value,
                    color: const Color(0xFF4A5560).withOpacity(0.55),
                    clouds: _liteCloudyClouds,
                    drift: 14,
                    scroll: 0.10,
                  ),
                );
              },
            ),
          ],
        );

      case _WeatherBackgroundMode.fog:
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF343B42),
                    Color(0xFF242A30),
                    Color(0xFF212121),
                  ],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => CustomPaint(
                size: Size.infinite,
                painter: _FogPainter(progress: _controller.value),
              ),
            ),
          ],
        );

      case _WeatherBackgroundMode.snow:
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF27333D),
                    Color(0xFF20272D),
                    Color(0xFF212121),
                  ],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => CustomPaint(
                size: Size.infinite,
                painter: _SnowPainter(progress: _controller.value),
              ),
            ),
          ],
        );

      // ---------------------------------------------
      // RAIN (LITE)
      // ---------------------------------------------
      case _WeatherBackgroundMode.rain:
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0E1218),
                    Color(0xFF161C24),
                    Color(0xFF212121),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _LiteRainPainter(
                    progress: _controller.value,
                    drops: _liteDrops,
                    speedMultiplier: 1.0,
                    alphaMultiplier: 1.0,
                  ),
                );
              },
            ),
          ],
        );

      // ---------------------------------------------
      // STORM (LITE)
      // ---------------------------------------------
      case _WeatherBackgroundMode.storm:
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF080B10),
                    Color(0xFF10151C),
                    Color(0xFF212121),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _LiteRainPainter(
                    progress: _controller.value,
                    drops: _liteDrops,
                    speedMultiplier: 1.8,
                    alphaMultiplier: 1.4,
                  ),
                );
              },
            ),

            // Simple whole-screen flash only (no bolt drawing).
            const _LightningOverlay(enabled: true, simple: true),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Low-end devices get the lightweight set of backgrounds.
    if (widget.lite) {
      return _buildLite();
    }

    final bool isStorm = widget.mode == _WeatherBackgroundMode.storm;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            switch (widget.mode) {
              case _WeatherBackgroundMode.sunny:
                return CustomPaint(
                  size: Size.infinite,
                  painter: _SunnyPainter(progress: _controller.value),
                );

              case _WeatherBackgroundMode.cloudy:
                return CustomPaint(
                  size: Size.infinite,
                  painter: _CloudyPainter(progress: _controller.value),
                );

              case _WeatherBackgroundMode.fog:
                return CustomPaint(
                  size: Size.infinite,
                  painter: _FogPainter(progress: _controller.value),
                );

              case _WeatherBackgroundMode.snow:
                return CustomPaint(
                  size: Size.infinite,
                  painter: _SnowPainter(progress: _controller.value),
                );

              case _WeatherBackgroundMode.rain:
              case _WeatherBackgroundMode.storm:
                return CustomPaint(
                  size: Size.infinite,
                  painter: _RainPainter(
                    progress: _controller.value,
                    isDark: true,
                    drops: _drops,
                    speedMultiplier: isStorm ? 1.8 : 1.0,
                    alphaMultiplier: isStorm ? 1.4 : 1.0,
                  ),
                );
            }
          },
        ),

        // Occasional lightning flashes, storm mode only.
        _LightningOverlay(enabled: isStorm),
      ],
    );
  }
}

class _FogPainter extends CustomPainter {
  const _FogPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF343B42), Color(0xFF242A30), Color(0xFF212121)],
        ).createShader(Offset.zero & size),
    );
    final Paint mist = Paint()
      ..color = const Color(0xFFCFD8DC).withValues(alpha: 0.075);
    for (int i = 0; i < 4; i++) {
      final double phase = (progress + i * 0.27) % 1;
      final double x = (phase * 1.35 - 0.15) * size.width;
      final double y = size.height * (0.38 + i * 0.12);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: size.width * 0.72,
          height: 34,
        ),
        mist,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FogPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SnowPainter extends CustomPainter {
  const _SnowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF27333D), Color(0xFF20272D), Color(0xFF212121)],
        ).createShader(Offset.zero & size),
    );
    final Paint flake = Paint()
      ..color = const Color(0xFFDCE7EF).withValues(alpha: 0.62);
    for (int i = 0; i < 22; i++) {
      final double seed = i * 37.71;
      final double x =
          ((math.sin(seed) + 1) / 2) * size.width +
          math.sin((progress * math.pi * 2) + seed) * 9;
      final double y =
          (((progress * (0.35 + (i % 4) * 0.12)) + i / 22) % 1) * size.height;
      canvas.drawCircle(Offset(x, y), 1.3 + (i % 3) * 0.55, flake);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _RainPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  final List<_RainDrop> drops;
  final double speedMultiplier;
  final double alphaMultiplier;

  _RainPainter({
    required this.progress,
    required this.isDark,
    required this.drops,
    this.speedMultiplier = 1.0,
    this.alphaMultiplier = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // =====================================================
    // BACKGROUND GRADIENT
    // =====================================================

    final List<Color> colors = isDark
        ? const [Color(0xFF0E1218), Color(0xFF161C24), Color(0xFF212121)]
        : const [Color(0xFF4877F7), Color(0xFFA9C4FB), Color(0xFFE8F0FE)];

    const List<double> stops = [0.0, 0.45, 1.0];

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: isDark ? stops : const [0.28, 0.55, 1.0],
        ).createShader(rect),
    );

    // =====================================================
    // SOFT CLOUDS (slow horizontal drift)
    // =====================================================

    final Paint cloudPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32)
      ..color = isDark
          ? const Color(0xFF3A4652).withOpacity(0.35)
          : Colors.white.withOpacity(0.40);

    final List<List<double>> clouds = [
      // x, y, radius (fractions of screen size)
      [0.10, 0.10, 0.22],
      [0.65, 0.05, 0.28],
      [0.98, 0.22, 0.20],
      [0.02, 0.58, 0.24],
      [1.00, 0.78, 0.24],
    ];

    for (int i = 0; i < clouds.length; i++) {
      final double drift = math.sin(progress * math.pi * 2 + i) * 12;

      canvas.drawCircle(
        Offset(clouds[i][0] * size.width + drift, clouds[i][1] * size.height),
        clouds[i][2] * size.width,
        cloudPaint,
      );
    }

    // =====================================================
    // RAIN DROPS
    // =====================================================

    final Paint rainPaint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final Color rainColor = isDark
        ? const Color(0xFFB0C4DE)
        : const Color(0xFF5F86D6);

    // Low opacity overall.
    final double maxAlpha = isDark ? 0.22 : 0.28;

    for (final _RainDrop d in drops) {
      final double travel = size.height + d.length;

      final double y =
          ((d.phase + progress * d.speed * speedMultiplier) % 1.0) * travel -
          d.length;

      final double x = d.x * size.width;

      // 0 in the center, 1 at the very edges.
      final double edgeDistance = ((d.x - 0.5).abs() * 2).clamp(0.0, 1.0);

      // Center stays very faint, edges are strongest.
      final double alpha =
          (maxAlpha *
                  d.opacity *
                  (0.15 + 0.85 * edgeDistance) *
                  alphaMultiplier)
              .clamp(0.0, 1.0);

      rainPaint.color = rainColor.withOpacity(alpha);

      canvas.drawLine(
        Offset(x, y),
        Offset(x - d.length * 0.2, y + d.length),
        rainPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.speedMultiplier != speedMultiplier ||
      oldDelegate.alphaMultiplier != alphaMultiplier;
}

// =====================================================
// SUNNY BACKGROUND
// =====================================================
//
// A bright, cheerful daytime sky: a light blue gradient, a
// glowing sun with soft rotating rays, a soft rainbow arc, and
// gently drifting white clouds. The sky is kept just saturated
// enough (not pastel-white) so the white text and glass cards
// on top of it stay readable.

class _SunnyPainter extends CustomPainter {
  final double progress;

  _SunnyPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // =====================================================
    // LIGHT SKY GRADIENT
    // =====================================================

    const List<Color> colors = [
      Color(0xFF1E5CA6), // deeper sky blue at the top
      Color(0xFF3C82C4), // mid sky
      Color(0xFF6FA6D4), // soft horizon
    ];

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    // =====================================================
    // SUN GLOW
    // =====================================================

    final Offset sunCenter = Offset(size.width * 0.80, size.height * 0.13);

    // Slow, gentle pulse.
    final double pulse = 0.92 + math.sin(progress * math.pi * 2) * 0.08;

    final double glowRadius = size.width * 0.55 * pulse;

    final Paint glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF3C4).withOpacity(0.55),
          const Color(0xFFFFE28A).withOpacity(0.22),
          const Color(0xFFFFE28A).withOpacity(0.0),
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: glowRadius));

    canvas.drawCircle(sunCenter, glowRadius, glowPaint);

    // =====================================================
    // SOFT LIGHT RAYS (very slow rotation)
    // =====================================================

    final Paint rayPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final double rotation = progress * math.pi * 2 * 0.1;

    for (int i = 0; i < 10; i++) {
      final double angle = rotation + (i * math.pi / 5);

      final Offset rayEnd = Offset(
        sunCenter.dx + math.cos(angle) * size.width * 0.75,
        sunCenter.dy + math.sin(angle) * size.width * 0.75,
      );

      canvas.drawLine(sunCenter, rayEnd, rayPaint);
    }

    // =====================================================
    // SUN CORE
    // =====================================================

    canvas.drawCircle(
      sunCenter,
      size.width * 0.075,
      Paint()..color = const Color(0xFFFFF8DC).withOpacity(0.80),
    );

    canvas.drawCircle(
      sunCenter,
      size.width * 0.075,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10)
        ..color = const Color(0xFFFFE9A0).withOpacity(0.5),
    );

    // =====================================================
    // RAINBOW
    // =====================================================
    //
    // Seven concentric arcs (red on the outside, violet on
    // the inside). The rainbow gently "breathes" in opacity
    // and is softly blurred so it blends into the sky.

    final Offset rainbowCenter = Offset(size.width * 0.42, size.height * 0.42);

    const List<Color> rainbowColors = [
      Color(0xFFFF4B4B), // red
      Color(0xFFFF9A3C), // orange
      Color(0xFFFFE04A), // yellow
      Color(0xFF5CDB6E), // green
      Color(0xFF4AB8FF), // blue
      Color(0xFF5B6CFF), // indigo
      Color(0xFFA26BFF), // violet
    ];

    final double bandWidth = size.width * 0.028;
    final double outerRadius = size.width * 0.62;

    final double shimmer = 0.5 + math.sin(progress * math.pi * 2) * 0.5; // 0..1

    // Soft white glow behind the whole rainbow.
    canvas.drawArc(
      Rect.fromCircle(
        center: rainbowCenter,
        radius: outerRadius - bandWidth * 3.5,
      ),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandWidth * 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
        ..color = Colors.white.withOpacity(0.10 + 0.04 * shimmer),
    );

    final Paint bandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bandWidth + 0.8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);

    for (int i = 0; i < rainbowColors.length; i++) {
      final double radius = outerRadius - i * bandWidth;

      bandPaint.color = rainbowColors[i].withOpacity(0.34 + 0.08 * shimmer);

      canvas.drawArc(
        Rect.fromCircle(center: rainbowCenter, radius: radius),
        math.pi,
        math.pi,
        false,
        bandPaint,
      );
    }

    // =====================================================
    // FLUFFY WHITE CLOUDS (slow horizontal drift)
    // =====================================================
    //
    // Some clouds sit at the rainbow's feet so it looks like it
    // rises out of them; the others just drift across the sky.

    final Paint cloudPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
      ..color = Colors.white.withOpacity(0.36);

    final List<List<double>> clouds = [
      // x, y, radius (fractions of screen size)
      [0.10, 0.44, 0.15], // rainbow left foot
      [0.20, 0.46, 0.12],
      [0.74, 0.44, 0.15], // rainbow right foot
      [0.64, 0.46, 0.12],
      [0.18, 0.12, 0.13],
      [0.50, 0.28, 0.11],
      [0.92, 0.30, 0.12],
      [0.30, 0.66, 0.14],
      [0.88, 0.74, 0.15],
    ];

    for (int i = 0; i < clouds.length; i++) {
      final double drift = math.sin(progress * math.pi * 2 + i) * 10;

      canvas.drawCircle(
        Offset(clouds[i][0] * size.width + drift, clouds[i][1] * size.height),
        clouds[i][2] * size.width,
        cloudPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SunnyPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// =====================================================
// CLOUDY BACKGROUND
// =====================================================
//
// Larger, slower-drifting clouds with no rain, for overcast /
// partly cloudy conditions.

class _CloudyPainter extends CustomPainter {
  final double progress;

  _CloudyPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    const List<Color> colors = [
      Color(0xFF161B22),
      Color(0xFF20262E),
      Color(0xFF212121),
    ];

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    final Paint cloudPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34)
      ..color = const Color(0xFF4A5560).withOpacity(0.45);

    final List<List<double>> clouds = [
      // x, y, radius (fractions of screen size)
      [0.05, 0.12, 0.26],
      [0.55, 0.06, 0.30],
      [0.95, 0.20, 0.24],
      [0.20, 0.55, 0.28],
      [0.85, 0.62, 0.26],
      [0.45, 0.35, 0.22],
    ];

    for (int i = 0; i < clouds.length; i++) {
      final double drift =
          math.sin(progress * math.pi * 2 * 0.5 + i) * 20 +
          progress * size.width * 0.15;

      final double x =
          (clouds[i][0] * size.width + drift) % (size.width * 1.3) -
          size.width * 0.15;

      canvas.drawCircle(
        Offset(x, clouds[i][1] * size.height),
        clouds[i][2] * size.width,
        cloudPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CloudyPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// =====================================================
// LOW-END BACKGROUND PAINTERS
// =====================================================
//
// Lightweight versions of the four backgrounds. Rules used
// to keep them fast on weak devices:
//   * NO MaskFilter.blur (the most expensive operation).
//   * Gradients are drawn once by a DecoratedBox instead of
//     being rebuilt every frame.
//   * Very few particles (22 raindrops, 4-5 clouds).
//   * Sun + rainbow are static and never repaint.

// x, y, radius (fractions of screen size)
const List<List<double>> _liteSunnyClouds = [
  [0.14, 0.14, 0.13],
  [0.55, 0.30, 0.11],
  [0.92, 0.40, 0.12],
  [0.25, 0.62, 0.13],
];

const List<List<double>> _liteCloudyClouds = [
  [0.05, 0.12, 0.26],
  [0.60, 0.08, 0.28],
  [0.25, 0.55, 0.26],
  [0.85, 0.62, 0.24],
];

// -----------------------------------------------------
// LITE RAIN PAINTER (rain + storm)
// -----------------------------------------------------
//
// Same edge-weighted look as the normal rain, but with no
// gradient, no clouds, and only a handful of drops.

class _LiteRainPainter extends CustomPainter {
  final double progress;
  final List<_RainDrop> drops;
  final double speedMultiplier;
  final double alphaMultiplier;

  _LiteRainPainter({
    required this.progress,
    required this.drops,
    this.speedMultiplier = 1.0,
    this.alphaMultiplier = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint rainPaint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.butt;

    const Color rainColor = Color(0xFFB0C4DE);

    const double maxAlpha = 0.24;

    for (final _RainDrop d in drops) {
      final double travel = size.height + d.length;

      final double y =
          ((d.phase + progress * d.speed * speedMultiplier) % 1.0) * travel -
          d.length;

      final double x = d.x * size.width;

      final double edgeDistance = ((d.x - 0.5).abs() * 2).clamp(0.0, 1.0);

      final double alpha =
          (maxAlpha *
                  d.opacity *
                  (0.15 + 0.85 * edgeDistance) *
                  alphaMultiplier)
              .clamp(0.0, 1.0);

      rainPaint.color = rainColor.withOpacity(alpha);

      canvas.drawLine(
        Offset(x, y),
        Offset(x - d.length * 0.2, y + d.length),
        rainPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiteRainPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.speedMultiplier != speedMultiplier ||
      oldDelegate.alphaMultiplier != alphaMultiplier;
}

// -----------------------------------------------------
// LITE CLOUDS PAINTER (sunny + cloudy)
// -----------------------------------------------------
//
// Soft clouds drawn with a cheap radial-gradient fade
// instead of a blur filter.

class _LiteCloudsPainter extends CustomPainter {
  final double progress;
  final Color color;
  final List<List<double>> clouds;

  // Sideways sway in pixels.
  final double drift;

  // Fraction of screen width the clouds slowly travel per cycle
  // (0 = they only sway in place).
  final double scroll;

  _LiteCloudsPainter({
    required this.progress,
    required this.color,
    required this.clouds,
    required this.drift,
    required this.scroll,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < clouds.length; i++) {
      final double sway = math.sin(progress * math.pi * 2 + i) * drift;

      double x = clouds[i][0] * size.width + sway;

      if (scroll > 0) {
        x =
            (x + progress * size.width * scroll) % (size.width * 1.3) -
            size.width * 0.15;
      }

      final Offset center = Offset(x, clouds[i][1] * size.height);

      final double radius = clouds[i][2] * size.width;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withOpacity(0.0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiteCloudsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// -----------------------------------------------------
// LITE SUN + RAINBOW PAINTER (static, painted once)
// -----------------------------------------------------

class _LiteSunPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Sun glow.
    final Offset sunCenter = Offset(size.width * 0.80, size.height * 0.13);

    final double glowRadius = size.width * 0.50;

    canvas.drawCircle(
      sunCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF3C4).withOpacity(0.55),
            const Color(0xFFFFE28A).withOpacity(0.20),
            const Color(0xFFFFE28A).withOpacity(0.0),
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: glowRadius)),
    );

    // Sun core.
    canvas.drawCircle(
      sunCenter,
      size.width * 0.075,
      Paint()..color = const Color(0xFFFFF8DC).withOpacity(0.85),
    );

    // Flat rainbow (no blur, no animation).
    final Offset rainbowCenter = Offset(size.width * 0.42, size.height * 0.42);

    const List<Color> rainbowColors = [
      Color(0xFFFF4B4B),
      Color(0xFFFF9A3C),
      Color(0xFFFFE04A),
      Color(0xFF5CDB6E),
      Color(0xFF4AB8FF),
      Color(0xFF5B6CFF),
      Color(0xFFA26BFF),
    ];

    final double bandWidth = size.width * 0.028;
    final double outerRadius = size.width * 0.62;

    final Paint bandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bandWidth + 0.8;

    for (int i = 0; i < rainbowColors.length; i++) {
      bandPaint.color = rainbowColors[i].withOpacity(0.36);

      canvas.drawArc(
        Rect.fromCircle(
          center: rainbowCenter,
          radius: outerRadius - i * bandWidth,
        ),
        math.pi,
        math.pi,
        false,
        bandPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiteSunPainter oldDelegate) => false;
}

// =====================================================
// LIGHTNING OVERLAY (STORM MODE)
// =====================================================
//
// Occasional, natural-looking lightning flashes: a brief
// whole-screen brightening plus a jagged bolt, on a random
// timer while storm mode is active.
//
// When `simple` is true (low-end storm background), only the
// whole-screen flash is drawn and the bolt is skipped.

class _LightningOverlay extends StatefulWidget {
  final bool enabled;
  final bool simple;

  const _LightningOverlay({required this.enabled, this.simple = false});

  @override
  State<_LightningOverlay> createState() => _LightningOverlayState();
}

class _LightningOverlayState extends State<_LightningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;
  Timer? _flashTimer;
  final math.Random _rnd = math.Random();
  double _boltX = 0.5;

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    if (widget.enabled) {
      _scheduleFlash();
    }
  }

  @override
  void didUpdateWidget(covariant _LightningOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.enabled && !oldWidget.enabled) {
      _scheduleFlash();
    } else if (!widget.enabled && oldWidget.enabled) {
      _flashTimer?.cancel();
      _flashController.stop();
    }
  }

  void _scheduleFlash() {
    _flashTimer?.cancel();

    final int delaySeconds = 4 + _rnd.nextInt(9); // 4-12s

    _flashTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted || !widget.enabled) return;

      _boltX = 0.15 + _rnd.nextDouble() * 0.7;

      _flashController.forward(from: 0).then((_) {
        if (!mounted) return;
        _flashController.reverse();
      });

      _scheduleFlash();
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _flashController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _LightningPainter(
            intensity: _flashController.value,
            boltX: _boltX,
            simple: widget.simple,
          ),
        );
      },
    );
  }
}

class _LightningPainter extends CustomPainter {
  final double intensity;
  final double boltX;
  final bool simple;

  _LightningPainter({
    required this.intensity,
    required this.boltX,
    this.simple = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final Rect rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()..color = Colors.white.withOpacity(0.22 * intensity),
    );

    // Low-end mode: flash only, skip the jagged bolt.
    if (simple) return;

    if (intensity > 0.3) {
      final Paint boltPaint = Paint()
        ..color = Colors.white.withOpacity(0.85 * intensity)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final double startX = boltX * size.width;

      final Path bolt = Path()..moveTo(startX, 0);

      final math.Random rnd = math.Random(boltX.hashCode);

      double x = startX;
      double y = 0;

      while (y < size.height * 0.6) {
        y += 24 + rnd.nextDouble() * 20;
        x += (rnd.nextDouble() - 0.5) * 30;
        bolt.lineTo(x, y);
      }

      canvas.drawPath(bolt, boltPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightningPainter oldDelegate) =>
      oldDelegate.intensity != intensity ||
      oldDelegate.boltX != boltX ||
      oldDelegate.simple != simple;
}

// =====================================================
// WATER + HUMAN + RUBBER DUCK
// =====================================================

class _WaterWithDuck extends StatefulWidget {
  final double width;
  final double height;
  final Animation<double> animation;
  final double animationStart;
  final double animationEnd;
  final double maxWaterLevel;
  final bool isDark;

  // True = water lite mode: straight water surface (no waving)
  // and no rubber duck.
  final bool lite;

  // True = low-end performance mode:
  //   * the human image is built once (not every animation frame)
  //     and kept in its own RepaintBoundary,
  //   * the tube outline is kept in its own RepaintBoundary,
  //   * the wave path uses fewer points,
  //   * images are decoded at their displayed size.
  final bool performance;

  const _WaterWithDuck({
    required this.width,
    required this.height,
    required this.animation,
    required this.animationStart,
    required this.animationEnd,
    required this.maxWaterLevel,
    required this.isDark,
    this.lite = false,
    this.performance = false,
  });

  @override
  State<_WaterWithDuck> createState() => _WaterWithDuckState();
}

class _WaterWithDuckState extends State<_WaterWithDuck>
    with SingleTickerProviderStateMixin {
  // =====================================================
  // DUCK ANIMATION
  // =====================================================

  late final AnimationController _duckController;

  Timer? _duckTimer;

  bool _showDuck = false;

  final math.Random _random = math.Random();

  // =====================================================
  // DUCK SIZE
  // =====================================================

  static const double duckWidth = 34.2;
  static const double duckHeight = 34.2;

  // =====================================================
  // HUMAN SIZE
  // =====================================================

  // Human represents 1.59 meters = 159 cm.
  // The water container represents 200 cm.
  static const double humanHeightCm = 159.0;
  static const double tubeHeightCm = 200.0;

  @override
  void initState() {
    super.initState();

    _duckController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    // The duck is never scheduled in water lite mode.
    if (!widget.lite) {
      _scheduleDuck();
    }
  }

  // =====================================================
  // WATER LITE MODE SWITCHED WHILE THE SCREEN IS OPEN
  // =====================================================

  @override
  void didUpdateWidget(covariant _WaterWithDuck oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.lite && !oldWidget.lite) {
      // Lite turned ON: remove the duck immediately.
      _duckTimer?.cancel();
      _duckController.stop();

      if (_showDuck) {
        _showDuck = false;
      }
    } else if (!widget.lite && oldWidget.lite) {
      // Lite turned OFF: let the duck appear again.
      _scheduleDuck();
    }
  }

  // =====================================================
  // RANDOM DUCK APPEARANCE
  // =====================================================

  void _scheduleDuck() {
    _duckTimer?.cancel();

    final int delaySeconds = 8 + _random.nextInt(11);

    _duckTimer = Timer(Duration(seconds: delaySeconds), _startDuck);
  }

  // =====================================================
  // START DUCK
  // =====================================================

  void _startDuck() {
    if (!mounted) return;

    // Safety: never start the duck in water lite mode.
    if (widget.lite) return;

    setState(() {
      _showDuck = true;
    });

    _duckController.forward(from: 0).then((_) {
      if (!mounted) return;

      // If lite was turned on while the duck was swimming,
      // the controller was stopped and nothing more to do.
      if (widget.lite) return;

      setState(() {
        _showDuck = false;
      });

      _scheduleDuck();
    });
  }

  @override
  void dispose() {
    _duckTimer?.cancel();
    _duckController.dispose();
    super.dispose();
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final bool perf = widget.performance;

    // LOW-END MODE: the human never changes while the water
    // animates, so it is built ONCE here and passed to the
    // AnimatedBuilder as its `child` (Flutter does not rebuild
    // the child on every animation frame). It also gets its own
    // RepaintBoundary so it is not repainted every frame.
    final Widget? cachedHuman = perf
        ? RepaintBoundary(
            child: ClipPath(
              clipper: _TubeInteriorClipper(),
              child: _buildHuman(),
            ),
          )
        : null;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, _duckController]),
      child: cachedHuman,
      builder: (context, child) {
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // =================================================
              // HUMAN
              // =================================================

              if (perf && child != null)
                child
              else
                ClipPath(clipper: _TubeInteriorClipper(), child: _buildHuman()),

              // =================================================
              // WATER
              // =================================================

              // IMPORTANT:
              // Water is intentionally painted AFTER the human.
              // The water is semi-transparent so the human remains
              // visible through the water as the level rises.
              Positioned.fill(
                child: CustomPaint(
                  painter: _WaterBucketPainter(
                    level: widget.animationEnd,
                    maxLevel: widget.maxWaterLevel,
                    isDark: widget.isDark,
                    wavePhase: widget.animation.value * math.pi * 2,
                    straight: widget.lite,
                    // LOW-END MODE: fewer wave points.
                    step: perf ? 4.0 : 2.0,
                  ),
                ),
              ),

              // =================================================
              // DUCK
              // =================================================
              if (_showDuck && !widget.lite)
                ClipPath(clipper: _TubeInteriorClipper(), child: _buildDuck()),

              // =================================================
              // BLUE TUBE OUTLINE
              // =================================================
              Positioned.fill(
                child: IgnorePointer(
                  child: perf
                      ? RepaintBoundary(
                          child: CustomPaint(painter: _TubeOutlinePainter()),
                        )
                      : CustomPaint(painter: _TubeOutlinePainter()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =====================================================
  // BUILD HUMAN
  // =====================================================

  Widget _buildHuman() {
    // =====================================================
    // HUMAN SCALE
    // =====================================================

    // The complete inside of the tube represents 200 cm.
    // The human represents 159 cm.
    //
    // IMPORTANT:
    // The previous version constrained BOTH width and height.
    // Because the PNG has its own aspect ratio, BoxFit.contain
    // reduced the visible human to around 80 cm.
    //
    // The human is now scaled BY HEIGHT instead.
    // This preserves the PNG's original proportions while making
    // its actual height approximately 159 cm inside the 200 cm tube.

    final double tubeInteriorHeight = widget.height - 8;

    final double humanHeight =
        tubeInteriorHeight * (humanHeightCm / tubeHeightCm);

    // LOW-END MODE: decode the PNG at the size it is shown.
    final int? humanCacheHeight = widget.performance
        ? (humanHeight * MediaQuery.of(context).devicePixelRatio).round()
        : null;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: humanHeight,
          child: IgnorePointer(
            child: Image.asset(
              'assets/images/body.png',
              height: humanHeight,
              cacheHeight: humanCacheHeight,
              fit: BoxFit.fitHeight,
              alignment: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // BUILD DUCK
  // =====================================================

  Widget _buildDuck() {
    // =====================================================
    // TUBE DIMENSIONS
    // =====================================================

    final double tubeWidth = widget.width * 0.9;

    final double left = (widget.width - tubeWidth) / 2;

    final double right = left + tubeWidth;

    const double top = 4;

    final double bottom = widget.height - 4;

    // =====================================================
    // DUCK MOVEMENT
    // =====================================================

    final double startX = right - duckWidth * 0.35;

    final double endX = left - duckWidth * 0.65;

    final double curvedProgress = Curves.easeInOut.transform(
      _duckController.value,
    );

    final double duckX = startX + (endX - startX) * curvedProgress;

    // =====================================================
    // CURRENT WATER LEVEL
    // =====================================================

    final double currentLevel =
        widget.animationStart +
        (widget.animationEnd - widget.animationStart) *
            Curves.easeInOut.transform(widget.animation.value);

    final double percent = (currentLevel / widget.maxWaterLevel)
        .clamp(0, 1)
        .toDouble();

    // =====================================================
    // WATER LEVEL POSITION
    // =====================================================

    final double fillHeight = (bottom - top) * percent;

    final double fillTop = bottom - fillHeight;

    // =====================================================
    // DUCK CENTER
    // =====================================================

    final double duckCenterX = duckX + duckWidth / 2;

    // =====================================================
    // WAVE POSITION
    // =====================================================

    final double normalizedX = ((duckCenterX - left) / tubeWidth).clamp(
      0.0,
      1.0,
    );

    const double waveHeight = 3.5;

    final double wave =
        math.sin(
          normalizedX * math.pi * 2 * 1.5 +
              widget.animation.value * math.pi * 2,
        ) *
        waveHeight;

    // =====================================================
    // SLOW FLOATING / BOBBING
    // =====================================================

    final double bob = math.sin(_duckController.value * math.pi * 2) * 1.5;

    // =====================================================
    // DUCK VERTICAL POSITION
    // =====================================================

    final double duckY = fillTop + wave + bob - duckHeight + 5;

    // LOW-END MODE: decode the PNG at the size it is shown.
    final int? duckCacheWidth = widget.performance
        ? (duckWidth * MediaQuery.of(context).devicePixelRatio).round()
        : null;

    // =====================================================
    // DUCK
    // =====================================================

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: duckX,
            top: duckY,
            width: duckWidth,
            height: duckHeight,
            child: IgnorePointer(
              child: Image.asset(
                'assets/images/rubber-duck.png',
                width: duckWidth,
                height: duckHeight,
                cacheWidth: duckCacheWidth,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// TUBE INTERIOR CLIPPER
// =====================================================

class _TubeInteriorClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final double tubeWidth = size.width * 0.9;

    final double left = (size.width - tubeWidth) / 2;

    final double right = left + tubeWidth;

    const double top = 4;

    final double bottom = size.height - 4;

    const double cornerRadius = 14;

    return Path()
      ..moveTo(left, top)
      ..lineTo(left, bottom - cornerRadius)
      ..quadraticBezierTo(left, bottom, left + cornerRadius, bottom)
      ..lineTo(right - cornerRadius, bottom)
      ..quadraticBezierTo(right, bottom, right, bottom - cornerRadius)
      ..lineTo(right, top)
      ..close();
  }

  @override
  bool shouldReclip(covariant _TubeInteriorClipper oldClipper) {
    return false;
  }
}

// =====================================================
// TUBE OUTLINE PAINTER
// =====================================================

class _TubeOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double tubeWidth = size.width * 0.9;

    final double left = (size.width - tubeWidth) / 2;

    final double right = left + tubeWidth;

    const double top = 4;

    final double bottom = size.height - 4;

    const double cornerRadius = 14;

    final outlinePaint = Paint()
      ..color = Colors.blue.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final tubePath = Path()
      ..moveTo(left, top)
      ..lineTo(left, bottom - cornerRadius)
      ..quadraticBezierTo(left, bottom, left + cornerRadius, bottom)
      ..lineTo(right - cornerRadius, bottom)
      ..quadraticBezierTo(right, bottom, right, bottom - cornerRadius)
      ..lineTo(right, top);

    canvas.drawPath(tubePath, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _TubeOutlinePainter oldDelegate) {
    return false;
  }
}

// =====================================================
// SENSOR CARD
// =====================================================

class SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final double? waterLevel;
  final bool isDark;

  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    this.unit = '',
    this.waterLevel,
    required this.isDark,
  });

  Color _getCardColor() {
    if (waterLevel == null) {
      return isDark ? const Color(0xFF2C2C2C) : Colors.white;
    }

    final level = waterLevel!;

    switch (FloodRiskReading.statusForWaterRise(level)) {
      case FloodRiskStatus.critical:
        return Colors.red.shade700;
      case FloodRiskStatus.warning:
        return Colors.orange.shade700;
      case FloodRiskStatus.normal:
        return Colors.green.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: _getCardColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[300] : Colors.grey,
            ),
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),

              const SizedBox(width: 2),

              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[300] : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================
// WARNING CARD
// =====================================================

class WarningCard extends StatelessWidget {
  final double waterLevel;
  final bool isDark;

  const WarningCard({
    super.key,
    required this.waterLevel,
    required this.isDark,
  });

  String get statusText {
    switch (FloodRiskReading.statusForWaterRise(waterLevel)) {
      case FloodRiskStatus.critical:
        return 'Critical';
      case FloodRiskStatus.warning:
        return 'Flooding';
      case FloodRiskStatus.normal:
        return 'Safe';
    }
  }

  Color get statusColor {
    switch (FloodRiskReading.statusForWaterRise(waterLevel)) {
      case FloodRiskStatus.critical:
        return Colors.red;
      case FloodRiskStatus.warning:
        return Colors.orange;
      case FloodRiskStatus.normal:
        return const Color.fromRGBO(76, 175, 80, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : statusColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Flood Risk Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            statusText,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// WATER BUCKET PAINTER
// =====================================================

class _WaterBucketPainter extends CustomPainter {
  final double level;
  final double maxLevel;
  final bool isDark;
  final double wavePhase;

  // True = flat water surface (no waving).
  final bool straight;

  // Horizontal distance (in pixels) between two points of the
  // wave path. 2.0 = original smoothness; 4.0 = low-end mode
  // (half as many points to calculate every frame).
  final double step;

  _WaterBucketPainter({
    required this.level,
    required this.maxLevel,
    required this.isDark,
    required this.wavePhase,
    this.straight = false,
    this.step = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double tubeWidth = size.width * 0.9;

    final double left = (size.width - tubeWidth) / 2;

    final double right = left + tubeWidth;

    final double top = 4;

    final double bottom = size.height - 4;

    final double cornerRadius = 14;

    // =====================================================
    // TUBE OUTLINE
    // =====================================================

    final outlinePaint = Paint()
      ..color = Colors.blue.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final tubePath = Path()
      ..moveTo(left, top)
      ..lineTo(left, bottom - cornerRadius)
      ..quadraticBezierTo(left, bottom, left + cornerRadius, bottom)
      ..lineTo(right - cornerRadius, bottom)
      ..quadraticBezierTo(right, bottom, right, bottom - cornerRadius)
      ..lineTo(right, top);

    // =====================================================
    // WATER LEVEL
    // =====================================================

    final double percent = (level / maxLevel).clamp(0, 1).toDouble();

    final double fillHeight = (bottom - top) * percent;

    final double fillTop = bottom - fillHeight;

    // =====================================================
    // SEMI-TRANSPARENT WATER
    // =====================================================

    final fillPaint = Paint()
      ..color = isDark
          ? Colors.blue.shade900.withOpacity(0.45)
          : Colors.blue.shade100.withOpacity(0.45);

    canvas.save();

    // =====================================================
    // CLIP WATER INSIDE TUBE
    // =====================================================

    canvas.clipPath(
      Path()
        ..moveTo(left, top)
        ..lineTo(left, bottom - cornerRadius)
        ..quadraticBezierTo(left, bottom, left + cornerRadius, bottom)
        ..lineTo(right - cornerRadius, bottom)
        ..quadraticBezierTo(right, bottom, right, bottom - cornerRadius)
        ..lineTo(right, top)
        ..close(),
    );

    // =====================================================
    // WATER BODY
    // =====================================================

    final waterPath = Path();

    // In straight (lite) mode the wave height is 0, so the
    // water surface is a flat horizontal line.
    final double waveHeight = straight ? 0.0 : 3.5;
    final double waveLength = tubeWidth;

    // Wave offset at a given x position.
    double waveAt(double x) {
      final double normalizedX = (x - left) / waveLength;

      return math.sin(normalizedX * math.pi * 2 * 1.5 + wavePhase) * waveHeight;
    }

    waterPath.moveTo(left, fillTop);

    for (double x = left; x <= right; x += step) {
      waterPath.lineTo(x, fillTop + waveAt(x));
    }

    // With a larger step the loop may stop a little before the
    // right edge, so the last point is added explicitly.
    if (step > 2.0) {
      waterPath.lineTo(right, fillTop + waveAt(right));
    }

    waterPath
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();

    canvas.drawPath(waterPath, fillPaint);

    // =====================================================
    // WATER HIGHLIGHT
    // =====================================================

    final highlightPaint = Paint()
      ..color = Colors.blue.shade400.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final highlightPath = Path();

    for (double x = left; x <= right; x += step) {
      if (x == left) {
        highlightPath.moveTo(x, fillTop + waveAt(x));
      } else {
        highlightPath.lineTo(x, fillTop + waveAt(x));
      }
    }

    if (step > 2.0) {
      highlightPath.lineTo(right, fillTop + waveAt(right));
    }

    canvas.drawPath(highlightPath, highlightPaint);

    canvas.restore();

    // =====================================================
    // TUBE OUTLINE
    // =====================================================

    canvas.drawPath(tubePath, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _WaterBucketPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.maxLevel != maxLevel ||
      oldDelegate.isDark != isDark ||
      oldDelegate.wavePhase != wavePhase ||
      oldDelegate.straight != straight ||
      oldDelegate.step != step;
}

// =====================================================
// HUMIDITY GAUGE PAINTER
// =====================================================

class _HumidityGaugePainter extends CustomPainter {
  final double percent;
  final bool isDark;

  _HumidityGaugePainter({required this.percent, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = 14;

    final Rect rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.width - strokeWidth,
    );

    final bgPaint = Paint()
      ..color = isDark
          ? Colors.blue.shade900.withOpacity(0.5)
          : Colors.blue.shade100
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = Colors.blue.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, math.pi, math.pi, false, bgPaint);

    canvas.drawArc(rect, math.pi, math.pi * percent, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _HumidityGaugePainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.isDark != isDark;
}
