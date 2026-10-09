import 'dart:async';
import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves, health-checks, and caches the local DETECT-CO ML API endpoint.
///
/// `ML_API_URL` has highest priority for development and CI. On mobile, the
/// default path uses DNS-SD instead of assuming a fixed IP or `.local` lookup.
class MlApiConnection {
  MlApiConnection._();

  static final instance = MlApiConnection._();
  final ValueNotifier<int> configurationChanges = ValueNotifier<int>(0);

  static const serviceType = '_detectco-ml._tcp';
  static const _manualUrlKey = 'ml_api_manual_url';
  static const _environmentUrl = String.fromEnvironment('ML_API_URL');
  static const _discoveryTimeout = Duration(seconds: 5);
  static const _healthTimeout = Duration(seconds: 4);

  Uri? _cachedPredictionUri;
  Future<Uri>? _resolveInFlight;
  int _networkGeneration = 0;

  void invalidate() {
    _networkGeneration++;
    _cachedPredictionUri = null;
  }

  Future<String?> get manualUrl async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_manualUrlKey);
  }

  Future<void> saveManualUrl(String? input) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = input == null || input.trim().isEmpty
        ? null
        : normalizeManualUrl(input);
    if (normalized == null) {
      await prefs.remove(_manualUrlKey);
    } else {
      await prefs.setString(_manualUrlKey, normalized);
    }
    invalidate();
    configurationChanges.value++;
  }

  static String normalizeManualUrl(String input) {
    var value = input.trim();
    if (value.contains(RegExp(r'\s'))) {
      throw const FormatException('The server address cannot contain spaces.');
    }
    if (!value.contains('://')) value = 'http://$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme)) {
      throw const FormatException('Enter a valid server IP or HTTP URL.');
    }
    final port = parsed.hasPort ? parsed.port : 8000;
    if (port < 1 || port > 65535) {
      throw const FormatException(
        'The server port must be between 1 and 65535.',
      );
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const FormatException('Do not include credentials in the server URL.');
    }
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: port,
      path: parsed.path.isEmpty || parsed.path == '/'
          ? '/predict'
          : parsed.path,
    ).toString();
  }

  Future<Uri> resolvePredictionUri() {
    final inFlight = _resolveInFlight;
    if (inFlight != null) return inFlight;
    final resolving = _resolvePredictionUri();
    _resolveInFlight = resolving;
    return resolving.whenComplete(() {
      if (identical(_resolveInFlight, resolving)) _resolveInFlight = null;
    });
  }

  Future<Uri> _resolvePredictionUri() async {
    final override = _environmentUrl.trim();
    if (override.isNotEmpty) {
      final uri = _predictionUri(override);
      await _requireHealthy(uri);
      _cachedPredictionUri = uri;
      return uri;
    }

    final cached = _cachedPredictionUri;
    if (cached != null) {
      try {
        await _requireHealthy(cached);
        return cached;
      } catch (_) {
        _cachedPredictionUri = null;
      }
    }

    if (kIsWeb) {
      final manual = await manualUrl;
      if (manual != null && manual.isNotEmpty) {
        final manualUri = _predictionUri(manual);
        await _requireHealthy(manualUri);
        _cachedPredictionUri = manualUri;
        return manualUri;
      }
      final local = Uri.parse('http://127.0.0.1:8000/predict');
      await _requireHealthy(local);
      _cachedPredictionUri = local;
      return local;
    }

    final generation = _networkGeneration;
    List<Uri> discovered = const [];
    try {
      discovered = await _discoverService();
      for (final candidate in discovered) {
        try {
          await _requireHealthy(candidate);
          if (generation == _networkGeneration) {
            _cachedPredictionUri = candidate;
          }
          return candidate;
        } catch (_) {
          // A laptop can advertise several interfaces; check each resolved IP.
        }
      }
    } catch (_) {
      // Discovery is optional. Try the user-configured address next.
    }

    final manual = await manualUrl;
    if (manual != null && manual.isNotEmpty) {
      final manualUri = _predictionUri(manual);
      await _requireHealthy(manualUri);
      if (generation == _networkGeneration) {
        _cachedPredictionUri = manualUri;
      }
      return manualUri;
    }

    throw StateError(
      discovered.isEmpty
          ? 'Could not discover the DETECT-CO ML server on this network. '
                'Check that both devices share Wi-Fi, then set a server address in Menu > Display Settings.'
          : 'The discovered ML server did not pass its health check.',
    );
  }

  Uri _predictionUri(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme)) {
      throw const FormatException('ML_API_URL is not a valid HTTP URL.');
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const FormatException('Do not include credentials in ML_API_URL.');
    }
    final path = parsed.path.endsWith('/predict')
        ? parsed.path
        : '${parsed.path.replaceFirst(RegExp(r'/$'), '')}/predict';
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : 8000,
      path: path,
    );
  }

  Uri _healthUri(Uri predictionUri) => predictionUri.replace(
    path: predictionUri.path.replaceFirst(RegExp(r'/predict$'), '/health'),
  );

  Future<void> _requireHealthy(Uri predictionUri) async {
    final response = await http
        .get(_healthUri(predictionUri))
        .timeout(_healthTimeout);
    if (response.statusCode != 200) {
      throw StateError(
        'ML health endpoint returned HTTP ${response.statusCode}.',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FormatException('ML health endpoint returned invalid JSON.');
    }
    if (decoded is! Map ||
        decoded['status']?.toString().toLowerCase() != 'healthy' ||
        decoded['models_loaded'] != true) {
      throw StateError('ML server responded but its models are not ready.');
    }
  }

  Future<List<Uri>> _discoverService() async {
    final discovery = BonsoirDiscovery(type: serviceType);
    StreamSubscription<BonsoirDiscoveryEvent>? subscription;
    var initialized = false;
    try {
      await discovery.initialize().timeout(const Duration(seconds: 3));
      initialized = true;
      final events = discovery.eventStream;
      if (events == null) return const [];

      final found = Completer<List<Uri>>();
      subscription = events.listen((event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          event.service.resolve(discovery.serviceResolver);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
          final service = event.service;
          if (found.isCompleted || service.port != 8000) {
            return;
          }
          final addresses = service.hostAddresses
              .where(_isIpv4)
              .map(
                (address) => Uri(
                  scheme: 'http',
                  host: address,
                  port: service.port,
                  path: '/predict',
                ),
              )
              .toList(growable: false);
          if (addresses.isNotEmpty) {
            found.complete(addresses);
          }
        }
      });
      await discovery.start().timeout(const Duration(seconds: 3));
      return await found.future.timeout(
        _discoveryTimeout,
        onTimeout: () => const [],
      );
    } finally {
      await subscription?.cancel();
      if (initialized) {
        try {
          await discovery.stop();
        } catch (_) {
          // The native discovery session can already be stopped on network loss.
        }
      }
    }
  }

  bool _isIpv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final value = int.tryParse(part);
      return value != null && value >= 0 && value <= 255;
    });
  }
}
