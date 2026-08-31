import 'package:flutter/material.dart';
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
  const MapTab({super.key});

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

class _MapTabState extends State<MapTab> {
  final mapController = MapController();

  LatLng? currentPosition;

  List<LatLng> routePoints = [];
  EvacSite? selectedSite;

  final LatLng swCorner =
      LatLng(14.13466576727542, 121.00698800147504);

  final LatLng neCorner =
      LatLng(14.242176187772285, 121.20972008423361);

  late final LatLng calambaCenter = LatLng(
    (swCorner.latitude + neCorner.latitude) / 2,
    (swCorner.longitude + neCorner.longitude) / 2,
  );

  final List<EvacSite> evacSites = [
    EvacSite(
      name: "Uwisan Brgy Hall Evacuation Site",
      description: "65PF+RC8, Looc Road, Calamba",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.23707209551028,
        121.17340069445697,
      ),
    ),
    EvacSite(
      name: "Lingga Elementary School",
      description: "658J+7WC, Dany, Calamba, 4027 Laguna",
      image: "assets/images/evac2.png",
      location: LatLng(
        14.215765305050551,
        121.18228271136698,
      ),
    ),
    EvacSite(
      name: "Palingon Elementary School",
      description:
          "658P+425, 202 Caballero St, Real, Calamba, 4027 Laguna",
      image: "assets/images/evac3.png",
      location: LatLng(
        14.215617735789499,
        121.1861596967596,
      ),
    ),
  ];

  bool followMe = false;
  StreamSubscription<Position>? _positionStream;

  double waterLevel = 0;

  final DatabaseReference dbRef =
      FirebaseDatabase.instance.ref().child('flood');

  late final StreamSubscription<DatabaseEvent> _firebaseSub;

  @override
  void initState() {
    super.initState();

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
  }

  @override
  void dispose() {
    _firebaseSub.cancel();
    _positionStream?.cancel();
    super.dispose();
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
  // EVACUATION SITE PANEL
  // =====================================================

  void _showEvacPanel(EvacSite site) {
    String riskText;
    Color riskColor;

    if (waterLevel > 40) {
      riskText = "SAFE";
      riskColor = const Color.fromRGBO(
        76,
        175,
        80,
        1,
      );
    } else if (waterLevel > 30) {
      riskText = "MEDIUM RISK";
      riskColor = Colors.orange;
    } else {
      riskText = "FLOODING";
      riskColor = const Color.fromRGBO(
        244,
        67,
        54,
        1,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height:
              MediaQuery.of(context).size.height * 0.50,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
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
                      Text(
                        site.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(site.description),

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
                        ),
                      ),

                      const SizedBox(height: 8),

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
                          icon: const Icon(
                            Icons.navigation,
                          ),
                          label: const Text(
                            "Directions from Me",
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
                              color: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    ).withOpacity(0.20)
                                  : waterLevel > 30
                                      ? Colors.orange
                                          .withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    )
                                  : waterLevel > 30
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
                              color: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    ).withOpacity(0.35)
                                  : waterLevel > 30
                                      ? Colors.orange
                                          .withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    )
                                  : waterLevel > 30
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
                              color: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    ).withOpacity(0.35)
                                  : waterLevel > 30
                                      ? Colors.orange
                                          .withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    )
                                  : waterLevel > 30
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
                          ],
                        ),
                      ],
                    ),

                    // =================================================
                    // GPS + NEAREST BUTTONS
                    // =================================================

                    Positioned(
                      top: 16,
                      right: 16,
                      child: Column(
                        children: [
                          FloatingActionButton(
                            heroTag: 'gps',
                            mini: true,
                            backgroundColor:
                                const Color.fromARGB(
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

                          const SizedBox(height: 10),

                          FloatingActionButton(
                            heroTag: 'nearest',
                            mini: true,
                            backgroundColor:
                                const Color.fromARGB(
                              255,
                              129,
                              160,
                              247,
                            ),
                            onPressed:
                                _goToNearestEvac,
                            child: const Icon(
                              Icons.place,
                              color: Colors.white,
                            ),
                          ),
                        ],
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