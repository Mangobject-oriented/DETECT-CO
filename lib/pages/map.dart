import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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

class EvacSite {
  final String name;
  final String description;
  final String image;
  final LatLng location;

  EvacSite({
    required this.name,
    required this.description,
    required this.image,
    required this.location,
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

class _MapTabState extends State<MapTab> {
  final mapController = MapController();

  LatLng? currentPosition;

  List<LatLng> routePoints = [];
  EvacSite? selectedSite;
  Hospital? selectedHospital;

  final LatLng swCorner =
      LatLng(14.13466576727542, 121.00698800147504);

  final LatLng neCorner =
      LatLng(14.242176187772285, 121.20972008423361);

  late final LatLng calambaCenter = LatLng(
    (swCorner.latitude + neCorner.latitude) / 2,
    (swCorner.longitude + neCorner.longitude) / 2,
  );

  final List<EvacSite> evacSites = [];
  final List<Hospital> hospitals = [];

  bool followMe = false;
  StreamSubscription<Position>? _positionStream;

  double waterLevel = 0;

  final DatabaseReference dbRef =
      FirebaseDatabase.instance.ref().child('flood');

  late final StreamSubscription<DatabaseEvent> _firebaseSub;

  Future<void> _loadMapPlaces() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/data/map_places.json');

      final List<dynamic> data = jsonDecode(jsonString);

      final List<EvacSite> loadedEvacSites = [];
      final List<Hospital> loadedHospitals = [];

      for (final item in data) {
        final Map<String, dynamic> place =
            Map<String, dynamic>.from(item as Map);

        final String type = place['type']?.toString() ?? '';

        final double latitude =
            (place['latitude'] as num).toDouble();
        final double longitude =
            (place['longitude'] as num).toDouble();

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
              image: place['image']?.toString() ??
                  'assets/images/evac1.png',
              location: LatLng(latitude, longitude),
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        evacSites
          ..clear()
          ..addAll(loadedEvacSites);

        hospitals
          ..clear()
          ..addAll(loadedHospitals);
      });
    } catch (e) {
      debugPrint('Map places loading error: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    _loadMapPlaces();

    _firebaseSub = dbRef.onValue.listen((event) {
      final data =
          event.snapshot.value as Map<dynamic, dynamic>?;

      if (data == null) return;

      final dynamic distanceRaw = data['distance'];

      final double value = distanceRaw is num
          ? distanceRaw.toDouble()
          : double.tryParse(distanceRaw.toString()) ?? 0;

      if (!mounted) return;

      setState(() {
        waterLevel = value;
      });
    });

    // If we were opened with a focus request already pending
    // (unlikely on first build, but handled for completeness),
    // apply it once the first frame is laid out.
    if (widget.focusLat != null && widget.focusLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusOnRequestedSite();
      });
    }
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
    _firebaseSub.cancel();
    _positionStream?.cancel();
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
      final bool sameName = widget.focusName != null &&
          site.name.toLowerCase() == widget.focusName!.toLowerCase();

      final bool sameSpot =
          (site.location.latitude - target.latitude).abs() < 0.0005 &&
          (site.location.longitude - target.longitude).abs() < 0.0005;

      if (sameName || sameSpot) {
        match = site;
        break;
      }
    }

    final EvacSite site = match ??
        EvacSite(
          name: widget.focusName ?? 'Evacuation Center',
          description: widget.focusDescription ?? '',
          image: 'assets/images/evac1.png',
          location: target,
        );

    setState(() {
      selectedSite = site;
    });

    mapController.move(site.location, 16);

    if (currentPosition != null) {
      getRoute(currentPosition!, site.location);
    }

    _showEvacPanel(site);
  }

  // =====================================================
  // GET ROUTE
  // =====================================================

  Future<void> getRoute(
    LatLng start,
    LatLng end,
  ) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final coords =
            data['routes'][0]['geometry']['coordinates'];

        if (!mounted) return;

        setState(() {
          routePoints = coords
              .map<LatLng>(
                (c) => LatLng(c[1], c[0]),
              )
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Route API error: $e');
    }
  }

  // =====================================================
  // GO TO NEAREST EVACUATION SITE
  // =====================================================

  void _goToNearestEvac() {
    if (currentPosition == null) {
      _locateMe();
      return;
    }

    final Distance distance = Distance();

    EvacSite nearest = evacSites[0];
    double minDist = double.infinity;

    for (final site in evacSites) {
      final dist = distance.as(
        LengthUnit.Meter,
        currentPosition!,
        site.location,
      );

      if (dist < minDist) {
        minDist = dist;
        nearest = site;
      }
    }

    setState(() {
      selectedSite = nearest;
    });

    mapController.move(nearest.location, 16);

    getRoute(
      currentPosition!,
      nearest.location,
    );

    _showEvacPanel(nearest);
  }

  // =====================================================
  // GO TO NEAREST HOSPITAL
  // =====================================================

  void _goToNearestHospital() {
    if (currentPosition == null) {
      _locateMe();
      return;
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
    });

    mapController.move(nearest.location, 16);

    getRoute(
      currentPosition!,
      nearest.location,
    );

    _showHospitalPanel(nearest, minDist);
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

    if (waterLevel >= 40) {
      riskText = "FLOODING";
      riskColor = const Color.fromRGBO(
        244,
        67,
        54,
        1,
      );
    } else if (waterLevel >= 20 && waterLevel < 40) {
      riskText = "MEDIUM RISK";
      riskColor = Colors.orange;
    } else {
      riskText = "SAFE";
      riskColor = const Color.fromRGBO(
        76,
        175,
        80,
        1,
      );
    }

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

            final Color panelBackground =
                isDarkMode ? const Color(0xFF2C2C2C) : Colors.white;

            final Color titleColor =
                isDarkMode ? Colors.white : const Color(0xFF1D2B4A);

            final Color subtitleColor =
                isDarkMode ? Colors.grey[400]! : const Color(0xFF5A6B8C);

            final Color primaryButtonColor = const Color(0xFF2867F5);

            return Container(
              height:
                  MediaQuery.of(context).size.height * 0.50,
              width: double.infinity,
              decoration: BoxDecoration(
                color: panelBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
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
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
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

                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  riskColor.withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                color: riskColor,
                              ),
                            ),
                            child: Text(
                              "Flood Risk: $riskText",
                              style: TextStyle(
                                color: riskColor,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),

                          const Spacer(),

                          // =====================================
                          // GO TO LOCATION BUTTON
                          // =====================================

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (currentPosition != null) {
                                  getRoute(
                                    currentPosition!,
                                    site.location,
                                  );
                                }

                                mapController.move(
                                  site.location,
                                  16,
                                );

                                Navigator.pop(context);
                              },
                              icon: const Icon(
                                Icons.directions,
                              ),
                              label: const Text(
                                "Go to Location",
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryButtonColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
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
                                  getRoute(
                                    currentPosition!,
                                    site.location,
                                  );

                                  mapController.move(
                                    currentPosition!,
                                    16,
                                  );
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
                                  borderRadius:
                                      BorderRadius.circular(12),
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
    final String distanceLabel = distanceMeters >= 1000
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
            final Color panelBackground =
                isDarkMode ? const Color(0xFF2C2C2C) : Colors.white;

            final Color titleColor =
                isDarkMode ? Colors.white : const Color(0xFF1D2B4A);

            final Color subtitleColor =
                isDarkMode ? Colors.grey[400]! : const Color(0xFF5A6B8C);

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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            );
          },
        );
      },
    );
  }

  // =====================================================
  // LEGEND ITEM
  // =====================================================

  Widget _legendItem(
    Color color,
    String text,
    bool isDarkMode,
  ) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 8),

        Text(
          text,
          style: TextStyle(
            color: isDarkMode
                ? Colors.white
                : Colors.black,
          ),
        ),
      ],
    );
  }

  // =====================================================
  // LOCATE USER
  // =====================================================

  Future<void> _locateMe() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint(
          'Location services are disabled.',
        );
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        debugPrint(
          'Location permission denied.',
        );
        return;
      }

      final pos =
          await Geolocator.getCurrentPosition();

      if (!mounted) return;

      setState(() {
        currentPosition = LatLng(
          pos.latitude,
          pos.longitude,
        );

        followMe = true;
      });

      mapController.move(
        currentPosition!,
        16,
      );
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (
        context,
        isDarkMode,
        child,
      ) {
        return Scaffold(
          backgroundColor: isDarkMode
              ? const Color(0xFF212121)
              : Colors.white,

          body: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================

              Container(
                color: isDarkMode
                    ? const Color(0xFF212121)
                    : const Color.fromARGB(
                        255,
                        72,
                        119,
                        247,
                      ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // LOGO

                        GestureDetector(
                          onDoubleTap: () {
                            isDarkModeNotifier.value =
                                !isDarkModeNotifier.value;
                          },
                          child: SizedBox(
                            width: 50,
                            height: 50,
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
                        cameraConstraint:
                            CameraConstraint.contain(
                          bounds: LatLngBounds(
                            swCorner,
                            neCorner,
                          ),
                        ),
                      ),

                      children: [
                        // =================================================
                        // OPENSTREETMAP TILES
                        // =================================================

                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName:
                              'com.detectco.app',
                        ),

                        // =================================================
                        // FLOOD ZONES
                        // =================================================

                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: LatLng(
                                14.234706315729172,
                                121.17367192746359,
                              ),
                              radius: 600,
                              useRadiusInMeter: true,
                              color: waterLevel <= 0
                                  ? Colors.green.withOpacity(0.35)
                                  : waterLevel >= 20 &&
                                          waterLevel < 40
                                      ? Colors.orange.withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel <= 0
                                  ? Colors.green
                                  : waterLevel >= 20 &&
                                          waterLevel < 40
                                      ? Colors.orange
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ),
                              borderStrokeWidth: 2,
                            ),

                            CircleMarker(
                              point: LatLng(
                                14.209895867059025,
                                121.18097126019865,
                              ),
                              radius: 600,
                              useRadiusInMeter: true,
                              color: waterLevel <= 0
                                  ? Colors.green.withOpacity(0.35)
                                  : waterLevel >= 20 &&
                                          waterLevel < 40
                                      ? Colors.orange.withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel <= 0
                                  ? Colors.green
                                  : waterLevel >= 20 &&
                                          waterLevel < 40
                                      ? Colors.orange
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ),
                              borderStrokeWidth: 2,
                            ),

                            CircleMarker(
                              point: LatLng(
                                14.215510239402107,
                                121.18530211042635,
                              ),
                              radius: 600,
                              useRadiusInMeter: true,
                              color: waterLevel <= 0
                                  ? Colors.green.withOpacity(0.35)
                                  : waterLevel >= 20 &&
                                          waterLevel < 40
                                      ? Colors.orange.withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel <= 0
                                  ? Colors.green
                                  : waterLevel >= 20 &&
                                          waterLevel < 40
                                      ? Colors.orange
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ),
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

                            for (final site in evacSites)
                              Marker(
                                point: site.location,
                                width: 45,
                                height: 45,
                                child: GestureDetector(
                                  onTap: () =>
                                      _showEvacPanel(site),
                                  child: Image.asset(
                                    'assets/icon/evacsite.png',
                                  ),
                                ),
                              ),

                            // ===== HOSPITAL MARKERS =====
                            for (final hospital in hospitals)
                              Marker(
                                point: hospital.location,
                                width: 44,
                                height: 44,
                                child: GestureDetector(
                                  onTap: () {
                                    final Distance distance = Distance();
                                    final double dist = currentPosition != null
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
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black26, blurRadius: 4),
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
                          ],
                        ),
                      ],
                    ),

                    // =====================================================
                    // GPS + NEAREST BUTTONS
                    // =====================================================

                    // TOP-RIGHT: EVACUATION + HOSPITAL BUTTONS
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Column(
                        children: [
                          // ===== NEAREST EVACUATION CENTER BUTTON =====
                          SizedBox(
                            width: 150,
                            height: 48,
                            child: FloatingActionButton.extended(
                              heroTag: 'nearest',
                              backgroundColor: const Color.fromARGB(
                                255,
                                129,
                                160,
                                247,
                              ),
                              onPressed: _goToNearestEvac,
                              icon: const Icon(
                                Icons.place,
                                color: Colors.white,
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

                          const SizedBox(height: 10),

                          // ===== NEAREST HOSPITAL BUTTON =====
                          SizedBox(
                            width: 150,
                            height: 48,
                            child: FloatingActionButton.extended(
                              heroTag: 'nearest_hospital',
                              backgroundColor: const Color(0xFFFF3035),
                              onPressed: _goToNearestHospital,
                              icon: const Icon(
                                Icons.local_hospital,
                                color: Colors.white,
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
                      bottom: 16,
                      right: 16,
                      child: FloatingActionButton(
                        heroTag: 'gps',
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
                    // =================================================

                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding:
                            const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF2C2C2C)
                                  .withOpacity(0.92)
                              : Colors.white
                                  .withOpacity(0.92),
                          borderRadius:
                              BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: isDarkMode
                                  ? Colors.black54
                                  : Colors.black26,
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _legendItem(
                              Colors.green,
                              "Safe",
                              isDarkMode,
                            ),

                            const SizedBox(height: 6),

                            _legendItem(
                              Colors.orange,
                              "Medium Risk",
                              isDarkMode,
                            ),

                            const SizedBox(height: 6),

                            _legendItem(
                              Colors.red,
                              "Flooding",
                              isDarkMode,
                            ),
                          ],
                        ),
                      ),
                    ),
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