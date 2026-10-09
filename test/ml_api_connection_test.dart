import 'dart:convert';

import 'package:detectco/services/ml_api_connection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  group('MlApiConnection remote configuration', () {
    const firstUrl = 'https://alpha-beta.trycloudflare.com';
    const secondUrl = 'https://gamma-delta.trycloudflare.com';

    Map<String, dynamic> config(String url, String version) => {
      'url': url,
      'version': version,
      'updatedAt': '1791550000000',
    };

    test('accepts only HTTPS Quick Tunnel hostnames', () {
      expect(MlApiConnection.normalizeQuickTunnelUrl('$firstUrl/'), firstUrl);
      for (final url in [
        'http://alpha-beta.trycloudflare.com',
        'https://example.org',
        'https://alpha-beta.trycloudflare.com.evil.org',
        'https://alpha-beta.trycloudflare.com/path',
      ]) {
        expect(
          () => MlApiConnection.normalizeQuickTunnelUrl(url),
          throwsFormatException,
        );
      }
    });

    test(
      'syncs a missed backend update and persists the verified URL',
      () async {
        var healthChecks = 0;
        final client = MockClient((request) async {
          healthChecks++;
          expect(request.url.toString(), '$firstUrl/health');
          return http.Response(
            jsonEncode({'status': 'healthy', 'models_loaded': true}),
            200,
          );
        });
        final connection = MlApiConnection.forTesting(
          client: client,
          configLoader: () async => config(firstUrl, 'version-1'),
        );
        var changes = 0;
        connection.configurationChanges.addListener(() => changes++);

        expect(await connection.synchronizeRemoteConfig(), isTrue);
        expect(await connection.remoteUrl, firstUrl);
        expect(await connection.synchronizeRemoteConfig(), isFalse);
        expect(healthChecks, 1);
        expect(changes, 1);
      },
    );

    test(
      'prediction resolution follows a newer synchronized Quick Tunnel URL',
      () async {
        var currentConfig = config(firstUrl, 'version-1');
        final healthUrls = <Uri>[];
        final client = MockClient((request) async {
          healthUrls.add(request.url);
          return http.Response(
            jsonEncode({'status': 'healthy', 'models_loaded': true}),
            200,
          );
        });
        final connection = MlApiConnection.forTesting(
          client: client,
          configLoader: () async => currentConfig,
        );

        expect(await connection.synchronizeRemoteConfig(), isTrue);
        expect(
          await connection.resolvePredictionUri(),
          Uri.parse('$firstUrl/predict'),
        );

        currentConfig = config(secondUrl, 'version-2');
        expect(await connection.synchronizeRemoteConfig(), isTrue);
        expect(
          await connection.resolvePredictionUri(),
          Uri.parse('$secondUrl/predict'),
        );
        expect(
          healthUrls.any((url) => url.host == 'gamma-delta.trycloudflare.com'),
          isTrue,
        );
      },
    );

    test(
      'keeps the prior URL when a replacement fails health validation',
      () async {
        final client = MockClient((request) async {
          if (request.url.host == 'alpha-beta.trycloudflare.com') {
            return http.Response(
              jsonEncode({'status': 'healthy', 'models_loaded': true}),
              200,
            );
          }
          return http.Response('unavailable', 503);
        });
        final connection = MlApiConnection.forTesting(
          client: client,
          configLoader: () async => null,
        );

        expect(
          await connection.applyRemoteConfig(config(firstUrl, 'version-1')),
          isTrue,
        );
        await expectLater(
          connection.applyRemoteConfig(config(secondUrl, 'version-2')),
          throwsStateError,
        );
        expect(await connection.remoteUrl, firstUrl);
      },
    );

    test(
      'ignores an older configuration message after a newer one was stored',
      () async {
        var healthChecks = 0;
        final client = MockClient((_) async {
          healthChecks++;
          return http.Response(
            jsonEncode({'status': 'healthy', 'models_loaded': true}),
            200,
          );
        });
        final connection = MlApiConnection.forTesting(
          client: client,
          configLoader: () async => null,
        );

        await connection.applyRemoteConfig({
          ...config(secondUrl, 'version-2'),
          'updatedAt': '2000',
        });
        final appliedOlder = await connection.applyRemoteConfig({
          ...config(firstUrl, 'version-1'),
          'updatedAt': '1000',
        });

        expect(appliedOlder, isFalse);
        expect(await connection.remoteUrl, secondUrl);
        expect(healthChecks, 1);
      },
    );

    test('ignores non-update FCM data and applies valid update data', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'status': 'healthy', 'models_loaded': true}),
          200,
        ),
      );
      final connection = MlApiConnection.forTesting(
        client: client,
        configLoader: () async => null,
      );

      expect(await connection.handleFcmData({'type': 'announcement'}), isFalse);
      expect(
        await connection.handleFcmData({
          'type': 'ml_api_update',
          ...config(firstUrl, 'version-1'),
        }),
        isTrue,
      );
      expect(await connection.remoteUrl, firstUrl);
    });
  });
}
