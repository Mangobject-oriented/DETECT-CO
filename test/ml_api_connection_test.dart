import 'package:detectco/services/ml_api_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MlApiConnection.normalizeManualUrl', () {
    test('uses HTTPS and the prediction path for a public hostname', () {
      expect(
        MlApiConnection.normalizeManualUrl('ml.example.org'),
        'https://ml.example.org/predict',
      );
    });

    test('keeps the local development port for explicit loopback HTTP', () {
      expect(
        MlApiConnection.normalizeManualUrl('http://127.0.0.1'),
        'http://127.0.0.1:8000/predict',
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
