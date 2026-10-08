enum FloodRiskStatus {
  normal,
  warning,
  critical,
}

/// Converts the ultrasonic sensor's distance into rise from the 150 cm
/// normal baseline.
class FloodRiskReading {
  static const double baselineDistanceCm = 150.0;

  /// Values at or above 200 cm retain the app's existing out-of-range state.
  static const double maxValidSensorDistanceCm = 200.0;

  static double? parseSensorDistanceCm(dynamic rawValue) {
    if (rawValue == null) return null;

    final distanceCm = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue.toString());

    if (distanceCm == null ||
        !distanceCm.isFinite ||
        distanceCm < 0 ||
        distanceCm >= maxValidSensorDistanceCm) {
      return null;
    }

    return distanceCm;
  }

  static double waterRiseCm(double currentDistanceCm) {
    final rise = baselineDistanceCm - currentDistanceCm;
    return rise > 0 ? rise : 0;
  }

  static FloodRiskStatus statusForWaterRise(double riseCm) {
    if (riseCm <= 4) return FloodRiskStatus.normal;
    if (riseCm <= 40) return FloodRiskStatus.warning;
    return FloodRiskStatus.critical;
  }

  static FloodRiskStatus statusForDistance(double distanceCm) =>
      statusForWaterRise(waterRiseCm(distanceCm));
}
