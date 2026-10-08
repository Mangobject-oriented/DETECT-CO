import 'package:flutter/foundation.dart';

import 'flood_risk.dart';

enum MlFloodRiskLevel { low, moderate, high }

/// Shared ML forecast snapshot used by Home and Map. The forecast remains
/// unavailable until real results arrive from the existing FastAPI endpoint.
class MlForecastSnapshot {
  const MlForecastSnapshot({
    required this.available,
    required this.predictionsMm,
    required this.modelPredictionsMm,
    required this.currentRainfallMm,
    required this.generatedAt,
    required this.error,
  });

  static const empty = MlForecastSnapshot(
    available: false,
    predictionsMm: {},
    modelPredictionsMm: {},
    currentRainfallMm: null,
    generatedAt: null,
    error: null,
  );

  final bool available;
  final Map<int, double?> predictionsMm;
  final Map<String, Map<int, double?>> modelPredictionsMm;
  final double? currentRainfallMm;
  final DateTime? generatedAt;
  final String? error;

  double? get rainfall1hMm => predictionsMm[1];
  double? get rainfall3hMm => predictionsMm[3];
  double? get rainfall6hMm => predictionsMm[6];
  double? get rainfall12hMm => predictionsMm[12];
  double? get rainfall24hMm => predictionsMm[24];

  factory MlForecastSnapshot.fromApi(Map<String, dynamic> result) {
    final rawPredictions = result['predictions'];
    if (rawPredictions is! Map) return empty;

    double? read(Map source, String key) {
      final raw = source[key];
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      return value != null && value.isFinite && value >= 0 ? value : null;
    }

    const keys = {
      1: 'rainfall_1h_mm',
      3: 'rainfall_3h_mm',
      6: 'rainfall_6h_mm',
      12: 'rainfall_12h_mm',
      24: 'rainfall_24h_mm',
    };
    final predictions = <int, double?>{
      for (final entry in keys.entries)
        entry.key: read(rawPredictions, entry.value),
    };

    final models = <String, Map<int, double?>>{};
    final rawModels = result['model_predictions'];
    if (rawModels is Map) {
      for (final modelEntry in rawModels.entries) {
        if (modelEntry.value is! Map) continue;
        models[modelEntry.key.toString()] = {
          for (final entry in keys.entries)
            entry.key: read(modelEntry.value as Map, entry.value),
        };
      }
    }

    final hasPredictions = predictions.values.any((value) => value != null);
    final currentRain = read(result, 'current_rainfall_mm');
    final timestamp = DateTime.tryParse(
      result['generated_at']?.toString() ??
          result['last_prediction_at']?.toString() ??
          '',
    );

    return MlForecastSnapshot(
      available: hasPredictions,
      predictionsMm: predictions,
      modelPredictionsMm: models,
      currentRainfallMm: currentRain,
      generatedAt: timestamp,
      error: hasPredictions ? null : 'ML predictions are unavailable.',
    );
  }
}

/// Central conversion for ML risk UI and notifications.
///
/// The repository currently has no validated rainfall-to-risk cutoffs. To
/// avoid inventing them, severity follows the measured water-rise thresholds;
/// real ML rainfall forecasts remain context and are surfaced separately.
class MlFloodRiskAssessment {
  const MlFloodRiskAssessment({
    required this.level,
    required this.waterRiseCm,
    required this.currentRainfallMm,
    required this.forecast,
  });

  final MlFloodRiskLevel level;
  final double waterRiseCm;
  final double? currentRainfallMm;
  final MlForecastSnapshot forecast;

  String get label => switch (level) {
    MlFloodRiskLevel.low => 'LOW',
    MlFloodRiskLevel.moderate => 'MODERATE',
    MlFloodRiskLevel.high => 'HIGH',
  };

  factory MlFloodRiskAssessment.calculate({
    required double waterRiseCm,
    required MlForecastSnapshot forecast,
  }) {
    final sensorStatus = FloodRiskReading.statusForWaterRise(waterRiseCm);
    final level = switch (sensorStatus) {
      FloodRiskStatus.normal => MlFloodRiskLevel.low,
      FloodRiskStatus.warning => MlFloodRiskLevel.moderate,
      FloodRiskStatus.critical => MlFloodRiskLevel.high,
    };

    return MlFloodRiskAssessment(
      level: level,
      waterRiseCm: waterRiseCm,
      currentRainfallMm: forecast.currentRainfallMm,
      forecast: forecast,
    );
  }
}

class MlFloodRiskStore extends ChangeNotifier {
  MlFloodRiskStore._();

  static final instance = MlFloodRiskStore._();

  MlForecastSnapshot _forecast = MlForecastSnapshot.empty;

  MlForecastSnapshot get forecast => _forecast;

  void update(Map<String, dynamic> result) {
    _forecast = MlForecastSnapshot.fromApi(result);
    notifyListeners();
  }

  void markUnavailable(String message) {
    _forecast = MlForecastSnapshot(
      available: false,
      predictionsMm: const {},
      modelPredictionsMm: const {},
      currentRainfallMm: null,
      generatedAt: null,
      error: message,
    );
    notifyListeners();
  }
}
