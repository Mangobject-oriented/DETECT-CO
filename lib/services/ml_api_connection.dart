import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef MlApiConfigLoader = Future<Map<String, dynamic>?> Function();

/// Resolves, health-checks, and caches the DETECT-CO ML API endpoint.
///
/// A verified Firebase RTDB update takes priority over build-time and manual
/// fallback URLs so new Quick Tunnel hosts propagate without reinstalling.
class MlApiConnection {
  MlApiConnection._({http.Client? client, MlApiConfigLoader? configLoader})
    : _client = client ?? http.Client(),
      _configLoader = configLoader ?? _loadFirebaseConfig;

  static final instance = MlApiConnection._();
  final ValueNotifier<int> configurationChanges = ValueNotifier<int>(0);

  static const _manualUrlKey = 'ml_api_manual_url';
  static const _remoteConfigKey = 'ml_api_remote_config';
  static const _environmentUrl = String.fromEnvironment('ML_API_URL');
  static const _healthTimeout = Duration(seconds: 8);
  static const _configTimeout = Duration(seconds: 10);
  static final _quickTunnelHost = RegExp(
    r'^[a-z0-9]+(?:-[a-z0-9]+){1,3}\.trycloudflare\.com$',
  );

  final http.Client _client;
  final MlApiConfigLoader _configLoader;

  Uri? _cachedPredictionUri;
  Future<Uri>? _resolveInFlight;
  Future<bool>? _syncInFlight;

  factory MlApiConnection.forTesting({
    required http.Client client,
    required MlApiConfigLoader configLoader,
  }) => MlApiConnection._(client: client, configLoader: configLoader);

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
      invalidate();
      final previousChangeCount = configurationChanges.value;
      await synchronizeRemoteConfig();
      if (configurationChanges.value == previousChangeCount) {
        configurationChanges.value++;
      }
      return;
    } else {
      await prefs.setString(_manualUrlKey, normalized);
    }
    invalidate();
    configurationChanges.value++;
  }

  static String normalizeQuickTunnelUrl(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        parsed.scheme != 'https' ||
        !_quickTunnelHost.hasMatch(parsed.host) ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasPort ||
        (parsed.path.isNotEmpty && parsed.path != '/') ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const FormatException(
        'ML API update must use a valid HTTPS Cloudflare Quick Tunnel URL.',
      );
    }
    return parsed.origin;
  }

  static Future<Map<String, dynamic>?> _loadFirebaseConfig() async {
    final snapshot = await FirebaseDatabase.instance
        .ref('ml_api/config')
        .get()
        .timeout(_configTimeout);
    final value = snapshot.value;
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  Future<bool> synchronizeRemoteConfig() {
    final pending = _syncInFlight;
    if (pending != null) return pending;
    final syncing = _synchronizeRemoteConfig();
    _syncInFlight = syncing;
    return syncing.whenComplete(() {
      if (identical(_syncInFlight, syncing)) _syncInFlight = null;
    });
  }

  Future<bool> _synchronizeRemoteConfig() async {
    try {
      final config = await _configLoader().timeout(_configTimeout);
      if (config == null) return false;
      return await applyRemoteConfig(config);
    } catch (error) {
      debugPrint('ML API configuration sync unavailable: $error');
      return false;
    }
  }

  Future<bool> applyRemoteConfig(Map<String, dynamic> config) async {
    final url = normalizeQuickTunnelUrl(config['url']?.toString() ?? '');
    final version = config['version']?.toString().trim() ?? '';
    final updatedAtValue = config['updatedAt'];
    final updatedAt = int.tryParse(updatedAtValue?.toString() ?? '');
    if (version.isEmpty ||
        version.length > 100 ||
        updatedAt == null ||
        updatedAt <= 0) {
      throw const FormatException('ML API update metadata is invalid.');
    }

    final prefs = await SharedPreferences.getInstance();
    final current = _readStoredRemoteConfig(prefs);
    final currentUpdatedAt = int.tryParse(
      current?['updatedAt']?.toString() ?? '',
    );
    if (currentUpdatedAt != null && updatedAt < currentUpdatedAt) {
      return false;
    }
    if (current?['version'] == version && current?['url'] == url) {
      return false;
    }

    final changedUrl = current?['url'] != url;
    if (changedUrl) {
      await _requireHealthy(Uri.parse('$url/predict'));
    }

    await prefs.setString(
      _remoteConfigKey,
      jsonEncode({'url': url, 'version': version, 'updatedAt': updatedAt}),
    );
    if (changedUrl) {
      invalidate();
      configurationChanges.value++;
    }
    return changedUrl;
  }

  Future<bool> handleFcmData(Map<String, dynamic> data) async {
    if (data['type']?.toString() != 'ml_api_update') return false;
    try {
      await applyRemoteConfig(data);
    } catch (error) {
      debugPrint('Rejected ML API configuration update: $error');
    }
    return true;
  }

  Map<String, dynamic>? _readStoredRemoteConfig(SharedPreferences prefs) {
    final raw = prefs.getString(_remoteConfigKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> get remoteUrl async {
    final prefs = await SharedPreferences.getInstance();
    return _readStoredRemoteConfig(prefs)?['url']?.toString();
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
    final remote = await remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      final uri = _predictionUri(remote);
      await _requireHealthy(uri);
      _cachedPredictionUri = uri;
      return uri;
    }

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
    final response = await _client
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
