import 'package:flutter_test/flutter_test.dart';
import 'package:detectco/services/weather_condition.dart';

void main() {
  test('clear sky stays clear when hourly rain probability is high', () {
    expect(
      resolveWeatherCondition(
        weatherCode: 0,
        currentPrecipitationMm: 0,
      ),
      WeatherCondition.clear,
    );
  });

  test('rain code with observed precipitation resolves to rain', () {
    expect(
      resolveWeatherCondition(
        weatherCode: 61,
        currentPrecipitationMm: 0.5,
      ),
      WeatherCondition.rain,
    );
  });

  test('rain code without observed precipitation does not show rain', () {
    expect(
      resolveWeatherCondition(
        weatherCode: 61,
        currentPrecipitationMm: 0,
      ),
      WeatherCondition.clear,
    );
  });

  test('fog is preserved without precipitation', () {
    expect(
      resolveWeatherCondition(
        weatherCode: 45,
        currentPrecipitationMm: 0,
      ),
      WeatherCondition.fog,
    );
  });

  test('thunderstorm with observed precipitation resolves to thunderstorm', () {
    expect(
      resolveWeatherCondition(
        weatherCode: 95,
        currentPrecipitationMm: 0.5,
      ),
      WeatherCondition.thunderstorm,
    );
  });

  test('snow code needs observed precipitation', () {
    expect(
      resolveWeatherCondition(
        weatherCode: 71,
        currentPrecipitationMm: 0,
      ),
      WeatherCondition.clear,
    );
    expect(
      resolveWeatherCondition(
        weatherCode: 71,
        currentPrecipitationMm: 0.5,
      ),
      WeatherCondition.snow,
    );
  });
}
