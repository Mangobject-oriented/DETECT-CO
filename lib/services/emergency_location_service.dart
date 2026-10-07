import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

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

/// Manages a temporary foreground location-sharing session.
class EmergencyLocationService {
  static const Duration sessionDuration = Duration(minutes: 30);

  DatabaseReference get _sessionsRef =>
      FirebaseDatabase.instance.ref().child('emergency_sessions');

  StreamSubscription<Position>? _positionSubscription;
  Timer? _expiryTimer;
  EmergencyLocationSession? _session;
  bool _ending = false;

  bool get isActive =>
      _session != null && DateTime.now().isBefore(_session!.expiresAt);

  EmergencyLocationSession? get session => _session;

  Future<EmergencyLocationSession> start({
    required void Function() onExpired,
  }) async {
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

    // The app currently has no Firebase Authentication integration, so no
    // userId is written. Timestamps are Unix milliseconds for easy expiry checks.
    await sessionRef.set({
      'sessionId': id,
      'latitude': initialPosition.latitude,
      'longitude': initialPosition.longitude,
      'accuracy': initialPosition.accuracy,
      'startedAt': startedAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'status': 'active',
    });

    _session = emergencySession;
    _ending = false;
    _expiryTimer = Timer(sessionDuration, () async {
      try {
        await _end(status: 'expired');
      } catch (_) {
        // expiresAt still makes the session expired if the network is offline.
      } finally {
        onExpired();
      }
    });

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
              // Keep the session active until stopped or expired. A later GPS
              // reading can still update the same session.
            },
          );
    } catch (_) {
      // A stream can fail on some devices; the initial fix remains shared.
    }

    return emergencySession;
  }

  Future<void> stop() => _end(status: 'stopped');

  /// Marks a session expired when the app resumes after the expiry time.
  Future<bool> expireIfNeeded() async {
    final currentSession = _session;
    if (currentSession == null ||
        DateTime.now().isBefore(currentSession.expiresAt)) {
      return false;
    }

    try {
      await _end(status: 'expired');
    } catch (_) {
      // The expiry timestamp remains authoritative if the status write fails.
    }
    return true;
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

  Future<void> _end({required String status}) async {
    final currentSession = _session;
    if (currentSession == null || _ending) return;

    _ending = true;
    _session = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    try {
      await _sessionsRef.child(currentSession.id).update({
        'status': status,
        'endedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } finally {
      _ending = false;
    }
  }
}

class EmergencyLocationException implements Exception {
  const EmergencyLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}
