import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int emergencyLocationNotificationId = 74101;
const String emergencyLocationStopActionId = 'stop_emergency_location';
const String emergencyLocationNotificationChannelId =
    'emergency_location_sharing';

@pragma('vm:entry-point')
void emergencyLocationNotificationBackgroundResponse(
  NotificationResponse response,
) {
  if (response.actionId == emergencyLocationStopActionId) {
    unawaited(EmergencyLocationService.stopPersistedSessionFromNotification());
  }
}

void emergencyLocationNotificationResponse(NotificationResponse response) {
  if (response.actionId == emergencyLocationStopActionId) {
    unawaited(EmergencyLocationService.instance.stop());
  }
}

class EmergencyLocationSession {
  const EmergencyLocationSession({
    required this.id,
    required this.startedAt,
    required this.expiresAt,
  });

  final String id;
  final DateTime startedAt;
  final DateTime expiresAt;
}

/// Owns the one active emergency location session and its Android notification.
class EmergencyLocationService extends ChangeNotifier {
  static const Duration sessionDuration = Duration(minutes: 30);
  static const String _sessionIdKey = 'emergency_location_session_id';
  static const String _startedAtKey = 'emergency_location_started_at';
  static const String _expiresAtKey = 'emergency_location_expires_at';

  static final EmergencyLocationService instance =
      EmergencyLocationService._internal();

  factory EmergencyLocationService() => instance;

  EmergencyLocationService._internal();

  /// Shared with the app's existing local notification initialization.
  static final FlutterLocalNotificationsPlugin notificationPlugin =
      FlutterLocalNotificationsPlugin();

  DatabaseReference get _sessionsRef =>
      FirebaseDatabase.instance.ref().child('emergency_sessions');

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<DatabaseEvent>? _sessionStatusSubscription;
  Timer? _expiryTimer;
  EmergencyLocationSession? _session;
  Future<EmergencyLocationSession?>? _restoreFuture;
  bool _ending = false;
  void Function()? _onExpired;

  bool get isActive =>
      _session != null && DateTime.now().isBefore(_session!.expiresAt);

  EmergencyLocationSession? get session => _session;

  Future<EmergencyLocationSession> start({
    required void Function() onExpired,
  }) async {
    if (_session == null) {
      final restored = await restoreActiveSession(onExpired: onExpired);
      if (restored != null) {
        throw StateError('An emergency location session is already active.');
      }
    }
    if (_session != null) {
      throw StateError('An emergency location session is already active.');
    }

    final Position initialPosition = await _getCurrentPosition();
    final DateTime startedAt = DateTime.now();
    final DateTime expiresAt = startedAt.add(sessionDuration);
    final DatabaseReference sessionRef = _sessionsRef.push();
    final String? id = sessionRef.key;
    if (id == null) {
      throw StateError('Could not create an emergency session ID.');
    }

    final emergencySession = EmergencyLocationSession(
      id: id,
      startedAt: startedAt,
      expiresAt: expiresAt,
    );

    // Keep the existing database structure used by the admin website.
    await sessionRef.set({
      'sessionId': id,
      'latitude': initialPosition.latitude,
      'longitude': initialPosition.longitude,
      'accuracy': initialPosition.accuracy,
      'startedAt': startedAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'status': 'active',
    });

    try {
      await _saveSessionLocally(emergencySession);
    } catch (_) {
      await _writeSessionEnd(id, 'stopped');
      rethrow;
    }

    _session = emergencySession;
    _onExpired = onExpired;
    _ending = false;
    _startSessionResources(emergencySession, onExpired);
    notifyListeners();
    await _showActiveNotification(emergencySession);
    return emergencySession;
  }

  /// Restores the existing session after app/process recreation. It never
  /// creates a replacement session or trusts stale local state over Firebase.
  Future<EmergencyLocationSession?> restoreActiveSession({
    required void Function() onExpired,
  }) {
    final currentRestore = _restoreFuture;
    if (currentRestore != null) return currentRestore;

    final restoreOperation = _restoreActiveSession(onExpired);
    _restoreFuture = restoreOperation;
    return restoreOperation.whenComplete(() {
      if (identical(_restoreFuture, restoreOperation)) {
        _restoreFuture = null;
      }
    });
  }

  Future<EmergencyLocationSession?> _restoreActiveSession(
    void Function() onExpired,
  ) async {
    final current = _session;
    if (current != null) {
      if (!DateTime.now().isBefore(current.expiresAt)) {
        await _end(status: 'expired');
        return null;
      }
      String? currentStatus;
      try {
        final currentSnapshot = await _sessionsRef.child(current.id).get();
        final currentValue = currentSnapshot.value;
        currentStatus = currentValue is Map
            ? currentValue['status']?.toString()
            : null;
      } catch (_) {
        // Preserve the locally known active session while temporarily offline.
        return current;
      }
      if (currentStatus == 'active') return current;
      await _finishExternally(expired: currentStatus == 'expired');
    }

    final preferences = await SharedPreferences.getInstance();
    final id = preferences.getString(_sessionIdKey);
    final startedAtMs = preferences.getInt(_startedAtKey);
    final expiresAtMs = preferences.getInt(_expiresAtKey);
    if (id == null || startedAtMs == null || expiresAtMs == null) {
      await _cancelActiveNotification();
      return null;
    }

    final session = EmergencyLocationSession(
      id: id,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
    );

    String? status;
    try {
      final snapshot = await _sessionsRef.child(id).get();
      final value = snapshot.value;
      status = value is Map ? value['status']?.toString() : null;
    } catch (_) {
      // Offline restoration trusts the persisted ID temporarily. The session
      // listener will reconcile it with Firebase when connectivity returns.
      status = 'active';
    }
    if (status != 'active') {
      await _clearSavedSession();
      await _cancelActiveNotification();
      return null;
    }

    if (!DateTime.now().isBefore(session.expiresAt)) {
      try {
        await _writeSessionEnd(id, 'expired');
      } catch (_) {
        // The persisted expiry is authoritative while the device is offline.
      }
      await _clearSavedSession();
      await _cancelActiveNotification();
      onExpired();
      return null;
    }

    _session = session;
    _onExpired = onExpired;
    _ending = false;
    _startSessionResources(session, onExpired);
    notifyListeners();
    unawaited(_showActiveNotification(session));
    return session;
  }

  void _startSessionResources(
    EmergencyLocationSession session,
    void Function() onExpired,
  ) {
    final remaining = session.expiresAt.difference(DateTime.now());
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () async {
        try {
          await _end(status: 'expired');
        } catch (_) {
          // The stored expiresAt remains authoritative while offline.
        }
      },
    );

    try {
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (position) => _updatePosition(position),
            onError: (Object error) {
              // Keep the session active; a later GPS reading can still update it.
            },
          );
    } catch (_) {
      // A stream can fail on some devices; the initial fix remains shared.
    }

    _sessionStatusSubscription = _sessionsRef
        .child(session.id)
        .onValue
        .listen(_onSessionRecordChanged);
  }

  void _onSessionRecordChanged(DatabaseEvent event) {
    final current = _session;
    if (current == null || _ending) return;

    final value = event.snapshot.value;
    final status = value is Map ? value['status']?.toString() : null;
    if (status == 'active' || status == null) return;

    final expired =
        status == 'expired' || !DateTime.now().isBefore(current.expiresAt);
    unawaited(_finishExternally(expired: expired));
  }

  Future<void> _finishExternally({required bool expired}) async {
    if (_session == null || _ending) return;
    _ending = true;
    _session = null;
    await _cancelSessionResources();
    await _clearSavedSession();
    await _cancelActiveNotification();
    _ending = false;
    notifyListeners();
    if (expired) _onExpired?.call();
  }

  Future<void> stop() => _end(status: 'stopped');

  /// Marks an in-memory session expired when the app resumes after its expiry.
  Future<bool> expireIfNeeded() async {
    final currentSession = _session;
    if (currentSession == null ||
        DateTime.now().isBefore(currentSession.expiresAt)) {
      return false;
    }

    try {
      await _end(status: 'expired');
    } catch (_) {
      // expiresAt still makes the session expired if the network is offline.
    }
    return true;
  }

  Future<void> _end({required String status}) async {
    final currentSession = _session;
    if (currentSession == null || _ending) return;

    _ending = true;
    _session = null;
    await _cancelSessionResources();
    notifyListeners();

    Object? updateError;
    try {
      await _writeSessionEnd(currentSession.id, status);
    } catch (error) {
      updateError = error;
    }

    // An expired session must stop locally and its notification must time out
    // even if Firebase is temporarily unreachable. A failed manual stop keeps
    // its persisted ID and notification so the action can be retried.
    if (updateError == null || status == 'expired') {
      await _clearSavedSession();
      await _cancelActiveNotification();
    }
    _ending = false;

    if (status == 'expired') _onExpired?.call();
    if (updateError != null && status != 'expired') {
      Error.throwWithStackTrace(updateError, StackTrace.current);
    }
  }

  Future<void> _cancelSessionResources() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _sessionStatusSubscription?.cancel();
    _sessionStatusSubscription = null;
  }

  Future<void> _updatePosition(Position position) async {
    final currentSession = _session;
    if (currentSession == null || _ending) return;

    if (!DateTime.now().isBefore(currentSession.expiresAt)) {
      try {
        await _end(status: 'expired');
      } catch (_) {
        // expiresAt still makes the session expired if the network is offline.
      }
      return;
    }

    try {
      await _sessionsRef.child(currentSession.id).update({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // Do not end the session because a transient database update failed.
    }
  }

  Future<Position> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const EmergencyLocationException(
        'Turn on your phone’s location services and try again.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const EmergencyLocationException(
        'Location permission is blocked. Enable it in app settings to share your location.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const EmergencyLocationException(
        'Location permission was denied. Allow it to start an emergency session.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
    } on TimeoutException {
      throw const EmergencyLocationException(
        'GPS could not get your location in time. Please try again outdoors.',
      );
    }
  }

  static Future<void> _saveSessionLocally(
    EmergencyLocationSession session,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sessionIdKey, session.id);
    await preferences.setInt(
      _startedAtKey,
      session.startedAt.millisecondsSinceEpoch,
    );
    await preferences.setInt(
      _expiresAtKey,
      session.expiresAt.millisecondsSinceEpoch,
    );
  }

  static Future<void> _clearSavedSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionIdKey);
    await preferences.remove(_startedAtKey);
    await preferences.remove(_expiresAtKey);
  }

  static Future<void> _writeSessionEnd(String id, String status) async {
    await FirebaseDatabase.instance
        .ref()
        .child('emergency_sessions')
        .child(id)
        .update({
          'status': status,
          'endedAt': DateTime.now().millisecondsSinceEpoch,
        });
  }

  Future<void> _showActiveNotification(EmergencyLocationSession session) async {
    final remaining = session.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      await _cancelActiveNotification();
      return;
    }

    try {
      await notificationPlugin.show(
        id: emergencyLocationNotificationId,
        title: 'DETECT-CO',
        body:
            'Emergency Location Sharing Active. Your emergency location is currently being shared.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            emergencyLocationNotificationChannelId,
            'Emergency Location Sharing',
            channelDescription:
                'Shows while Emergency Locate Me is sharing your location.',
            icon: 'ic_stat_detect_co',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.locationSharing,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: true,
            when: session.startedAt.millisecondsSinceEpoch,
            timeoutAfter: remaining.inMilliseconds,
            playSound: false,
            enableVibration: false,
            actions: const [
              AndroidNotificationAction(
                emergencyLocationStopActionId,
                'Stop Emergency',
                showsUserInterface: false,
                cancelNotification: false,
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Keep emergency sharing active if notification permission is unavailable.
    }
  }

  Future<void> _cancelActiveNotification() async {
    try {
      await notificationPlugin.cancel(id: emergencyLocationNotificationId);
    } catch (_) {
      // The notification also has an Android expiry timeout as a fallback.
    }
  }

  /// Background notification action entry. It runs in a separate isolate,
  /// updates the existing RTDB session record, clears its saved ID, and then
  /// removes the ongoing notification without creating a Flutter UI screen.
  @pragma('vm:entry-point')
  static Future<void> stopPersistedSessionFromNotification() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await notificationPlugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final preferences = await SharedPreferences.getInstance();
      final id = preferences.getString(_sessionIdKey);
      final expiresAtMs = preferences.getInt(_expiresAtKey);
      if (id != null) {
        final sessionRef = FirebaseDatabase.instance
            .ref()
            .child('emergency_sessions')
            .child(id);
        final snapshot = await sessionRef.get();
        final value = snapshot.value;
        final status = value is Map ? value['status']?.toString() : null;
        if (status == 'active') {
          final expired =
              expiresAtMs != null &&
              DateTime.now().millisecondsSinceEpoch >= expiresAtMs;
          await _writeSessionEnd(id, expired ? 'expired' : 'stopped');
        }
        await _clearSavedSession();
      }

      await notificationPlugin.cancel(id: emergencyLocationNotificationId);
    } catch (_) {
      // Leave the notification and persisted session available for retry if
      // Firebase cannot record the stop while the device is offline.
    }
  }
}

class EmergencyLocationException implements Exception {
  const EmergencyLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}
