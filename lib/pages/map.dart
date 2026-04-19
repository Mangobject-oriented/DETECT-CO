import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

/// -------------------------------
/// EVAC DATA MODEL (ADDED ONLY)
/// -------------------------------
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

  // ✅ Boundary (unchanged)
  final LatLng swCorner = LatLng(14.13466576727542, 121.00698800147504);
  final LatLng neCorner = LatLng(14.242176187772285, 121.20972008423361);

  late final LatLng calambaCenter = LatLng(
    (swCorner.latitude + neCorner.latitude) / 2,
    (swCorner.longitude + neCorner.longitude) / 2,
  );

  /// 🚨 EVACUATION SITES (UPDATED INTO OBJECTS, NOT REMOVED)
  final List<EvacSite> evacSites = [
    EvacSite(
      name: "Uwisan Brgy Hall Evacuation Site",
      description: "65PF+RC8, Looc Road, Calamba, 4027 Laguna",
      image: "assets/images/evac1.png",
      location: LatLng(14.23707209551028, 121.17340069445697),
    ),
    EvacSite(
      name: "Lingga Elementary School Evacuation Site",
      description: "658J+7WC, Dany, Calamba, 4027 Laguna",
      image: "assets/images/evac2.png",
      location: LatLng(14.215765305050551, 121.18228271136698),
    ),
    EvacSite(
      name: "Palingon Elementary School Evacuation Site",
      description: "658P+425, 202 Caballero St, Real, Calamba, 4027 Laguna",
      image: "assets/images/evac3.png",
      location: LatLng(14.215617735789499, 121.1861596967596),
    ),
  ];

  int selectedEvacIndex = 0;

  bool followMe = false;
  StreamSubscription<Position>? _positionStream;

  /// -------------------------------
  /// EVAC PANEL (NEW FEATURE ONLY)
  /// -------------------------------
  void _showEvacPanel(EvacSite site) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.4,
          maxChildSize: 0.7,
          minChildSize: 0.3,
          builder: (_, controller) {
            return SingleChildScrollView(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    site.image,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(site.description),
                        const SizedBox(height: 20),

                        ElevatedButton.icon(
                          onPressed: () {
                            mapController.move(site.location, 16.0);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.directions),
                          label: const Text("Go to Location"),
                        ),
                      ],
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

  /// -------------------------------
  /// YOUR ORIGINAL FUNCTIONS (UNCHANGED)
  /// -------------------------------

  Future<void> _locateMe() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    setState(() {
      followMe = !followMe;
    });

    if (followMe) {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final lat = pos.latitude.clamp(swCorner.latitude, neCorner.latitude);
      final lng = pos.longitude.clamp(swCorner.longitude, neCorner.longitude);

      final clamped = LatLng(lat, lng);

      setState(() {
        currentPosition = clamped;
      });

      mapController.move(clamped, 16.0);
    } else {
      _positionStream?.cancel();
      _positionStream = null;
    }
  }

  void _locateEvac() {
    final target = evacSites[selectedEvacIndex].location;
    mapController.move(target, 16.0);
  }

  void _nextEvacSite() {
    setState(() {
      selectedEvacIndex = (selectedEvacIndex + 1) % evacSites.length;
    });

    mapController.move(evacSites[selectedEvacIndex].location, 16.0);
  }

  /// -------------------------------
  /// UI
  /// -------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flood Monitoring Map'),
        centerTitle: true,
        backgroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              center: calambaCenter,
              zoom: 13.5,
              minZoom: 12.0,
              maxZoom: 18.0,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(swCorner, neCorner),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.detectco',
              ),

              MarkerLayer(
                markers: [
                  /// 📍 USER MARKER (UNCHANGED)
                  if (currentPosition != null)
                    Marker(
                      point: currentPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 36,
                      ),
                    ),

                  /// 🚨 EVAC MARKERS (NOW CLICKABLE)
                  for (int i = 0; i < evacSites.length; i++)
                    Marker(
                      point: evacSites[i].location,
                      width: 45,
                      height: 45,
                      child: GestureDetector(
                        onTap: () => _showEvacPanel(evacSites[i]),
                        child: Transform.scale(
                          scale: i == selectedEvacIndex ? 1.2 : 1.0,
                          child: Image.asset('assets/icon/evacsite.png'),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          /// -------------------------------
          /// FLOATING BUTTONS (UNCHANGED)
          /// -------------------------------
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  onPressed: _locateMe,
                  heroTag: 'locateMe',
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  mini: true,
                  onPressed: _locateEvac,
                  heroTag: 'locateEvac',
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.local_hospital),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  mini: true,
                  onPressed: _nextEvacSite,
                  heroTag: 'nextEvac',
                  backgroundColor: Colors.orange,
                  child: const Icon(Icons.swap_horiz),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}