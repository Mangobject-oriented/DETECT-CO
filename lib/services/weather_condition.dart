/// Interpretation of Open-Meteo's current WMO code and observed precipitation.
/// Forecast probability and hourly forecast values are intentionally not used.
enum WeatherCondition { clear, partlyCloudy, cloudy, fog, drizzle, rain, thunderstorm, snow }

WeatherCondition resolveWeatherCondition({
  required int? weatherCode,
  required double? currentPrecipitationMm,
}) {
  final double precipitation = currentPrecipitationMm ?? 0;
  final int? code = weatherCode;

  if (code != null && code >= 95 && code <= 99) {
    return precipitation > 0
        ? WeatherCondition.thunderstorm
        : WeatherCondition.cloudy;
  }
  if (code != null && (code == 45 || code == 48)) {
    return WeatherCondition.fog;
  }
  if (code != null && const {71, 73, 75, 77, 85, 86}.contains(code)) {
    return precipitation > 0 ? WeatherCondition.snow : WeatherCondition.clear;
  }
  if (code != null && const {51, 53, 55, 56, 57}.contains(code)) {
    return precipitation > 0 ? WeatherCondition.drizzle : WeatherCondition.clear;
  }
  if (code != null && const {61, 63, 65, 66, 67, 80, 81, 82}.contains(code)) {
    return precipitation > 0 ? WeatherCondition.rain : WeatherCondition.clear;
  }
  if (code == 3) return WeatherCondition.cloudy;
  if (code == 2) return WeatherCondition.partlyCloudy;
  if (code == 1) return WeatherCondition.partlyCloudy;
  return WeatherCondition.clear;
}
