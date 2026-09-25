import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';

// =====================================================
// GLASSMORPHISM CARD HELPER
// =====================================================
//
// Reusable frosted-glass container used across the new
// dashboard UI. Semi-transparent background, subtle light
// border, soft drop shadow, and an optional colored glow
// border (used for the flood-risk card).

Widget _glassCard({
  required Widget child,
  Color? glowColor,
  EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  BorderRadius? borderRadius,
}) {
  final BorderRadius radius =
      borderRadius ?? BorderRadius.circular(18);

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

class _HomeTabState extends State<HomeTab>
    with SingleTickerProviderStateMixin {
      String _selectedBarangay = 'Uwisan';
      Timer? _manilaTimeTimer;
      DateTime _manilaTime = DateTime.now().toUtc().add(const Duration(hours: 8));

  // =====================================================
  // WATER SETTINGS
  // =====================================================

  // Maximum water level is 200 cm.
  // The value displayed to the user remains in centimeters.
  static const double maxWaterLevel = 200.0;

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

  static const String mlApiUrl =
      'http://192.168.18.14:8000/predict';

  double? _mlRainfall1h;
  double? _mlRainfall3h;
  double? _mlRainfall6h;
  double? _mlRainfall12h;
  double? _mlRainfall24h;

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
  Timer? _weatherConditionTimer;

  // =====================================================
  // INIT STATE
  // =====================================================

  @override
  void initState() {
    super.initState();

    // Continuous water-wave animation.
    _waterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    // =====================================================
    // MANILA TIME
    // =====================================================

    _manilaTimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;

        setState(() {
          _manilaTime =
              DateTime.now().toUtc().add(const Duration(hours: 8));
        });
      },
    );

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

    _weatherConditionTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _fetchWeatherCondition(),
    );
  }

  @override
  void dispose() {
    _mlPredictionTimer?.cancel();
    _esp32StatusTimer?.cancel();
    _manilaTimeTimer?.cancel();
    _weatherConditionTimer?.cancel();
    _waterAnimationController.dispose();
    super.dispose();
  }

  // =====================================================
  // CHECK ESP32 CONNECTION
  // =====================================================

  void _checkEsp32Connection() {
    if (!mounted) return;

    bool newOnlineStatus = false;

    if (_latestEsp32Timestamp != null) {
      final int now =
          DateTime.now().millisecondsSinceEpoch;

      final int age =
          now - _latestEsp32Timestamp!;

      newOnlineStatus =
          age >= 0 &&
          age <=
              const Duration(
                seconds: esp32TimeoutSeconds,
              ).inMilliseconds;
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
    } else {
      // IMPORTANT:
      // Force the StreamBuilder UI to rebuild even when
      // Firebase itself is no longer sending events.
      //
      // This is what allows the old/stale ESP32 reading
      // to stop being displayed after 30 seconds.
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

    return double.tryParse(
      value?.toString() ?? '',
    );
  }

  // =====================================================
  // ML PREDICTION
  // =====================================================

  Future<void> _fetchMLPrediction() async {
    if (_mlLoading) return;

    if (mounted) {
      setState(() {
        _mlLoading = true;
        _mlError = null;
      });
    }

    try {
      final response = await http
          .post(
            Uri.parse(mlApiUrl),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'latitude': 14.15,
              'longitude': 121.05,
            }),
          )
          .timeout(
        const Duration(seconds: 20),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'ML API returned HTTP ${response.statusCode}',
        );
      }

      final Map<String, dynamic> result =
          jsonDecode(response.body);

      // =================================================
      // CHECK IF ML IS IDLE
      // =================================================

      final String mlStatus =
          result['status']?.toString().toLowerCase() ?? '';

      if (mlStatus == 'idle') {
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

      final dynamic rawPredictions =
          result['predictions'];

      if (rawPredictions is! Map) {
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

      final Map<String, dynamic> predictions =
          Map<String, dynamic>.from(
        rawPredictions,
      );

      final double? rainfall1h =
          _parseDouble(
        predictions['rainfall_1h_mm'],
      );

      final double? rainfall3h =
          _parseDouble(
        predictions['rainfall_3h_mm'],
      );

      final double? rainfall6h =
          _parseDouble(
        predictions['rainfall_6h_mm'],
      );

      final double? rainfall12h =
          _parseDouble(
        predictions['rainfall_12h_mm'],
      );

      final double? rainfall24h =
          _parseDouble(
        predictions['rainfall_24h_mm'],
      );

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

      setState(() {
        _mlRainfall1h = rainfall1h;
        _mlRainfall3h = rainfall3h;
        _mlRainfall6h = rainfall6h;
        _mlRainfall12h = rainfall12h;
        _mlRainfall24h = rainfall24h;

        _mlError = null;
        _mlForecastIdle = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _mlError =
            'Unable to connect to ML server';

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
      if (!mounted) return;

      setState(() {
        _mlLoading = false;
      });
    }
  }

  // =====================================================
  // OPEN-METEO FALLBACK WEATHER
  // =====================================================

  Future<void> _fetchFallbackWeather() async {
    if (_fallbackWeatherLoading) return;

    if (mounted) {
      setState(() {
        _fallbackWeatherLoading = true;
        _fallbackWeatherError = null;
      });
    }

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=14.15'
        '&longitude=121.05'
        '&current=temperature_2m,relative_humidity_2m,rain,precipitation,precipitation_probability'
        '&hourly=precipitation,rain,precipitation_probability'
        '&forecast_hours=24'
        '&timezone=Asia%2FManila',
      );

      final response = await http
          .get(uri)
          .timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Open-Meteo returned HTTP ${response.statusCode}',
        );
      }

      final Map<String, dynamic> result =
          jsonDecode(response.body);

      final Map<String, dynamic>? current =
          result['current'] is Map
              ? Map<String, dynamic>.from(
                  result['current'] as Map,
                )
              : null;

      if (current == null) {
        throw Exception(
          'Open-Meteo current weather data missing',
        );
      }

      final dynamic temperatureRaw =
          current['temperature_2m'];

      final dynamic humidityRaw =
          current['relative_humidity_2m'];

      final double? temperature =
          _parseDouble(temperatureRaw);

      final double? humidity =
          _parseDouble(humidityRaw);

      if (temperature == null || humidity == null) {
        throw Exception(
          'Invalid Open-Meteo weather values',
        );
      }

      // =================================================
      // ALSO READ RAINFALL DATA
      // =================================================

      final double? currentRain =
          _parseDouble(current['rain']);

      final double? currentPrecipitation =
          _parseDouble(current['precipitation']);

      final double? currentProbability =
          _parseDouble(
        current['precipitation_probability'],
      );

      final Map<String, dynamic>? hourly =
          result['hourly'] is Map
              ? Map<String, dynamic>.from(
                  result['hourly'] as Map,
                )
              : null;

      double rainfall1h = 0;
      double rainfall3h = 0;
      double rainfall6h = 0;
      double rainfall12h = 0;
      double rainfall24h = 0;

      double probability1h = 0;
      double probability3h = 0;
      double probability6h = 0;
      double probability12h = 0;
      double probability24h = 0;

      if (hourly != null) {
        final List<dynamic> precipitationValues =
            hourly['precipitation'] is List
                ? hourly['precipitation'] as List
                : [];

        final List<dynamic> probabilityValues =
            hourly['precipitation_probability'] is List
                ? hourly['precipitation_probability'] as List
                : [];

        double sumRainfall(int count) {
          final int limit =
              math.min(
            count,
            precipitationValues.length,
          );

          double total = 0;

          for (int i = 0; i < limit; i++) {
            total +=
                _parseDouble(
                      precipitationValues[i],
                    ) ??
                    0;
          }

          return total;
        }

        double averageProbability(int count) {
          final int limit =
              math.min(
            count,
            probabilityValues.length,
          );

          if (limit == 0) {
            return 0;
          }

          double total = 0;

          for (int i = 0; i < limit; i++) {
            total +=
                _parseDouble(
                      probabilityValues[i],
                    ) ??
                    0;
          }

          return total / limit;
        }

        rainfall1h = sumRainfall(1);
        rainfall3h = sumRainfall(3);
        rainfall6h = sumRainfall(6);
        rainfall12h = sumRainfall(12);
        rainfall24h = sumRainfall(24);

        probability1h =
            averageProbability(1);

        probability3h =
            averageProbability(3);

        probability6h =
            averageProbability(6);

        probability12h =
            averageProbability(12);

        probability24h =
            averageProbability(24);
      }

      if (!mounted) return;

      setState(() {
        _fallbackTemperature = temperature;
        _fallbackHumidity = humidity;

        _fallbackWeatherError = null;

        // =================================================
        // OPEN-METEO RAINFALL DATA
        // =================================================

        _openMeteoCurrentRainfall =
            currentRain ??
                currentPrecipitation;

        _openMeteoRainfall1h =
            rainfall1h;

        _openMeteoRainfall3h =
            rainfall3h;

        _openMeteoRainfall6h =
            rainfall6h;

        _openMeteoRainfall12h =
            rainfall12h;

        _openMeteoRainfall24h =
            rainfall24h;

        _openMeteoRainProbability =
            currentProbability ??
                probability1h;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _fallbackWeatherError =
            'Unable to load Open-Meteo weather';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _fallbackWeatherLoading = false;
      });
    }
  }

  // =====================================================
  // OPEN-METEO RAINFALL FALLBACK
  // =====================================================

  Future<void> _fetchOpenMeteoRainfall() async {
    if (_openMeteoRainLoading) return;

    if (mounted) {
      setState(() {
        _openMeteoRainLoading = true;
        _openMeteoRainError = null;
      });
    }

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=14.15'
        '&longitude=121.05'
        '&current=rain,precipitation,precipitation_probability'
        '&hourly=precipitation,rain,precipitation_probability'
        '&forecast_hours=24'
        '&timezone=Asia%2FManila',
      );

      final response = await http
          .get(uri)
          .timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Open-Meteo returned HTTP ${response.statusCode}',
        );
      }

      final Map<String, dynamic> result =
          jsonDecode(response.body);

      final Map<String, dynamic>? current =
          result['current'] is Map
              ? Map<String, dynamic>.from(
                  result['current'] as Map,
                )
              : null;

      if (current == null) {
        throw Exception(
          'Open-Meteo current rainfall data missing',
        );
      }

      final double? currentRain =
          _parseDouble(current['rain']);

      final double? currentPrecipitation =
          _parseDouble(current['precipitation']);

      final double? currentProbability =
          _parseDouble(
        current['precipitation_probability'],
      );

      final Map<String, dynamic>? hourly =
          result['hourly'] is Map
              ? Map<String, dynamic>.from(
                  result['hourly'] as Map,
                )
              : null;

      double rainfall1h = 0;
      double rainfall3h = 0;
      double rainfall6h = 0;
      double rainfall12h = 0;
      double rainfall24h = 0;

      double probability1h = 0;

      if (hourly != null) {
        final List<dynamic> precipitationValues =
            hourly['precipitation'] is List
                ? hourly['precipitation'] as List
                : [];

        final List<dynamic> probabilityValues =
            hourly['precipitation_probability'] is List
                ? hourly['precipitation_probability'] as List
                : [];

        double sumRainfall(int count) {
          final int limit =
              math.min(
            count,
            precipitationValues.length,
          );

          double total = 0;

          for (int i = 0; i < limit; i++) {
            total +=
                _parseDouble(
                      precipitationValues[i],
                    ) ??
                    0;
          }

          return total;
        }

        double averageProbability(int count) {
          final int limit =
              math.min(
            count,
            probabilityValues.length,
          );

          if (limit == 0) {
            return 0;
          }

          double total = 0;

          for (int i = 0; i < limit; i++) {
            total +=
                _parseDouble(
                      probabilityValues[i],
                    ) ??
                    0;
          }

          return total / limit;
        }

        rainfall1h = sumRainfall(1);
        rainfall3h = sumRainfall(3);
        rainfall6h = sumRainfall(6);
        rainfall12h = sumRainfall(12);
        rainfall24h = sumRainfall(24);

        probability1h =
            averageProbability(1);
      }

      if (!mounted) return;

      setState(() {
        _openMeteoCurrentRainfall =
            currentRain ??
                currentPrecipitation;

        _openMeteoRainfall1h =
            rainfall1h;

        _openMeteoRainfall3h =
            rainfall3h;

        _openMeteoRainfall6h =
            rainfall6h;

        _openMeteoRainfall12h =
            rainfall12h;

        _openMeteoRainfall24h =
            rainfall24h;

        _openMeteoRainProbability =
            currentProbability ??
                probability1h;

        _openMeteoRainError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _openMeteoRainError =
            'Unable to load Open-Meteo rainfall';
      });
    } finally {
      if (!mounted) return;

      setState(() {
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
  // This is a small, separate Open-Meteo call used only to
  // decide which background animation to show. It does not
  // touch or duplicate the flood/rainfall logic above; it
  // only reads weather_code and cloud_cover, which none of
  // the existing calls request.

  Future<void> _fetchWeatherCondition() async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=14.15'
        '&longitude=121.05'
        '&current=weather_code,cloud_cover'
        '&timezone=Asia%2FManila',
      );

      final response = await http
          .get(uri)
          .timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        return;
      }

      final Map<String, dynamic> result =
          jsonDecode(response.body);

      final Map<String, dynamic>? current =
          result['current'] is Map
              ? Map<String, dynamic>.from(
                  result['current'] as Map,
                )
              : null;

      if (current == null) {
        return;
      }

      final double? weatherCodeValue =
          _parseDouble(current['weather_code']);

      final double? cloudCoverValue =
          _parseDouble(current['cloud_cover']);

      if (!mounted) return;

      setState(() {
        if (weatherCodeValue != null) {
          _weatherCode = weatherCodeValue.round();
        }

        if (cloudCoverValue != null) {
          _cloudCover = cloudCoverValue;
        }
      });
    } catch (e) {
      // Silently ignored: the background simply falls back
      // to whatever rainfall data is already available.
    }
  }

  // =====================================================
  // COMPUTE BACKGROUND WEATHER MODE
  // =====================================================
  //
  // Combines the weather_code/cloud_cover fetched above with
  // the rainfall figures already tracked elsewhere in this
  // file (ML prediction or Open-Meteo fallback) to decide
  // which background animation to show.

  _WeatherBackgroundMode _computeWeatherMode() {
    final int? code = _weatherCode;

    final bool isThunderCode =
        code != null && code >= 95 && code <= 99;

    final bool isRainCode = code != null &&
        ((code >= 51 && code <= 67) ||
            (code >= 80 && code <= 82));

    final bool isCloudyCode =
        code != null && code >= 1 && code <= 3;

    final double? rain1h =
        (!_mlForecastIdle && _mlError == null)
            ? _mlRainfall1h
            : _openMeteoRainfall1h;

    final double currentRain =
        _openMeteoCurrentRainfall ?? 0;

    final double hourlyRain = rain1h ?? 0;

    final bool heavyByAmount =
        hourlyRain >= 4.0 || currentRain >= 2.0;

    final bool lightByAmount =
        hourlyRain > 0 || currentRain > 0;

    if (isThunderCode || heavyByAmount) {
      return _WeatherBackgroundMode.storm;
    }

    if (isRainCode || lightByAmount) {
      return _WeatherBackgroundMode.rain;
    }

    if (isCloudyCode || (_cloudCover ?? 0) > 50) {
      return _WeatherBackgroundMode.cloudy;
    }

    return _WeatherBackgroundMode.sunny;
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
      timestamp = double.tryParse(
        timestampRaw.toString(),
      );
    }

    if (timestamp == null || !timestamp.isFinite) {
      return false;
    }

    // Firebase server timestamps are milliseconds.
    // This also safely handles seconds if they are ever used.
    if (timestamp < 100000000000) {
      timestamp *= 1000;
    }

    final int now =
        DateTime.now().millisecondsSinceEpoch;

    final int timestampMilliseconds =
        timestamp.round();

    final int age =
        now - timestampMilliseconds;

    // Future timestamps are also treated as valid within
    // the timeout range to tolerate a small clock difference.
    return age <=
        const Duration(
          seconds: esp32TimeoutSeconds,
        ).inMilliseconds;
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final dbRef = FirebaseDatabase.instance.ref();

    // Dark mode is now the permanent, fixed UI for this app.
    const bool isDarkMode = true;

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
      color: isDarkMode
          ? const Color(0xFF212121)
          : Colors.white,
      child: Scaffold(
        backgroundColor: isDarkMode
            ? const Color(0xFF212121)
            : Colors.white,
        // =====================================================
        // RAIN BACKGROUND (BEHIND EVERYTHING) + PAGE CONTENT
        // =====================================================
        body: Stack(
          fit: StackFit.expand,
          children: [

            // Weather-based background.
            // IgnorePointer keeps all taps and double-taps working.
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: _RainBackground(
                    mode: _computeWeatherMode(),
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
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              );
            }

            // =====================================================
            // SENSOR DATA
            // =====================================================

            Map<String, dynamic> data = {};

            double waterLevel =
                idleWaterLevel;

            bool sensorActive = false;

            bool esp32Online = _esp32Online;

            if (snapshot.hasData &&
                snapshot.data!.snapshot.value != null) {
              final rawValue =
                  snapshot.data!.snapshot.value;

              if (rawValue is Map) {
                final rawData =
                    rawValue as Map<dynamic, dynamic>;

                data = rawData.map(
                  (key, value) =>
                      MapEntry(
                    key.toString(),
                    value,
                  ),
                );

                // =================================================
                // ESP32 TIMESTAMP
                // =================================================

                final dynamic timestampRaw =
                    data['timestamp'];

                // Store the latest Firebase timestamp.
                //
                // This value will continue to be checked by
                // _esp32StatusTimer even after the ESP32 stops
                // sending Firebase updates.
                double? parsedTimestamp;

                if (timestampRaw is num) {
                  parsedTimestamp =
                      timestampRaw.toDouble();
                } else {
                  parsedTimestamp =
                      double.tryParse(
                    timestampRaw?.toString() ?? '',
                  );
                }

                if (parsedTimestamp != null &&
                    parsedTimestamp.isFinite) {
                  if (parsedTimestamp <
                      100000000000) {
                    parsedTimestamp *= 1000;
                  }

                  _latestEsp32Timestamp =
                      parsedTimestamp.round();

                  _hasReceivedFirebaseData = true;
                }

                // Use the timestamp immediately for the current
                // Firebase rebuild.
                esp32Online =
                    _isEsp32TimestampRecent(
                  timestampRaw,
                );

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
              final dynamic distanceRaw =
                  data['distance'];

              if (distanceRaw != null) {
                final double? parsedDistance =
                    distanceRaw is num
                        ? distanceRaw.toDouble()
                        : double.tryParse(
                            distanceRaw.toString(),
                          );

                if (parsedDistance != null &&
                    parsedDistance.isFinite) {
                  if (parsedDistance >=
                      maxWaterLevel) {
                    sensorActive = false;
                    waterLevel =
                        idleWaterLevel;
                  } else if (parsedDistance >= 0) {
                    sensorActive = true;

                    waterLevel =
                        parsedDistance
                            .clamp(
                              0.0,
                              maxWaterLevel,
                            )
                            .toDouble();
                  } else {
                    // Keep the ESP32 online but do not
                    // treat an ultrasonic out-of-range
                    // reading as a real water level.
                    sensorActive = false;
                    waterLevel =
                        idleWaterLevel;
                  }
                }
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
              waterLevel =
                  idleWaterLevel;
            }

            // =====================================================
            // TEMPERATURE
            // =====================================================

            final dynamic temperatureRaw =
                data['temperature'];

            final double? sensorTemperature =
                temperatureRaw is num
                    ? temperatureRaw.toDouble()
                    : double.tryParse(
                        temperatureRaw
                                ?.toString() ??
                            '',
                      );

            final double? displayedTemperature =
                esp32Online
                    ? sensorTemperature
                    : _fallbackTemperature;

            // =====================================================
            // HUMIDITY
            // =====================================================

            final dynamic humidityRaw =
                data['humidity'];

            final double? sensorHumidity =
                humidityRaw is num
                    ? humidityRaw.toDouble()
                    : double.tryParse(
                        humidityRaw?.toString() ??
                            '',
                      );

            final double humidity =
                (esp32Online
                        ? sensorHumidity
                        : _fallbackHumidity) ??
                    0;

            // =====================================================
            // SCREEN / HEADER
            // =====================================================

            final double screenHeight =
                MediaQuery.of(context).size.height;

            final double topHeight =
                screenHeight * 0.32;

            // =====================================================
            // WATER ANIMATION
            // =====================================================

            final double animationStart =
                _previousWaterLevel;

            final double animationEnd =
                waterLevel;

            _previousWaterLevel =
                waterLevel;

            // =====================================================
            // FLOOD RISK STATUS (dynamic — unchanged logic)
            // =====================================================

            final Color floodColor = !sensorActive
                ? Colors.grey.shade500
                : waterLevel > 50
                    ? Colors.red.shade400
                    : waterLevel > 30
                        ? Colors.orange.shade400
                        : Colors.green.shade400;

            final String floodStatusText = !sensorActive
                ? 'IDLE'
                : waterLevel > 50
                    ? 'FLOODING'
                    : waterLevel > 30
                        ? 'MEDIUM RISK'
                        : 'SAFE';

            final String floodMessage = !sensorActive
                ? 'Waiting for sensor data'
                : waterLevel > 50
                    ? 'High water levels detected'
                    : waterLevel > 30
                        ? 'Monitor conditions closely'
                        : 'Conditions are normal';

            // =====================================================
            // FIXED PAGE - NO SCROLLING
            // =====================================================

            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
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
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
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
                                ),
                              ),

                              const SizedBox(
                                width: 8,
                              ),

                              const Text(
                                'DETECT-CO',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight:
                                      FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),

                              const Spacer(),
                            ],
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          // =====================================
                          // GREETING
                          // =====================================

                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [

                              const Expanded(
                                child: Text(
                                  'Hello!',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight:
                                        FontWeight.w500,
                                    color:
                                        Colors.white,
                                  ),
                                ),
                              ),

                              Text(
                                'Last Synced',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white
                                      .withOpacity(
                                    0.85,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 4,
                          ),

                          // =====================================
                          // LOCATION / TIME
                          // =====================================

                          Row(
                            children: [

                              const Icon(
                                Icons.location_on,
                                color:
                                    Colors.white70,
                                size: 16,
                              ),

                              const SizedBox(
                                width: 4,
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.025),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.12),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.22),
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedBarangay,
                                    isDense: true,
                                    borderRadius: BorderRadius.circular(16),
                                    dropdownColor: const Color(0xFF303030),
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Uwisan',
                                        child: Text('Barangay Uwisan'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Palingon',
                                        child: Text('Barangay Palingon'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Lingga',
                                        child: Text('Barangay Lingga'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;

                                      setState(() {
                                        _selectedBarangay = value;
                                      });
                                    },
                                  ),
                                ),
                              ),

                              const Spacer(),

                              Text(
                                '${((_manilaTime.hour % 12) == 0 ? 12 : (_manilaTime.hour % 12)).toString().padLeft(2, '0')}:${_manilaTime.minute.toString().padLeft(2, '0')}:${_manilaTime.second.toString().padLeft(2, '0')} ${_manilaTime.hour >= 12 ? 'PM' : 'AM'}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
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

                Expanded(
                  child: Transform.translate(
                    offset:
                        const Offset(0, -28),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [

                          // =========================================
                          // TOP ROW: TEMPERATURE + HUMIDITY
                          // =========================================

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
                                              (esp32Online ||
                                                      _fallbackHumidity != null)
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
                          // FLOOD RISK STATUS
                          // =========================================

                          _glassCard(
                            glowColor: floodColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color:
                                              floodColor.withOpacity(0.18),
                                          border: Border.all(
                                            color:
                                                floodColor.withOpacity(0.6),
                                            width: 1.4,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.shield_outlined,
                                        color: floodColor,
                                        size: 28,
                                      ),
                                      Positioned(
                                        bottom: 8,
                                        right: 8,
                                        child: Icon(
                                          Icons.check_circle,
                                          color: floodColor,
                                          size: 16,
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
                                          fontSize: 20,
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
                          // WATER LEVEL
                          // =========================================

                          Expanded(
                            child: _glassCard(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Water Level',
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
                                        final double tubeCanvasWidth =
                                            math.min(
                                          180,
                                          constraints.maxWidth * 0.62,
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
                                                      double>(
                                                    tween: Tween<double>(
                                                      begin: animationStart,
                                                      end: animationEnd,
                                                    ),
                                                    duration: const Duration(
                                                      milliseconds: 800,
                                                    ),
                                                    curve: Curves.easeInOut,
                                                    builder: (
                                                      context,
                                                      animatedLevel,
                                                      child,
                                                    ) {
                                                      return Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 12,
                                                          vertical: 4,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(
                                                            0.10,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
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
                                                              ? '${animatedLevel.toStringAsFixed(1)} cm'
                                                              : 'IDLE',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold,
                                                            color:
                                                                Colors.white,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),

                                                  const SizedBox(height: 4),

                                                  Expanded(
                                                    child: Center(
                                                      child: _WaterWithDuck(
                                                        width:
                                                            tubeCanvasWidth,
                                                        height:
                                                            constraints
                                                                    .maxHeight -
                                                                40,
                                                        animation:
                                                            _waterAnimationController,
                                                        animationStart:
                                                            animationStart,
                                                        animationEnd:
                                                            animationEnd,
                                                        maxWaterLevel:
                                                            maxWaterLevel,
                                                        isDark: isDarkMode,
                                                      ),
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
                                                      constraints.maxHeight -
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
                                                        '200 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .red.shade400,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '180 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .red.shade400,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '160 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .red.shade400,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '140 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .orange
                                                              .shade700,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '120 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .orange
                                                              .shade700,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '100 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .orange
                                                              .shade700,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '80 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .orange
                                                              .shade300,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '60 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .orange
                                                              .shade300,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '40 cm',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .orange
                                                              .shade300,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '20 cm',
                                                        style: TextStyle(
                                                          color: Colors.green
                                                              .shade600,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                      Text(
                                                        '0 cm',
                                                        style: TextStyle(
                                                          color: Colors.green
                                                              .shade600,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 10,
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

                          _glassCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
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
                                      size: 24,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _mlForecastIdle ||
                                                _mlError != null
                                            ? 'RAINFALL FORECAST'
                                            : 'ML RAINFALL FORECAST',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.0,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    if (_mlLoading &&
                                        !_mlForecastIdle &&
                                        _mlError == null)
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    else if (_openMeteoRainLoading)
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                  ),
                                  child: Column(
                                    children: [

                                      // MAIN RAINFALL VALUE
                                      if (!_mlForecastIdle &&
                                          _mlError == null &&
                                          _mlRainfall24h != null)
                                        Text(
                                          '24h: ${_mlRainfall24h!.toStringAsFixed(2)} mm',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight:
                                                FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      else if (_openMeteoRainfall24h !=
                                          null)
                                        Text(
                                          '24h: ${_openMeteoRainfall24h!.toStringAsFixed(2)} mm',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight:
                                                FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      else
                                        const Text(
                                          '--',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight:
                                                FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),

                                      const SizedBox(height: 4),

                                      // 1 HOUR RAINFALL
                                      if (!_mlForecastIdle &&
                                          _mlError == null &&
                                          _mlRainfall1h != null)
                                        Text(
                                          '1h: ${_mlRainfall1h!.toStringAsFixed(2)} mm',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[300],
                                          ),
                                        )
                                      else if (_openMeteoRainfall1h !=
                                          null)
                                        Text(
                                          '1h: ${_openMeteoRainfall1h!.toStringAsFixed(2)} mm',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[300],
                                          ),
                                        ),

                                      // CURRENT RAIN
                                      if ((_mlForecastIdle ||
                                              _mlError != null) &&
                                          _openMeteoCurrentRainfall !=
                                              null)
                                        Text(
                                          'Current rain: '
                                          '${_openMeteoCurrentRainfall!.toStringAsFixed(2)} mm',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[300],
                                          ),
                                        ),

                                      // RAIN PROBABILITY
                                      if ((_mlForecastIdle ||
                                              _mlError != null) &&
                                          _openMeteoRainProbability !=
                                              null)
                                        Text(
                                          'Rain probability: '
                                          '${_openMeteoRainProbability!.toStringAsFixed(0)}%',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[300],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
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
          ],
        ),
      ),
      ),
    );
  }
}

// =====================================================
// BACKGROUND WEATHER MODE
// =====================================================

enum _WeatherBackgroundMode {
  sunny,
  cloudy,
  rain,
  storm,
}

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

  const _RainBackground({
    required this.mode,
  });

  @override
  State<_RainBackground> createState() =>
      _RainBackgroundState();
}

class _RainBackgroundState
    extends State<_RainBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_RainDrop> _drops;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isStorm =
        widget.mode == _WeatherBackgroundMode.storm;

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
                  painter: _SunnyPainter(
                    progress: _controller.value,
                  ),
                );

              case _WeatherBackgroundMode.cloudy:
                return CustomPaint(
                  size: Size.infinite,
                  painter: _CloudyPainter(
                    progress: _controller.value,
                  ),
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
        ? const [
            Color(0xFF0E1218),
            Color(0xFF161C24),
            Color(0xFF212121),
          ]
        : const [
            Color(0xFF4877F7),
            Color(0xFFA9C4FB),
            Color(0xFFE8F0FE),
          ];

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
      ..maskFilter =
          const MaskFilter.blur(BlurStyle.normal, 32)
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
      final double drift =
          math.sin(progress * math.pi * 2 + i) * 12;

      canvas.drawCircle(
        Offset(
          clouds[i][0] * size.width + drift,
          clouds[i][1] * size.height,
        ),
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
          ((d.phase + progress * d.speed * speedMultiplier) %
                      1.0) *
                  travel -
              d.length;

      final double x = d.x * size.width;

      // 0 in the center, 1 at the very edges.
      final double edgeDistance =
          ((d.x - 0.5).abs() * 2).clamp(0.0, 1.0);

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
  bool shouldRepaint(
    covariant _RainPainter oldDelegate,
  ) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.speedMultiplier != speedMultiplier ||
      oldDelegate.alphaMultiplier != alphaMultiplier;
}

// =====================================================
// SUNNY BACKGROUND
// =====================================================
//
// A subtle warm glow with slow, faint light rays. Kept low-key
// so it still reads as the app's dark theme rather than a bright
// daytime sky.

class _SunnyPainter extends CustomPainter {
  final double progress;

  _SunnyPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    const List<Color> colors = [
      Color(0xFF0E1218),
      Color(0xFF161C24),
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

    final Offset sunCenter = Offset(
      size.width * 0.78,
      size.height * 0.16,
    );

    // Slow, gentle pulse.
    final double pulse =
        0.9 + math.sin(progress * math.pi * 2) * 0.1;

    final double glowRadius =
        size.width * 0.32 * pulse;

    final Paint glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD98A).withOpacity(0.35),
          const Color(0xFFFFD98A).withOpacity(0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: sunCenter,
          radius: glowRadius,
        ),
      );

    canvas.drawCircle(sunCenter, glowRadius, glowPaint);

    final Paint corePaint = Paint()
      ..color = const Color(0xFFFFE7B3).withOpacity(0.55);

    canvas.drawCircle(
      sunCenter,
      size.width * 0.06,
      corePaint,
    );

    // Subtle, very slow-rotating light rays.
    final Paint rayPaint = Paint()
      ..color = const Color(0xFFFFE7B3).withOpacity(0.06)
      ..strokeWidth = 2;

    final double rotation =
        progress * math.pi * 2 * 0.1;

    for (int i = 0; i < 8; i++) {
      final double angle =
          rotation + (i * math.pi / 4);

      final Offset rayEnd = Offset(
        sunCenter.dx +
            math.cos(angle) * size.width * 0.5,
        sunCenter.dy +
            math.sin(angle) * size.width * 0.5,
      );

      canvas.drawLine(sunCenter, rayEnd, rayPaint);
    }
  }

  @override
  bool shouldRepaint(
    covariant _SunnyPainter oldDelegate,
  ) =>
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
      ..maskFilter =
          const MaskFilter.blur(BlurStyle.normal, 34)
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
          (clouds[i][0] * size.width + drift) %
                  (size.width * 1.3) -
              size.width * 0.15;

      canvas.drawCircle(
        Offset(x, clouds[i][1] * size.height),
        clouds[i][2] * size.width,
        cloudPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _CloudyPainter oldDelegate,
  ) =>
      oldDelegate.progress != progress;
}

// =====================================================
// LIGHTNING OVERLAY (STORM MODE)
// =====================================================
//
// Occasional, natural-looking lightning flashes: a brief
// whole-screen brightening plus a jagged bolt, on a random
// timer while storm mode is active.

class _LightningOverlay extends StatefulWidget {
  final bool enabled;

  const _LightningOverlay({required this.enabled});

  @override
  State<_LightningOverlay> createState() =>
      _LightningOverlayState();
}

class _LightningOverlayState
    extends State<_LightningOverlay>
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
  void didUpdateWidget(
    covariant _LightningOverlay oldWidget,
  ) {
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

    _flashTimer = Timer(
      Duration(seconds: delaySeconds),
      () {
        if (!mounted || !widget.enabled) return;

        _boltX = 0.15 + _rnd.nextDouble() * 0.7;

        _flashController.forward(from: 0).then((_) {
          if (!mounted) return;
          _flashController.reverse();
        });

        _scheduleFlash();
      },
    );
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
          ),
        );
      },
    );
  }
}

class _LightningPainter extends CustomPainter {
  final double intensity;
  final double boltX;

  _LightningPainter({
    required this.intensity,
    required this.boltX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final Rect rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withOpacity(0.22 * intensity),
    );

    if (intensity > 0.3) {
      final Paint boltPaint = Paint()
        ..color = Colors.white.withOpacity(0.85 * intensity)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final double startX = boltX * size.width;

      final Path bolt = Path()..moveTo(startX, 0);

      final math.Random rnd =
          math.Random(boltX.hashCode);

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
  bool shouldRepaint(
    covariant _LightningPainter oldDelegate,
  ) =>
      oldDelegate.intensity != intensity ||
      oldDelegate.boltX != boltX;
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

  const _WaterWithDuck({
    required this.width,
    required this.height,
    required this.animation,
    required this.animationStart,
    required this.animationEnd,
    required this.maxWaterLevel,
    required this.isDark,
  });

  @override
  State<_WaterWithDuck> createState() =>
      _WaterWithDuckState();
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

  @override
  void initState() {
    super.initState();

    _duckController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    _scheduleDuck();
  }

  // =====================================================
  // RANDOM DUCK APPEARANCE
  // =====================================================

  void _scheduleDuck() {
    _duckTimer?.cancel();

    final int delaySeconds =
        8 + _random.nextInt(11);

    _duckTimer = Timer(
      Duration(seconds: delaySeconds),
      _startDuck,
    );
  }

  // =====================================================
  // START DUCK
  // =====================================================

  void _startDuck() {
    if (!mounted) return;

    setState(() {
      _showDuck = true;
    });

    _duckController.forward(from: 0).then(
      (_) {
        if (!mounted) return;

        setState(() {
          _showDuck = false;
        });

        _scheduleDuck();
      },
    );
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
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.animation,
        _duckController,
      ]),
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

              ClipPath(
                clipper: _TubeInteriorClipper(),
                child: _buildHuman(),
              ),

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
                    wavePhase:
                        widget.animation.value *
                            math.pi *
                            2,
                  ),
                ),
              ),

              // =================================================
              // DUCK
              // =================================================

              if (_showDuck)
                ClipPath(
                  clipper: _TubeInteriorClipper(),
                  child: _buildDuck(),
                ),

              // =================================================
              // BLUE TUBE OUTLINE
              // =================================================

              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _TubeOutlinePainter(),
                  ),
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

    final double tubeInteriorHeight =
        widget.height - 8;

    final double humanHeight =
        tubeInteriorHeight *
            (humanHeightCm /
                widget.maxWaterLevel);

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

    final double tubeWidth =
        widget.width * 0.9;

    final double left =
        (widget.width - tubeWidth) / 2;

    final double right =
        left + tubeWidth;

    const double top = 4;

    final double bottom =
        widget.height - 4;

    // =====================================================
    // DUCK MOVEMENT
    // =====================================================

    final double startX =
        right - duckWidth * 0.35;

    final double endX =
        left - duckWidth * 0.65;

    final double curvedProgress =
        Curves.easeInOut.transform(
      _duckController.value,
    );

    final double duckX =
        startX +
            (endX - startX) *
                curvedProgress;

    // =====================================================
    // CURRENT WATER LEVEL
    // =====================================================

    final double currentLevel =
        widget.animationStart +
            (widget.animationEnd -
                    widget.animationStart) *
                Curves.easeInOut.transform(
                  widget.animation.value,
                );

    final double percent =
        (currentLevel /
                widget.maxWaterLevel)
            .clamp(0, 1)
            .toDouble();

    // =====================================================
    // WATER LEVEL POSITION
    // =====================================================

    final double fillHeight =
        (bottom - top) * percent;

    final double fillTop =
        bottom - fillHeight;

    // =====================================================
    // DUCK CENTER
    // =====================================================

    final double duckCenterX =
        duckX + duckWidth / 2;

    // =====================================================
    // WAVE POSITION
    // =====================================================

    final double normalizedX =
        ((duckCenterX - left) /
                tubeWidth)
            .clamp(0.0, 1.0);

    const double waveHeight = 3.5;

    final double wave =
        math.sin(
              normalizedX *
                      math.pi *
                      2 *
                      1.5 +
                  widget.animation.value *
                      math.pi *
                      2,
            ) *
            waveHeight;

    // =====================================================
    // SLOW FLOATING / BOBBING
    // =====================================================

    final double bob =
        math.sin(
              _duckController.value *
                  math.pi *
                  2,
            ) *
            1.5;

    // =====================================================
    // DUCK VERTICAL POSITION
    // =====================================================

    final double duckY =
        fillTop +
            wave +
            bob -
            duckHeight +
            5;

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
    final double tubeWidth =
        size.width * 0.9;

    final double left =
        (size.width - tubeWidth) / 2;

    final double right =
        left + tubeWidth;

    const double top = 4;

    final double bottom =
        size.height - 4;

    const double cornerRadius = 14;

    return Path()
      ..moveTo(left, top)
      ..lineTo(
        left,
        bottom - cornerRadius,
      )
      ..quadraticBezierTo(
        left,
        bottom,
        left + cornerRadius,
        bottom,
      )
      ..lineTo(
        right - cornerRadius,
        bottom,
      )
      ..quadraticBezierTo(
        right,
        bottom,
        right,
        bottom - cornerRadius,
      )
      ..lineTo(
        right,
        top,
      )
      ..close();
  }

  @override
  bool shouldReclip(
    covariant _TubeInteriorClipper oldClipper,
  ) {
    return false;
  }
}

// =====================================================
// TUBE OUTLINE PAINTER
// =====================================================

class _TubeOutlinePainter extends CustomPainter {
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final double tubeWidth =
        size.width * 0.9;

    final double left =
        (size.width - tubeWidth) / 2;

    final double right =
        left + tubeWidth;

    const double top = 4;

    final double bottom =
        size.height - 4;

    const double cornerRadius = 14;

    final outlinePaint = Paint()
      ..color = Colors.blue.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final tubePath = Path()
      ..moveTo(left, top)
      ..lineTo(
        left,
        bottom - cornerRadius,
      )
      ..quadraticBezierTo(
        left,
        bottom,
        left + cornerRadius,
        bottom,
      )
      ..lineTo(
        right - cornerRadius,
        bottom,
      )
      ..quadraticBezierTo(
        right,
        bottom,
        right,
        bottom - cornerRadius,
      )
      ..lineTo(
        right,
        top,
      );

    canvas.drawPath(
      tubePath,
      outlinePaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _TubeOutlinePainter oldDelegate,
  ) {
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
      return isDark
          ? const Color(0xFF2C2C2C)
          : Colors.white;
    }

    final level = waterLevel!;

    if (level > 50) {
      return Colors.red.shade700;
    }

    if (level > 30) {
      return Colors.orange.shade700;
    }

    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 400),
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: _getCardColor(),
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.grey.shade800
              : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.25 : 0.08,
            ),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [

          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  FontWeight.w500,
              color: isDark
                  ? Colors.grey[300]
                  : Colors.grey,
            ),
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.baseline,
            textBaseline:
                TextBaseline.alphabetic,
            children: [

              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight:
                      FontWeight.bold,
                  color: isDark
                      ? Colors.white
                      : Colors.black,
                ),
              ),

              const SizedBox(width: 2),

              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.grey[300]
                      : Colors.grey,
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
    if (waterLevel > 50) {
      return 'Flooding!';
    }

    if (waterLevel > 30) {
      return 'Medium Risk';
    }

    return 'Safe';
  }

  Color get statusColor {
    if (waterLevel > 50) {
      return Colors.red;
    }

    if (waterLevel > 30) {
      return Colors.orange;
    }

    return const Color.fromRGBO(
      76,
      175,
      80,
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 400),
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2C)
            : statusColor,
        borderRadius:
            BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [

          const Text(
            'Flood Risk Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  FontWeight.w500,
              color: Colors.white70,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            statusText,
            style: const TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.bold,
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

class _WaterBucketPainter
    extends CustomPainter {
  final double level;
  final double maxLevel;
  final bool isDark;
  final double wavePhase;

  _WaterBucketPainter({
    required this.level,
    required this.maxLevel,
    required this.isDark,
    required this.wavePhase,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final double tubeWidth =
        size.width * 0.9;

    final double left =
        (size.width - tubeWidth) / 2;

    final double right =
        left + tubeWidth;

    final double top = 4;

    final double bottom =
        size.height - 4;

    final double cornerRadius =
        14;

    // =====================================================
    // TUBE OUTLINE
    // =====================================================

    final outlinePaint = Paint()
      ..color = Colors.blue.shade600
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap =
          StrokeCap.round;

    final tubePath = Path()
      ..moveTo(left, top)
      ..lineTo(
        left,
        bottom - cornerRadius,
      )
      ..quadraticBezierTo(
        left,
        bottom,
        left + cornerRadius,
        bottom,
      )
      ..lineTo(
        right - cornerRadius,
        bottom,
      )
      ..quadraticBezierTo(
        right,
        bottom,
        right,
        bottom - cornerRadius,
      )
      ..lineTo(
        right,
        top,
      );

    // =====================================================
    // WATER LEVEL
    // =====================================================

    final double percent =
        (level / maxLevel)
            .clamp(0, 1)
            .toDouble();

    final double fillHeight =
        (bottom - top) * percent;

    final double fillTop =
        bottom - fillHeight;

    // =====================================================
    // SEMI-TRANSPARENT WATER
    // =====================================================

    final fillPaint = Paint()
      ..color = isDark
          ? Colors.blue.shade900
              .withOpacity(0.45)
          : Colors.blue.shade100
              .withOpacity(0.45);

    canvas.save();

    // =====================================================
    // CLIP WATER INSIDE TUBE
    // =====================================================

    canvas.clipPath(
      Path()
        ..moveTo(left, top)
        ..lineTo(
          left,
          bottom - cornerRadius,
        )
        ..quadraticBezierTo(
          left,
          bottom,
          left + cornerRadius,
          bottom,
        )
        ..lineTo(
          right - cornerRadius,
          bottom,
        )
        ..quadraticBezierTo(
          right,
          bottom,
          right,
          bottom - cornerRadius,
        )
        ..lineTo(
          right,
          top,
        )
        ..close(),
    );

    // =====================================================
    // WATER BODY
    // =====================================================

    final waterPath = Path();

    final double waveHeight = 3.5;
    final double waveLength = tubeWidth;

    waterPath.moveTo(
      left,
      fillTop,
    );

    for (
      double x = left;
      x <= right;
      x += 2
    ) {
      final double normalizedX =
          (x - left) / waveLength;

      final double wave =
          math.sin(
                normalizedX *
                        math.pi *
                        2 *
                        1.5 +
                    wavePhase,
              ) *
              waveHeight;

      waterPath.lineTo(
        x,
        fillTop + wave,
      );
    }

    waterPath
      ..lineTo(
        right,
        bottom,
      )
      ..lineTo(
        left,
        bottom,
      )
      ..close();

    canvas.drawPath(
      waterPath,
      fillPaint,
    );

    // =====================================================
    // WATER HIGHLIGHT
    // =====================================================

    final highlightPaint = Paint()
      ..color = Colors.blue.shade400
          .withOpacity(0.35)
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 2;

    final highlightPath = Path();

    for (
      double x = left;
      x <= right;
      x += 2
    ) {
      final double normalizedX =
          (x - left) / waveLength;

      final double wave =
          math.sin(
                normalizedX *
                        math.pi *
                        2 *
                        1.5 +
                    wavePhase,
              ) *
              waveHeight;

      if (x == left) {
        highlightPath.moveTo(
          x,
          fillTop + wave,
        );
      } else {
        highlightPath.lineTo(
          x,
          fillTop + wave,
        );
      }
    }

    canvas.drawPath(
      highlightPath,
      highlightPaint,
    );

    canvas.restore();

    // =====================================================
    // TUBE OUTLINE
    // =====================================================

    canvas.drawPath(
      tubePath,
      outlinePaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _WaterBucketPainter oldDelegate,
  ) =>
      oldDelegate.level != level ||
      oldDelegate.maxLevel != maxLevel ||
      oldDelegate.isDark != isDark ||
      oldDelegate.wavePhase != wavePhase;
}

// =====================================================
// HUMIDITY GAUGE PAINTER
// =====================================================

class _HumidityGaugePainter
    extends CustomPainter {
  final double percent;
  final bool isDark;

  _HumidityGaugePainter({
    required this.percent,
    required this.isDark,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final double strokeWidth = 14;

    final Rect rect =
        Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.width - strokeWidth,
    );

    final bgPaint = Paint()
      ..color = isDark
          ? Colors.blue.shade900
              .withOpacity(0.5)
          : Colors.blue.shade100
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap =
          StrokeCap.round;

    final fgPaint = Paint()
      ..color = Colors.blue.shade600
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap =
          StrokeCap.round;

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    canvas.drawArc(
      rect,
      math.pi,
      math.pi * percent,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _HumidityGaugePainter oldDelegate,
  ) =>
      oldDelegate.percent != percent ||
      oldDelegate.isDark != isDark;
}