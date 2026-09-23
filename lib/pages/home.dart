import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:detectco/main.dart'; // for isDarkModeNotifier

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
  // INIT STATE
  // =====================================================

  @override
  void initState() {
    super.initState();

    loadTheme();

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
  }

  @override
  void dispose() {
    _mlPredictionTimer?.cancel();
    _esp32StatusTimer?.cancel();
    _manilaTimeTimer?.cancel();
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
  // THEME
  // =====================================================

  void loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    isDarkModeNotifier.value =
        prefs.getBool('darkMode') ?? isDarkModeNotifier.value;
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();

    isDarkModeNotifier.value =
        !isDarkModeNotifier.value;

    await prefs.setBool(
      'darkMode',
      isDarkModeNotifier.value,
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final dbRef = FirebaseDatabase.instance.ref();

    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          color: isDarkMode
              ? const Color(0xFF212121)
              : Colors.white,
          child: Scaffold(
            backgroundColor: isDarkMode
                ? const Color(0xFF212121)
                : Colors.white,
            body: StreamBuilder<DatabaseEvent>(
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
                    screenHeight * 0.40;

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
                      color: isDarkMode
                          ? const Color(0xFF212121)
                          : const Color.fromARGB(
                              255,
                              72,
                              119,
                              247,
                            ),
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

                                  GestureDetector(
                                    onDoubleTap:
                                        toggleTheme,
                                    child: SizedBox(
                                      width: 50,
                                      height: 50,
                                      child: Image.asset(
                                        "assets/icon/detect-co_logo.png",
                                      ),
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
                                      color: isDarkMode
                                          ? const Color(0xFF303030)
                                          : const Color(0xFF4877F7),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDarkMode
                                            ? Colors.white.withOpacity(0.12)
                                            : Colors.white.withOpacity(0.20),
                                        width: 1,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedBarangay,
                                        isDense: true,
                                        borderRadius: BorderRadius.circular(16),
                                        dropdownColor: isDarkMode
                                            ? const Color(0xFF303030)
                                            : const Color(0xFF4877F7),
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
                    // SENSOR CARD
                    // =================================================

                    Expanded(
                      child: Transform.translate(
                        offset:
                            const Offset(0, -100),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color(0xFF2C2C2C)
                                  : Colors.white,
                              borderRadius:
                                  BorderRadius.circular(
                                20,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withOpacity(
                                    isDarkMode
                                        ? 0.25
                                        : 0.08,
                                  ),
                                  blurRadius: 6,
                                  offset:
                                      const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [

                                // =================================================
                                // TEMPERATURE + HOUSE
                                // =================================================

                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [

                                          Text(
                                            'Current Temperature:',
                                            style:
                                                TextStyle(
                                              fontSize: 14,
                                              fontWeight:
                                                  FontWeight
                                                      .w500,
                                              color:
                                                  isDarkMode
                                                      ? Colors
                                                          .white
                                                      : Colors
                                                          .black,
                                            ),
                                          ),

                                          const SizedBox(
                                            height: 6,
                                          ),

                                          Row(
                                            children: [

                                              Image.asset(
                                                'assets/icon/thermometer.png',
                                                width: 50,
                                                height: 80,
                                              ),

                                              const SizedBox(
                                                width: 8,
                                              ),

                                              Flexible(
                                                child:
                                                    Text(
                                                  displayedTemperature !=
                                                          null
                                                      ? '${displayedTemperature.toStringAsFixed(1)}°C'
                                                      : '--°C',
                                                  style:
                                                      TextStyle(
                                                    fontSize:
                                                        30,
                                                    fontWeight:
                                                        FontWeight
                                                            .bold,
                                                    color:
                                                        isDarkMode
                                                            ? Colors
                                                                .white
                                                            : Colors
                                                                .black,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),


                                  ],
                                ),

                                const SizedBox(
                                  height: 6,
                                ),

                                // =================================================
                                // WATER LEVEL + HUMIDITY
                                // =================================================

                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [

                                      // =================================================
                                      // WIDER WATER LEVEL
                                      // =================================================

                                      Expanded(
                                        flex: 6,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .center,
                                          children: [

                                            Text(
                                              'Water Level',
                                              style:
                                                  TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight
                                                        .w600,
                                                color:
                                                    isDarkMode
                                                        ? Colors
                                                            .white
                                                        : Colors
                                                            .black,
                                              ),
                                            ),

                                            const SizedBox(
                                              height: 6,
                                            ),

                                            Expanded(
                                              child:
                                                  LayoutBuilder(
                                                builder:
                                                    (
                                                  context,
                                                  constraints,
                                                ) {

                                                  // =================================================
                                                  // WIDER WATER CONTAINER + SCALE
                                                  // =================================================

                                                  final double
                                                      tubeCanvasWidth =
                                                      math.min(
                                                    180,
                                                    constraints
                                                            .maxWidth *
                                                        0.62,
                                                  );

                                                  return Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [

                                                      // =============================================
                                                      // WATER CONTAINER
                                                      // =============================================

                                                      SizedBox(
                                                        width:
                                                            tubeCanvasWidth +
                                                                8,
                                                        child:
                                                            Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [

                                                            // =====================================
                                                            // WATER LEVEL TEXT
                                                            // =====================================

                                                            TweenAnimationBuilder<
                                                                double>(
                                                              tween:
                                                                  Tween<
                                                                      double>(
                                                                begin:
                                                                    animationStart,
                                                                end:
                                                                    animationEnd,
                                                              ),
                                                              duration:
                                                                  const Duration(
                                                                milliseconds:
                                                                    800,
                                                              ),
                                                              curve:
                                                                  Curves.easeInOut,
                                                              builder:
                                                                  (
                                                                context,
                                                                animatedLevel,
                                                                child,
                                                              ) {
                                                                return Text(
                                                                  sensorActive
                                                                      ? '${animatedLevel.toStringAsFixed(1)} cm'
                                                                      : 'IDLE',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        20,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    color:
                                                                        isDarkMode
                                                                            ? Colors.white
                                                                            : Colors.black,
                                                                  ),
                                                                );
                                                              },
                                                            ),

                                                            const SizedBox(
                                                              height: 2,
                                                            ),

                                                            Expanded(
                                                              child:
                                                                  Center(
                                                                child:
                                                                    _WaterWithDuck(
                                                                  width:
                                                                      tubeCanvasWidth,
                                                                  height:
                                                                      constraints.maxHeight -
                                                                          34,
                                                                  animation:
                                                                      _waterAnimationController,
                                                                  animationStart:
                                                                      animationStart,
                                                                  animationEnd:
                                                                      animationEnd,
                                                                  maxWaterLevel:
                                                                      maxWaterLevel,
                                                                  isDark:
                                                                      isDarkMode,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),

                                                      const SizedBox(
                                                        width: 8,
                                                      ),

                                                      // =============================================
                                                      // GAUGE SCALE
                                                      // =============================================

                                                      Expanded(
                                                        child:
                                                            Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                            top: 34,
                                                            left: 0,
                                                          ),
                                                          child:
                                                              SizedBox(
                                                            height:
                                                                constraints.maxHeight -
                                                                    34,
                                                            child:
                                                                Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [

                                                                Text(
                                                                  '200 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.red.shade400,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '180 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.red.shade400,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '160 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.red.shade400,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '140 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.orange.shade700,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '120 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.orange.shade700,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '100 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.orange.shade700,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '80 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.orange.shade300,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '60 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.orange.shade300,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '40 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.orange.shade300,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '20 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.green.shade600,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                                ),

                                                                Text(
                                                                  '0 cm',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        Colors.green.shade600,
                                                                    fontWeight:
                                                                        FontWeight.bold,
                                                                    fontSize:
                                                                        10,
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

                                      const SizedBox(
                                        width: 12,
                                      ),

                                      // =================================================
                                      // HUMIDITY + FLOOD STATUS
                                      // =================================================

                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .center,
                                          children: [

                                            Text(
                                              'Humidity',
                                              style:
                                                  TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight
                                                        .w600,
                                                color:
                                                    isDarkMode
                                                        ? Colors
                                                            .white
                                                        : Colors
                                                            .black,
                                              ),
                                            ),

                                            const SizedBox(
                                              height: 6,
                                            ),

                                            // =================================================
                                            // HUMIDITY GAUGE
                                            // =================================================

                                            LayoutBuilder(
                                              builder:
                                                  (
                                                context,
                                                constraints,
                                              ) {
                                                final double
                                                    gaugeSize =
                                                    math.min(
                                                  150,
                                                  constraints
                                                      .maxWidth,
                                                );

                                                return CustomPaint(
                                                  size: Size(
                                                    gaugeSize,
                                                    gaugeSize *
                                                        0.6,
                                                  ),
                                                  painter:
                                                      _HumidityGaugePainter(
                                                    percent:
                                                        (humidity /
                                                                100)
                                                            .clamp(
                                                              0,
                                                              1,
                                                            )
                                                            .toDouble(),
                                                    isDark:
                                                        isDarkMode,
                                                  ),
                                                  child:
                                                      SizedBox(
                                                    width:
                                                        gaugeSize,
                                                    height:
                                                        gaugeSize *
                                                            0.6,
                                                    child:
                                                        Padding(
                                                      padding:
                                                          const EdgeInsets
                                                              .only(
                                                        top: 26,
                                                      ),
                                                      child:
                                                          Center(
                                                        child:
                                                            Text(
                                                          (esp32Online ||
                                                                  _fallbackHumidity !=
                                                                      null)
                                                              ? '${humidity.toStringAsFixed(0)}%'
                                                              : '--%',
                                                          style:
                                                              TextStyle(
                                                            fontSize:
                                                                24,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color:
                                                                isDarkMode
                                                                    ? Colors.white
                                                                    : Colors.black,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),

                                            const SizedBox(
                                              height: 4,
                                            ),

                                            // =================================================
                                            // FLOOD RISK STATUS
                                            // =================================================

                                            Text(
                                              'Flood Risk Status',
                                              style:
                                                  TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight
                                                        .w600,
                                                color:
                                                    isDarkMode
                                                        ? Colors
                                                            .white
                                                        : Colors
                                                            .black,
                                              ),
                                            ),

                                            const SizedBox(
                                              height: 4,
                                            ),

                                            Container(
                                              width:
                                                  double.infinity,
                                              constraints:
                                                  const BoxConstraints(
                                                maxWidth:
                                                    double.infinity,
                                              ),
                                              padding:
                                                  const EdgeInsets
                                                      .symmetric(
                                                vertical: 10,
                                                horizontal: 8,
                                              ),
                                              decoration:
                                                  BoxDecoration(
                                                color:
                                                    !sensorActive
                                                        ? Colors
                                                            .grey
                                                            .shade600
                                                        : waterLevel >
                                                                50
                                                            ? Colors
                                                                .red
                                                                .shade700
                                                            : waterLevel >
                                                                    30
                                                                ? Colors
                                                                    .orange
                                                                    .shade700
                                                                : Colors
                                                                    .green
                                                                    .shade700,
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                  12,
                                                ),
                                              ),
                                              child:
                                                  FittedBox(
                                                fit: BoxFit
                                                    .scaleDown,
                                                child:
                                                    Text(
                                                  !sensorActive
                                                      ? 'IDLE'
                                                      : waterLevel >
                                                              50
                                                          ? 'FLOODING'
                                                          : waterLevel >
                                                                  30
                                                              ? 'MEDIUM RISK'
                                                              : 'SAFE',
                                                  maxLines: 1,
                                                  style:
                                                      const TextStyle(
                                                    fontSize:
                                                        16,
                                                    fontWeight:
                                                        FontWeight
                                                            .w900,
                                                    color:
                                                        Colors
                                                            .white,
                                                    letterSpacing:
                                                        0.5,
                                                  ),
                                                ),
                                              ),
                                            ),

                                            const SizedBox(
                                              height: 4,
                                            ),

                                            // =================================================
                                            // ML / OPEN-METEO RAINFALL PREDICTION
                                            // =================================================

                                            Container(
                                              width:
                                                  double.infinity,
                                              padding:
                                                  const EdgeInsets
                                                      .symmetric(
                                                vertical: 8,
                                                horizontal: 8,
                                              ),
                                              decoration:
                                                  BoxDecoration(
                                                color: isDarkMode
                                                    ? const Color(
                                                        0xFF353535,
                                                      )
                                                    : Colors
                                                        .blue
                                                        .shade50,
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                  12,
                                                ),
                                              ),
                                              child: Column(
                                                children: [

                                                  // =================================================
                                                  // FORECAST TITLE
                                                  // =================================================

                                                  Text(
                                                    _mlForecastIdle ||
                                                            _mlError !=
                                                                null
                                                        ? 'Rainfall Forecast'
                                                        : 'ML Rainfall Forecast',
                                                    textAlign:
                                                        TextAlign
                                                            .center,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight
                                                              .w700,
                                                      color:
                                                          isDarkMode
                                                              ? Colors
                                                                  .white
                                                              : Colors
                                                                  .black87,
                                                    ),
                                                  ),

                                                  const SizedBox(
                                                    height: 4,
                                                  ),

                                                  // =================================================
                                                  // MAIN RAINFALL VALUE
                                                  // =================================================

                                                  if (_mlLoading &&
                                                      !_mlForecastIdle &&
                                                      _mlError ==
                                                          null)
                                                    const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  else if (!_mlForecastIdle &&
                                                      _mlError ==
                                                          null &&
                                                      _mlRainfall24h !=
                                                          null)
                                                    Text(
                                                      '24h: ${_mlRainfall24h!.toStringAsFixed(2)} mm',
                                                      textAlign:
                                                          TextAlign
                                                              .center,
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight
                                                                .bold,
                                                        color:
                                                            isDarkMode
                                                                ? Colors
                                                                    .white
                                                                : Colors
                                                                    .black,
                                                      ),
                                                    )
                                                  else if (_openMeteoRainfall24h !=
                                                      null)
                                                    Text(
                                                      '24h: ${_openMeteoRainfall24h!.toStringAsFixed(2)} mm',
                                                      textAlign:
                                                          TextAlign
                                                              .center,
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight
                                                                .bold,
                                                        color:
                                                            isDarkMode
                                                                ? Colors
                                                                    .white
                                                                : Colors
                                                                    .black,
                                                      ),
                                                    )
                                                  else if (_openMeteoRainLoading)
                                                    const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  else
                                                    Text(
                                                      '--',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight
                                                                .bold,
                                                        color:
                                                            isDarkMode
                                                                ? Colors
                                                                    .white
                                                                : Colors
                                                                    .black,
                                                      ),
                                                    ),

                                                  const SizedBox(
                                                    height: 2,
                                                  ),

                                                  // =================================================
                                                  // 1 HOUR RAINFALL
                                                  // =================================================

                                                  if (!_mlForecastIdle &&
                                                      _mlError ==
                                                          null &&
                                                      _mlRainfall1h !=
                                                          null)
                                                    Text(
                                                      '1h: ${_mlRainfall1h!.toStringAsFixed(2)} mm',
                                                      textAlign:
                                                          TextAlign
                                                              .center,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            isDarkMode
                                                                ? Colors
                                                                    .grey[300]
                                                                : Colors
                                                                    .grey[700],
                                                      ),
                                                    )
                                                  else if (_openMeteoRainfall1h !=
                                                      null)
                                                    Text(
                                                      '1h: ${_openMeteoRainfall1h!.toStringAsFixed(2)} mm',
                                                      textAlign:
                                                          TextAlign
                                                              .center,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            isDarkMode
                                                                ? Colors
                                                                    .grey[300]
                                                                : Colors
                                                                    .grey[700],
                                                      ),
                                                    ),

                                                  // =================================================
                                                  // CURRENT RAIN
                                                  // =================================================

                                                  if ((_mlForecastIdle ||
                                                          _mlError !=
                                                              null) &&
                                                      _openMeteoCurrentRainfall !=
                                                          null)
                                                    Text(
                                                      'Current rain: '
                                                      '${_openMeteoCurrentRainfall!.toStringAsFixed(2)} mm',
                                                      textAlign:
                                                          TextAlign
                                                              .center,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            isDarkMode
                                                                ? Colors
                                                                    .grey[300]
                                                                : Colors
                                                                    .grey[700],
                                                      ),
                                                    ),

                                                  // =================================================
                                                  // RAIN PROBABILITY
                                                  // =================================================

                                                  if ((_mlForecastIdle ||
                                                          _mlError !=
                                                              null) &&
                                                      _openMeteoRainProbability !=
                                                          null)
                                                    Text(
                                                      'Rain probability: '
                                                      '${_openMeteoRainProbability!.toStringAsFixed(0)}%',
                                                      textAlign:
                                                          TextAlign
                                                              .center,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            isDarkMode
                                                                ? Colors
                                                                    .grey[300]
                                                                : Colors
                                                                    .grey[700],
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
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