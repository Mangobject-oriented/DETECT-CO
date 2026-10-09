import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves, health-checks, and caches the DETECT-CO ML API endpoint.
///
/// Public deployments should set ML_API_URL to the HTTPS prediction endpoint.
class MlApiConnection {
  MlApiConnection._();

  static final instance = MlApiConnection._();
  final ValueNotifier<int> configurationChanges = ValueNotifier<int>(0);

  static const _manualUrlKey = 'ml_api_manual_url';
  static const _environmentUrl = String.fromEnvironment('ML_API_URL');
  static const _healthTimeout = Duration(seconds: 8);

  Uri? _cachedPredictionUri;
  Future<Uri>? _resolveInFlight;

  void invalidate() {
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
    if (!value.contains('://')) value = 'https://$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme) ||
        (parsed.scheme != 'https' &&
            !{'localhost', '127.0.0.1'}.contains(parsed.host))) {
      throw const FormatException('Enter a valid public HTTPS API URL.');
    }
    final port = parsed.hasPort
        ? parsed.port
        : (parsed.scheme == 'http' ? 8000 : null);
    if (port != null && (port < 1 || port > 65535)) {
      throw const FormatException(
        'The server port must be between 1 and 65535.',
      );
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const FormatException(
        'Do not include credentials in the server URL.',
      );
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

    final manual = await manualUrl;
    if (manual != null && manual.isNotEmpty) {
      final manualUri = _predictionUri(manual);
      await _requireHealthy(manualUri);
      _cachedPredictionUri = manualUri;
      return manualUri;
    }

    throw StateError(
      'The DETECT-CO ML service URL is not configured. Build with '
      '--dart-define=ML_API_URL=https://your-api-host/predict, or set the '
      'public HTTPS address in Menu > Display Settings.',
    );
  }

  Uri _predictionUri(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme) ||
        (parsed.scheme != 'https' &&
            !{'localhost', '127.0.0.1'}.contains(parsed.host))) {
      throw const FormatException('ML_API_URL must be a public HTTPS URL.');
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
      port: parsed.hasPort
          ? parsed.port
          : (parsed.scheme == 'http' ? 8000 : null),
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
}
