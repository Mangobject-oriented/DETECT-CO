import 'package:detectco/services/ml_flood_risk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared forecast store notifies Home and Map consumers of updates', () {
    final store = MlFloodRiskStore.instance;
    var notifications = 0;
    void onChanged() => notifications++;
    store.addListener(onChanged);

    store.update({
      'generated_at': '2026-10-10T01:00:00Z',
      'current_rainfall_mm': 1.2,
      'predictions': {
        'rainfall_1h_mm': 2.4,
        'rainfall_3h_mm': 4.8,
        'rainfall_6h_mm': 7.2,
        'rainfall_12h_mm': 9.6,
        'rainfall_24h_mm': 12.0,
      },
    });

    expect(notifications, 1);
    expect(store.forecast.available, isTrue);
    expect(store.forecast.rainfall1hMm, 2.4);
    expect(store.forecast.rainfall24hMm, 12.0);

    store.markUnavailable('API temporarily unavailable');
    expect(notifications, 2);
    expect(store.forecast.available, isFalse);
    expect(store.forecast.error, 'API temporarily unavailable');

    store.removeListener(onChanged);
  });
}
