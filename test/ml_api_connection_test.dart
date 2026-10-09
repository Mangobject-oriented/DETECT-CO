import 'package:detectco/services/ml_api_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MlApiConnection.normalizeManualUrl', () {
    test('adds the default API port and prediction path to an IP address', () {
      expect(
        MlApiConnection.normalizeManualUrl('192.168.1.41'),
        'http://192.168.1.41:8000/predict',
      );
    });

    test('preserves an explicitly configured API URL', () {
      expect(
        MlApiConnection.normalizeManualUrl(
          'https://ml.example.test:8443/api/predict?ignored=1',
        ),
        'https://ml.example.test:8443/api/predict',
      );
    });

    test('rejects invalid schemes and addresses', () {
      expect(
        () => MlApiConnection.normalizeManualUrl('ftp://server:8000'),
        throwsFormatException,
      );
      expect(
        () => MlApiConnection.normalizeManualUrl('not a host'),
        throwsFormatException,
      );
    });
  });
}
