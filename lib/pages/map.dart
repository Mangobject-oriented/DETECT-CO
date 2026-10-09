import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// Offline tile cache + connectivity (new)
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:detectco/services/weather_condition.dart';
import 'package:detectco/services/flood_risk.dart';
import 'package:detectco/services/ml_flood_risk.dart';

// Firebase Realtime Database
import 'package:firebase_database/firebase_database.dart';

import 'package:detectco/main.dart'; // for isDarkModeNotifier

class MapTab extends StatefulWidget {
  const MapTab({
    super.key,
    this.focusRequestId = 0,
    this.focusName,
    this.focusLat,
    this.focusLng,
    this.focusDescription,
  });

  // ===================================================
  // FOCUS REQUEST
  //
  // MapTab is kept alive inside an IndexedStack, so it
  // won't rebuild from scratch when you tap an evacuation
  // card. Instead, BottomNavPage bumps focusRequestId every
  // time a new site is requested; didUpdateWidget below
  // detects that change and re-centers the map even though
  // the widget itself never left the tree.
  // ===================================================

  final int focusRequestId;
  final String? focusName;
  final double? focusLat;
  final double? focusLng;
  final String? focusDescription;

  @override
  State<MapTab> createState() => _MapTabState();
}

// =====================================================
// EVACUATION CENTER STATUS
//
// Static data (assets/data/map_places.json) may carry an
// optional "status" field: "open", "full", "unavailable"
// or "unknown". If it is missing, the center is treated as
// Open by default (set per request: all evacuation centers
// are available). This is a static default, not real-time
// information.
//
// Statuses can also be supplied remotely through the
// Firebase node `evac_status/<place_key>` (read-only here),
// where <place_key> is the lower-case place name with every
// non-alphanumeric run replaced by "_". A remote value
// overrides the static one when present.
// =====================================================

enum EvacStatus { open, full, unavailable, unknown }

EvacStatus? tryParseEvacStatus(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'open':
      return EvacStatus.open;
    case 'full':
      return EvacStatus.full;
    case 'unavailable':
      return EvacStatus.unavailable;
    case 'unknown':
      return EvacStatus.unknown;
    default:
      return null;
  }
}

extension EvacStatusX on EvacStatus {
  String get label {
    switch (this) {
      case EvacStatus.open:
        return 'Open';
      case EvacStatus.full:
        return 'Full';
      case EvacStatus.unavailable:
        return 'Unavailable';
      case EvacStatus.unknown:
        return 'Unknown';
    }
  }

  // Text shown in badges (never relies on color alone).
  String get description {
    switch (this) {
      case EvacStatus.unknown:
        return 'Unknown (not confirmed)';
      default:
        return label;
    }
  }

  IconData get icon {
    switch (this) {
      case EvacStatus.open:
        return Icons.check_circle;
      case EvacStatus.full:
        return Icons.group;
      case EvacStatus.unavailable:
        return Icons.block;
      case EvacStatus.unknown:
        return Icons.help;
    }
  }

  Color get color {
    switch (this) {
      case EvacStatus.open:
        return const Color(0xFF2E7D32);
      case EvacStatus.full:
        return const Color(0xFFEF6C00);
      case EvacStatus.unavailable:
        return const Color(0xFFB71C1C);
      case EvacStatus.unknown:
        return const Color(0xFF546E7A);
    }
  }
}

class EvacSite {
  final String name;
  final String description;
  final String image;
  final LatLng location;
  final EvacStatus status;

  EvacSite({
    required this.name,
    required this.description,
    required this.image,
    required this.location,
    this.status = EvacStatus.open,
  });
}

// =====================================================
// HOSPITAL MODEL
// =====================================================

class Hospital {
  final String name;
  final String description;
  final LatLng location;

  Hospital({
    required this.name,
    required this.description,
    required this.location,
  });
}

// =====================================================
// HELPER MODELS (search + nearest evacuation center)
// =====================================================

class _SearchResult {
  final String name;
  final EvacSite? site;
  final Hospital? hospital;

  const _SearchResult({required this.name, this.site, this.hospital});
}

class _EvacCandidate {
  final EvacSite site;
  final double distanceMeters;
  final EvacStatus status;
  final bool inFloodZone;

  const _EvacCandidate({
    required this.site,
    required this.distanceMeters,
    required this.status,
    required this.inFloodZone,
  });
}

// =====================================================
// OFFLINE TILE CACHE (NEW)
//
// A tiny disk cache that sits behind the existing
// OpenStreetMap TileLayer:
//   * a tile already on disk is read from disk (no network)
//   * otherwise it is downloaded once, shown, and saved
//   * when the device is offline an uncached tile simply
//     fails (the existing tile-error handler shows one
//     gentle message) and the rest of the map keeps working
//
// No extra map package is needed, so the existing
// flutter_map setup is untouched.
// =====================================================

class _TileUnavailable implements Exception {
  const _TileUnavailable();

  @override
  String toString() => 'Tile not cached and device is offline';
}

class _CachedFileInfo {
  final File file;
  final int size;
  final DateTime modified;

  const _CachedFileInfo(this.file, this.size, this.modified);
}

class _OfflineTileProvider extends TileProvider {
  _OfflineTileProvider();

  // Set once the cache folder is ready. Until then tiles
  // simply load from the network without being saved.
  String? cachePath;

  // Updated from the connectivity listener. While true,
  // uncached tiles fail immediately instead of waiting for
  // a network timeout.
  bool offline = false;

  final http.Client _client = http.Client();

  Map<String, String> get _requestHeaders {
    final Map<String, String> h = Map<String, String>.from(headers);
    h.putIfAbsent('User-Agent', () => 'flutter_map (com.detectco.app)');
    return h;
  }

  File? fileFor(int z, int x, int y) {
    final String? p = cachePath;
    if (p == null) return null;
    return File('$p/${z}_${x}_$y.png');
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      url: getTileUrl(coordinates, options),
      file: fileFor(coordinates.z, coordinates.x, coordinates.y),
      provider: this,
    );
  }

  Future<Uint8List> download(String url, File? file) async {
    final http.Response resp = await _client
        .get(Uri.parse(url), headers: _requestHeaders)
        .timeout(const Duration(seconds: 15));

    final String contentType = resp.headers['content-type'] ?? '';

    if (resp.statusCode != 200 ||
        resp.bodyBytes.isEmpty ||
        !contentType.startsWith('image')) {
      throw HttpException('Tile request failed (${resp.statusCode})');
    }

    final Uint8List bytes = resp.bodyBytes;

    if (file != null) {
      await _store(file, bytes);
    }

    return bytes;
  }

  Future<void> _store(File file, Uint8List bytes) async {
    final File tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );

    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('Tile cache write error: $e');
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  // Used by the one-time prefetch. Never throws; returns true
  // when the tile is on disk afterwards.
  Future<bool> ensureTile(int z, int x, int y) async {
    final File? f = fileFor(z, x, y);
    if (f == null) return false;

    try {
      if (await f.exists()) return true;

      await download('https://tile.openstreetmap.org/$z/$x/$y.png', f);
      return true;
    } catch (e) {
      debugPrint('Tile prefetch error: $e');
      return false;
    }
  }

  // Keeps the on-demand high-zoom tiles (z17) from growing
  // without limit. The prefetched area (z12-16) is never
  // touched.
  Future<void> trimDetailTiles({
    int maxBytes = 60 * 1024 * 1024,
    int targetBytes = 40 * 1024 * 1024,
  }) async {
    final String? p = cachePath;
    if (p == null) return;

    try {
      final List<_CachedFileInfo> detail = [];
      int total = 0;

      await for (final FileSystemEntity e in Directory(p).list()) {
        if (e is! File) continue;

        final String name = e.uri.pathSegments.last;
        if (!name.startsWith('17_') || !name.endsWith('.png')) continue;

        final FileStat stat = await e.stat();
        detail.add(_CachedFileInfo(e, stat.size, stat.modified));
        total += stat.size;
      }

      if (total <= maxBytes) return;

      detail.sort((a, b) => a.modified.compareTo(b.modified));

      for (final info in detail) {
        if (total <= targetBytes) break;

        try {
          await info.file.delete();
          total -= info.size;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Tile cache trim error: $e');
    }
  }

  void close() {
    _client.close();
  }
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({
    required this.url,
    required this.file,
    required this.provider,
  });

  final String url;
  final File? file;
  final _OfflineTileProvider provider;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachedTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final File? f = file;

    // 1) Disk first.
    if (f != null) {
      try {
        if (await f.exists()) {
          final Uint8List bytes = await f.readAsBytes();

          if (bytes.isNotEmpty) {
            try {
              return await decode(
                await ui.ImmutableBuffer.fromUint8List(bytes),
              );
            } catch (_) {
              // Corrupt cached file: drop it and fall back to network.
              try {
                await f.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {
        // Fall through to the network.
      }
    }

    // 2) Known offline and not cached: fail fast, no request.
    if (provider.offline) {
      throw const _TileUnavailable();
    }

    // 3) Network, then save to disk.
    final Uint8List bytes = await provider.download(url, f);

    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) {
    return other is _CachedTileImage && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}

// =====================================================
// WEATHER VISUAL MODEL (NEW)
//
// Open-Meteo current weather codes are combined with observed
// precipitation by the shared condition resolver before effects
// are selected. Probability values never trigger precipitation.
// =====================================================

enum _WxKind { none, clear, partly, cloudy, fog, drizzle, rain, thunder, snow }

@immutable
class _WxVisual {
  final _WxKind kind;

  // 1 = light, 2 = moderate, 3 = heavy
  final int level;
  final bool isDay;

  const _WxVisual(this.kind, this.level, this.isDay);

  static const _WxVisual none = _WxVisual(_WxKind.none, 1, true);

  @override
  bool operator ==(Object other) {
    return other is _WxVisual &&
        other.kind == kind &&
        other.level == level &&
        other.isDay == isDay;
  }

  @override
  int get hashCode => Object.hash(kind, level, isDay);
}

_WxVisual _visualForCode(int code, bool isDay, double precipitationMm) {
  final WeatherCondition condition = resolveWeatherCondition(
    weatherCode: code,
    currentPrecipitationMm: precipitationMm,
  );
  final int level = switch (code) {
    0 || 65 || 67 || 75 || 82 || 86 || 96 || 99 => 3,
    1 || 51 || 61 || 71 || 77 || 80 || 95 => 1,
    _ => 2,
  };
  return switch (condition) {
    WeatherCondition.clear =>
      code <= 1 && isDay
          ? _WxVisual(_WxKind.clear, code == 0 ? 2 : 1, isDay)
          : _WxVisual.none,
    WeatherCondition.partlyCloudy => _WxVisual(_WxKind.partly, 1, isDay),
    WeatherCondition.cloudy => _WxVisual(_WxKind.cloudy, 2, isDay),
    WeatherCondition.fog => _WxVisual(_WxKind.fog, 1, isDay),
    WeatherCondition.drizzle => _WxVisual(_WxKind.drizzle, level, isDay),
    WeatherCondition.rain => _WxVisual(_WxKind.rain, level, isDay),
    WeatherCondition.thunderstorm => _WxVisual(_WxKind.thunder, level, isDay),
    WeatherCondition.snow => _WxVisual(_WxKind.snow, level, isDay),
  };
}

bool _isOfflineResult(dynamic result) {
  // connectivity_plus 6.x returns a List, 5.x a single value.
  if (result is List) {
    return result.isEmpty || result.every((e) => e == ConnectivityResult.none);
  }
  return result == ConnectivityResult.none;
}

// =====================================================
// WEATHER OVERLAY WIDGET (NEW)
//
// One CustomPainter, a handful of reusable particles
// (fixed arrays, no widgets), its own RepaintBoundary and
// a throttled ticker (about 8-25 fps depending on effect).
// Wrapped in IgnorePointer so it never touches gestures.
// The ticker stops completely when there is no effect, and
// Flutter mutes it automatically when the tab is not shown.
// =====================================================

class _WxClock extends ChangeNotifier {
  double seconds = 0;

  void tick(double s) {
    seconds = s;
    notifyListeners();
  }
}

class _WeatherOverlay extends StatefulWidget {
  const _WeatherOverlay({required this.visual});

  final _WxVisual visual;

  @override
  State<_WeatherOverlay> createState() => _WeatherOverlayState();
}

class _WeatherOverlayState extends State<_WeatherOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _WxClock _clock = _WxClock();
  late _WeatherPainter _painter;

  Duration _lastTick = Duration.zero;
  int _minMs = 120;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _setup();
  }

  @override
  void didUpdateWidget(covariant _WeatherOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.visual != widget.visual) {
      _setup();
    }
  }

  void _setup() {
    _painter = _WeatherPainter(widget.visual, _clock);

    switch (widget.visual.kind) {
      case _WxKind.rain:
      case _WxKind.drizzle:
      case _WxKind.thunder:
        _minMs = 40;
        break;
      case _WxKind.snow:
        _minMs = 50;
        break;
      default:
        _minMs = 120;
    }

    _lastTick = Duration.zero;

    if (widget.visual.kind == _WxKind.none) {
      if (_ticker.isActive) _ticker.stop();
    } else {
      if (!_ticker.isActive) _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if ((elapsed - _lastTick).inMilliseconds < _minMs) return;

    _lastTick = elapsed;
    _clock.tick(elapsed.inMicroseconds / 1000000.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visual.kind == _WxKind.none) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: SizedBox.expand(
        child: RepaintBoundary(child: CustomPaint(painter: _painter)),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.visual, this._clock) : super(repaint: _clock) {
    _buildParticles();
  }

  final _WxVisual visual;
  final _WxClock _clock;

  // Particle seeds (normalized 0..1), created once.
  late final int _count;
  late final Float32List _sx;
  late final Float32List _sy;
  late final Float32List _sp;
  late final Float32List _sl;

  // Reused drawing buffers (no per-frame allocation).
  late final Float32List _buf;
  late final Float32List _bufSmall;
  late final Float32List _bufLarge;

  Size _size = Size.zero;

  Paint? _sunPaint;
  Paint? _cloudPaint;
  Paint? _fogPaint;

  final Paint _fill = Paint();

  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final Paint _dotPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _buildParticles() {
    final int idx = math.max(0, math.min(2, visual.level - 1));

    int n = 0;

    switch (visual.kind) {
      case _WxKind.rain:
        n = const [38, 52, 68][idx];
        break;
      case _WxKind.thunder:
        n = const [50, 64, 76][idx];
        break;
      case _WxKind.drizzle:
        n = const [16, 22, 28][idx];
        break;
      case _WxKind.snow:
        n = const [26, 38, 50][idx];
        break;
      default:
        n = 0;
    }

    _count = n;

    final math.Random rng = math.Random(11 + visual.kind.index);

    _sx = Float32List(n);
    _sy = Float32List(n);
    _sp = Float32List(n);
    _sl = Float32List(n);

    for (int i = 0; i < n; i++) {
      _sx[i] = rng.nextDouble();
      _sy[i] = rng.nextDouble();
      _sl[i] = rng.nextDouble();

      switch (visual.kind) {
        case _WxKind.drizzle:
          _sp[i] = 0.45 + rng.nextDouble() * 0.2;
          break;
        case _WxKind.snow:
          _sp[i] = 0.07 + rng.nextDouble() * 0.07;
          break;
        default:
          _sp[i] = 0.40 + rng.nextDouble() * 0.25;
      }
    }

    final bool snow = visual.kind == _WxKind.snow;
    final int half = n ~/ 2;

    _buf = Float32List(snow ? 0 : n * 4);
    _bufSmall = Float32List(snow ? half * 2 : 0);
    _bufLarge = Float32List(snow ? (n - half) * 2 : 0);
  }

  void _tint(Canvas canvas, Size size, Color color, double alpha) {
    _fill.color = color.withOpacity(alpha.clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, _fill);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (size != _size) {
      _size = size;
      _sunPaint = null;
      _cloudPaint = null;
      _fogPaint = null;
    }

    final double t = _clock.seconds;

    switch (visual.kind) {
      case _WxKind.clear:
        _paintSun(canvas, size, t, visual.level >= 2 ? 1.0 : 0.6);
        break;

      case _WxKind.partly:
        if (visual.isDay) _paintSun(canvas, size, t, 0.45);
        _paintClouds(canvas, size, t, 0.55, 2, 0.03);
        break;

      case _WxKind.cloudy:
        _paintClouds(canvas, size, t, 0.85, 3, 0.07);
        break;

      case _WxKind.fog:
        _paintFog(canvas, size, t);
        break;

      case _WxKind.drizzle:
        _tint(canvas, size, const Color(0xFF78909C), 0.04);
        _paintRain(
          canvas,
          size,
          t,
          alpha: 0.26 + 0.04 * (visual.level - 1),
          width: 0.9,
          minLen: 8,
          maxLen: 13,
        );
        break;

      case _WxKind.rain:
        _tint(canvas, size, const Color(0xFF78909C), 0.06);
        _paintRain(
          canvas,
          size,
          t,
          alpha: 0.34 + 0.04 * (visual.level - 1),
          width: 1.3,
          minLen: 14,
          maxLen: 24,
        );
        break;

      case _WxKind.thunder:
        _tint(canvas, size, const Color(0xFF263238), 0.10);
        _paintRain(
          canvas,
          size,
          t,
          alpha: 0.38,
          width: 1.4,
          minLen: 15,
          maxLen: 26,
        );

        final double f = _flash(t);
        if (f > 0) {
          _fill.color = Color.fromRGBO(255, 255, 255, 0.20 * f);
          canvas.drawRect(Offset.zero & size, _fill);
        }
        break;

      case _WxKind.snow:
        _paintSnow(canvas, size, t);
        break;

      case _WxKind.none:
        break;
    }
  }

  // ---------------------------------------------------
  // SUN: soft warm glow from the top-right corner.
  // ---------------------------------------------------

  void _paintSun(Canvas canvas, Size size, double t, double strength) {
    _tint(canvas, size, const Color(0xFFFFE9A8), 0.035 * strength);

    _sunPaint ??= Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.88, size.height * 0.02),
        size.width * 1.1,
        const [Color(0x4DFFE08A), Color(0x00FFE08A)],
        const [0.0, 1.0],
      );

    final double pulse = 0.82 + 0.18 * math.sin(t * 0.9);

    _sunPaint!.color = Color.fromRGBO(
      255,
      255,
      255,
      (strength * pulse).clamp(0.0, 1.0),
    );

    canvas.drawRect(Offset.zero & size, _sunPaint!);
  }

  // ---------------------------------------------------
  // CLOUDS: faint gray wash + a few slowly drifting
  // soft blobs (cached radial gradient, no blur filter).
  // ---------------------------------------------------

  void _paintClouds(
    Canvas canvas,
    Size size,
    double t,
    double rel,
    int count,
    double tintAlpha,
  ) {
    _tint(canvas, size, const Color(0xFF78909C), tintAlpha);

    final double r = size.width * 0.42;

    _cloudPaint ??= Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        r,
        const [Color(0x7390A4AE), Color(0x0090A4AE)],
        const [0.0, 1.0],
      );

    _cloudPaint!.color = Color.fromRGBO(255, 255, 255, rel.clamp(0.0, 1.0));

    final double span = size.width + 2 * r;

    for (int i = 0; i < count; i++) {
      final double x = ((i * 0.41 + t * (0.006 + 0.002 * i)) % 1.0) * span - r;
      final double y = size.height * (0.16 + 0.30 * i);

      canvas.save();
      canvas.translate(x, y);
      canvas.scale(1.0, 0.42);
      canvas.drawCircle(Offset.zero, r, _cloudPaint!);
      canvas.restore();
    }
  }

  // ---------------------------------------------------
  // FOG: thin white wash + three slowly sliding bands.
  // ---------------------------------------------------

  void _paintFog(Canvas canvas, Size size, double t) {
    _tint(canvas, size, const Color(0xFFFFFFFF), 0.10);

    final double bandH = size.height * 0.34;

    _fogPaint ??= Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, bandH),
        const [Color(0x00FFFFFF), Color(0x44FFFFFF), Color(0x00FFFFFF)],
        const [0.0, 0.5, 1.0],
      );

    for (int i = 0; i < 3; i++) {
      final double dx = math.sin(t * 0.07 + i * 2.1) * size.width * 0.10;
      final double y = size.height * (0.02 + 0.32 * i);

      canvas.save();
      canvas.translate(dx, y);
      canvas.drawRect(
        Rect.fromLTWH(-size.width * 0.15, 0, size.width * 1.3, bandH),
        _fogPaint!,
      );
      canvas.restore();
    }
  }

  // ---------------------------------------------------
  // RAIN: every streak goes into one reusable buffer and is
  // drawn with a single drawRawPoints call.
  // ---------------------------------------------------

  void _paintRain(
    Canvas canvas,
    Size size,
    double t, {
    required double alpha,
    required double width,
    required double minLen,
    required double maxLen,
  }) {
    final double w = size.width;
    final double h = size.height;

    const double slant = 0.18;

    for (int i = 0; i < _count; i++) {
      final double len = minLen + (maxLen - minLen) * _sl[i];
      final double fy = (_sy[i] + t * _sp[i]) % 1.0;
      final double y = fy * (h + len) - len;
      final double x = (_sx[i] * 1.3 - 0.3) * w + y * slant;

      final int o = i * 4;
      _buf[o] = x;
      _buf[o + 1] = y;
      _buf[o + 2] = x + len * slant;
      _buf[o + 3] = y + len;
    }

    _linePaint
      ..strokeWidth = width
      ..color = const Color(0xFF546E7A).withOpacity(alpha.clamp(0.0, 1.0));

    canvas.drawRawPoints(ui.PointMode.lines, _buf, _linePaint);
  }

  // ---------------------------------------------------
  // LIGHTNING: at most one short double-flash every ~17 s,
  // soft (max 20% white), never rapid.
  // ---------------------------------------------------

  double _flash(double t) {
    const double cycle = 17.0;

    final int n = (t / cycle).floor();
    final double offset = 2.0 + ((n * 7919) % 100) / 100.0 * 11.0;
    final double p = t - n * cycle - offset;

    if (p < 0 || p > 0.6) return 0;

    double tri(double x, double c, double w) {
      final double d = (x - c).abs();
      return d >= w ? 0 : 1 - d / w;
    }

    return math.max(tri(p, 0.06, 0.06), 0.55 * tri(p, 0.30, 0.10));
  }

  // ---------------------------------------------------
  // SNOW: two flake sizes, each drawn in one call, with a
  // faint outline so white flakes stay visible on the map.
  // ---------------------------------------------------

  void _paintSnow(Canvas canvas, Size size, double t) {
    _tint(canvas, size, const Color(0xFF90A4AE), 0.04);

    final double w = size.width;
    final double h = size.height;
    final int half = _count ~/ 2;

    for (int i = 0; i < _count; i++) {
      final double fy = (_sy[i] + t * _sp[i]) % 1.0;
      final double y = fy * (h + 10) - 5;
      final double x = _sx[i] * w + math.sin(t * 0.7 + _sl[i] * 6.283) * 10;

      if (i < half) {
        _bufSmall[i * 2] = x;
        _bufSmall[i * 2 + 1] = y;
      } else {
        final int j = i - half;
        _bufLarge[j * 2] = x;
        _bufLarge[j * 2 + 1] = y;
      }
    }

    _dotPaint.color = const Color(0x40607D8B);
    _dotPaint.strokeWidth = 4.4;
    canvas.drawRawPoints(ui.PointMode.points, _bufSmall, _dotPaint);
    _dotPaint.strokeWidth = 6.0;
    canvas.drawRawPoints(ui.PointMode.points, _bufLarge, _dotPaint);

    _dotPaint.color = const Color(0xE6FFFFFF);
    _dotPaint.strokeWidth = 2.6;
    canvas.drawRawPoints(ui.PointMode.points, _bufSmall, _dotPaint);
    _dotPaint.strokeWidth = 4.0;
    canvas.drawRawPoints(ui.PointMode.points, _bufLarge, _dotPaint);
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter oldDelegate) {
    return oldDelegate.visual != visual;
  }
}

class _MapTabState extends State<MapTab> {
  final mapController = MapController();

  LatLng? currentPosition;

  List<LatLng> routePoints = [];
  EvacSite? selectedSite;
  Hospital? selectedHospital;

  final LatLng swCorner = LatLng(14.13466576727542, 121.00698800147504);

  final LatLng neCorner = LatLng(14.242176187772285, 121.20972008423361);

  late final LatLng calambaCenter = LatLng(
    (swCorner.latitude + neCorner.latitude) / 2,
    (swCorner.longitude + neCorner.longitude) / 2,
  );

  // =====================================================
  // CAMERA BOUNDS WITH BREATHING ROOM
  //
  // Only the camera constraint is padded; swCorner/neCorner
  // and every marker/flood coordinate stay exactly as they
  // were. More room is added on the north side because the
  // search bar + filter chips cover the top of the map, so
  // markers near the northern edge can be panned clear of
  // them.
  // =====================================================
  // TEMP DEBUG: set to a WMO code (e.g. 63 = rain, 95 = thunder, 45 = fog)
  // to force an effect. Set back to null when done.
  static const int? _debugForceCode = 63;

  static const double _boundsPadNorth = 0.010; // ~1.1 km
  static const double _boundsPadOther = 0.004; // ~0.45 km

  late final LatLngBounds _cameraBounds = LatLngBounds(
    LatLng(
      swCorner.latitude - _boundsPadOther,
      swCorner.longitude - _boundsPadOther,
    ),
    LatLng(
      neCorner.latitude + _boundsPadNorth,
      neCorner.longitude + _boundsPadOther,
    ),
  );

  final List<EvacSite> evacSites = [];
  final List<Hospital> hospitals = [];

  bool followMe = false;
  StreamSubscription<Position>? _positionStream;

  // Water rise in centimeters, calculated from the 150 cm sensor baseline.
  double waterLevel = 0;
  bool _waterSensorAvailable = false;

  // Map consumes Home's shared five-minute ML forecast; it must not create a
  // separate API client, URL cache, or prediction timer. Home resolves each
  // request through MlApiConnection and publishes results to this shared store.
  MlForecastSnapshot _mlForecast = MlFloodRiskStore.instance.forecast;

  FloodRiskStatus get _currentFloodRisk =>
      FloodRiskReading.statusForWaterRise(waterLevel);

  MlFloodRiskAssessment get _mlRiskAssessment =>
      MlFloodRiskAssessment.calculate(
        waterRiseCm: waterLevel,
        forecast: _mlForecast,
      );

  final DatabaseReference dbRef = FirebaseDatabase.instance.ref().child(
    'flood',
  );

  late final StreamSubscription<DatabaseEvent> _firebaseSub;

  // =====================================================
  // FLOOD ZONES (same centers/radius as the circles drawn
  // on the map). Used only to rank evacuation centers.
  // =====================================================

  static const List<LatLng> _floodZoneCenters = [
    LatLng(14.234706315729172, 121.17367192746359),
    LatLng(14.209895867059025, 121.18097126019865),
    LatLng(14.215510239402107, 121.18530211042635),
  ];

  static const double _floodZoneRadiusMeters = 600;

  // =====================================================
  // NEW STATE: filters, search, legend, status, messages
  // =====================================================

  bool _showEvacCenters = true;
  bool _showHospitals = true;
  bool _showFloodAreas = true;

  bool _legendExpanded = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _placesLoadFailed = false;
  bool _locating = false;

  final Map<String, EvacStatus> _remoteStatus = {};
  StreamSubscription<DatabaseEvent>? _statusSub;

  String? _lastMessage;
  DateTime? _lastMessageAt;
  DateTime? _lastTileErrorAt;

  // =====================================================
  // OFFLINE MAP + WEATHER STATE (NEW)
  // =====================================================

  // Zoom range cached ahead of time for the DETECT-CO area.
  // z12-16 is roughly 1,000 tiles (about 10-20 MB). Zoom 17 is
  // saved only for places the user actually views, and is
  // trimmed if it grows large. Deeper zoom reuses z17 tiles.
  static const int _prefetchMinZoom = 12;
  static const int _prefetchMaxZoom = 16;
  static const int _tileMaxNativeZoom = 17;

  // Weather is refreshed rarely and never while offline.
  static const Duration _weatherRefreshEvery = Duration(minutes: 20);
  static const Duration _weatherMaxCachedAge = Duration(hours: 6);

  final _OfflineTileProvider _tileProvider = _OfflineTileProvider();

  bool _offline = false;
  bool _prefetching = false;
  bool _fetchingWeather = false;

  _WxVisual _weatherVisual = _WxVisual.none;

  Timer? _weatherTimer;
  StreamSubscription<dynamic>? _connectivitySub;

  // =====================================================
  // LIGHTWEIGHT "GLASS" SURFACE FOR FLOATING CONTROLS
  //
  // Plain translucent fill + hairline border + very small
  // shadow. Deliberately NO BackdropFilter: a live blur
  // over a panning map is re-computed every frame and is
  // costly on low/mid-range Android devices.
  // =====================================================

  BoxDecoration _glassDecoration(bool isDarkMode, {double radius = 14}) {
    return BoxDecoration(
      color: (isDarkMode ? const Color(0xFF2C2C2C) : Colors.white).withOpacity(
        0.85,
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.10),
        width: 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    );
  }

  // =====================================================
  // USER MESSAGES (SnackBar, de-duplicated so errors never
  // spam the screen)
  // =====================================================

  void _showMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;

    final DateTime now = DateTime.now();

    if (_lastMessage == message &&
        _lastMessageAt != null &&
        now.difference(_lastMessageAt!) < const Duration(seconds: 8)) {
      return;
    }

    _lastMessage = message;
    _lastMessageAt = now;

    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );

    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(label: actionLabel, onPressed: onAction)
              : null,
        ),
      );
  }

  // =====================================================
  // TILE ERRORS (shown at most once a minute, no retries)
  // =====================================================

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    final DateTime now = DateTime.now();

    if (_lastTileErrorAt != null &&
        now.difference(_lastTileErrorAt!) < const Duration(seconds: 60)) {
      return;
    }

    _lastTileErrorAt = now;

    debugPrint('Map tile error: $error');

    if (_offline) {
      _showMessage(
        'You are offline. This part of the map has not been saved '
        'for offline use. Places and search still work.',
      );
      return;
    }

    _showMessage(
      'Map tiles could not be loaded. Check your internet '
      'connection. Places and search still work.',
    );
  }

  // =====================================================
  // OFFLINE SUPPORT SETUP (NEW)
  //
  // Prepares the tile cache folder, restores the last known
  // weather, starts watching connectivity and, when online,
  // refreshes the weather and fills the cache for the
  // DETECT-CO area once.
  // =====================================================

  void _setOffline(bool value) {
    _offline = value;
    _tileProvider.offline = value;
  }

  Future<void> _initOfflineSupport() async {
    try {
      final Directory base = await getApplicationSupportDirectory();
      final Directory dir = Directory('${base.path}/detectco_map_cache');

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _tileProvider.cachePath = dir.path;
    } catch (e) {
      // Map still works online without a disk cache.
      debugPrint('Tile cache folder error: $e');
    }

    if (!mounted) return;

    await _loadSavedWeather();

    try {
      final dynamic result = await Connectivity().checkConnectivity();
      _setOffline(_isOfflineResult(result));
    } catch (e) {
      debugPrint('Connectivity check error: $e');
    }

    if (!mounted) return;

    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen((
        dynamic result,
      ) {
        final bool wasOffline = _offline;
        final bool nowOffline = _isOfflineResult(result);

        _setOffline(nowOffline);

        // Only react when we actually come back online.
        if (!nowOffline && wasOffline) {
          _refreshWeather();
          _schedulePrefetch();
        }
      });
    } catch (e) {
      debugPrint('Connectivity listener error: $e');
    }

    _weatherTimer = Timer.periodic(_weatherRefreshEvery, (_) {
      _refreshWeather();
    });

    if (!_offline) {
      _refreshWeather();
      _schedulePrefetch();
    }

    _tileProvider.trimDetailTiles();
  }

  // =====================================================
  // WEATHER (NEW)
  //
  // One small Open-Meteo request for the map center. It is
  // skipped while offline, and the last good result is kept
  // (in memory and in a tiny file) so the effect keeps
  // showing offline.
  // =====================================================

  Future<void> _loadSavedWeather() async {
    final String? root = _tileProvider.cachePath;
    if (root == null) return;

    try {
      final File f = File('$root/weather.json');
      if (!await f.exists()) return;

      final dynamic data = jsonDecode(await f.readAsString());

      final DateTime saved = DateTime.fromMillisecondsSinceEpoch(
        (data['ts'] as num).toInt(),
      );

      if (DateTime.now().difference(saved) > _weatherMaxCachedAge) {
        return;
      }

      if (!mounted) return;

      setState(() {
        _weatherVisual = _visualForCode(
          (data['code'] as num).toInt(),
          data['isDay'] == true,
          (data['precipitation'] as num?)?.toDouble() ?? 0,
        );
      });
    } catch (e) {
      debugPrint('Saved weather read error: $e');
    }
  }

  Future<void> _saveWeather(
    int code,
    bool isDay,
    double precipitationMm,
  ) async {
    final String? root = _tileProvider.cachePath;
    if (root == null) return;

    try {
      await File('$root/weather.json').writeAsString(
        jsonEncode({
          'code': code,
          'isDay': isDay,
          'precipitation': precipitationMm,
          'ts': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      debugPrint('Weather save error: $e');
    }
  }

  Future<void> _refreshWeather() async {
    if (!mounted || _offline || _fetchingWeather) return;

    _fetchingWeather = true;

    try {
      final Uri uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${calambaCenter.latitude.toStringAsFixed(4)}'
        '&longitude=${calambaCenter.longitude.toStringAsFixed(4)}'
        '&current=weather_code,is_day,precipitation,rain'
        '&timezone=auto',
      );

      final http.Response response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw HttpException('Weather status ${response.statusCode}');
      }

      final dynamic data = jsonDecode(response.body);
      final dynamic current = data['current'];

      final int code = (current['weather_code'] as num).toInt();
      final bool isDay = ((current['is_day'] as num?)?.toInt() ?? 1) == 1;
      final double precipitationMm = math
          .max(
            (current['precipitation'] as num?)?.toDouble() ?? 0,
            (current['rain'] as num?)?.toDouble() ?? 0,
          )
          .toDouble();

      _saveWeather(code, isDay, precipitationMm);

      if (!mounted) return;

      debugPrint('Weather code=$code isDay=$isDay');

      final _WxVisual next = _visualForCode(
        _debugForceCode ?? code,
        isDay,
        precipitationMm,
      );

      if (next != _weatherVisual) {
        setState(() {
          _weatherVisual = next;
        });
      }
    } catch (e) {
      // Keep the last known weather. The next attempt is the
      // periodic timer or the next time the connection returns.
      debugPrint('Weather fetch error: $e');
    } finally {
      _fetchingWeather = false;
    }
  }

  // =====================================================
  // ONE-TIME TILE PREFETCH FOR THE DETECT-CO AREA (NEW)
  //
  // Only the original swCorner/neCorner area, zoom 12-16,
  // two tiles at a time with a short pause. Already-saved
  // tiles are skipped, so it resumes after interruptions and
  // is marked done once everything is on disk.
  // =====================================================

  int _lonToTileX(double lon, int z) {
    return ((lon + 180.0) / 360.0 * (1 << z)).floor();
  }

  int _latToTileY(double lat, int z) {
    final double r = lat * math.pi / 180.0;

    return ((1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) /
            2.0 *
            (1 << z))
        .floor();
  }

  List<List<int>> _tilesToPrefetch() {
    final List<List<int>> tiles = [];

    for (int z = _prefetchMinZoom; z <= _prefetchMaxZoom; z++) {
      final int xMin = _lonToTileX(swCorner.longitude, z);
      final int xMax = _lonToTileX(neCorner.longitude, z);
      final int yMin = _latToTileY(neCorner.latitude, z);
      final int yMax = _latToTileY(swCorner.latitude, z);

      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          tiles.add([z, x, y]);
        }
      }
    }

    return tiles;
  }

  void _schedulePrefetch() {
    Future.delayed(const Duration(seconds: 5), _prefetchTiles);
  }

  Future<void> _prefetchTiles() async {
    if (!mounted || _prefetching || _offline) return;

    final String? root = _tileProvider.cachePath;
    if (root == null) return;

    final File marker = File('$root/prefetch_v1.done');

    try {
      if (await marker.exists()) return;
    } catch (_) {
      return;
    }

    _prefetching = true;

    try {
      final List<List<int>> tiles = _tilesToPrefetch();

      int failures = 0;

      for (int i = 0; i < tiles.length; i += 2) {
        if (!mounted || _offline) return;

        final List<bool> results = await Future.wait(
          tiles
              .skip(i)
              .take(2)
              .map((t) => _tileProvider.ensureTile(t[0], t[1], t[2])),
        );

        failures += results.where((ok) => !ok).length;

        // Give up for now; it resumes on the next app start or
        // when the connection returns.
        if (failures >= 5) return;

        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (failures == 0) {
        await marker.writeAsString('ok');
      }
    } catch (e) {
      debugPrint('Tile prefetch error: $e');
    } finally {
      _prefetching = false;
    }
  }

  // =====================================================
  // STATUS HELPERS
  // =====================================================

  String _statusKey(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  EvacStatus _statusFor(EvacSite site) {
    return _remoteStatus[_statusKey(site.name)] ?? site.status;
  }

  void _listenForEvacStatus() {
    try {
      _statusSub = FirebaseDatabase.instance
          .ref()
          .child('evac_status')
          .onValue
          .listen(
            (event) {
              final dynamic value = event.snapshot.value;
              final Map<String, EvacStatus> parsed = {};

              if (value is Map) {
                value.forEach((key, v) {
                  final dynamic raw = v is Map ? v['status'] : v;
                  final EvacStatus? status = tryParseEvacStatus(
                    raw?.toString(),
                  );

                  if (status != null) {
                    parsed[key.toString()] = status;
                  }
                });
              }

              if (!mounted) return;

              setState(() {
                _remoteStatus
                  ..clear()
                  ..addAll(parsed);
              });
            },
            onError: (Object e) {
              // Static / default statuses keep working.
              debugPrint('Evac status listener error: $e');
            },
          );
    } catch (e) {
      debugPrint('Evac status setup error: $e');
    }
  }

  // =====================================================
  // FLOOD ZONE CHECK
  //
  // A place is treated as "inside an active flood-risk area"
  // when the live water rise reaches the 5 cm warning threshold AND the
  // place lies within one of the monitored flood circles.
  // =====================================================

  bool _isInFloodZone(LatLng point) {
    if (_currentFloodRisk == FloodRiskStatus.normal) return false;

    const Distance distance = Distance();

    for (final center in _floodZoneCenters) {
      if (distance.as(LengthUnit.Meter, center, point) <=
          _floodZoneRadiusMeters) {
        return true;
      }
    }

    return false;
  }

  String _floodNote(EvacSite site) {
    if (_isInFloodZone(site.location)) {
      return 'Inside a monitored flood-risk area';
    }

    if (_currentFloodRisk != FloodRiskStatus.normal) {
      return 'Outside monitored flood areas';
    }

    return 'No active flood alert';
  }

  void _showMlRiskDetails(bool isDarkMode) {
    final assessment = _mlRiskAssessment;
    final forecast = _mlForecast;
    const horizons = [1, 3, 6, 12, 24];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF303030) : Colors.white,
        title: Text(
          'ML Flood Risk · ${_waterSensorAvailable ? assessment.label : 'UNAVAILABLE'}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _waterSensorAvailable
                  ? 'Current water rise: ${assessment.waterRiseCm.toStringAsFixed(1)} cm'
                  : 'Current water rise: unavailable (sensor data missing)',
            ),
            Text(
              forecast.currentRainfallMm == null
                  ? 'Current rainfall: unavailable'
                  : 'Current rainfall: ${forecast.currentRainfallMm!.toStringAsFixed(1)} mm',
            ),
            const SizedBox(height: 10),
            for (final horizon in horizons)
              Text(
                '$horizon-hour prediction: ${forecast.predictionsMm[horizon]?.toStringAsFixed(1) ?? '--'} mm',
              ),
            if (forecast.generatedAt != null)
              Text(
                'Updated: ${TimeOfDay.fromDateTime(forecast.generatedAt!).format(context)}',
              ),
            if (!forecast.available)
              const Text(
                'ML forecast is unavailable. Risk uses the current sensor reading.',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    return meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km away'
        : '${meters.toStringAsFixed(0)} m away';
  }

  Future<void> _loadMapPlaces() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/map_places.json',
      );

      final List<dynamic> data = jsonDecode(jsonString);

      final List<EvacSite> loadedEvacSites = [];
      final List<Hospital> loadedHospitals = [];

      for (final item in data) {
        final Map<String, dynamic> place = Map<String, dynamic>.from(
          item as Map,
        );

        final String type = place['type']?.toString() ?? '';

        final double latitude = (place['latitude'] as num).toDouble();
        final double longitude = (place['longitude'] as num).toDouble();

        if (type == 'hospital') {
          loadedHospitals.add(
            Hospital(
              name: place['name']?.toString() ?? '',
              description: place['description']?.toString() ?? '',
              location: LatLng(latitude, longitude),
            ),
          );
        } else {
          loadedEvacSites.add(
            EvacSite(
              name: place['name']?.toString() ?? '',
              description: place['description']?.toString() ?? '',
              image: place['image']?.toString() ?? 'assets/images/evac1.png',
              location: LatLng(latitude, longitude),
              status:
                  tryParseEvacStatus(place['status']?.toString()) ??
                  EvacStatus.open,
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _placesLoadFailed = false;

        evacSites
          ..clear()
          ..addAll(loadedEvacSites);

        hospitals
          ..clear()
          ..addAll(loadedHospitals);
      });
    } catch (e) {
      debugPrint('Map places loading error: $e');

      if (!mounted) return;

      setState(() {
        _placesLoadFailed = true;
      });

      _showMessage(
        'Place information could not be loaded. Search and '
        'nearby-place features are unavailable.',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    MlFloodRiskStore.instance.addListener(_onMlForecastChanged);

    _loadMapPlaces();
    _listenForEvacStatus();

    // Offline tile cache + last-known weather + connectivity.
    _initOfflineSupport();

    _firebaseSub = dbRef.onValue.listen(
      (event) {
        final rawData = event.snapshot.value;
        final data = rawData is Map ? rawData : null;
        final distanceCm = data == null
            ? null
            : FloodRiskReading.parseSensorDistanceCm(data['distance']);

        if (!mounted) return;

        setState(() {
          _waterSensorAvailable = distanceCm != null;
          waterLevel = distanceCm == null
              ? 0
              : FloodRiskReading.waterRiseCm(distanceCm);
        });
      },
      onError: (Object e) {
        debugPrint('Flood data listener error: $e');
        if (mounted) {
          setState(() {
            _waterSensorAvailable = false;
            waterLevel = 0;
          });
        }
      },
    );

    // If we were opened with a focus request already pending
    // (unlikely on first build, but handled for completeness),
    // apply it once the first frame is laid out.
    if (widget.focusLat != null && widget.focusLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusOnRequestedSite();
      });
    }
  }

  void _onMlForecastChanged() {
    if (!mounted) return;
    setState(() => _mlForecast = MlFloodRiskStore.instance.forecast);
  }

  // =====================================================
  // REACT TO NEW FOCUS REQUESTS
  //
  // Because MapTab is kept alive inside an IndexedStack, it
  // is never destroyed/recreated when switching tabs, so
  // initState only runs once. When the Evacuate tab asks to
  // focus on a new site, BottomNavPage rebuilds MapTab with
  // a new focusRequestId; this is what actually triggers the
  // camera move + info panel, even for the map tab hidden in
  // the background.
  // =====================================================

  @override
  void didUpdateWidget(covariant MapTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusRequestId != oldWidget.focusRequestId &&
        widget.focusLat != null &&
        widget.focusLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusOnRequestedSite();
      });
    }
  }

  @override
  void dispose() {
    MlFloodRiskStore.instance.removeListener(_onMlForecastChanged);
    _firebaseSub.cancel();
    _statusSub?.cancel();
    _positionStream?.cancel();
    _connectivitySub?.cancel();
    _weatherTimer?.cancel();
    _tileProvider.close();
    _searchController.dispose();
    super.dispose();
  }

  // =====================================================
  // FOCUS ON A SITE PASSED IN FROM THE EVACUATE TAB
  // =====================================================

  void _focusOnRequestedSite() {
    if (!mounted) return;
    if (widget.focusLat == null || widget.focusLng == null) return;

    final LatLng target = LatLng(widget.focusLat!, widget.focusLng!);

    // Try to match an existing EvacSite by name or by close
    // coordinates, so we reuse its real image/description if
    // one is already defined above.
    EvacSite? match;

    for (final site in evacSites) {
      final bool sameName =
          widget.focusName != null &&
          site.name.toLowerCase() == widget.focusName!.toLowerCase();

      final bool sameSpot =
          (site.location.latitude - target.latitude).abs() < 0.0005 &&
          (site.location.longitude - target.longitude).abs() < 0.0005;

      if (sameName || sameSpot) {
        match = site;
        break;
      }
    }

    final EvacSite site =
        match ??
        EvacSite(
          name: widget.focusName ?? 'Evacuation Center',
          description: widget.focusDescription ?? '',
          image: 'assets/images/evac1.png',
          location: target,
        );

    setState(() {
      selectedSite = site;
      _showEvacCenters = true;
    });

    mapController.move(site.location, 16);

    if (currentPosition != null) {
      getRoute(currentPosition!, site.location);
    }

    _showEvacPanel(site);
  }

  // =====================================================
  // GET ROUTE
  //
  // Single request with a timeout. On failure the user gets
  // a simple message; there is no automatic retry.
  // =====================================================

  Future<void> getRoute(LatLng start, LatLng end) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final routes = data['routes'];

        if (routes is! List || routes.isEmpty) {
          _showMessage('No route could be found to this place.');
          return;
        }

        final coords = routes[0]['geometry']['coordinates'];

        if (!mounted) return;

        setState(() {
          routePoints = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
        });
      } else {
        debugPrint('Route API status: ${response.statusCode}');
        _showMessage(
          'Routing is temporarily unavailable. Please try again later.',
        );
      }
    } on TimeoutException catch (e) {
      debugPrint('Route API timeout: $e');
      _showMessage(
        'Routing is temporarily unavailable. Please check your '
        'internet connection and try again later.',
      );
    } catch (e) {
      debugPrint('Route API error: $e');
      _showMessage(
        'Routing is temporarily unavailable. Please check your '
        'internet connection and try again later.',
      );
    }
  }

  // =====================================================
  // SELECT AN EVACUATION SITE (move map + route)
  // =====================================================

  void _selectEvacSite(EvacSite site) {
    setState(() {
      selectedSite = site;
      _showEvacCenters = true;
    });

    mapController.move(site.location, 16);

    if (currentPosition != null) {
      getRoute(currentPosition!, site.location);
    }
  }

  // =====================================================
  // GO TO NEAREST APPROPRIATE EVACUATION SITE
  //
  // User location
  //   -> available evacuation centers (Full / Unavailable
  //      are excluded)
  //   -> flood-risk information (centers inside an active
  //      monitored flood area are ranked lower)
  //   -> distance
  //   -> present suitable evacuation centers
  // =====================================================

  Future<void> _goToNearestEvac() async {
    if (evacSites.isEmpty) {
      _showMessage(
        _placesLoadFailed
            ? 'Evacuation center information is unavailable right now.'
            : 'No evacuation centers are loaded yet.',
      );
      return;
    }

    if (currentPosition == null) {
      final bool located = await _locateMe();
      if (!located || currentPosition == null || !mounted) return;
    }

    const Distance distance = Distance();

    final List<_EvacCandidate> candidates = [];

    for (final site in evacSites) {
      final EvacStatus status = _statusFor(site);

      if (status == EvacStatus.full || status == EvacStatus.unavailable) {
        continue;
      }

      candidates.add(
        _EvacCandidate(
          site: site,
          distanceMeters: distance.as(
            LengthUnit.Meter,
            currentPosition!,
            site.location,
          ),
          status: status,
          inFloodZone: _isInFloodZone(site.location),
        ),
      );
    }

    if (candidates.isEmpty) {
      _showMessage(
        'No available evacuation center was found. All known '
        'centers are marked Full or Unavailable.',
      );
      return;
    }

    candidates.sort((a, b) {
      if (a.inFloodZone != b.inFloodZone) {
        return a.inFloodZone ? 1 : -1;
      }

      final int aRank = a.status == EvacStatus.open ? 0 : 1;
      final int bRank = b.status == EvacStatus.open ? 0 : 1;

      if (aRank != bRank) return aRank - bRank;

      return a.distanceMeters.compareTo(b.distanceMeters);
    });

    final EvacSite best = candidates.first.site;

    _selectEvacSite(best);

    _showNearestEvacSheet(candidates.take(3).toList());
  }

  // =====================================================
  // GO TO NEAREST HOSPITAL
  // =====================================================

  Future<void> _goToNearestHospital() async {
    if (hospitals.isEmpty) {
      _showMessage(
        _placesLoadFailed
            ? 'Hospital information is unavailable right now.'
            : 'No hospitals are loaded yet.',
      );
      return;
    }

    if (currentPosition == null) {
      final bool located = await _locateMe();
      if (!located || currentPosition == null || !mounted) return;
    }

    final Distance distance = Distance();

    Hospital nearest = hospitals[0];
    double minDist = double.infinity;

    for (final hospital in hospitals) {
      final dist = distance.as(
        LengthUnit.Meter,
        currentPosition!,
        hospital.location,
      );

      if (dist < minDist) {
        minDist = dist;
        nearest = hospital;
      }
    }

    setState(() {
      selectedHospital = nearest;
      _showHospitals = true;
    });

    mapController.move(nearest.location, 16);

    getRoute(currentPosition!, nearest.location);

    _showHospitalPanel(nearest, minDist);
  }

  // =====================================================
  // STATUS BADGE (icon + text, not color only)
  // =====================================================

  Widget _statusChip(EvacStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 16, color: status.color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Status: ${status.description}',
              style: TextStyle(
                color: status.color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // NEAREST APPROPRIATE EVACUATION CENTER SHEET
  // =====================================================

  void _showNearestEvacSheet(List<_EvacCandidate> candidates) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ValueListenableBuilder<bool>(
          valueListenable: isDarkModeNotifier,
          builder: (context, isDarkMode, child) {
            final Color panelBackground = isDarkMode
                ? const Color(0xFF2C2C2C)
                : Colors.white;

            final Color titleColor = isDarkMode
                ? Colors.white
                : const Color(0xFF1D2B4A);

            final Color subtitleColor = isDarkMode
                ? Colors.grey[400]!
                : const Color(0xFF5A6B8C);

            const Color accent = Color(0xFF2867F5);

            return Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: panelBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearest Appropriate Evacuation Center',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Centers marked Full or Unavailable are left out. '
                        'Centers inside an active flood-risk area are '
                        'ranked lower.',
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < candidates.length; i++)
                        _buildCandidateTile(
                          context,
                          candidates[i],
                          i == 0,
                          titleColor,
                          subtitleColor,
                          accent,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'This is based on the information available in the '
                        'app and does not guarantee that a location is safe. '
                        'Always follow official advisories.',
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCandidateTile(
    BuildContext sheetContext,
    _EvacCandidate c,
    bool recommended,
    Color titleColor,
    Color subtitleColor,
    Color accent,
  ) {
    return Semantics(
      button: true,
      label:
          '${recommended ? "Recommended. " : ""}${c.site.name}, '
          '${_formatDistance(c.distanceMeters)}, '
          'status ${c.status.description}, ${_floodNote(c.site)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pop(sheetContext);

          if (!identical(c.site, selectedSite)) {
            _selectEvacSite(c.site);
          }

          _showEvacPanel(c.site);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: recommended ? accent : subtitleColor.withOpacity(0.4),
              width: recommended ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(recommended ? Icons.star : Icons.place, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recommended)
                      Text(
                        'RECOMMENDED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    Text(
                      c.site.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDistance(c.distanceMeters)}  •  '
                      'Status: ${c.status.description}',
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                    Text(
                      _floodNote(c.site),
                      style: TextStyle(
                        fontSize: 12,
                        color: c.inFloodZone
                            ? const Color(0xFFB71C1C)
                            : subtitleColor,
                        fontWeight: c.inFloodZone
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // EVACUATION SITE PANEL
  //
  // Wrapped in a ValueListenableBuilder so the sheet's
  // background, text and buttons follow isDarkModeNotifier
  // instead of being hardcoded to light mode.
  // =====================================================

  void _showEvacPanel(EvacSite site) {
    String riskText;
    Color riskColor;

    if (_currentFloodRisk == FloodRiskStatus.critical) {
      riskText = "CRITICAL";
      riskColor = const Color.fromRGBO(244, 67, 54, 1);
    } else if (_currentFloodRisk == FloodRiskStatus.warning) {
      riskText = "FLOODING";
      riskColor = Colors.orange;
    } else {
      riskText = "SAFE";
      riskColor = const Color.fromRGBO(76, 175, 80, 1);
    }

    final EvacStatus siteStatus = _statusFor(site);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ValueListenableBuilder<bool>(
          valueListenable: isDarkModeNotifier,
          builder: (context, isDarkMode, child) {
            // =====================================================
            // THEME-AWARE COLORS FOR THIS PANEL
            // =====================================================

            final Color panelBackground = isDarkMode
                ? const Color(0xFF2C2C2C)
                : Colors.white;

            final Color titleColor = isDarkMode
                ? Colors.white
                : const Color(0xFF1D2B4A);

            final Color subtitleColor = isDarkMode
                ? Colors.grey[400]!
                : const Color(0xFF5A6B8C);

            final Color primaryButtonColor = const Color(0xFF2867F5);

            return Container(
              height: MediaQuery.of(context).size.height * 0.55,
              width: double.infinity,
              decoration: BoxDecoration(
                color: panelBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    child: Image.asset(
                      site.image,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Scrollable info area so the extra status
                          // badge can never overflow small screens.
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // =====================================
                                  // SITE NAME
                                  // =====================================

                                  Text(
                                    site.name,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: titleColor,
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // =====================================
                                  // SITE DESCRIPTION
                                  // =====================================
                                  Text(
                                    site.description,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: subtitleColor,
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: riskColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(color: riskColor),
                                        ),
                                        child: Text(
                                          "Flood Risk: $riskText",
                                          style: TextStyle(
                                            color: riskColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),

                                      // =================================
                                      // EVACUATION CENTER STATUS
                                      // =================================
                                      _statusChip(siteStatus),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // =====================================
                          // GO TO LOCATION BUTTON
                          // =====================================
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (currentPosition != null) {
                                  getRoute(currentPosition!, site.location);
                                } else {
                                  _showMessage(
                                    'Turn on location to see a route '
                                    'from where you are.',
                                  );
                                }

                                mapController.move(site.location, 16);

                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.directions),
                              label: const Text("Go to Location"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryButtonColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // =====================================
                          // DIRECTIONS FROM ME BUTTON
                          // =====================================
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (currentPosition != null) {
                                  getRoute(currentPosition!, site.location);

                                  mapController.move(currentPosition!, 16);
                                } else {
                                  // Ask for location only now that the
                                  // user explicitly wants directions.
                                  _locateMe().then((located) {
                                    if (located && currentPosition != null) {
                                      getRoute(currentPosition!, site.location);
                                    }
                                  });
                                }

                                Navigator.pop(context);
                              },
                              icon: Icon(
                                Icons.navigation,
                                color: primaryButtonColor,
                              ),
                              label: Text(
                                "Directions from Me",
                                style: TextStyle(
                                  color: primaryButtonColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: primaryButtonColor,
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // =====================================================
  // HOSPITAL PANEL
  //
  // Same theme-aware treatment as the evacuation panel.
  // =====================================================

  void _showHospitalPanel(Hospital hospital, double distanceMeters) {
    // A distance of 0 means the user's location is not known.
    final String distanceLabel = distanceMeters <= 0
        ? 'Distance unavailable (location off)'
        : distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km away'
        : '${distanceMeters.toStringAsFixed(0)} m away';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ValueListenableBuilder<bool>(
          valueListenable: isDarkModeNotifier,
          builder: (context, isDarkMode, child) {
            final Color panelBackground = isDarkMode
                ? const Color(0xFF2C2C2C)
                : Colors.white;

            final Color titleColor = isDarkMode
                ? Colors.white
                : const Color(0xFF1D2B4A);

            final Color subtitleColor = isDarkMode
                ? Colors.grey[400]!
                : const Color(0xFF5A6B8C);

            const Color hospitalColor = Color(0xFFFF3035);

            return Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: BoxDecoration(
                color: panelBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: hospitalColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_hospital,
                          color: hospitalColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // =============================================
                            // HOSPITAL NAME
                            // =============================================

                            Text(
                              hospital.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 2),

                            // =============================================
                            // HOSPITAL DESCRIPTION
                            // =============================================
                            Text(
                              hospital.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Text(
                      distanceLabel,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // =====================================
                  // GO TO HOSPITAL BUTTON
                  // =====================================
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (currentPosition != null) {
                          getRoute(currentPosition!, hospital.location);
                        } else {
                          _showMessage(
                            'Turn on location to see a route '
                            'from where you are.',
                          );
                        }
                        mapController.move(hospital.location, 16);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.directions),
                      label: const Text("Go to Hospital"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hospitalColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // =====================================================
  // LEGEND ITEM
  // =====================================================

  Widget _legendItem(Color color, String text, bool isDarkMode) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),

        const SizedBox(width: 6),

        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }

  // LEGEND ITEM WITH A CUSTOM SYMBOL (used by the expandable part)
  Widget _legendSymbolItem(Widget symbol, String text, bool isDarkMode) {
    return Row(
      children: [
        SizedBox(width: 18, height: 18, child: Center(child: symbol)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendExtras(bool isDarkMode) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140, maxHeight: 200),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _legendSymbolItem(
              Image.asset('assets/icon/evacsite.png', width: 18, height: 18),
              'Evacuation Center',
              isDarkMode,
            ),
            const SizedBox(height: 4),
            _legendSymbolItem(
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3035),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_hospital,
                  color: Colors.white,
                  size: 11,
                ),
              ),
              'Hospital',
              isDarkMode,
            ),
            const SizedBox(height: 4),
            _legendSymbolItem(
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4A7FF7),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 2),
                  ],
                ),
              ),
              'Your Location',
              isDarkMode,
            ),
            const SizedBox(height: 4),
            _legendSymbolItem(
              Container(width: 18, height: 4, color: const Color(0xFF4A7FF7)),
              'Route',
              isDarkMode,
            ),
            const SizedBox(height: 4),
            _legendSymbolItem(
              Icon(
                Icons.circle_outlined,
                size: 16,
                color: isDarkMode ? Colors.white : Colors.black54,
              ),
              'Shaded circle: monitored flood area (color = risk)',
              isDarkMode,
            ),
            const SizedBox(height: 6),
            Text(
              'Evacuation center status',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            for (final status in EvacStatus.values) ...[
              _legendSymbolItem(
                Icon(status.icon, size: 16, color: status.color),
                status.label,
                isDarkMode,
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  // =====================================================
  // SEARCH BAR, FILTER CHIPS AND SEARCH RESULTS
  // =====================================================

  Widget _buildSearchBar(bool isDarkMode) {
    final Color textColor = isDarkMode ? Colors.white : Colors.black;

    return Positioned(
      top: 8,
      left: 10,
      right: 10,
      child: Container(
        height: 40,
        decoration: _glassDecoration(isDarkMode, radius: 12),
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(color: textColor),
          onChanged: (value) {
            setState(() {
              _searchQuery = value.trim();
            });
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search evacuation centers or hospitals',
            hintStyle: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 20,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    required bool isDarkMode,
  }) {
    final Color cardColor = isDarkMode ? const Color(0xFF2C2C2C) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : const Color(0xFF1D2B4A);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        selected: selected,
        showCheckmark: true,
        checkmarkColor: textColor,
        backgroundColor: cardColor.withOpacity(0.85),
        selectedColor: const Color(0xFF4A7FF7).withOpacity(0.35),
        side: BorderSide(
          color: selected ? const Color(0xFF4A7FF7) : Colors.grey,
        ),
        // 32 px tall, no invisible 48 px padding band over the map.
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        tooltip: selected ? 'Hide $label' : 'Show $label',
        onSelected: onSelected,
      ),
    );
  }

  Widget _buildFilterChips(bool isDarkMode) {
    return Positioned(
      top: 54,
      left: 10,
      right: 10,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip(
              label: 'Evacuation Centers',
              selected: _showEvacCenters,
              isDarkMode: isDarkMode,
              onSelected: (v) => setState(() => _showEvacCenters = v),
            ),
            _filterChip(
              label: 'Hospitals',
              selected: _showHospitals,
              isDarkMode: isDarkMode,
              onSelected: (v) => setState(() => _showHospitals = v),
            ),
            _filterChip(
              label: 'Flood Areas',
              selected: _showFloodAreas,
              isDarkMode: isDarkMode,
              onSelected: (v) => setState(() => _showFloodAreas = v),
            ),
          ],
        ),
      ),
    );
  }

  List<_SearchResult> _computeSearchResults() {
    final String q = _searchQuery.toLowerCase();

    if (q.isEmpty) return const [];

    final List<_SearchResult> results = [];

    for (final site in evacSites) {
      if (site.name.toLowerCase().contains(q)) {
        results.add(_SearchResult(name: site.name, site: site));
      }
    }

    for (final hospital in hospitals) {
      if (hospital.name.toLowerCase().contains(q)) {
        results.add(_SearchResult(name: hospital.name, hospital: hospital));
      }
    }

    return results.take(8).toList();
  }

  void _onSearchResultTap(_SearchResult result) {
    FocusScope.of(context).unfocus();
    _searchController.clear();

    if (result.site != null) {
      final EvacSite site = result.site!;

      setState(() {
        _searchQuery = '';
        _showEvacCenters = true;
        selectedSite = site;
      });

      mapController.move(site.location, 16);
      _showEvacPanel(site);
    } else if (result.hospital != null) {
      final Hospital hospital = result.hospital!;

      final double dist = currentPosition != null
          ? const Distance().as(
              LengthUnit.Meter,
              currentPosition!,
              hospital.location,
            )
          : 0;

      setState(() {
        _searchQuery = '';
        _showHospitals = true;
        selectedHospital = hospital;
      });

      mapController.move(hospital.location, 16);
      _showHospitalPanel(hospital, dist);
    }
  }

  Widget _buildSearchResults(bool isDarkMode) {
    if (_searchQuery.isEmpty) return const SizedBox.shrink();

    final Color cardColor = isDarkMode ? const Color(0xFF2C2C2C) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;
    final Color subColor = isDarkMode ? Colors.grey[400]! : Colors.grey[700]!;

    final List<_SearchResult> results = _computeSearchResults();

    Widget content;

    if (results.isEmpty) {
      final bool noData =
          _placesLoadFailed || (evacSites.isEmpty && hospitals.isEmpty);

      content = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          noData
              ? 'Place information is unavailable right now.'
              : 'No places match "$_searchQuery".',
          style: TextStyle(color: textColor),
        ),
      );
    } else {
      content = ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final _SearchResult r = results[index];
          final bool isHospital = r.hospital != null;

          final String subtitle = isHospital
              ? 'Hospital'
              : 'Evacuation Center  •  Status: '
                    '${_statusFor(r.site!).label}';

          return ListTile(
            leading: Icon(
              isHospital ? Icons.local_hospital : Icons.place,
              color: isHospital
                  ? const Color(0xFFFF3035)
                  : const Color(0xFF4A7FF7),
            ),
            title: Text(
              r.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(color: subColor, fontSize: 12),
            ),
            onTap: () => _onSearchResultTap(r),
          );
        },
      );
    }

    return Positioned(
      top: 52,
      left: 10,
      right: 10,
      child: Material(
        elevation: 4,
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: content,
        ),
      ),
    );
  }

  // =====================================================
  // LOCATE USER
  //
  // Returns true when a position was obtained. Every failure
  // shows a simple, non-blocking message. Permission is only
  // requested here, in response to a user action, and never
  // in a loop.
  // =====================================================

  Future<bool> _locateMe() async {
    if (_locating) return false;
    _locating = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        _showMessage(
          'Location services are turned off. Turn on GPS to use '
          'location features.',
          actionLabel: 'Settings',
          onAction: () {
            Geolocator.openLocationSettings();
          },
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied.');
        _showMessage(
          'Location permission is blocked. Enable it in app '
          'settings to use location features.',
          actionLabel: 'Open Settings',
          onAction: () {
            Geolocator.openAppSettings();
          },
        );
        return false;
      }

      if (permission == LocationPermission.denied) {
        debugPrint('Location permission denied.');
        _showMessage(
          'Location permission is required for location-based '
          'features. The map still works without it.',
        );
        return false;
      }

      final pos = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 20),
      );

      if (!mounted) return false;

      setState(() {
        currentPosition = LatLng(pos.latitude, pos.longitude);

        followMe = true;
      });

      mapController.move(currentPosition!, 16);

      return true;
    } on TimeoutException catch (e) {
      debugPrint('Location timeout: $e');
      _showMessage(
        'Your location is temporarily unavailable. You can keep '
        'using the map.',
      );
      return false;
    } catch (e) {
      debugPrint('Location error: $e');
      _showMessage(
        'Your location is temporarily unavailable. You can keep '
        'using the map.',
      );
      return false;
    } finally {
      _locating = false;
    }
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        return Scaffold(
          backgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,

          body: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================

              Container(
                color: isDarkMode
                    ? const Color(0xFF212121)
                    : const Color.fromARGB(255, 72, 119, 247),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        // LOGO

                        GestureDetector(
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Image.asset(
                              "assets/icon/detect-co_logo.png",
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // APP NAME
                        const Text(
                          'Map',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================================
              // MAP
              // =================================================
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: mapController,

                      options: MapOptions(
                        initialCenter: calambaCenter,
                        initialZoom: 13.5,
                        minZoom: 11,
                        maxZoom: 17,
                        cameraConstraint: CameraConstraint.contain(
                          bounds: _cameraBounds,
                        ),
                      ),

                      children: [
                        // =================================================
                        // OPENSTREETMAP TILES
                        //
                        // Same OSM source as before, now read through the
                        // small disk cache so visited/prefetched tiles keep
                        // working offline. Zoom levels above 17 reuse the
                        // cached z17 tiles instead of requesting new ones.
                        // =================================================

                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.detectco.app',
                          tileProvider: _tileProvider,
                          maxNativeZoom: _tileMaxNativeZoom,
                          errorTileCallback: _onTileError,
                        ),

                        // =================================================
                        // WEATHER EFFECT (NEW)
                        //
                        // Sits above the tiles but below flood circles,
                        // route and markers. IgnorePointer + its own
                        // RepaintBoundary: it never blocks gestures and
                        // never repaints the map.
                        // =================================================
                        _WeatherOverlay(visual: _weatherVisual),

                        // =================================================
                        // FLOOD ZONES (toggled by the "Flood Areas" filter)
                        // =================================================
                        if (_showFloodAreas)
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: LatLng(
                                  14.234706315729172,
                                  121.17367192746359,
                                ),
                                radius: 600,
                                useRadiusInMeter: true,
                                color:
                                    _currentFloodRisk == FloodRiskStatus.normal
                                    ? Colors.green.withOpacity(0.35)
                                    : _currentFloodRisk ==
                                          FloodRiskStatus.warning
                                    ? Colors.orange.withOpacity(0.35)
                                    : const Color.fromRGBO(
                                        244,
                                        67,
                                        54,
                                        1,
                                      ).withOpacity(0.35),
                                borderColor:
                                    _currentFloodRisk == FloodRiskStatus.normal
                                    ? Colors.green
                                    : _currentFloodRisk ==
                                          FloodRiskStatus.warning
                                    ? Colors.orange
                                    : const Color.fromRGBO(244, 67, 54, 1),
                                borderStrokeWidth: 2,
                              ),

                              CircleMarker(
                                point: LatLng(
                                  14.209895867059025,
                                  121.18097126019865,
                                ),
                                radius: 600,
                                useRadiusInMeter: true,
                                color:
                                    _currentFloodRisk == FloodRiskStatus.normal
                                    ? Colors.green.withOpacity(0.35)
                                    : _currentFloodRisk ==
                                          FloodRiskStatus.warning
                                    ? Colors.orange.withOpacity(0.35)
                                    : const Color.fromRGBO(
                                        244,
                                        67,
                                        54,
                                        1,
                                      ).withOpacity(0.35),
                                borderColor:
                                    _currentFloodRisk == FloodRiskStatus.normal
                                    ? Colors.green
                                    : _currentFloodRisk ==
                                          FloodRiskStatus.warning
                                    ? Colors.orange
                                    : const Color.fromRGBO(244, 67, 54, 1),
                                borderStrokeWidth: 2,
                              ),

                              CircleMarker(
                                point: LatLng(
                                  14.215510239402107,
                                  121.18530211042635,
                                ),
                                radius: 600,
                                useRadiusInMeter: true,
                                color:
                                    _currentFloodRisk == FloodRiskStatus.normal
                                    ? Colors.green.withOpacity(0.35)
                                    : _currentFloodRisk ==
                                          FloodRiskStatus.warning
                                    ? Colors.orange.withOpacity(0.35)
                                    : const Color.fromRGBO(
                                        244,
                                        67,
                                        54,
                                        1,
                                      ).withOpacity(0.35),
                                borderColor:
                                    _currentFloodRisk == FloodRiskStatus.normal
                                    ? Colors.green
                                    : _currentFloodRisk ==
                                          FloodRiskStatus.warning
                                    ? Colors.orange
                                    : const Color.fromRGBO(244, 67, 54, 1),
                                borderStrokeWidth: 2,
                              ),
                            ],
                          ),

                        // =================================================
                        // ROUTE
                        // =================================================
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              strokeWidth: 4,
                              color: const Color(0xFF4A7FF7),
                            ),
                          ],
                        ),

                        // =================================================
                        // MARKERS
                        // =================================================
                        MarkerLayer(
                          markers: [
                            if (currentPosition != null)
                              Marker(
                                point: currentPosition!,
                                width: 28,
                                height: 28,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF4A7FF7),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            if (_showEvacCenters)
                              for (final site in evacSites)
                                Marker(
                                  point: site.location,
                                  width: 45,
                                  height: 45,
                                  child: Semantics(
                                    button: true,
                                    label:
                                        'Evacuation center ${site.name}, '
                                        'status ${_statusFor(site).label}',
                                    child: GestureDetector(
                                      onTap: () => _showEvacPanel(site),
                                      child: Container(
                                        // Ring marks the selected center.
                                        decoration:
                                            (selectedSite != null &&
                                                selectedSite!.location ==
                                                    site.location)
                                            ? BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFF2867F5,
                                                  ),
                                                  width: 3,
                                                ),
                                              )
                                            : null,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned.fill(
                                              child: Image.asset(
                                                'assets/icon/evacsite.png',
                                              ),
                                            ),
                                            // Small status icon (not color only);
                                            // hidden while status is Unknown.
                                            if (_statusFor(site) !=
                                                EvacStatus.unknown)
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: Container(
                                                  width: 18,
                                                  height: 18,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Colors.white,
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: Icon(
                                                    _statusFor(site).icon,
                                                    size: 16,
                                                    color: _statusFor(
                                                      site,
                                                    ).color,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                            // ===== HOSPITAL MARKERS =====
                            if (_showHospitals)
                              for (final hospital in hospitals)
                                Marker(
                                  point: hospital.location,
                                  width: 44,
                                  height: 44,
                                  child: Semantics(
                                    button: true,
                                    label: 'Hospital ${hospital.name}',
                                    child: GestureDetector(
                                      onTap: () {
                                        final Distance distance = Distance();
                                        final double dist =
                                            currentPosition != null
                                            ? distance.as(
                                                LengthUnit.Meter,
                                                currentPosition!,
                                                hospital.location,
                                              )
                                            : 0;
                                        _showHospitalPanel(hospital, dist);
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF3035),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.local_hospital,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),

                    Positioned(
                      left: 10,
                      right: 58,
                      bottom: 74,
                      child: GestureDetector(
                        onTap: () => _showMlRiskDetails(isDarkMode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 9,
                          ),
                          decoration: _glassDecoration(isDarkMode, radius: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.analytics_rounded,
                                size: 19,
                                color: !_waterSensorAvailable
                                    ? Colors.grey
                                    : switch (_mlRiskAssessment.level) {
                                        MlFloodRiskLevel.low =>
                                          Colors.greenAccent,
                                        MlFloodRiskLevel.moderate =>
                                          Colors.orangeAccent,
                                        MlFloodRiskLevel.high =>
                                          Colors.redAccent,
                                      },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'ML FLOOD RISK · ${_waterSensorAvailable ? _mlRiskAssessment.label : 'UNAVAILABLE'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_waterSensorAvailable ? 'Rise ${waterLevel.toStringAsFixed(1)} cm' : 'Sensor unavailable'} · '
                                      '1h ${_mlForecast.rainfall1hMm?.toStringAsFixed(1) ?? '--'} mm · '
                                      '3h ${_mlForecast.rainfall3hMm?.toStringAsFixed(1) ?? '--'} mm',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey[300],
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.info_outline,
                                color: Colors.white70,
                                size: 17,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // =====================================================
                    // GPS + NEAREST BUTTONS
                    // =====================================================

                    // TOP-RIGHT: EVACUATION + HOSPITAL BUTTONS
                    // (sits just below search + filter chips; compact
                    //  40 px pills that size to their content)
                    Positioned(
                      top: 94,
                      right: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // ===== NEAREST EVACUATION CENTER BUTTON =====
                          SizedBox(
                            height: 40,
                            child: FloatingActionButton.extended(
                              heroTag: 'nearest',
                              tooltip:
                                  'Find nearest appropriate evacuation center',
                              backgroundColor: const Color.fromARGB(
                                255,
                                129,
                                160,
                                247,
                              ),
                              elevation: 2,
                              highlightElevation: 3,
                              extendedPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              extendedIconLabelSpacing: 6,
                              onPressed: _goToNearestEvac,
                              icon: const Icon(
                                Icons.place,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: const Text(
                                'Evacuation Center',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // ===== NEAREST HOSPITAL BUTTON =====
                          SizedBox(
                            height: 40,
                            child: FloatingActionButton.extended(
                              heroTag: 'nearest_hospital',
                              tooltip: 'Find nearest hospital',
                              backgroundColor: const Color(0xFFFF3035),
                              elevation: 2,
                              highlightElevation: 3,
                              extendedPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              extendedIconLabelSpacing: 6,
                              onPressed: _goToNearestHospital,
                              icon: const Icon(
                                Icons.local_hospital,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: const Text(
                                'Hospital',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // BOTTOM-RIGHT: LOCATE ME
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: FloatingActionButton(
                        heroTag: 'gps',
                        tooltip: 'Show my location',
                        mini: true,
                        elevation: 2,
                        highlightElevation: 3,
                        backgroundColor: const Color.fromARGB(
                          255,
                          245,
                          245,
                          245,
                        ),
                        onPressed: _locateMe,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                        ),
                      ),
                    ),

                    // =================================================
                    // LEGEND
                    // (sits just below search + filter chips; the three
                    //  flood items stay always visible, the other
                    //  symbols open/close with "Map symbols")
                    // =================================================
                    Positioned(
                      top: 94,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: _glassDecoration(isDarkMode, radius: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _legendItem(
                              Colors.green,
                              "Normal · 0–4 cm rise",
                              isDarkMode,
                            ),

                            const SizedBox(height: 4),

                            _legendItem(
                              Colors.orange,
                              "Flooding · 5–40 cm rise",
                              isDarkMode,
                            ),

                            const SizedBox(height: 4),

                            _legendItem(
                              Colors.red,
                              "Critical · >40 cm rise",
                              isDarkMode,
                            ),

                            // OPEN / CLOSE EXTRA SYMBOLS
                            Semantics(
                              button: true,
                              label: _legendExpanded
                                  ? 'Hide map symbols'
                                  : 'Show map symbols',
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _legendExpanded = !_legendExpanded;
                                  });
                                },
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 36,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Map symbols',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDarkMode
                                              ? Colors.white
                                              : const Color(0xFF2867F5),
                                        ),
                                      ),
                                      Icon(
                                        _legendExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 18,
                                        color: isDarkMode
                                            ? Colors.white
                                            : const Color(0xFF2867F5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            if (_legendExpanded) _buildLegendExtras(isDarkMode),
                          ],
                        ),
                      ),
                    ),

                    // =================================================
                    // SEARCH + FILTERS (results drawn last, on top)
                    // =================================================
                    _buildSearchBar(isDarkMode),
                    _buildFilterChips(isDarkMode),
                    _buildSearchResults(isDarkMode),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
